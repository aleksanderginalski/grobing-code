import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../data/database.dart';
import 'background.dart';
import 'backup_service.dart';
import 'backup_settings.dart';
import 'data_stamp.dart';
import 'documents.dart';
import 'restore_swap.dart';

/// One run of the background backup (ISSUE-010) in the worker's engine (`BackupWorker.kt`). Every
/// check that can end the run comes before the database is opened, and only a backup that is needed
/// opens it:
/// 1. no backup configured → done;
/// 2. the data lock is taken (setup, restore, "Zrób kopię teraz") → retry later (D3);
/// 3. a restore marker, or a database at another schema version → done without a backup: finishing a
///    restore and migrating belong to the app's start, which then asks for a backup again (D3);
/// 4. the data stamp equals the last successful backup's → done (D2);
/// 5. the data changed less than [quiet] ago, and the first unsaved change ([firstChangeAt], when the
///    backup was asked for) is younger than [cap] → later, once it has been quiet (D2: one backup per
///    session of work);
/// 6. otherwise the same backup as the button, marked "in the background"; a failure → retry, data
///    that changed while it ran → again (D2 iii, iv).
Future<BackgroundRun> runBackgroundBackup({
  required Directory dataDir,
  required Directory workDir,
  required DataLock lock,
  required DocumentStore documents,
  required DateTime firstChangeAt,
  int schemaVersion = GrobingDatabase.currentSchemaVersion,
  GrobingDatabase Function(File file) openDatabase = GrobingDatabase.atFile,
  Duration quiet = backupQuiet,
  Duration cap = backupCap,
  DateTime Function()? clock,
}) async {
  final DateTime Function() now = clock ?? DateTime.now;
  final DataLocation location = DataLocation.inDirectory(dataDir);
  final BackupSettingsStore settings = BackupSettingsStore(
    File('${dataDir.path}/backup.json'),
  );
  if (await settings.read() == null) return _done;
  if (!await lock.tryAcquire()) return _retry;
  try {
    if (await File('${dataDir.path}/$restoreMarkerName').exists() ||
        !await location.databaseFile.exists() ||
        _userVersion(location.databaseFile) != schemaVersion) {
      return _done;
    }
    final BackupSettings? current = await settings.read();
    if (current == null ||
        current.lastSuccessStamp == await dataStamp(location)) {
      return _done;
    }
    final Duration? wait = _stillChanging(
      now(),
      await lastDataChange(location),
      firstChangeAt,
      quiet,
      cap,
    );
    if (wait != null) return (outcome: BackgroundOutcome.later, wait: wait);

    final GrobingDatabase database = openDatabase(location.databaseFile);
    try {
      final BackupSettings result = await BackupService(
        database: database,
        location: location,
        workDir: workDir,
        settings: settings,
        documents: documents,
        lock: lock,
        clock: clock,
      ).backUpWhileLocked(inBackground: true);
      if (result.lastAttemptFailed) return _retry;
      return result.lastSuccessStamp == await dataStamp(location)
          ? _done
          : (outcome: BackgroundOutcome.again, wait: quiet);
    } finally {
      await database.close();
    }
  } finally {
    await lock.release();
  }
}

const BackgroundRun _done = (
  outcome: BackgroundOutcome.done,
  wait: Duration.zero,
);
const BackgroundRun _retry = (
  outcome: BackgroundOutcome.retry,
  wait: Duration.zero,
);

/// How much longer to wait for the data to go quiet — or null: back up now. A clock that moved back
/// (a change "in the future") never makes the backup wait.
Duration? _stillChanging(
  DateTime now,
  DateTime? lastChange,
  DateTime firstChangeAt,
  Duration quiet,
  Duration cap,
) {
  if (lastChange == null) return null;
  final Duration sinceLast = now.difference(lastChange);
  final Duration sinceFirst = now.difference(firstChangeAt);
  if (sinceLast.isNegative || sinceLast >= quiet) return null;
  if (sinceFirst.isNegative || sinceFirst >= cap) return null;
  final Duration untilQuiet = quiet - sinceLast;
  final Duration untilCap = cap - sinceFirst;
  return untilQuiet < untilCap ? untilQuiet : untilCap;
}

/// `PRAGMA user_version` without the app's database class, which would migrate on open. Read-only, on
/// the same bundled SQLite as the app's connection.
int _userVersion(File database) {
  final Database raw = sqlite3.open(database.path, mode: OpenMode.readOnly);
  try {
    configureConnection(raw);
    return raw.userVersion;
  } finally {
    raw.close();
  }
}
