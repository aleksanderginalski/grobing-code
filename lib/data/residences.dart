import 'package:drift/drift.dart';

import 'cemeteries.dart' show GeoPoint;
import 'database.dart';
import 'graves.dart' show PartialDate, QualifiedDate, watchTables;

// Where and when a person lived (ISSUE-042, ADR-020; 05_DESIGN/zamieszkanie.md): read in the order of the
// years (D4), written with the person's entry — in its transaction, at "Zapisz" (D5).

/// A residence's place: a country of the list, or a locality of it — today's, with its point (N2: the name
/// of the time is [Residence.nameThen]).
class ResidencePlace {
  const ResidencePlace.country({
    required this.countryCode,
    required this.countryName,
    required this.point,
  }) : name = countryName,
       unit = null,
       geonamesId = null;

  const ResidencePlace.locality({
    required this.name,
    this.unit,
    required this.countryCode,
    required this.countryName,
    required this.point,
    required int this.geonamesId,
  });

  /// The locality's name today, or the country's.
  final String name;

  /// "woj. testowe" — a locality's unit of the first order, when the list has one.
  final String? unit;
  final String countryCode;
  final String countryName;

  /// The country's label point or the locality's centre.
  final GeoPoint point;

  /// The locality's id in GeoNames; null for a country.
  final int? geonamesId;

  bool get isCountry => geonamesId == null;

  /// One place, whatever was written about it: the same country, or the same locality of the list.
  @override
  bool operator ==(Object other) =>
      other is ResidencePlace &&
      other.countryCode == countryCode &&
      other.geonamesId == geonamesId;

  @override
  int get hashCode => Object.hash(countryCode, geonamesId);
}

/// One residence — as read, and as the form keeps it until "Zapisz" ([id] null: not written yet).
class Residence {
  const Residence({
    this.id,
    this.from,
    this.to,
    required this.place,
    this.nameThen,
    this.address,
  });

  final int? id;

  /// The start and the end, each exact or about (D3); either may be missing.
  final QualifiedDate? from;
  final QualifiedDate? to;
  final ResidencePlace place;

  /// The place's name at the time, when it was different (N2).
  final String? nameThen;

  /// "ul. Przykładowa 3" — only in a locality (A1).
  final String? address;

  PlaceLevel get level => place.isCountry
      ? PlaceLevel.country
      : address == null
      ? PlaceLevel.locality
      : PlaceLevel.address;

  /// Everything written, the place's words too — what decides whether "Zapisz" changes the row.
  bool sameAs(Residence o) =>
      o.from == from &&
      o.to == to &&
      o.place == place &&
      o.place.name == place.name &&
      o.place.unit == place.unit &&
      o.place.countryName == place.countryName &&
      o.place.point == place.point &&
      o.nameThen == nameThen &&
      o.address == address;
}

/// The qualifiers a residence's date takes (D3): a stay is a period, `FROM … TO …` in GEDCOM 7 — "przed",
/// "po" and "między" are kinds of one unknown date, not of a period's end.
const List<DateQualifier> stayQualifiers = [
  DateQualifier.exact,
  DateQualifier.about,
];

/// Whether [to] is not before [from], as far as both say — the same year is fine ("1945 – 1945"), and a
/// month or a day decides only when both have it.
bool notBefore(PartialDate from, PartialDate to) {
  if (to.year != from.year) return to.year > from.year;
  if (from.month == null || to.month == null) return true;
  if (to.month != from.month) return to.month! > from.month!;
  if (from.day == null || to.day == null) return true;
  return to.day! >= from.day!;
}

/// [residences] in the order of the years (D4): by the start, without one by the end; without either at
/// the end — those, and residences of the same years, in the order they were entered.
List<Residence> inStayOrder(Iterable<Residence> residences) {
  final List<(int, Residence)> indexed = residences.indexed.toList();
  int key(PartialDate d) =>
      d.year * 10000 + (d.month ?? 0) * 100 + (d.day ?? 0);
  indexed.sort((a, b) {
    final PartialDate? x = (a.$2.from ?? a.$2.to)?.from;
    final PartialDate? y = (b.$2.from ?? b.$2.to)?.from;
    if (x == null || y == null) {
      if (x != y) return x == null ? 1 : -1;
    } else if (key(x) != key(y)) {
      return key(x).compareTo(key(y));
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final (int, Residence) e in indexed) e.$2];
}

/// The end each of [inOrder] (residences in the order of the years, [inStayOrder]) takes from the next one
/// (zamieszkanie.md v1.2, D12 — the author at stop #2): a residence with a start and without an end ends where
/// the nearest one with a later start begins, with its qualifier and precision. A typed end wins, and a
/// residence without a start, or with no later start after it, gets none. Worked out when read, never
/// written: the database keeps what the source said.
List<QualifiedDate?> impliedEnds(List<Residence> inOrder) => [
  for (final (int i, Residence r) in inOrder.indexed)
    if (r.to != null || r.from == null)
      null
    else
      _nextStart(r.from!.from, inOrder.skip(i + 1)),
];

QualifiedDate? _nextStart(PartialDate start, Iterable<Residence> after) {
  for (final Residence next in after) {
    final QualifiedDate? from = next.from;
    if (from != null && _startKey(from.from) > _startKey(start)) return from;
  }
  return null;
}

int _startKey(PartialDate d) =>
    d.year * 10000 + (d.month ?? 0) * 100 + (d.day ?? 0);

/// [personId]'s residences in the order of the years (D4); among the same years, as entered.
Future<List<Residence>> residencesOf(GrobingDatabase db, int personId) async =>
    inStayOrder([
      for (final ResidenceRow r
          in await (db.select(db.residences)
                ..where((r) => r.personId.equals(personId))
                ..orderBy([(r) => OrderingTerm.asc(r.id)]))
              .get())
        _residence(r),
    ]);

/// Everyone's residences, each person's in the order of the years (D4) — the migration map (ISSUE-045,
/// 05_DESIGN/mapa-migracji.md): who lived where in a year. A person without residences is not in it.
Future<Map<int, List<Residence>>> allResidences(GrobingDatabase db) async {
  final Map<int, List<Residence>> byPerson = {};
  for (final ResidenceRow r in await (db.select(
    db.residences,
  )..orderBy([(r) => OrderingTerm.asc(r.id)])).get()) {
    (byPerson[r.personId] ??= []).add(_residence(r));
  }
  return {
    for (final MapEntry<int, List<Residence>> e in byPerson.entries)
      e.key: inStayOrder(e.value),
  };
}

/// [allResidences] anew after every write to the residences (`watchTables` in graves.dart).
Stream<Map<int, List<Residence>>> watchAllResidences(GrobingDatabase db) =>
    watchTables(db, 'all_residences', {db.residences}, () => allResidences(db));

/// Up to [limit] different places of the residences written, the newest first — "Ostatnio wybrane" of the
/// choice of a place (D6): a family lived in a few of the same places.
Future<List<ResidencePlace>> recentPlaces(
  GrobingDatabase db, {
  int limit = 5,
}) async {
  final List<ResidencePlace> places = [];
  // Read in pages: the newest residences are usually enough.
  for (int offset = 0; places.length < limit; offset += 50) {
    final List<ResidenceRow> rows =
        await (db.select(db.residences)
              ..orderBy([(r) => OrderingTerm.desc(r.id)])
              ..limit(50, offset: offset))
            .get();
    for (final ResidenceRow r in rows) {
      final ResidencePlace p = _residence(r).place;
      if (!places.contains(p)) places.add(p);
      if (places.length == limit) break;
    }
    if (rows.length < 50) break;
  }
  return places;
}

/// Makes [personId]'s residences [residences]: rows not in it go, rows that changed are updated, new ones
/// (without an id) are inserted. Run inside the person's write (`graves.dart` → `AlsoWrite`), so a failed
/// "Zapisz" leaves none of it (D5). Throws [ArgumentError] for a residence the screen would not let through.
Future<void> writeResidences(
  GrobingDatabase db,
  int personId,
  List<Residence> residences,
) => db.transaction(() async {
  for (final Residence r in residences) {
    _check(r);
  }
  final Map<int, Residence> stored = {
    for (final Residence r in await residencesOf(db, personId)) r.id!: r,
  };
  final Set<int> kept = {for (final Residence r in residences) ?r.id};
  final Set<int> unknown = kept.difference(stored.keys.toSet());
  if (unknown.isNotEmpty) {
    throw ArgumentError('Residences $unknown are not of person $personId');
  }
  await (db.delete(
    db.residences,
  )..where((r) => r.personId.equals(personId) & r.id.isNotIn(kept))).go();
  for (final Residence r in residences) {
    final int? id = r.id;
    if (id == null) {
      await db.into(db.residences).insert(_companion(personId, r));
    } else if (!stored[id]!.sameAs(r)) {
      await (db.update(
        db.residences,
      )..where((row) => row.id.equals(id))).write(_companion(personId, r));
    }
  }
});

void _check(Residence r) {
  for (final QualifiedDate? d in [r.from, r.to]) {
    if (d != null && (!stayQualifiers.contains(d.qualifier) || d.to != null)) {
      throw ArgumentError('A residence date is exact or about: $d');
    }
  }
  if (r.from case final QualifiedDate from) {
    if (r.to case final QualifiedDate to when !notBefore(from.from, to.from)) {
      throw ArgumentError('The end of a residence is before its start');
    }
  }
  if (r.address != null && r.place.isCountry) {
    throw ArgumentError('An address needs a locality');
  }
}

ResidencesCompanion _companion(int personId, Residence r) =>
    ResidencesCompanion(
      personId: Value(personId),
      fromQualifier: Value(r.from?.qualifier),
      fromYear: Value(r.from?.from.year),
      fromMonth: Value(r.from?.from.month),
      fromDay: Value(r.from?.from.day),
      toQualifier: Value(r.to?.qualifier),
      toYear: Value(r.to?.from.year),
      toMonth: Value(r.to?.from.month),
      toDay: Value(r.to?.from.day),
      level: Value(r.level),
      placeName: Value(r.place.name),
      placeUnit: Value(r.place.unit),
      countryCode: Value(r.place.countryCode),
      countryName: Value(r.place.countryName),
      lat: Value(r.place.point.lat),
      lon: Value(r.place.point.lon),
      geonamesId: Value(r.place.geonamesId),
      nameThen: Value(r.nameThen),
      address: Value(r.address),
    );

Residence _residence(ResidenceRow r) {
  QualifiedDate? date(DateQualifier? q, int? year, int? month, int? day) =>
      year == null
      ? null
      : QualifiedDate(q ?? DateQualifier.exact, PartialDate(year, month, day));
  final GeoPoint point = GeoPoint(r.lat, r.lon);
  return Residence(
    id: r.id,
    from: date(r.fromQualifier, r.fromYear, r.fromMonth, r.fromDay),
    to: date(r.toQualifier, r.toYear, r.toMonth, r.toDay),
    place: r.geonamesId == null
        ? ResidencePlace.country(
            countryCode: r.countryCode,
            countryName: r.countryName,
            point: point,
          )
        : ResidencePlace.locality(
            name: r.placeName,
            unit: r.placeUnit,
            countryCode: r.countryCode,
            countryName: r.countryName,
            point: point,
            geonamesId: r.geonamesId!,
          ),
    nameThen: r.nameThen,
    address: r.address,
  );
}
