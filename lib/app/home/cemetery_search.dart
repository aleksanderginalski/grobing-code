import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'cemetery_card.dart';

/// What the search ends with.
sealed class SearchOutcome {
  const SearchOutcome();
}

/// Show this cemetery on the map, its sheet open.
class OpenCemetery extends SearchOutcome {
  const OpenCemetery(this.id);

  final int id;
}

/// Add a cemetery by hand, the name taken from the search.
class AddByHand extends SearchOutcome {
  const AddByHand(this.name);

  final String name;
}

/// The search mode over the map (05_DESIGN/cmentarze.md, elements 10–13): the family's cemeteries by
/// name or locality, without case, Polish diacritics or word endings (D3). The section "Z bazy
/// cmentarzy" arrives with ISSUE-015, so the results are built as sections already.
class CemeterySearchScreen extends StatefulWidget {
  const CemeterySearchScreen({super.key, required this.cemeteries});

  final List<CemeterySummary> cemeteries;

  @override
  State<CemeterySearchScreen> createState() => _CemeterySearchScreenState();
}

class _CemeterySearchScreenState extends State<CemeterySearchScreen> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CemeterySummary> get _sorted =>
      [...widget.cemeteries]..sort((a, b) => polishCompare(a.name, b.name));

  void _addByHand() =>
      Navigator.of(context).pop(AddByHand(capitalizeWords(_query.text)));

  @override
  Widget build(BuildContext context) {
    final String q = _query.text.trim();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GrobingColors.background,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: GrobingColors.outline)),
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: GrobingColors.text, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Szukaj cmentarza',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              color: GrobingColors.textMuted,
              tooltip: 'Wyczyść',
              onPressed: _query.clear,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: q.length < 2 ? _all() : _results(q),
      ),
    );
  }

  /// Element 11: every cemetery, also those without a point — the one way to them (D4).
  List<Widget> _all() {
    if (widget.cemeteries.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Wpisz nazwę cmentarza albo miejscowość.',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
          ),
        ),
      ];
    }
    return [_header('Twoje cmentarze'), for (final c in _sorted) _card(c)];
  }

  /// Elements 12 and 13 (without the database section — ISSUE-015).
  List<Widget> _results(String q) {
    final List<CemeterySummary> hits = _sorted
        .where((c) => matchesQuery(q, [c.name, c.locality]))
        .toList();
    if (hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Text(
            'Nie ma cmentarza „$q”.',
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 14,
            ),
          ),
        ),
        FilledButton.icon(
          style: primaryButtonStyle,
          onPressed: _addByHand,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Dodaj ręcznie'),
        ),
      ];
    }
    return [
      _header('Twoje cmentarze'),
      for (final c in hits) _card(c),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _addByHand,
          child: const Text('Dodaj ręcznie'),
        ),
      ),
    ];
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
    ),
  );

  Widget _card(CemeterySummary c) => CemeteryCard(
    cemetery: c,
    onTap: () => Navigator.of(context).pop(OpenCemetery(c.id)),
  );
}
