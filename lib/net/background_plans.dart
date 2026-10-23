import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../backup/background.dart';
import '../backup/restore_swap.dart';
import '../data/cemeteries.dart' show GeoPoint;
import '../data/cemetery_plans.dart';
import '../data/database.dart';
import 'overpass_plan_source.dart';

/// One run of the background downloads of cemeteries' plans (ISSUE-052 B1) in the worker's engine
/// (`PlanWorker.kt`): the author adds the cemeteries at home and closes the app, and the plans come once
/// the phone has a network (05_DESIGN/cmentarz.md D40). The same downloads as in the app
/// ([OverpassPlanSource], [savePlan]); the app may fetch the same cemetery meanwhile — the plan's row is
/// overwritten with the same plan, which costs one request and breaks nothing.
///
/// 1. a restore marker, or a database at another schema version → done: finishing a restore and migrating
///    belong to the app's start, which asks for the plans again when it leaves;
/// 2. the missing plans, read again before each cemetery, one after another; none is started after
///    [startNoLaterThan], so the run ends before WorkManager's ten minutes even when the last one takes
///    the source's whole deadline;
/// 3. nothing missing → done, or retry when a server failed this run; time up with cemeteries left →
///    again at once when the run got anywhere, otherwise retry (WorkManager's growing waits); no network →
///    retry.
///
/// A stored plan is part of the backup (ADR-015), so a run that stored one asks for a background backup.
Future<BackgroundRun> runBackgroundPlans({
  required Directory dataDir,
  PlanSource? source,
  BackgroundBackups? backups,
  int schemaVersion = GrobingDatabase.currentSchemaVersion,
  GrobingDatabase Function(File file) openDatabase = GrobingDatabase.atFile,
  Duration startNoLaterThan = const Duration(minutes: 1),
  DateTime Function()? clock,
}) async {
  final DateTime Function() now = clock ?? DateTime.now;
  final DateTime started = now();
  final DataLocation location = DataLocation.inDirectory(dataDir);
  if (await File('${dataDir.path}/$restoreMarkerName').exists() ||
      !await location.databaseFile.exists() ||
      _userVersion(location.databaseFile) != schemaVersion) {
    return _done;
  }
  final PlanSource plans = source ?? OverpassPlanSource();
  final GrobingDatabase database = openDatabase(location.databaseFile);
  final Set<int> tried = {};
  bool stored = false, failed = false;
  try {
    while (true) {
      final ({int id, GeoPoint point})? next = (await cemeteriesWithoutPlan(
        database,
      )).where((c) => !tried.contains(c.id)).firstOrNull;
      if (next == null) return failed ? _retry : _done;
      if (now().difference(started) >= startNoLaterThan) {
        return stored || !failed ? _again : _retry;
      }
      tried.add(next.id);
      switch (await plans.fetch(next.point)) {
        case PlanFound(:final areas, :final paths, :final server):
          stored |= await savePlan(
            database,
            next.id,
            forPoint: next.point,
            areas: areas,
            paths: paths,
            server: server,
          );
        case PlanNotInOsm(:final server):
          stored |= await saveNotInOsm(
            database,
            next.id,
            forPoint: next.point,
            server: server,
          );
        case PlanOffline():
          return _retry;
        case PlanServerError():
          failed = true;
      }
    }
  } finally {
    await database.close();
    if (stored) {
      try {
        await backups?.request();
      } on Object {
        // The next start or leaving of the app asks for the backup as well.
      }
    }
  }
}

const BackgroundRun _done = (
  outcome: BackgroundOutcome.done,
  wait: Duration.zero,
);
const BackgroundRun _again = (
  outcome: BackgroundOutcome.again,
  wait: Duration.zero,
);
const BackgroundRun _retry = (
  outcome: BackgroundOutcome.retry,
  wait: Duration.zero,
);

/// `PRAGMA user_version` without the app's database class, which would migrate on open — as the background
/// backup reads it (`background_backup.dart`).
int _userVersion(File database) {
  final Database raw = sqlite3.open(database.path, mode: OpenMode.readOnly);
  try {
    configureConnection(raw);
    return raw.userVersion;
  } finally {
    raw.close();
  }
}
