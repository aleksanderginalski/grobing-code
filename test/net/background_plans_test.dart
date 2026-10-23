import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/background.dart';
import 'package:grobing/backup/restore_swap.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/net/background_plans.dart';
import 'package:grobing/net/overpass_plan_source.dart';

// ISSUE-052 B1 — the plans' downloads with the app closed (05_DESIGN/cmentarz.md D40; `PlanWorker.kt` runs
// this in a headless engine). One run: the missing plans, read again before each cemetery, the same writes as
// the app; done / again / retry for the worker; a stored plan asks for a background backup. A fake source: no
// network; invented cemeteries and geometry only (family-data.md).

const List<PlanArea> _areas = [
  PlanArea([
    GeoPoint(51.498, 19.498),
    GeoPoint(51.498, 19.502),
    GeoPoint(51.502, 19.502),
    GeoPoint(51.498, 19.498),
  ]),
];

const PlanResult _found = PlanFound(
  areas: _areas,
  paths: [],
  server: 'overpass.example',
);

class _Source implements PlanSource {
  _Source(this.answer);

  PlanResult Function(GeoPoint point) answer;
  final List<GeoPoint> asked = [];

  /// Run before each answer — to write in the middle of a run, as the app may.
  Future<void> Function()? before;

  @override
  Future<PlanResult> fetch(GeoPoint point) async {
    asked.add(point);
    await before?.call();
    return answer(point);
  }
}

class _Backups implements BackgroundBackups {
  int requests = 0;

  @override
  Future<void> request() async => requests++;
}

GrobingDatabase _open(File file) =>
    GrobingDatabase(NativeDatabase(file, setup: configureConnection));

void main() {
  // The app's connection and the run's, as on the phone; no executor is shared.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late DataLocation location;
  late int a, b;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_background_plans_test');
    location = DataLocation.inDirectory(tmp);
    final GrobingDatabase db = _open(location.databaseFile);
    a = await addCemetery(
      db,
      name: 'Cmentarz Wymyślony',
      point: const GeoPoint(51.5, 19.5),
    );
    b = await addCemetery(
      db,
      name: 'Cmentarz Testowy',
      point: const GeoPoint(51.6, 19.5),
    );
    // Without a point there is nothing to ask about (2a (e)).
    await addCemetery(db, name: 'Cmentarz Próbny');
    await db.close();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<int, PlanStatus>> stored() async {
    final GrobingDatabase db = _open(location.databaseFile);
    try {
      return {
        for (final CemeteryPlanRow r in await db.select(db.cemeteryPlans).get())
          r.cemeteryId: r.status,
      };
    } finally {
      await db.close();
    }
  }

  test(
    'B1: every missing plan downloaded and stored as the app stores it — done, and a backup asked for once',
    () async {
      final _Source source = _Source(
        (p) => p.lat == 51.5
            ? _found
            : const PlanNotInOsm(server: 'overpass.example'),
      );
      final _Backups backups = _Backups();
      final BackgroundRun run = await runBackgroundPlans(
        dataDir: tmp,
        source: source,
        backups: backups,
      );
      expect(run.outcome, BackgroundOutcome.done);
      expect(source.asked.map((p) => p.lat), [51.5, 51.6]);
      expect(await stored(), {a: PlanStatus.ok, b: PlanStatus.notInOsm});
      expect(backups.requests, 1);
    },
  );

  test(
    'B1: a server that fails for one — the others still tried; retry, so WorkManager waits and tries again',
    () async {
      final _Source source = _Source(
        (p) => p.lat == 51.5 ? const PlanServerError() : _found,
      );
      final _Backups backups = _Backups();
      final BackgroundRun run = await runBackgroundPlans(
        dataDir: tmp,
        source: source,
        backups: backups,
      );
      expect(run.outcome, BackgroundOutcome.retry);
      expect(source.asked, hasLength(2));
      expect(await stored(), {b: PlanStatus.ok});
      expect(backups.requests, 1);
    },
  );

  test('B1: no network — retry at once, nothing stored, no backup', () async {
    final _Source source = _Source((_) => const PlanOffline());
    final _Backups backups = _Backups();
    final BackgroundRun run = await runBackgroundPlans(
      dataDir: tmp,
      source: source,
      backups: backups,
    );
    expect(run.outcome, BackgroundOutcome.retry);
    expect(source.asked, hasLength(1));
    expect(await stored(), isEmpty);
    expect(backups.requests, 0);
  });

  test(
    'B1: no cemetery is started after startNoLaterThan — the run that stored a plan ends with "again", the '
    'next one takes the rest',
    () async {
      DateTime now = DateTime.utc(2026, 10, 22, 12);
      final _Source source = _Source((_) {
        now = now.add(const Duration(minutes: 2));
        return _found;
      });
      final BackgroundRun first = await runBackgroundPlans(
        dataDir: tmp,
        source: source,
        clock: () => now,
      );
      expect(first.outcome, BackgroundOutcome.again);
      expect(await stored(), {a: PlanStatus.ok});

      final BackgroundRun second = await runBackgroundPlans(
        dataDir: tmp,
        source: source,
        clock: () => now,
      );
      expect(second.outcome, BackgroundOutcome.done);
      expect(await stored(), {a: PlanStatus.ok, b: PlanStatus.ok});
    },
  );

  test(
    'B1: the missing plans are read again before each cemetery — one the app stored meanwhile is not asked for',
    () async {
      final _Source source = _Source((_) => _found);
      source.before = () async {
        if (source.asked.length != 1) return;
        final GrobingDatabase app = _open(location.databaseFile);
        await savePlan(
          app,
          b,
          forPoint: const GeoPoint(51.6, 19.5),
          areas: _areas,
          paths: const [],
          server: 'overpass.example',
        );
        await app.close();
      };
      final BackgroundRun run = await runBackgroundPlans(
        dataDir: tmp,
        source: source,
      );
      expect(run.outcome, BackgroundOutcome.done);
      expect(source.asked.map((p) => p.lat), [51.5]);
      expect(await stored(), {a: PlanStatus.ok, b: PlanStatus.ok});
    },
  );

  test(
    'B1: a restore in progress or a database at another schema version — done without asking: they belong to '
    'the app\'s start',
    () async {
      final _Source source = _Source((_) => _found);
      File('${tmp.path}/$restoreMarkerName').writeAsStringSync('{}');
      expect(
        (await runBackgroundPlans(dataDir: tmp, source: source)).outcome,
        BackgroundOutcome.done,
      );
      File('${tmp.path}/$restoreMarkerName').deleteSync();
      expect(
        (await runBackgroundPlans(
          dataDir: tmp,
          source: source,
          schemaVersion: GrobingDatabase.currentSchemaVersion + 1,
        )).outcome,
        BackgroundOutcome.done,
      );
      expect(source.asked, isEmpty);
      expect(await stored(), isEmpty);
    },
  );

  test('B1: nothing missing — done without asking', () async {
    final _Source source = _Source((_) => _found);
    await runBackgroundPlans(dataDir: tmp, source: source);
    source.asked.clear();
    final _Backups backups = _Backups();
    final BackgroundRun run = await runBackgroundPlans(
      dataDir: tmp,
      source: source,
      backups: backups,
    );
    expect(run.outcome, BackgroundOutcome.done);
    expect(source.asked, isEmpty);
    expect(backups.requests, 0);
  });
}
