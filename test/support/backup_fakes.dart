import 'dart:io';

// drift has its own `DatabaseOpener` (LazyDatabase); this one is the restore's.
import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter/services.dart';
import 'package:grobing/backup/backup_service.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/backup/documents.dart';
import 'package:grobing/backup/restore_service.dart';
import 'package:grobing/data/database.dart';

/// The system "save as" and "open" windows and the provider behind them, as files in [root]. Each
/// [createDocument] answers with the next entry of [answers]: a file name, or null for "the user
/// closed the window"; [openDocument] the same with [openAnswers].
class FakeDocumentStore implements DocumentStore {
  FakeDocumentStore(
    this.root, {
    List<String?>? answers,
    List<String?>? openAnswers,
  }) : _answers = answers ?? [backupKeyFileName, backupFileName],
       _openAnswers = openAnswers ?? [];

  final Directory root;
  final List<String?> _answers;
  final List<String?> _openAnswers;
  final Set<String> kept = {};
  final List<String> suggestedNames = [];

  /// When set, [writeFile] fails like the native side does.
  PlatformException? writeError;

  /// Free bytes in the app's storage, as `StatFs` would say.
  int free = 1 << 40;

  /// The provider does not know sizes (remote files may not).
  bool sizeUnknown = false;

  /// The provider lets the app write picked documents (`FLAG_SUPPORTS_WRITE`).
  bool writable = true;

  /// Every [readFile] budget asked for, in order.
  final List<int> readBudgets = [];

  File fileFor(String uri) => File('${root.path}/${Uri.parse(uri).path}');

  static String uriOf(String name) => 'content://fake/$name';

  @override
  Future<String?> createDocument(String suggestedName) async {
    suggestedNames.add(suggestedName);
    final String? name = _answers.removeAt(0);
    if (name == null) return null;
    final String uri = uriOf(name);
    fileFor(uri).createSync(recursive: true);
    return uri;
  }

  @override
  Future<String?> openDocument() async {
    final String? name = _openAnswers.removeAt(0);
    return name == null ? null : uriOf(name);
  }

  @override
  Future<void> keepAccess(String uri) async {
    if (!writable) throw PlatformException(code: 'no_access');
    kept.add(uri);
  }

  @override
  Future<void> releaseAccess(String uri) async => kept.remove(uri);

  @override
  Future<bool> hasAccess(String uri) async => kept.contains(uri);

  @override
  Future<DocumentInfo> documentInfo(String uri) async {
    final File file = fileFor(uri);
    if (!file.existsSync()) throw PlatformException(code: 'not_found');
    return DocumentInfo(
      size: sizeUnknown ? null : file.lengthSync(),
      name: Uri.parse(uri).pathSegments.last,
      writable: writable,
    );
  }

  @override
  Future<void> writeFile(String uri, File file) async {
    if (writeError != null) throw writeError!;
    await file.copy(fileFor(uri).path);
  }

  /// Like the native side: stops once more than [maxBytes] arrive and leaves no partial file.
  @override
  Future<void> readFile(
    String uri,
    File target, {
    required int maxBytes,
  }) async {
    readBudgets.add(maxBytes);
    final File source = fileFor(uri);
    if (!source.existsSync()) throw PlatformException(code: 'not_found');
    if (source.lengthSync() > maxBytes) {
      if (target.existsSync()) target.deleteSync();
      throw PlatformException(code: 'too_large');
    }
    await source.copy(target.path);
  }

  @override
  Future<int> freeSpace() async => free;
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

/// A [RestoreService] over the data directory [dataDir] and the live [db] in it.
RestoreService restoreServiceIn(
  Directory dataDir,
  GeneratedDatabase db,
  FakeDocumentStore documents, {
  int schemaVersion = 1,
  DatabaseOpener? openDatabase,
}) => RestoreService(
  dataDir: dataDir,
  database: db,
  settings: BackupSettingsStore(File('${dataDir.path}/backup.json')),
  documents: documents,
  schemaVersion: schemaVersion,
  openDatabase: openDatabase,
);
