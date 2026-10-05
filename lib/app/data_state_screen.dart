import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/data_state.dart';
import '../data/database.dart';
import '../dev/fictional_data.dart';
import 'theme.dart';

/// "Stan danych" (ISSUE-007): schema version, row counts and the data fingerprint — the measure that
/// backup and restore are checked against. A technical screen in the base theme, not a product view.
class DataStateScreen extends StatefulWidget {
  const DataStateScreen({
    super.key,
    required this.database,
    required this.location,
  });

  final GrobingDatabase database;
  final DataLocation location;

  @override
  State<DataStateScreen> createState() => _DataStateScreenState();
}

class _DataStateScreenState extends State<DataStateScreen> {
  late Future<DataState> _state = _read();

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
    });
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
