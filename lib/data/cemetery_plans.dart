import 'dart:convert';

import 'package:drift/drift.dart';

import 'cemeteries.dart';
import 'database.dart';

/// One polygon of a cemetery's outline: the outer ring and its holes (a relation in OpenStreetMap may have
/// several, e.g. two parts across a road).
class PlanArea {
  const PlanArea(this.outer, [this.holes = const []]);

  final List<GeoPoint> outer;
  final List<List<GeoPoint>> holes;
}

/// A path inside the outline (05_DESIGN/cmentarz.md, element 2; style-b.md rule 13): a main one is drawn
/// 4 dp wide, a side one 2 dp (ISSUE-027 D5).
class PlanPath {
  const PlanPath(this.points, {required this.main});

  final List<GeoPoint> points;
  final bool main;
}

/// A cemetery's stored plan (ADR-015): the outline and paths, or [PlanStatus.notInOsm] with neither.
class CemeteryPlan {
  const CemeteryPlan({
    required this.status,
    this.areas = const [],
    this.paths = const [],
    required this.fetchedAt,
    required this.server,
  });

  final PlanStatus status;
  final List<PlanArea> areas;
  final List<PlanPath> paths;
  final DateTime fetchedAt;
  final String server;
}

/// The cemetery's plan; null while it is not downloaded. A new value after every write to the plans.
Stream<CemeteryPlan?> watchCemeteryPlan(GrobingDatabase db, int cemeteryId) =>
    (db.select(db.cemeteryPlans)..where((p) => p.cemeteryId.equals(cemeteryId)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _plan(row));

/// Cemeteries with a point and no plan, in the order they were added — what the downloads go through
/// (ISSUE-027 D3). Without a point there is nothing to ask about (element 2a (e)).
Future<List<({int id, GeoPoint point})>> cemeteriesWithoutPlan(
  GrobingDatabase db,
) async {
  final List<QueryRow> rows = await db
      .customSelect(
        'SELECT c.id, c.center_lat, c.center_lon FROM cemeteries c '
        'WHERE c.center_lat IS NOT NULL AND c.center_lon IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM cemetery_plans p WHERE p.cemetery_id = c.id) '
        'ORDER BY c.id',
        readsFrom: {db.cemeteries, db.cemeteryPlans},
      )
      .get();
  return [
    for (final QueryRow r in rows)
      (
        id: r.read<int>('id'),
        point: GeoPoint(
          r.read<double>('center_lat'),
          r.read<double>('center_lon'),
        ),
      ),
  ];
}

/// Keeps a downloaded plan. [forPoint] is the point it was asked for: when the cemetery's point changed (or
/// it was deleted) while the download ran, the plan belongs to no cemetery and nothing is written. Returns
/// whether it was written.
Future<bool> savePlan(
  GrobingDatabase db,
  int cemeteryId, {
  required GeoPoint forPoint,
  required List<PlanArea> areas,
  required List<PlanPath> paths,
  required String server,
  DateTime? now,
}) => _save(
  db,
  cemeteryId,
  forPoint,
  CemeteryPlansCompanion.insert(
    cemeteryId: Value(cemeteryId),
    status: PlanStatus.ok,
    outline: Value(encodeAreas(areas)),
    paths: Value(encodePaths(paths)),
    fetchedAt: now ?? DateTime.now(),
    server: server,
  ),
);

/// Keeps that OpenStreetMap has no outline around [forPoint] (element 2a (d)), on the same terms as
/// [savePlan].
Future<bool> saveNotInOsm(
  GrobingDatabase db,
  int cemeteryId, {
  required GeoPoint forPoint,
  required String server,
  DateTime? now,
}) => _save(
  db,
  cemeteryId,
  forPoint,
  CemeteryPlansCompanion.insert(
    cemeteryId: Value(cemeteryId),
    status: PlanStatus.notInOsm,
    fetchedAt: now ?? DateTime.now(),
    server: server,
  ),
);

Future<bool> _save(
  GrobingDatabase db,
  int cemeteryId,
  GeoPoint forPoint,
  CemeteryPlansCompanion row,
) => db.transaction(() async {
  final Cemetery? cemetery = await (db.select(
    db.cemeteries,
  )..where((c) => c.id.equals(cemeteryId))).getSingleOrNull();
  if (cemetery == null ||
      cemetery.centerLat != forPoint.lat ||
      cemetery.centerLon != forPoint.lon) {
    return false;
  }
  await db.into(db.cemeteryPlans).insertOnConflictUpdate(row);
  return true;
});

CemeteryPlan _plan(CemeteryPlanRow row) => CemeteryPlan(
  status: row.status,
  areas: row.outline == null ? const [] : decodeAreas(row.outline!),
  paths: row.paths == null ? const [] : decodePaths(row.paths!),
  fetchedAt: row.fetchedAt,
  server: row.server,
);

// The JSON of the two columns: every line a flat list [lat, lon, lat, lon, …], rounded to 6 decimals —
// about 0.1 m, finer than any path is drawn — which keeps a large cemetery near 70 KB (measured before
// ISSUE-027). Outline: [{"o": ring, "h": [ring, …]}, …]. Paths: {"main": [line, …], "side": [line, …]}.

String encodeAreas(List<PlanArea> areas) => jsonEncode([
  for (final PlanArea a in areas)
    {
      'o': _flat(a.outer),
      if (a.holes.isNotEmpty)
        'h': [for (final List<GeoPoint> h in a.holes) _flat(h)],
    },
]);

List<PlanArea> decodeAreas(String json) => [
  for (final Object? a in jsonDecode(json) as List<Object?>)
    if (a case final Map<String, Object?> area)
      PlanArea(_points(area['o']), [
        for (final Object? h in (area['h'] as List<Object?>?) ?? const [])
          _points(h),
      ]),
];

String encodePaths(List<PlanPath> paths) => jsonEncode({
  'main': [
    for (final PlanPath p in paths)
      if (p.main) _flat(p.points),
  ],
  'side': [
    for (final PlanPath p in paths)
      if (!p.main) _flat(p.points),
  ],
});

List<PlanPath> decodePaths(String json) {
  final Map<String, Object?> map = jsonDecode(json) as Map<String, Object?>;
  return [
    for (final Object? line in (map['main'] as List<Object?>?) ?? const [])
      PlanPath(_points(line), main: true),
    for (final Object? line in (map['side'] as List<Object?>?) ?? const [])
      PlanPath(_points(line), main: false),
  ];
}

/// One line or ring as the plan stores it — a flat list, 6 decimals — for the author's sectors too (ISSUE-028).
String encodeRing(List<GeoPoint> points) => jsonEncode(_flat(points));

List<GeoPoint> decodeRing(String json) => _points(jsonDecode(json));

List<double> _flat(List<GeoPoint> points) => [
  for (final GeoPoint p in points) ...[_round(p.lat), _round(p.lon)],
];

double _round(double v) => (v * 1e6).roundToDouble() / 1e6;

List<GeoPoint> _points(Object? flat) {
  final List<Object?> values = flat! as List<Object?>;
  return [
    for (int i = 0; i + 1 < values.length; i += 2)
      GeoPoint(
        (values[i]! as num).toDouble(),
        (values[i + 1]! as num).toDouble(),
      ),
  ];
}
