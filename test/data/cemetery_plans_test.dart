import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';

// ISSUE-027 (ADR-015) — a cemetery's plan in the database: kept, read back, deleted with a new point, never
// written for a point the cemetery no longer has. Invented geometry and cemeteries only (family-data.md).

const GeoPoint _point = GeoPoint(51.5, 19.5);

final List<PlanArea> _areas = [
  const PlanArea(
    [
      GeoPoint(51.498, 19.498),
      GeoPoint(51.498, 19.502),
      GeoPoint(51.502, 19.502),
      GeoPoint(51.502, 19.498),
      GeoPoint(51.498, 19.498),
    ],
    [
      [
        GeoPoint(51.4999, 19.4999),
        GeoPoint(51.4999, 19.5001),
        GeoPoint(51.5001, 19.5001),
        GeoPoint(51.4999, 19.4999),
      ],
    ],
  ),
];

const List<PlanPath> _paths = [
  PlanPath([GeoPoint(51.499, 19.5), GeoPoint(51.501, 19.5)], main: true),
  PlanPath([
    GeoPoint(51.5, 19.499),
    GeoPoint(51.5, 19.5004),
    GeoPoint(51.5, 19.501),
  ], main: false),
];

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> cemetery({GeoPoint? point = _point}) =>
      addCemetery(db, name: 'Cmentarz Wymyślony', point: point);

  test(
    'the JSON of both columns round-trips, rounded to 6 places (about 0.1 m)',
    () {
      final List<PlanArea> areas = decodeAreas(encodeAreas(_areas));
      expect(areas.single.outer, _areas.single.outer);
      expect(areas.single.holes.single, _areas.single.holes.single);
      final List<PlanPath> paths = decodePaths(encodePaths(_paths));
      expect(paths.map((p) => (p.main, p.points.length)), [
        (true, 2),
        (false, 3),
      ]);
      final List<PlanArea> rounded = decodeAreas(
        encodeAreas([
          const PlanArea([GeoPoint(51.123456789, 19.987654321)]),
        ]),
      );
      expect(rounded.single.outer.single, const GeoPoint(51.123457, 19.987654));
      // Coordinates only: no names, no tags of OpenStreetMap.
      expect(encodeAreas(_areas), isNot(contains('name')));
    },
  );

  test(
    'AC-1 — a downloaded plan is kept and read back with its server; "not in OpenStreetMap" is kept '
    'with no geometry',
    () async {
      final int id = await cemetery();
      expect(await watchCemeteryPlan(db, id).first, isNull);
      expect(
        await savePlan(
          db,
          id,
          forPoint: _point,
          areas: _areas,
          paths: _paths,
          server: 'overpass.example',
          now: DateTime(2026, 10, 12, 12),
        ),
        isTrue,
      );
      final CemeteryPlan plan = (await watchCemeteryPlan(db, id).first)!;
      expect(plan.status, PlanStatus.ok);
      expect(plan.areas.single.outer.length, 5);
      expect(plan.paths.length, 2);
      expect(plan.server, 'overpass.example');
      expect(plan.fetchedAt, DateTime(2026, 10, 12, 12));

      final int other = await cemetery(point: const GeoPoint(50.5, 18.5));
      await saveNotInOsm(
        db,
        other,
        forPoint: const GeoPoint(50.5, 18.5),
        server: 'overpass.example',
      );
      final CemeteryPlan none = (await watchCemeteryPlan(db, other).first)!;
      expect(none.status, PlanStatus.notInOsm);
      expect(none.areas, isEmpty);
      expect(none.paths, isEmpty);
    },
  );

  test(
    'a plan asked for an old point is not written: the cemetery moved (or went) while it was downloaded',
    () async {
      final int id = await cemetery();
      await updateCemetery(
        db,
        id,
        name: 'Cmentarz Wymyślony',
        point: const GeoPoint(51.6, 19.6),
      );
      expect(
        await savePlan(
          db,
          id,
          forPoint: _point,
          areas: _areas,
          paths: _paths,
          server: 'overpass.example',
        ),
        isFalse,
      );
      expect(await watchCemeteryPlan(db, id).first, isNull);
      expect(
        await saveNotInOsm(db, 999, forPoint: _point, server: 'x'),
        isFalse,
      );
    },
  );

  test(
    'D3 — a new point deletes the plan in the same write; the same point, or only a new name, keeps it',
    () async {
      final int id = await cemetery();
      await savePlan(
        db,
        id,
        forPoint: _point,
        areas: _areas,
        paths: _paths,
        server: 'overpass.example',
      );
      await updateCemetery(
        db,
        id,
        name: 'Cmentarz Wymyślony Nowy',
        locality: 'Wymyślin',
        point: _point,
      );
      expect(await watchCemeteryPlan(db, id).first, isNotNull);
      await updateCemetery(
        db,
        id,
        name: 'Cmentarz Wymyślony Nowy',
        point: const GeoPoint(51.51, 19.51),
      );
      expect(await watchCemeteryPlan(db, id).first, isNull);

      await savePlan(
        db,
        id,
        forPoint: const GeoPoint(51.51, 19.51),
        areas: _areas,
        paths: _paths,
        server: 'overpass.example',
      );
      // "Zapisz bez punktu": no point, no plan — 2a (e).
      await updateCemetery(db, id, name: 'Cmentarz Wymyślony Nowy');
      expect(await watchCemeteryPlan(db, id).first, isNull);
    },
  );

  test(
    'D3 — what the downloads go through: cemeteries with a point and no plan, in the order added',
    () async {
      final int a = await cemetery();
      await cemetery(point: null);
      final int c = await cemetery(point: const GeoPoint(50.5, 18.5));
      final int d = await cemetery(point: const GeoPoint(52.5, 20.5));
      await saveNotInOsm(
        db,
        d,
        forPoint: const GeoPoint(52.5, 20.5),
        server: 'x',
      );
      expect((await cemeteriesWithoutPlan(db)).map((x) => (x.id, x.point)), [
        (a, _point),
        (c, const GeoPoint(50.5, 18.5)),
      ]);
    },
  );
}
