import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/grobing_app.dart';
import 'app/photo/photos.dart';
import 'backup/background.dart';
import 'backup/background_backup.dart';
import 'backup/backup_service.dart';
import 'backup/backup_settings.dart';
import 'backup/documents.dart';
import 'backup/restore_service.dart';
import 'backup/restore_swap.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App-private storage. Excluded from Android's own backup and device transfer (ADR-004 pkt 4,
  // res/xml/data_extraction_rules.xml): the one way off the phone is the backup below.
  final Directory support = await getApplicationSupportDirectory();
  final Directory cache = await getTemporaryDirectory();
  final AppData data = await _open(support, cache);
  runApp(
    GrobingApp(
      database: data.database,
      location: data.location,
      backup: data.backup,
      restore: data.restore,
      reopen: () => _open(support, cache),
    ),
  );
}

/// Opens the data — at start, and again after a restore replaced it.
Future<AppData> _open(Directory support, Directory cache) async {
  // A restore interrupted after its commit point is finished here, before the database is opened;
  // one that never committed leaves only leftovers, deleted here (ISSUE-009, AC-4).
  await completePendingRestore(support);
  final DataLocation location = DataLocation.inDirectory(support);
  final GrobingDatabase database = GrobingDatabase.atFile(
    location.databaseFile,
  );
  final BackupSettingsStore settings = BackupSettingsStore(
    File('${support.path}/backup.json'),
  );
  const DocumentStore documents = PlatformDocumentStore();
  const PlatformBackground background = PlatformBackground();
  final BackupService backup = BackupService(
    database: database,
    location: location,
    workDir: _backupWorkDir(cache),
    settings: settings,
    documents: documents,
    lock: background,
    background: background,
  );
  // The start is a trigger too (ISSUE-010, D2): it catches the data a restore just brought, a schema
  // migration (retro 1, R6), and any change made outside drift that no write notified. In the
  // background, so the first screen does not wait for the database to open.
  unawaited(backup.requestBackgroundOnStart());
  // An interrupted photo preparation (ISSUE-016) leaves a scratch file — never a kept photo.
  unawaited(Photos.platform(location).clearWork());
  return (
    database: database,
    location: location,
    backup: backup,
    restore: RestoreService(
      dataDir: support,
      database: database,
      settings: settings,
      documents: documents,
      schemaVersion: database.schemaVersion,
      lock: background,
    ),
  );
}

/// Scratch space of every backup, from the button or the background — one at a time (the data lock).
Directory _backupWorkDir(Directory cache) => Directory('${cache.path}/backup');

/// The background backup (ISSUE-010): `BackupWorker.kt` runs this in a headless engine, with the time
/// of the first unsaved change (ms since the epoch) as the only argument. Nothing in Dart calls it, so
/// `vm:entry-point` keeps it in release builds.
@pragma('vm:entry-point')
Future<void> backgroundBackupMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  const PlatformBackground background = PlatformBackground();
  final int? firstChange = args.isEmpty ? null : int.tryParse(args.first);
  BackgroundRun run;
  try {
    run = await runBackgroundBackup(
      dataDir: await getApplicationSupportDirectory(),
      workDir: _backupWorkDir(await getTemporaryDirectory()),
      lock: background,
      documents: const PlatformDocumentStore(),
      firstChangeAt: firstChange == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(firstChange, isUtc: true),
    );
  } on Object {
    run = (outcome: BackgroundOutcome.retry, wait: Duration.zero);
  }
  await background.finished(run);
}
