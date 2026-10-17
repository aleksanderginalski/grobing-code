import '../../data/cemeteries.dart' show GeoPoint;
import '../../data/graves.dart' show QualifiedDate;
import '../../data/residences.dart';
import '../person/residence_screen.dart' show residenceCardLine;
import '../polish.dart' show peopleLabel;
import 'tree_time.dart';

// The migration map's time (05_DESIGN/mapa-migracji.md v1.1; ISSUE-045): who lives where in a year of the tree's
// slider. Pure Dart, worked out once for the family's residences: the map then only asks, as the tree asks
// TreeTime.

/// What the map shows of a person in one year.
enum MapPresence {
  /// Not born yet (the tree's window: InYear.notYet).
  notYet,

  /// Alive, and a residence says where.
  here,

  /// Alive, and no residence covers the year — "bez miejsca" in the pill.
  nowhere,

  /// Surely dead: off the map (K2 — the author at stop #1; mapa-migracji.md D16).
  gone,
}

/// One person in one year.
class MapPersonYear {
  const MapPersonYear(this.presence, {this.residence, this.unsure = false});

  final MapPresence presence;

  /// The residence of the year when [presence] is [MapPresence.here].
  final Residence? residence;

  /// In the window of an uncertain birth or death — the dashed outline, as on the tree (N3, drzewo.md D32).
  final bool unsure;

  ResidencePlace? get place => residence?.place;
}

/// The family's residences on the slider's years (element 4, D4).
class MigrationYear {
  MigrationYear({
    required TreeTime time,
    required Map<int, List<Residence>> residences,
    required Iterable<int> people,
  }) : _time = time,
       _people = List.unmodifiable(people),
       _stays = {
         for (final MapEntry<int, List<Residence>> e in residences.entries)
           e.key: _staysOf(time, e.key, e.value),
       };

  final TreeTime _time;
  final List<int> _people;
  final Map<int, List<_Stay>> _stays;

  /// This year — "dziś" on the slider.
  int get now => _time.now;

  /// Everyone the map knows of, residences or not.
  List<int> get people => _people;

  /// Whether anyone has a residence at all — else the empty map (mapa-migracji.md → States).
  bool get hasPlaces => _stays.values.any((s) => s.isNotEmpty);

  /// [person] in [year]; null is "dziś".
  MapPersonYear person(int person, int? year) {
    final InYear inYear = _time.person(person, year);
    switch (inYear) {
      case InYear.notYet:
        return const MapPersonYear(MapPresence.notYet);
      case InYear.dead:
        return const MapPersonYear(MapPresence.gone);
      case InYear.maybeBorn || InYear.maybeDead || InYear.alive:
        break;
    }
    final bool unsure =
        inYear == InYear.maybeBorn || inYear == InYear.maybeDead;
    final int y = year ?? _time.now;
    _Stay? best;
    for (final _Stay s in _stays[person] ?? const <_Stay>[]) {
      // Of two stays in one year the later start wins (D4) — the move of that year.
      if (s.from <= y && y < s.until && (best == null || s.from >= best.from)) {
        best = s;
      }
    }
    return best == null
        ? MapPersonYear(MapPresence.nowhere, unsure: unsure)
        : MapPersonYear(
            MapPresence.here,
            residence: best.residence,
            unsure: unsure,
          );
  }

  /// The people on the map in [year] by place, each place's people with [first] (the person in the middle)
  /// leading and then by the year of birth — the order of a stack (element 4, D3).
  Map<ResidencePlace, List<int>> groups(int? year, {int? first}) {
    final Map<ResidencePlace, List<int>> byPlace = {};
    for (final int p in _people) {
      final MapPersonYear s = person(p, year);
      if (s.place case final ResidencePlace place?) {
        (byPlace[place] ??= []).add(p);
      }
    }
    for (final List<int> ids in byPlace.values) {
      ids.sort((a, b) {
        if (a == first) return -1;
        if (b == first) return 1;
        final int c = _born(a).compareTo(_born(b));
        return c != 0 ? c : a.compareTo(b);
      });
    }
    return byPlace;
  }

  /// The pill (element 3, D7): alive in [year] with a place — off the frame too — and alive without one.
  ({int here, int nowhere}) counts(int? year) {
    int here = 0, nowhere = 0;
    for (final int p in _people) {
      switch (person(p, year).presence) {
        case MapPresence.here:
          here++;
        case MapPresence.nowhere:
          nowhere++;
        case MapPresence.notYet || MapPresence.gone:
          break;
      }
    }
    return (here: here, nowhere: nowhere);
  }

  /// Every point of every residence — the first frame (R4: "wszystkie miejsca z danych", element 10).
  List<GeoPoint> allPoints() => [
    for (final List<_Stay> stays in _stays.values)
      for (final _Stay s in stays) s.residence.place.point,
  ];

  int _born(int p) => _time.birthWindow(p)?.from ?? 1 << 30;

  /// The years each residence of [person] covers, `[from, until)` (D4): a typed "Do" counts its own year, so
  /// "do 1945" and "od 1946" leave no gap; an empty "Do" ends where the next start begins (zamieszkanie.md D12,
  /// `impliedEnds` — the same end as the person's view), the last at death; a stay with only "Do" begins at birth.
  /// A residence without years has no place on the time axis.
  static List<_Stay> _staysOf(
    TreeTime time,
    int person,
    List<Residence> residences,
  ) {
    final List<Residence> ordered = inStayOrder(residences);
    final List<QualifiedDate?> implied = impliedEnds(ordered);
    final int born = time.birthWindow(person)?.from ?? -(1 << 30);
    final int gone = time.deathWindow(person)?.to ?? 1 << 30;
    return [
      for (final (int i, Residence r) in ordered.indexed)
        if (r.from != null || r.to != null)
          _Stay(
            r,
            from: r.from?.from.year ?? born,
            until: r.to != null
                ? r.to!.from.year + 1
                : implied[i]?.from.year ?? gone,
          ),
    ];
  }
}

class _Stay {
  const _Stay(this.residence, {required this.from, required this.until});

  final Residence residence;
  final int from;
  final int until;
}

/// "W 1930" or "Dziś" — the hard space keeps the one-letter word with its year (style-b.md rule 6).
String mapWhen(int? year) => year == null ? 'Dziś' : 'W\u00A0$year';

/// The card's line in the map's part (element 12): "W 1930: Zmyślin, Polska · dziś Ukraina", "W 1950: nie wiadomo,
/// gdzie mieszka", "W 1900: przed narodzinami"; after death none — the card's years say it (D16).
String? mapWhereLine(MapPersonYear s, int? year) => switch (s.presence) {
  MapPresence.notYet => '${mapWhen(year)}: przed narodzinami',
  MapPresence.here => '${mapWhen(year)}: ${residenceCardLine(s.residence!)}',
  MapPresence.nowhere => '${mapWhen(year)}: nie wiadomo, gdzie mieszka',
  MapPresence.gone => null,
};

/// The pill (element 3): "W 1950 na mapie: 9 osób · 3 bez miejsca", "Dziś na mapie: 6 osób"; a line breaks before
/// the "·", never after it (rule 6).
String mapPill(({int here, int nowhere}) counts, int? year) =>
    '${mapWhen(year)} na mapie: ${peopleLabel(counts.here)}'
    '${counts.nowhere > 0 ? ' ·\u00A0${counts.nowhere} bez miejsca' : ''}';

/// The label under a place's people (element 4): today's name of a locality, "Francja · cały kraj" for a country.
String mapPlaceLabel(ResidencePlace p) =>
    p.isCountry ? '${p.countryName} ·\u00A0cały kraj' : p.name;
