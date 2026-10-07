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
      final String names = fold([c.name, ...c.otherNames].join(' | '));
      _names.add(names);
      _all.add(
        '$names | ${fold([c.locality, ?c.district, ...c.nearby].join(' | '))}',
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
  final List<String> _names = [];
  final List<String> _all = [];

  /// The cemeteries every word of [query] matches — without case, Polish letters or word endings, like
  /// the family's own (05_DESIGN/cmentarze.md D3). First those whose names match every word, then
  /// those found through a locality; each group stays in alphabetical order (ISSUE-015 D8).
  BaseResults search(String query, {int limit = 30}) {
    final List<String> stems = searchStems(query);
    if (stems.isEmpty) return (shown: const [], total: 0);
    final List<int> byName = [], byPlace = [];
    for (int i = 0; i < cemeteries.length; i++) {
      if (!stems.every(_all[i].contains)) continue;
      (stems.every(_names[i].contains) ? byName : byPlace).add(i);
    }
    return (
      shown: [
        for (final int i in [...byName, ...byPlace].take(limit)) cemeteries[i],
      ],
      total: byName.length + byPlace.length,
    );
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
