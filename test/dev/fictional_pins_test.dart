import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/dev/fictional_data.dart';
import 'package:grobing/net/osm_plan.dart';

// ISSUE-027 — the made-up pins of the debug build: until US-008 the only way to see the candles of a
// cemetery's map. Only on cemeteries with a plan, inside its outline, every third grave left without one.
// Invented cemeteries, people and geometry only (family-data.md).
void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const List<PlanArea> areas = [
    PlanArea([
      GeoPoint(51.498, 19.498),
      GeoPoint(51.498, 19.502),
      GeoPoint(51.502, 19.502),
      GeoPoint(51.502, 19.498),
      GeoPoint(51.498, 19.498),
    ]),
  ];

  Future<int> cemeteryWith(int graves, {required bool plan}) async {
    const GeoPoint point = GeoPoint(51.5, 19.5);
    final int id = await addCemetery(
      db,
      name: 'Cmentarz Wymyślony',
      point: point,
    );
    if (plan) {
      await savePlan(
        db,
        id,
        forPoint: point,
        areas: areas,
        paths: const [],
        server: 'x',
      );
    }
    for (int i = 0; i < graves; i++) {
      await addPersonToNewGrave(
        db,
        cemeteryId: id,
        entry: PersonEntry(givenNames: 'Jan $i', surname: 'Wymyślony'),
      );
    }
    return id;
  }

  test(
    'pins inside the outline for two of every three graves, with each source the pin\'s line can say — the photo, '
    'GPS with its accuracy, the plan (ISSUE-029) — and a date; a cemetery without a plan gets none',
    () async {
      final int withPlan = await cemeteryWith(6, plan: true);
      final int without = await cemeteryWith(2, plan: false);

      await addFictionalPins(db);

      final List<Grave> pinned = await (db.select(
        db.graves,
      )..where((g) => g.cemeteryId.equals(withPlan))).get();
      expect(pinned.map((g) => g.lat != null), [
        true,
        true,
        false,
        true,
        true,
        false,
      ]);
      for (final Grave g in pinned.where((g) => g.lat != null)) {
        expect(insideAreas(GeoPoint(g.lat!, g.lon!), areas), isTrue);
        expect(g.positionRecordedAt, isNotNull);
      }
      expect(
        pinned
            .where((g) => g.lat != null)
            .map((g) => (g.positionSource, g.positionAccuracyM)),
        [
          (PositionSource.satellite, null),
          (PositionSource.gps, 6.0),
          (PositionSource.gps, 6.0),
          (PositionSource.plan, null),
        ],
      );
      final List<Grave> none = await (db.select(
        db.graves,
      )..where((g) => g.cemeteryId.equals(without))).get();
      expect(none.map((g) => g.lat), everyElement(isNull));
    },
  );
}
