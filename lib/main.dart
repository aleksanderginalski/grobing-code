import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/grobing_app.dart';
import 'backup/backup_service.dart';
import 'backup/backup_settings.dart';
import 'backup/documents.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App-private storage. Excluded from Android's own backup and device transfer (ADR-004 pkt 4,
  // res/xml/data_extraction_rules.xml): the one way off the phone is the backup below.
  final Directory support = await getApplicationSupportDirectory();
  final Directory cache = await getTemporaryDirectory();
  final DataLocation location = DataLocation.inDirectory(support);
  final GrobingDatabase database = GrobingDatabase.atFile(
    location.databaseFile,
  );
  final BackupService backup = BackupService(
    database: database,
    location: location,
    workDir: Directory('${cache.path}/backup'),
    settings: BackupSettingsStore(File('${support.path}/backup.json')),
    documents: const PlatformDocumentStore(),
  );
  runApp(GrobingApp(database: database, location: location, backup: backup));
}
