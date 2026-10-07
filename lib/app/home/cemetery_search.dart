import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../external_link.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'base_preview_screen.dart';
import 'cemetery_base.dart';
import 'cemetery_card.dart';
import 'cemetery_form.dart';
import 'poland_map.dart';
import 'poland_map_data.dart';

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

/// A cemetery from the database was saved (ISSUE-015): show its candle and its sheet.
class AddedFromBase extends SearchOutcome {
  const AddedFromBase(this.id, this.point);

  final int id;
  final GeoPoint point;
}

/// The attribution the ODbL asks for, in the words of openstreetmap.org/copyright/pl (ISSUE-015 D3).
const String osmAttribution = 'Dane: © autorzy OpenStreetMap (ODbL)';

/// The search mode over the map (05_DESIGN/cmentarze.md, elements 10–13): the family's cemeteries,
/// then the cemeteries of Poland from the bundled database — by name, other name or locality, without
/// case, Polish diacritics or word endings (D3).
class CemeterySearchScreen extends StatefulWidget {
  const CemeterySearchScreen({
    super.key,
    required this.cemeteries,
    required this.base,
    required this.saveFromBase,
    this.mapData,
    this.pins = const [],
    this.openUrl = openExternalUrl,
  });

  final List<CemeterySummary> cemeteries;

  /// Read on the first entry into the search and kept for the session (ISSUE-015 D5).
  final Future<CemeteryBase> base;

  /// Saves a cemetery from the database with what the window returned; its id.
  final Future<int> Function(BaseCemetery cemetery, CemeteryFormValues values)
  saveFromBase;

  /// For the preview (element 14); null when the bundled map could not be read.
  final PolandMapData? mapData;
  final List<MapPin> pins;
  final Future<bool> Function(String url) openUrl;

  @override
  State<CemeterySearchScreen> createState() => _CemeterySearchScreenState();
}

class _CemeterySearchScreenState extends State<CemeterySearchScreen> {
  final TextEditingController _query = TextEditingController();
  CemeteryBase? _base;
  bool _baseFailed = false;

  /// The database takes longer than about 0.3 s: a thin progress bar under the field (States).
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    widget.base.then(
      (base) {
        if (mounted) setState(() => _base = base);
      },
      onError: (Object _) {
        if (mounted) setState(() => _baseFailed = true);
      },
    );
    _slowTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _base == null && !_baseFailed) {
        setState(() => _slow = true);
      }
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _query.dispose();
    super.dispose();
  }

  List<CemeterySummary> get _sorted =>
      [...widget.cemeteries]..sort((a, b) => polishCompare(a.name, b.name));

  void _addByHand() =>
      Navigator.of(context).pop(AddByHand(capitalizeWords(_query.text)));

  /// A cemetery from the database: the one you already have opens its sheet, another its preview.
  Future<void> _openFromBase(BaseCemetery c, int? addedId) async {
    if (addedId != null) {
      Navigator.of(context).pop(OpenCemetery(addedId));
      return;
    }
    final int? savedId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => BasePreviewScreen(
          cemetery: c,
          onSave: (values) => widget.saveFromBase(c, values),
          mapData: widget.mapData,
          saved: widget.pins,
          openUrl: widget.openUrl,
        ),
      ),
    );
    if (savedId != null && mounted) {
      Navigator.of(context).pop(AddedFromBase(savedId, c.point));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String q = _query.text.trim();
    final bool loading = _slow && _base == null && !_baseFailed;
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: loading
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  color: GrobingColors.amber,
                  backgroundColor: Colors.transparent,
                  semanticsLabel: 'Wczytywanie bazy cmentarzy',
                )
              : const SizedBox(height: 2),
        ),
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
      return [_muted('Wpisz nazwę cmentarza albo miejscowość.')];
    }
    return [_header('Twoje cmentarze'), for (final c in _sorted) _card(c)];
  }

  /// Elements 12 and 13: the family's cemeteries first, then the database (D17).
  List<Widget> _results(String q) {
    final List<CemeterySummary> yours = _sorted
        .where((c) => matchesQuery(q, [c.name, c.locality]))
        .toList();
    final BaseResults? found = _base?.search(q);
    if (yours.isEmpty && found != null && found.total == 0) {
      // Element 13.
      return [
        _muted('Nie ma cmentarza „$q” ani u Ciebie, ani w bazie.'),
        const SizedBox(height: 8),
        _addByHandButton(primary: true),
      ];
    }
    return [
      if (yours.isNotEmpty) ...[
        _header('Twoje cmentarze'),
        for (final c in yours) _card(c),
      ],
      if (_baseFailed) ...[
        // The database is bundled: an error is a fault of the app; the family's cemeteries and adding by
        // hand still work (States).
        _muted('Baza cmentarzy jest niedostępna — dodaj ręcznie.'),
        _addByHandButton(primary: yours.isEmpty),
      ] else if (found != null) ...[
        if (found.total > 0) ...[
          // 24 dp between the groups, with the card's own margin (style-b.md rule 5).
          if (yours.isNotEmpty) const SizedBox(height: 12),
          _header('Z bazy cmentarzy'),
          // Seen at once, not five screens down under the 30th card (ui review).
          if (found.total > found.shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Pokazuję ${found.shown.length} z ${found.total} — dopisz miejscowość.',
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
          for (final BaseCemetery c in found.shown)
            BaseCemeteryCard(
              cemetery: c,
              added: addedAs(c, widget.cemeteries) != null,
              onTap: () => _openFromBase(c, addedAs(c, widget.cemeteries)),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              osmAttribution,
              style: TextStyle(color: GrobingColors.textMuted, fontSize: 13),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _addByHand,
            child: const Text('Nie ma go w bazie — dodaj ręcznie'),
          ),
        ),
      ],
    ];
  }

  Widget _addByHandButton({required bool primary}) => primary
      ? FilledButton.icon(
          style: primaryButtonStyle,
          onPressed: _addByHand,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Dodaj ręcznie'),
        )
      : Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _addByHand,
            child: const Text('Dodaj ręcznie'),
          ),
        );

  Widget _muted(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(
      text,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
    ),
  );

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
