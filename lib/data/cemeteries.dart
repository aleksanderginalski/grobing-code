import 'package:drift/drift.dart';

import 'database.dart';

/// A point on the map, in degrees (WGS 84). The data layer's own type, so it does not depend on the
/// map package.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

/// One cemetery as the home screen shows it (05_DESIGN/cmentarze.md, elements 4, 6, 11).
class CemeterySummary {
  const CemeterySummary({
    required this.id,
    required this.name,
    this.locality,
    this.point,
    required this.graveCount,
    required this.personCount,
  });

  final int id;
  final String name;
  final String? locality;

  /// Null: the cemetery has no candle on the map, only the search finds it (ISSUE-014 AC-2).
  final GeoPoint? point;
  final int graveCount;

  /// Distinct people with a burial in a grave of this cemetery: a person whose sources disagree on the
  /// grave (ADR-006 D2) counts once (05_DESIGN/cmentarze.md D13).
  final int personCount;
}

/// The family's cemeteries with their counts, in the order they were added; a new value after every
/// write to cemeteries, graves or burials.
Stream<List<CemeterySummary>> watchCemeteries(GrobingDatabase db) => db
    .customSelect(
      'SELECT c.id, c.name, c.locality, c.center_lat, c.center_lon, '
      '(SELECT COUNT(*) FROM graves g WHERE g.cemetery_id = c.id) AS grave_count, '
      '(SELECT COUNT(DISTINCT b.person_id) FROM burials b '
      'JOIN graves g ON g.id = b.grave_id WHERE g.cemetery_id = c.id) AS person_count '
      'FROM cemeteries c ORDER BY c.id',
      readsFrom: {db.cemeteries, db.graves, db.burials},
    )
    .watch()
    .map(
      (rows) => [
        for (final QueryRow r in rows)
          CemeterySummary(
            id: r.read<int>('id'),
            name: r.read<String>('name'),
            locality: r.readNullable<String>('locality'),
            point: _point(
              r.readNullable<double>('center_lat'),
              r.readNullable<double>('center_lon'),
            ),
            graveCount: r.read<int>('grave_count'),
            personCount: r.read<int>('person_count'),
          ),
      ],
    );

GeoPoint? _point(double? lat, double? lon) =>
    lat == null || lon == null ? null : GeoPoint(lat, lon);

// Writes go through drift's own API, so they notify `tableUpdates` and ask for a background backup
// (ISSUE-010). A cemetery is a place, not a fact about a person: it has no claims (FR-001 covers dates,
// relations and burials).

/// Adds a cemetery; returns its id. [name] must not be blank; a blank [locality] is stored as none.
Future<int> addCemetery(
  GrobingDatabase db, {
  required String name,
  String? locality,
  GeoPoint? point,
}) => db
    .into(db.cemeteries)
    .insert(
      CemeteriesCompanion.insert(
        name: _name(name),
        locality: Value(_blankToNull(locality)),
        centerLat: Value(point?.lat),
        centerLon: Value(point?.lon),
      ),
    );

/// Corrects a cemetery's name, locality and point (05_DESIGN/cmentarze.md, element 8). A null [point]
/// takes the cemetery off the map ("Zapisz bez punktu").
Future<void> updateCemetery(
  GrobingDatabase db,
  int id, {
  required String name,
  String? locality,
  GeoPoint? point,
}) async {
  final int updated =
      await (db.update(db.cemeteries)..where((c) => c.id.equals(id))).write(
        CemeteriesCompanion(
          name: Value(_name(name)),
          locality: Value(_blankToNull(locality)),
          centerLat: Value(point?.lat),
          centerLon: Value(point?.lon),
        ),
      );
  if (updated != 1) throw StateError('No cemetery with id $id');
}

String _name(String name) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'is blank');
  return trimmed;
}

String? _blankToNull(String? s) {
  final String? trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
