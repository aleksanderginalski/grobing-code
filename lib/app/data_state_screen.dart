import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../backup/backup_archive.dart';
import '../backup/backup_service.dart';
import '../backup/backup_settings.dart';
import '../data/data_state.dart';
import '../data/database.dart';
import '../dev/fictional_data.dart';
import 'backup_setup_screen.dart';
import 'theme.dart';

/// "Stan danych" (ISSUE-007): schema version, row counts and the data fingerprint — the measure that
/// backup and restore are checked against — and the backup (ISSUE-008). A technical screen in the
/// base theme, not a product view.
class DataStateScreen extends StatefulWidget {
  const DataStateScreen({
    super.key,
    required this.database,
    required this.location,
    required this.backup,
  });

  final GrobingDatabase database;
  final DataLocation location;
  final BackupService backup;

  @override
  State<DataStateScreen> createState() => _DataStateScreenState();
}

class _DataStateScreenState extends State<DataStateScreen> {
  late Future<DataState> _state = _read();
  late Future<BackupSettings?> _backup = widget.backup.readSettings();
  bool _backingUp = false;

  static const Map<String, String> _tableLabels = {
    'persons': 'Osoby',
    'families': 'Rodziny',
    'family_partners': 'Partnerzy w rodzinach',
    'family_children': 'Dzieci w rodzinach',
    'events': 'Zdarzenia',
    'cemeteries': 'Cmentarze',
    'graves': 'Groby',
    'burials': 'Pochówki',
    'media': 'Zdjęcia (wpisy)',
    'settings': 'Ustawienia',
  };

  Future<DataState> _read() =>
      readDataState(widget.database, mediaDir: widget.location.mediaDir);

  void _refresh() {
    // A block body: an arrow `() => _state = ...` would return the Future to setState.
    setState(() {
      _state = _read();
      _backup = widget.backup.readSettings();
    });
  }

  Future<void> _backUpNow() async {
    setState(() => _backingUp = true);
    try {
      await widget.backup.backUpNow();
    } on BackupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _backingUp = false;
          _backup = widget.backup.readSettings();
        });
      }
    }
  }

  Future<void> _setUp({required bool replacesExisting}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => BackupSetupScreen(
          backup: widget.backup,
          replacesExisting: replacesExisting,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _addFictionalData() async {
    await addFictionalData(widget.database, widget.location.mediaDir);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stan danych'),
        backgroundColor: GrobingColors.background,
        actions: [
          IconButton(
            tooltip: 'Odśwież',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<DataState>(
        future: _state,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Błąd odczytu: ${snapshot.error}'));
          }
          final DataState? state = snapshot.data;
          if (state == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Row(label: 'Wersja schematu', value: '${state.schemaVersion}'),
              _Row(
                label: 'Odcisk danych',
                value: state.shortFingerprint,
                monospace: true,
              ),
              const Divider(height: 32),
              // Known tables in reading order; a table added by a later schema still shows up.
              for (final String table in [
                ..._tableLabels.keys.where(state.rowCounts.containsKey),
                ...state.rowCounts.keys.where(
                  (t) => !_tableLabels.containsKey(t),
                ),
              ])
                _Row(
                  label: _tableLabels[table] ?? table,
                  value: '${state.rowCounts[table]}',
                ),
              _Row(label: 'Pliki zdjęć', value: '${state.mediaFileCount}'),
              const Divider(height: 32),
              _BackupSection(
                settings: _backup,
                backingUp: _backingUp,
                onBackUpNow: _backUpNow,
                onSetUp: () => _setUp(replacesExisting: false),
                onSetUpAgain: () => _setUp(replacesExisting: true),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: _addFictionalData,
                  child: const Text('Wgraj wymyślone dane'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection({
    required this.settings,
    required this.backingUp,
    required this.onBackUpNow,
    required this.onSetUp,
    required this.onSetUpAgain,
  });

  final Future<BackupSettings?> settings;
  final bool backingUp;
  final VoidCallback onBackUpNow;
  final VoidCallback onSetUp;
  final VoidCallback onSetUpAgain;

  static const TextStyle _muted = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 13,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BackupSettings?>(
      future: settings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Błąd odczytu ustawień kopii: ${snapshot.error}');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final BackupSettings? backup = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Kopia',
              style: TextStyle(
                color: GrobingColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (backup == null) ...[
              const Text(
                'Kopia nie jest skonfigurowana. Do jej otwarcia będą potrzebne: '
                'plik kopii, plik klucza i hasło.',
                style: _muted,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onSetUp,
                child: const Text('Skonfiguruj kopię'),
              ),
            ] else ...[
              _Row(
                label: 'Ostatnia udana kopia',
                value: backup.lastSuccessAt == null
                    ? 'jeszcze nie było'
                    : _formatLocal(backup.lastSuccessAt!),
              ),
              // Honest about what the app can see (ADR-004, Consequences; SPIKE-003, M3).
              const Text(
                'Zapisana w Dysku na telefonie. Do chmury wysyła ją aplikacja Dysk — '
                'Grobing nie widzi, kiedy.',
                style: _muted,
              ),
              if (backup.lastAttemptFailed) ...[
                const SizedBox(height: 8),
                Text(
                  'Ostatnia próba (${_formatLocal(backup.lastFailureAt!)}) nie '
                  'powiodła się: ${backup.lastFailure}',
                  style: const TextStyle(color: GrobingColors.amber),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: backingUp ? null : onBackUpNow,
                child: backingUp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Zrób kopię teraz'),
              ),
              TextButton(
                onPressed: backingUp ? null : onSetUpAgain,
                child: const Text('Skonfiguruj kopię od nowa'),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _formatLocal(DateTime time) {
    final DateTime t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: GrobingColors.textMuted),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: GrobingColors.text,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
