import 'package:flutter/material.dart';

import '../backup/backup_archive.dart';
import '../backup/documents.dart';
import '../backup/restore_service.dart';
import '../data/data_state.dart';
import 'theme.dart';

/// Restore from a backup (ISSUE-009): the backup file and the key file from the system "open" window,
/// the passphrase, then everything is checked before the phone's data is replaced. A technical
/// screen in the base theme, like "Stan danych".
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({
    super.key,
    required this.restore,
    required this.current,
    required this.onRestored,
  });

  final RestoreService restore;

  /// The phone's data now — a phone that has data gets a warning first (ISSUE-009, D4).
  final DataState current;

  /// Reopens the app on the restored data, with a notice for "Stan danych".
  final Future<void> Function(String notice) onRestored;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _Picked {
  const _Picked(this.uri, this.info);

  final String uri;
  final DocumentInfo info;
}

class _RestoreScreenState extends State<RestoreScreen> {
  final TextEditingController _passphrase = TextEditingController();
  _Picked? _backupFile;
  _Picked? _keyFile;
  RestoreStep? _step;
  bool _picking = false;
  String? _problem;

  static const Map<RestoreStep, String> _stepLabels = {
    RestoreStep.checkingSpace: 'Sprawdzam miejsce w telefonie…',
    RestoreStep.unlockingKey: 'Otwieram plik klucza hasłem (ok. 15-40 s)…',
    RestoreStep.copying: 'Pobieram plik kopii…',
    RestoreStep.decrypting: 'Odszyfrowuję i rozpakowuję kopię…',
    RestoreStep.verifying: 'Sprawdzam sumy kontrolne, bazę i odcisk danych…',
    RestoreStep.migrating: 'Przenoszę dane do tej wersji aplikacji…',
    RestoreStep.replacing: 'Zastępuję dane…',
  };

  bool get _phoneHasData =>
      widget.current.mediaFileCount > 0 ||
      widget.current.rowCounts.values.any((n) => n > 0);

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<_Picked?> _pick() async {
    setState(() {
      _picking = true;
      _problem = null;
    });
    try {
      final String? uri = await widget.restore.pickFile();
      if (uri == null) return null;
      return _Picked(uri, await widget.restore.describe(uri));
    } on Exception catch (e) {
      if (mounted) {
        setState(
          () => _problem = 'Nie udało się wybrać pliku (${e.runtimeType}).',
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<bool> _confirmReplace() async {
    final Map<String, int> counts = widget.current.rowCounts;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Zastąpić dane w telefonie?'),
            content: Text(
              'W telefonie są dane: osoby ${counts['persons'] ?? 0}, groby '
              '${counts['graves'] ?? 0}, cmentarze ${counts['cemeteries'] ?? 0}, pliki zdjęć '
              '${widget.current.mediaFileCount}. Odtworzenie zastąpi je w całości danymi z '
              'kopii. Tego nie da się cofnąć.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Anuluj'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Zastąp dane'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _start() async {
    if (_phoneHasData && !await _confirmReplace()) return;
    setState(() {
      _problem = null;
      _step = RestoreStep.checkingSpace;
    });
    try {
      final RestoreResult result = await widget.restore.restore(
        backupUri: _backupFile!.uri,
        keyUri: _keyFile!.uri,
        passphrase: _passphrase.text,
        onStep: (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      _passphrase.clear();
      await widget.onRestored(_notice(result));
    } on Exception catch (e) {
      final String message = e is BackupException
          ? e.message
          : 'Odtworzenie nie powiodło się (${e.runtimeType}).';
      if (widget.restore.databaseClosed) {
        // Past the commit point the data on disk decides; reopen whatever it is.
        await widget.onRestored(
          'Odtworzenie zostało przerwane: $message Aplikacja wczytała dane od nowa — '
          'sprawdź odcisk danych.',
        );
        return;
      }
      if (mounted) {
        setState(() => _problem = '$message\nDane w telefonie są nietknięte.');
      }
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  static String _notice(RestoreResult result) {
    final String fingerprint = result.dataFingerprint.substring(0, 16);
    final String data = result.schemaFrom == result.schemaTo
        ? 'Odcisk danych w kopii: $fingerprint — ten sam co niżej.'
        : 'Dane przeniesione z wersji ${result.schemaFrom} do ${result.schemaTo}, więc odcisk '
              'niżej różni się od odcisku w kopii ($fingerprint).';
    final String backup = switch (result.backup) {
      RestoredBackup.kept =>
        'Kopia działa jak dotąd: ten sam klucz, ten sam plik.',
      RestoredBackup.continued =>
        'Kopia działa dalej tym samym kluczem, do pliku, z którego odtworzono — notka '
            'przekazania pozostaje aktualna.',
      RestoredBackup.notConfigured =>
        'Kopia nie jest skonfigurowana: Dysk nie pozwolił zapisywać do tego pliku. Nowa '
            'konfiguracja utworzy nowy klucz — zaktualizuj potem notkę przekazania.',
    };
    return 'Odtworzono kopię z dnia ${_formatLocal(result.createdAt)}. $data $backup';
  }

  static String _formatLocal(DateTime time) {
    final DateTime t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  static String _describe(_Picked? picked) {
    if (picked == null) return 'nie wybrano';
    final int? size = picked.info.size;
    final String name = picked.info.name ?? 'wybrany plik';
    if (size == null) return name;
    final String amount = size < 1024 * 1024
        ? '${(size / 1024).ceil()} KB'
        : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '$name · $amount';
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _step != null || _picking;
    final bool ready =
        _backupFile != null &&
        _keyFile != null &&
        _passphrase.text.isNotEmpty &&
        !busy;
    const TextStyle body = TextStyle(color: GrobingColors.text, height: 1.4);
    const TextStyle muted = TextStyle(
      color: GrobingColors.textMuted,
      fontSize: 13,
      height: 1.4,
    );
    return PopScope(
      canPop: _step == null,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Odtwórz z kopii'),
          backgroundColor: GrobingColors.background,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Odtworzenie zastępuje dane w telefonie danymi z kopii. Potrzebne są trzy rzeczy: '
              'plik kopii (grobing-kopia.age), plik klucza (grobing-klucz.age) i hasło z notki '
              'przekazania.',
              style: body,
            ),
            const SizedBox(height: 12),
            const Text(
              'Zanim cokolwiek zostanie zastąpione, aplikacja sprawdza kopię: hasło, sumy '
              'kontrolne każdego pliku, spójność bazy, liczby rekordów i odcisk danych. Zła '
              'kopia niczego w telefonie nie zmienia.',
              style: body,
            ),
            const SizedBox(height: 12),
            // SPIKE-003, M6: on a freshly signed-in phone the Drive folder looks empty for minutes.
            const Text(
              'Na nowym telefonie folder Dysku w oknie wyboru bywa przez kilka minut pusty. '
              'Wtedy dotknij lupy u góry okna i wpisz „grobing”.',
              style: muted,
            ),
            if (_phoneHasData) ...[
              const SizedBox(height: 12),
              const Text(
                'W telefonie są już dane. Odtworzenie zastąpi je w całości — tego nie da się '
                'cofnąć.',
                style: TextStyle(color: GrobingColors.amber, height: 1.4),
              ),
            ],
            const SizedBox(height: 24),
            _FileRow(
              label: 'Plik kopii',
              value: _describe(_backupFile),
              button: 'Wybierz plik kopii',
              onPressed: busy
                  ? null
                  : () async {
                      final _Picked? picked = await _pick();
                      if (picked != null && mounted) {
                        setState(() => _backupFile = picked);
                      }
                    },
            ),
            const SizedBox(height: 12),
            _FileRow(
              label: 'Plik klucza',
              value: _describe(_keyFile),
              button: 'Wybierz plik klucza',
              onPressed: busy
                  ? null
                  : () async {
                      final _Picked? picked = await _pick();
                      if (picked != null && mounted) {
                        setState(() => _keyFile = picked);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphrase,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(labelText: 'Hasło'),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 16),
              Text(
                _problem!,
                style: const TextStyle(color: GrobingColors.amber, height: 1.4),
              ),
            ],
            if (_step != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_stepLabels[_step]!, style: body)),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: ready ? _start : null,
              child: const Text('Odtwórz'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.value,
    required this.button,
    required this.onPressed,
  });

  final String label;
  final String value;
  final String button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label: $value',
          style: const TextStyle(color: GrobingColors.textMuted),
        ),
        const SizedBox(height: 4),
        OutlinedButton(onPressed: onPressed, child: Text(button)),
      ],
    );
  }
}
