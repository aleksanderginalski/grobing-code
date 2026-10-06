import 'dart:io';

import 'package:flutter/services.dart';
import 'package:grobing/backup/backup_service.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/backup/documents.dart';
import 'package:grobing/data/database.dart';

/// The system "save as" window and the provider behind it, as files in [root]. Each
/// [createDocument] answers with the next entry of [answers]: a file name, or null for "the user
/// closed the window".
class FakeDocumentStore implements DocumentStore {
  FakeDocumentStore(this.root, {List<String?>? answers})
    : _answers = answers ?? [backupKeyFileName, backupFileName];

  final Directory root;
  final List<String?> _answers;
  final Set<String> kept = {};
  final List<String> suggestedNames = [];

  /// When set, [writeFile] fails like the native side does.
  PlatformException? writeError;

  File fileFor(String uri) => File('${root.path}/${Uri.parse(uri).path}');

  @override
  Future<String?> createDocument(String suggestedName) async {
    suggestedNames.add(suggestedName);
    final String? name = _answers.removeAt(0);
    if (name == null) return null;
    final String uri = 'content://fake/$name';
    fileFor(uri).createSync(recursive: true);
    return uri;
  }

  @override
  Future<void> keepAccess(String uri) async => kept.add(uri);

  @override
  Future<void> releaseAccess(String uri) async => kept.remove(uri);

  @override
  Future<bool> hasAccess(String uri) async => kept.contains(uri);

  @override
  Future<void> writeFile(String uri, File file) async {
    if (writeError != null) throw writeError!;
    await file.copy(fileFor(uri).path);
  }
}

/// A [BackupService] with everything under [tmp]: data, scratch space, settings, "Drive".
BackupService backupServiceIn(
  Directory tmp,
  GrobingDatabase db,
  FakeDocumentStore documents, {
  DateTime Function()? clock,
}) => BackupService(
  database: db,
  location: DataLocation.inDirectory(Directory('${tmp.path}/data')),
  workDir: Directory('${tmp.path}/cache/backup'),
  settings: BackupSettingsStore(File('${tmp.path}/data/backup.json')),
  documents: documents,
  clock: clock,
);
