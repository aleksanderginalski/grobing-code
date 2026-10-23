import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/cemeteries.dart';
import '../polish.dart';

/// One cemetery of the bundled database (05_DESIGN/cmentarze.md, elements 12 and 14).
class BaseCemetery {
  const BaseCemetery({
    required this.name,
    this.otherNames = const [],
    required this.point,
    this.kind,
    required this.locality,
    this.district,
    required this.voivodeship,
    this.nearby = const [],
  });

  /// Empty when OpenStreetMap has no name: the card says "Cmentarz bez nazwy" (style-b.md rule 7).
  final String name;

  /// Other names people use — colloquial, official, old ("Stare Powązki").
  final List<String> otherNames;
  final GeoPoint point;

  /// Denomination in Polish ("rzymskokatolicki"), when the database knows it.
  final String? kind;

  /// The locality shown: the nearest place weighted by its rank (ISSUE-014 D9).
  final String locality;

  /// The district in brackets, in a city or a town.
  final String? district;

  /// Without the word "województwo": "mazowieckie".
  final String voivodeship;

  /// Other places within reach — found by the search, not shown.
  final List<String> nearby;

  /// "Warszawa (Żoliborz)".
  String get place => district == null ? locality : '$locality ($district)';
}

/// What the search of the database returns: at most [limit] cemeteries, and how many matched.
typedef BaseResults = ({List<BaseCemetery> shown, int total});

/// The cemeteries of Poland from OpenStreetMap, bundled with the app (`assets/cemeteries/
/// poland_cemeteries.json`, ODbL, rebuilt by `tool/cemeteries/extract_cemeteries.dart`): found without
/// the network (ISSUE-015 AC-1).
class CemeteryBase {
  CemeteryBase(List<BaseCemetery> cemeteries)
    : cemeteries = _sorted(cemeteries) {
    for (final BaseCemetery c in this.cemeteries) {
      _all.add(
        fold(
          [
            c.name,
            ...c.otherNames,
            c.locality,
            ?c.district,
            ...c.nearby,
          ].join(' | '),
        ),
      );
    }
  }

  factory CemeteryBase.fromJson(String source) {
    final Map<String, Object?> json =
        jsonDecode(source) as Map<String, Object?>;
    final List<String> voivodeships = (json['voivodeships']! as List<Object?>)
        .cast<String>();
    final List<String> kinds = (json['kinds']! as List<Object?>).cast<String>();
    String? orNull(String s) => s.isEmpty ? null : s;
    return CemeteryBase([
      for (final Object? row in json['cemeteries']! as List<Object?>)
        if (row case [
          final String name,
          final List<Object?> otherNames,
          final num lat,
          final num lon,
          final int kind,
          final String locality,
          final String district,
          final int voivodeship,
          final List<Object?> nearby,
        ])
          BaseCemetery(
            name: name,
            otherNames: otherNames.cast<String>(),
            point: GeoPoint(lat.toDouble(), lon.toDouble()),
            kind: kind < 0 ? null : kinds[kind],
            locality: locality,
            district: orNull(district),
            voivodeship: voivodeships[voivodeship],
            nearby: nearby.cast<String>(),
          ),
    ]);
  }

  static const String asset = 'assets/cemeteries/poland_cemeteries.json';

  /// About 2 MB: read and parsed off the main isolate, so the keyboard does not freeze (ISSUE-015 D5).
  static Future<CemeteryBase> load([AssetBundle? bundle]) async => compute(
    CemeteryBase.fromJson,
    await (bundle ?? rootBundle).loadString(asset),
  );

  /// In the order the results show them: by name in the Polish alphabet, then by locality.
  final List<BaseCemetery> cemeteries;
  final List<String> _all = [];

  /// The cemeteries every word of [query] matches — without case, Polish letters or word endings, like
  /// the family's own (05_DESIGN/cmentarze.md D3). Which cemeteries match is D3's; their order is D36's
  /// (ISSUE-052): (1) more words of the query typed in full that are whole words of the cemetery; (2) the
  /// furthest place a word has to be found in — the name, the locality or district on the card, a nearby
  /// place, only inside a word; (3) fewer fields holding all the words — a nearby place named in full
  /// before words scattered over several; (4) alphabetical, as the file is (ISSUE-015 D8).
  BaseResults search(String query, {int limit = 30}) {
    final List<String> stems = searchStems(query);
    if (stems.isEmpty) return (shown: const [], total: 0);
    final _Query q = _Query(query);
    final List<int> hits = [];
    final Map<int, _Rank> ranks = {};
    for (int i = 0; i < cemeteries.length; i++) {
      if (!stems.every(_all[i].contains)) continue;
      hits.add(i);
      ranks[i] = q.rank(_fields[i] ??= _Fields.of(cemeteries[i]));
    }
    // List.sort is not stable: the index keeps the alphabetical order within a rank.
    hits.sort((a, b) {
      final int c = ranks[a]!.compareTo(ranks[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
    return (
      shown: [for (final int i in hits.take(limit)) cemeteries[i]],
      total: hits.length,
    );
  }

  /// The words of each cemetery's fields, split the first time a search meets it: most searches meet a
  /// few hundred of the 16 thousand, so the base does not split them all when it loads (ISSUE-015 D5).
  late final List<_Fields?> _fields = List.filled(cemeteries.length, null);
}

/// The nearby place a result of [query] was found through, for "· przy: …" on its card
/// (05_DESIGN/cmentarze.md, element 12, D35): when a word of the query starts no word of the name, the
/// locality or the district, the nearby place that the most such words start a word of — the first of
/// the base's list on a tie. Null when every word is on the card, or no nearby place holds one.
String? foundThrough(BaseCemetery c, String query) {
  final _Query q = _Query(query);
  final _Fields f = _Fields.of(c);
  final List<String> missing = [
    for (final String stem in q.stems)
      if (!f.onCard.any((words) => _startsWord(words, stem))) stem,
  ];
  if (missing.isEmpty) return null;
  String? best;
  int most = 0;
  for (int i = 0; i < c.nearby.length; i++) {
    final int n = missing.where((s) => _startsWord(f.nearby[i], s)).length;
    if (n > most) {
      most = n;
      best = c.nearby[i];
    }
  }
  return best;
}

/// Letters and digits, split at everything else — spaces, hyphens, dots, brackets ("Wymyślin-Zmyślice",
/// "przy ul. Testowej"). By Unicode class, because [fold] plains Polish letters only.
final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _wordsOf(String text) => [
  for (final String w in fold(text).split(_nonWord))
    if (w.isNotEmpty) w,
];

bool _startsWord(List<String> words, String stem) =>
    words.any((w) => w.startsWith(stem));

/// A cemetery's fields as words, each with how far it is from the card: the name and other names (0), the
/// locality and the district shown on the card (1), each nearby place (2).
class _Fields {
  _Fields(this.name, this.place, this.nearby);

  factory _Fields.of(BaseCemetery c) => _Fields(
    _wordsOf([c.name, ...c.otherNames].join(' ')),
    [_wordsOf(c.locality), if (c.district != null) _wordsOf(c.district!)],
    [for (final String p in c.nearby) _wordsOf(p)],
  );

  final List<String> name;
  final List<List<String>> place;
  final List<List<String>> nearby;

  List<List<String>> get onCard => [name, ...place];

  /// Every field with its distance, nearest first.
  List<({int reach, List<String> words})> get all => [
    (reach: 0, words: name),
    for (final List<String> p in place) (reach: 1, words: p),
    for (final List<String> p in nearby) (reach: 2, words: p),
  ];
}

/// A query as the order reads it: its words without punctuation, and their stems ([searchStems]' rule).
class _Query {
  _Query(String query) : words = _wordsOf(query) {
    stems = [
      for (final String w in words)
        w.length >= 5 ? w.substring(0, w.length - 2) : w,
    ];
  }

  final List<String> words;
  late final List<String> stems;

  /// Where this query's words are in [f] (D36). Called only for cemeteries D3 matched.
  _Rank rank(_Fields f) {
    final List<({int reach, List<String> words})> fields = f.all;
    final int whole = words
        .where((w) => fields.any((field) => field.words.contains(w)))
        .length;
    if (stems.isEmpty) return _Rank(whole, 3, 0);
    // Each stem's nearest field with a word it starts; a stem found only inside a word reaches 3.
    final List<int> nearest = [
      for (final String s in stems)
        fields.indexWhere((field) => _startsWord(field.words, s)),
    ];
    if (nearest.contains(-1)) return _Rank(whole, 3, stems.length);
    final int reach = [
      for (final int i in nearest) fields[i].reach,
    ].reduce((a, b) => a > b ? a : b);
    // Fields holding all the stems, taken greedily — each time the field that holds the most of those
    // left: one field when one holds them all, and a nearby place named in full is not split into the
    // first places its words start (measured: "Przykładowe …" + "Wymyśl…" before "Przykładowa Wymyślanka").
    final List<List<String>> reachable = [
      for (final field in fields)
        if (field.reach <= reach) field.words,
    ];
    final Set<String> left = {...stems};
    int spread = 0;
    while (left.isNotEmpty) {
      Set<String> most = const {};
      for (final List<String> words in reachable) {
        final Set<String> held = {
          for (final String s in left)
            if (_startsWord(words, s)) s,
        };
        if (held.length > most.length) most = held;
      }
      if (most.isEmpty) break;
      left.removeAll(most);
      spread++;
    }
    return _Rank(whole, reach, spread);
  }
}

/// The order of one result (D36): more whole words, then the nearer reach, then fewer fields.
class _Rank implements Comparable<_Rank> {
  const _Rank(this.whole, this.reach, this.spread);

  final int whole;
  final int reach;
  final int spread;

  @override
  int compareTo(_Rank other) {
    if (whole != other.whole) return other.whole.compareTo(whole);
    if (reach != other.reach) return reach.compareTo(other.reach);
    return spread.compareTo(other.spread);
  }
}

/// The bundled file comes sorted (the extract script sorts it), so one pass checks it; sorting 16
/// thousand names in the Polish alphabet at the first search took a third of the load (measured).
List<BaseCemetery> _sorted(List<BaseCemetery> cemeteries) {
  for (int i = 1; i < cemeteries.length; i++) {
    if (byShownName(cemeteries[i - 1], cemeteries[i]) > 0) {
      return [...cemeteries]..sort(byShownName);
    }
  }
  return List.unmodifiable(cemeteries);
}

/// The order of the results: by the name shown — an unnamed cemetery as "Cmentarz bez nazwy" — then
/// by place.
int byShownName(BaseCemetery a, BaseCemetery b) {
  final int c = polishCompare(shownName(a), shownName(b));
  return c != 0 ? c : polishCompare(a.place, b.place);
}

/// "Warszawa (Żoliborz) · woj. mazowieckie · rzymskokatolicki" — a line may break before a "·", never
/// after it, so no line ends on a separator (ui review).
String joinPlaceLine(Iterable<String> parts) => parts.join(' ·\u00A0');

String shownName(BaseCemetery c) =>
    c.name.isEmpty ? 'Cmentarz bez nazwy' : c.name;

/// How close a saved cemetery must be to count as this one: "Dodany" (ISSUE-015 D7).
const double addedWithinMetres = 100;

/// The id of the family's cemetery standing where [base] is, if any.
int? addedAs(BaseCemetery base, List<CemeterySummary> yours) {
  for (final CemeterySummary c in yours) {
    final GeoPoint? p = c.point;
    if (p != null && distanceMetres(p, base.point) < addedWithinMetres) {
      return c.id;
    }
  }
  return null;
}

/// Equirectangular distance — exact enough at the scale of a cemetery.
double distanceMetres(GeoPoint a, GeoPoint b) {
  const double toRad = math.pi / 180;
  final double x =
      (b.lon - a.lon) * toRad * math.cos((a.lat + b.lat) / 2 * toRad);
  final double y = (b.lat - a.lat) * toRad;
  return 6371000 * math.sqrt(x * x + y * y);
}
