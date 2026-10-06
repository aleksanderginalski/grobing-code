import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/grobing_app.dart';
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
  return (
    database: database,
    location: location,
    backup: BackupService(
      database: database,
      location: location,
      workDir: Directory('${cache.path}/backup'),
      settings: settings,
      documents: documents,
    ),
    restore: RestoreService(
      dataDir: support,
      database: database,
      settings: settings,
      documents: documents,
      schemaVersion: database.schemaVersion,
    ),
  );
}
