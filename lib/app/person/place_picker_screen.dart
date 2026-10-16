import 'package:flutter/material.dart';

import '../../data/places.dart';
import '../../data/residences.dart';
import '../../dev/frame_log.dart';
import '../home/cemetery_base.dart' show joinPlaceLine;
import '../theme.dart';
import '../widgets/date_block.dart' show inputTextStyle;
import 'place_list_asset.dart';

/// The choice of a residence's place (05_DESIGN/zamieszkanie.md, B, elements 17–22): the list in the app,
/// so it works without the network (AC-3). Without text — the places chosen lately (D6); with text — the
/// localities, then the countries. Returns the place chosen; back returns nothing.
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({super.key, required this.recent, this.places});

  /// "Ostatnio wybrane" (element 18).
  final Future<List<ResidencePlace>> recent;

  /// The list; the bundled one when null (tests give a made-up one).
  final Future<PlaceList>? places;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final TextEditingController _query = TextEditingController();
  final Stopwatch _opening = Stopwatch()..start();
  PlaceList? _list;
  bool _failed = false;
  List<ResidencePlace> _recent = const [];
  List<ListedPlace> _localities = const [];
  CountryMatches _countries = (atStart: const [], inside: const []);

  /// From this many letters a country whose name starts with the text stands over the localities
  /// (zamieszkanie.md D8): at 1–2 letters up to 28 countries share a start and would push the localities
  /// off the screen; at 3 — 1 to 3 for the countries the family comes from (measured by `ui`).
  static const int _countriesOnTopFrom = 3;

  @override
  void initState() {
    super.initState();
    (widget.places ?? BundledPlaces.open()).then(
      (list) {
        measureLog('places_open', _opening.elapsed);
        if (!mounted) return;
        setState(() => _list = list);
        _search();
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    widget.recent.then((recent) {
      if (mounted) setState(() => _recent = recent);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final PlaceList? list = _list;
    if (list == null) return;
    final Stopwatch took = Stopwatch()..start();
    final List<ListedPlace> localities = list.search(_query.text);
    final CountryMatches countries = list.searchCountries(_query.text);
    measureLog(
      'places_search len=${placeKey(_query.text).length}',
      took.elapsed,
    );
    setState(() {
      _localities = localities;
      _countries = countries;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(),
          Expanded(child: _results()),
        ],
      ),
    ),
  );

  /// Element 17: back and the field, focused, with the keyboard at once.
  Widget _bar() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
    child: Row(
      children: [
        const BackButton(color: GrobingColors.text),
        const SizedBox(width: 4),
        Expanded(
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(inputDecorationTheme: GrobingTheme.fields),
            child: TextField(
              controller: _query,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.search,
              style: inputTextStyle,
              onChanged: (_) => _search(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: GrobingColors.textMuted),
                hintText: 'Kraj albo miejscowość',
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _results() {
    final int typed = placeKey(_query.text).length;
    final bool empty = typed == 0;
    final bool onTop = typed >= _countriesOnTopFrom;
    final List<ListedCountry> under = [
      if (!onTop) ..._countries.atStart,
      ..._countries.inside,
    ];
    final List<Widget> rows = [
      if (_failed)
        _note('Nie udało się otworzyć listy miejsc.')
      else if (_list == null && !empty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (empty) ...[
        // Element 18: the places chosen lately; without any — the field's hint alone.
        if (_recent.isNotEmpty) ...[
          _header('Ostatnio wybrane'),
          for (final ResidencePlace p in _recent)
            _PlaceRow(
              icon: Icons.history,
              name: p.name,
              detail: _detail(p),
              onTap: () => Navigator.of(context).pop(p),
            ),
        ],
      ] else ...[
        // Element 20 (v1.1, D8): from 3 letters the countries whose name starts with the text, over the
        // localities — the same row, no header (the icon and "cały kraj" say what it is).
        if (onTop) ...[
          for (final ListedCountry c in _countries.atStart) _country(c),
        ],
        // Element 19: the localities.
        for (final ListedPlace l in _localities)
          _PlaceRow(
            icon: Icons.location_city_outlined,
            name: l.name,
            detail: joinPlaceLine([?l.unit, l.countryName]),
            onTap: () => Navigator.of(context).pop(
              ResidencePlace.locality(
                name: l.name,
                unit: l.unit,
                countryCode: l.countryCode,
                countryName: l.countryName,
                point: l.point,
                geonamesId: l.geonamesId,
              ),
            ),
          ),
        // Element 20: the other countries — matched by a later word, and at 1–2 letters all — under the
        // localities.
        if (under.isNotEmpty) ...[
          _header('Kraje'),
          for (final ListedCountry c in under) _country(c),
        ],
        // Element 21.
        if (_list != null &&
            _localities.isEmpty &&
            _countries.atStart.isEmpty &&
            _countries.inside.isEmpty)
          _note(
            'Nie ma na liście? Wybierz kraj i\u00A0wpisz nazwę w\u00A0„Nazwa z\u00A0tamtego czasu”.',
          ),
      ],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ...rows,
        // Element 22: the source of the list, as its licence asks (CC BY 4.0).
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Lista miejsc: GeoNames (CC BY 4.0) ·\u00A0Natural Earth',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 13),
          ),
        ),
      ],
    );
  }

  /// A country's row (element 20): back to the window with the level "kraj".
  Widget _country(ListedCountry c) => _PlaceRow(
    icon: Icons.public,
    name: c.name,
    detail: 'cały kraj',
    onTap: () => Navigator.of(context).pop(
      ResidencePlace.country(
        countryCode: c.code,
        countryName: c.name,
        point: c.point,
      ),
    ),
  );

  static String _detail(ResidencePlace p) =>
      p.isCountry ? 'cały kraj' : joinPlaceLine([?p.unit, p.countryName]);

  static Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
    ),
  );

  static Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(
      text,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
    ),
  );
}

/// A row of the choice: the icon, the name, and what tells it apart — at least 56 dp, the whole row one
/// target (element 19).
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.name,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: '$name, $detail',
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: GrobingColors.textMuted),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: GrobingColors.text,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
