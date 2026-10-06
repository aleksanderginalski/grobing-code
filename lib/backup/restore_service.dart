import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/data_state.dart';
import '../data/database.dart';
import 'age/age.dart';
import 'background.dart';
import 'backup_archive.dart';
import 'backup_settings.dart';
import 'documents.dart';
import 'restore_swap.dart';
import 'tar_reader.dart';

/// Where the restore is, for the progress line on screen.
enum RestoreStep {
  checkingSpace,
  unlockingKey,
  copying,
  decrypting,
  verifying,
  migrating,
  replacing,
}

/// What happens to the backup after a restore (ISSUE-009, D3).
enum RestoredBackup {
  /// This phone already had a backup set up: same key, same file.
  kept,

  /// A fresh phone: the backup goes on with the restored key, to the file it was restored from — the
  /// key file in the hand-over note keeps opening new backups.
  continued,

  /// A fresh phone whose provider would not let the app write the backup file.
  notConfigured,
}

class RestoreResult {
  const RestoreResult({
    required this.createdAt,
    required this.dataFingerprint,
    required this.schemaFrom,
    required this.schemaTo,
    required this.backup,
  });

  /// When the restored backup was made.
  final DateTime createdAt;

  /// The backup's fingerprint — the restored data's, unless a migration ran ([schemaFrom] <
  /// [schemaTo]), which changes the fingerprint by definition.
  final String dataFingerprint;
  final int schemaFrom;
  final int schemaTo;
  final RestoredBackup backup;
}

/// Opens a database file with the app's own migrations (`GrobingDatabase` on the phone).
typedef DatabaseOpener = GeneratedDatabase Function(File file);

/// Restore (ADR-004 pkt 5-6): key file + passphrase + backup file → the phone's data, replaced only
/// after the backup has been checked in a private staging directory. Until [RestoreService.restore]
/// commits, nothing the phone holds has changed; after that, `restore_swap.dart` guarantees old or
/// new data across any interruption.
class RestoreService {
  RestoreService({
    required this.dataDir,
    required this.database,
    required this.settings,
    required this.documents,
    required this.schemaVersion,
    required this.lock,
    DatabaseOpener? openDatabase,
  }) : _openDatabase = openDatabase ?? _openGrobingDatabase;

  /// The app's data directory: `grobing.db`, `media/`, `backup.json` (`DataLocation.inDirectory`).
  final Directory dataDir;

  /// The live database; closed right before the swap.
  final GeneratedDatabase database;
  final BackupSettingsStore settings;
  final DocumentStore documents;

  /// The app's schema version: older backups are migrated, newer ones refused (ADR-004 pkt 5).
  final int schemaVersion;

  /// Held from the first check to the end of the swap (ISSUE-010, D3), so no backup reads the data
  /// half replaced. Released before the app reopens its data: a background run that starts then sees
  /// either finished data or, after an interrupted swap, the marker — which it leaves to the app.
  final DataLock lock;
  final DatabaseOpener _openDatabase;

  /// Free space kept after the restore's own needs (ISSUE-009, D2).
  static const int spaceMargin = 200 * 1024 * 1024;

  /// A key file is a few hundred bytes; anything much larger is not one.
  static const int keyFileMaxBytes = 64 * 1024;

  /// scrypt work factor accepted from a key file: 2^20 needs ~1 GB of memory, the official default
  /// (and Grobing's) is 18; the official limit of 22 (~4 GB) would not fit a phone.
  static const int maxWorkFactor = 20;

  bool _databaseClosed = false;

  /// True once the live database was closed for the swap: the app must reopen its data, whether the
  /// restore finished or not (`completePendingRestore` decides which data that is).
  bool get databaseClosed => _databaseClosed;

  /// The system "open" window.
  Future<String?> pickFile() => documents.openDocument();

  Future<DocumentInfo> describe(String uri) => documents.documentInfo(uri);

  Future<RestoreResult> restore({
    required String backupUri,
    required String keyUri,
    required String passphrase,
    void Function(RestoreStep step)? onStep,
  }) async {
    if (passphrase.isEmpty) throw const BackupException('Wpisz hasło.');
    if (!await lock.tryAcquire()) throw const BackupException(dataBusyMessage);
    try {
      return await _restoreLocked(
        backupUri: backupUri,
        keyUri: keyUri,
        passphrase: passphrase,
        onStep: onStep,
      );
    } finally {
      await lock.release();
    }
  }

  Future<RestoreResult> _restoreLocked({
    required String backupUri,
    required String keyUri,
    required String passphrase,
    void Function(RestoreStep step)? onStep,
  }) async {
    final Directory staging = Directory('${dataDir.path}/$restoreStagingName');
    final Directory incoming = restoreIncomingDir(dataDir);
    try {
      await _delete(staging);
      await incoming.create(recursive: true);

      onStep?.call(RestoreStep.checkingSpace);
      final DocumentInfo info = await _document(
        () => documents.documentInfo(backupUri),
      );
      final int budget = _budget(info.size, await documents.freeSpace());

      onStep?.call(RestoreStep.unlockingKey);
      final File keyFile = File('${staging.path}/klucz.age');
      await _document(
        () => documents.readFile(keyUri, keyFile, maxBytes: keyFileMaxBytes),
        tooLarge: _notAKeyFile,
      );
      final ({String identities, String recipient}) key = await _unlockKey(
        keyFile.path,
        passphrase,
      );
      await keyFile.delete();

      onStep?.call(RestoreStep.copying);
      final File encrypted = File('${staging.path}/kopia.age');
      await _document(
        () => documents.readFile(backupUri, encrypted, maxBytes: budget),
        tooLarge: _noSpace,
      );

      onStep?.call(RestoreStep.decrypting);
      final List<TarEntry> entries = await _extract(
        encrypted.path,
        key.identities,
        incoming.path,
        budget,
      );
      await encrypted.delete();

      onStep?.call(RestoreStep.verifying);
      final BackupManifest manifest = await _verify(
        incoming.path,
        entries,
        schemaVersion,
      );
      if (manifest.schemaVersion < schemaVersion) {
        onStep?.call(RestoreStep.migrating);
        await _migrate(File('${incoming.path}/$backupDatabaseName'), manifest);
      }
      final RestoredBackup backup = await _continueBackup(
        incoming,
        recipient: key.recipient,
        backupUri: backupUri,
        writable: info.writable,
      );

      onStep?.call(RestoreStep.replacing);
      _databaseClosed = true;
      await database.close();
      await commitRestore(dataDir);
      return RestoreResult(
        createdAt: manifest.createdAt,
        dataFingerprint: manifest.dataFingerprint,
        schemaFrom: manifest.schemaVersion,
        schemaTo: schemaVersion,
        backup: backup,
      );
    } on Object catch (e) {
      if (!_databaseClosed) await _delete(staging);
      if (e is BackupException) rethrow;
      throw BackupException(_describe(e));
    }
  }

  /// Bytes the backup file may have — and its contents, which are never larger (ISSUE-009, D2): the
  /// phone must hold the encrypted copy and the extracted files at once, plus [spaceMargin].
  int _budget(int? size, int free) {
    if (size != null) {
      final int needed = 2 * size + spaceMargin;
      if (free < needed) {
        throw BackupException(
          'Za mało miejsca w telefonie: kopia ma ${_mb(size)} MB, a odtworzenie '
          'potrzebuje ${_mb(needed)} MB wolnego miejsca (wolne: ${_mb(free)} MB). '
          'Zwolnij miejsce i spróbuj jeszcze raz.',
        );
      }
      return size;
    }
    // The provider does not know the size: the budget is what fits twice, and reading stops there.
    final int budget = (free - spaceMargin) ~/ 2;
    if (budget <= 0) throw const BackupException(_noSpace);
    return budget;
  }

  Future<void> _migrate(File staged, BackupManifest manifest) async {
    final GeneratedDatabase db = _openDatabase(staged);
    try {
      // The first query opens the file and runs the app's migrations (NFR-003).
      final int version =
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          );
      if (version != schemaVersion || !await _integrityOk(db)) {
        throw const BackupException(_migrationFailed);
      }
      for (final MapEntry<String, int> table in manifest.recordCounts.entries) {
        final int count =
            (await db
                    .customSelect(
                      'SELECT count(*) AS c FROM ${_quote(table.key)}',
                    )
                    .getSingle())
                .read<int>('c');
        if (count != table.value) {
          throw const BackupException(_migrationFailed);
        }
      }
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException(_migrationFailed);
    } finally {
      await db.close();
    }
  }

  /// D3: a phone with a backup keeps it; a fresh phone goes on with the restored key and file.
  Future<RestoredBackup> _continueBackup(
    Directory incoming, {
    required String recipient,
    required String backupUri,
    required bool writable,
  }) async {
    if (await settings.read() != null) return RestoredBackup.kept;
    if (!writable) return RestoredBackup.notConfigured;
    try {
      await documents.keepAccess(backupUri);
    } on PlatformException {
      return RestoredBackup.notConfigured;
    }
    // Swapped in with the data (`restore_swap.dart`), so it exists exactly when the data does.
    await BackupSettingsStore(
      File('${incoming.path}/backup.json'),
    ).write(BackupSettings(recipient: recipient, documentUri: backupUri));
    return RestoredBackup.continued;
  }
}

const String _notAKeyFile =
    'To nie jest plik klucza Grobing. Wybierz plik klucza (np. grobing-klucz.age).';
const String _noSpace =
    'Za mało miejsca w telefonie na odtworzenie tej kopii. Zwolnij miejsce i spróbuj jeszcze raz.';
const String _mismatch =
    'Zawartość kopii nie zgadza się z jej opisem — plik jest uszkodzony.';
const String _migrationFailed =
    'Nie udało się przenieść danych z kopii do tej wersji aplikacji.';

GeneratedDatabase _openGrobingDatabase(File file) =>
    GrobingDatabase(NativeDatabase.createInBackground(file));

/// Runs a document-channel call, turning its errors into messages.
Future<T> _document<T>(Future<T> Function() call, {String? tooLarge}) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw BackupException(switch (e.code) {
      'too_large' => tooLarge ?? _noSpace,
      'not_found' => 'Nie ma już tego pliku. Wybierz go jeszcze raz.',
      'no_access' =>
        'Aplikacja nie ma dostępu do tego pliku. Wybierz go jeszcze raz.',
      _ => 'Nie udało się odczytać pliku (${e.code}).',
    });
  }
}

// The closures sent to Isolate.run are created in these top-level functions, so they capture only
// the values passed in — never the service, its database connection or the channel.

/// scrypt (~15 s, hundreds of MB) off the UI isolate. Returns the identity file's text, which stays in
/// memory only, and its public key.
Future<({String identities, String recipient})> _unlockKey(
  String keyPath,
  String passphrase,
) async {
  try {
    return await Isolate.run(() async {
      final BytesBuilder out = BytesBuilder(copy: false);
      await for (final List<int> chunk in ageDecrypt(File(keyPath).openRead(), [
        ScryptIdentity(passphrase, maxWorkFactor: RestoreService.maxWorkFactor),
      ])) {
        out.add(chunk);
      }
      final String text = utf8.decode(out.takeBytes());
      final List<X25519Identity> identities = parseIdentityFile(text);
      if (identities.isEmpty) throw const FormatException('No identity');
      return (identities: text, recipient: identities.first.recipient.encode());
    });
  } on AgeException catch (e) {
    throw BackupException(switch (e.failure) {
      AgeFailure.noMatch =>
        'Złe hasło albo to nie jest plik klucza. Sprawdź hasło z notki przekazania.',
      AgeFailure.header =>
        'Nie da się otworzyć pliku klucza: to nie jest plik klucza Grobing, jest uszkodzony albo '
            'wymaga więcej pamięci, niż ma telefon.',
      AgeFailure.hmac || AgeFailure.payload => 'Plik klucza jest uszkodzony.',
    });
  } on FormatException {
    throw const BackupException(_notAKeyFile);
  }
}

/// Decrypts the backup file and extracts its archive into [incomingPath], checksumming every file.
Future<List<TarEntry>> _extract(
  String encryptedPath,
  String identities,
  String incomingPath,
  int budget,
) async {
  try {
    return await Isolate.run(
      () => extractTar(
        ageDecrypt(
          File(encryptedPath).openRead(),
          parseIdentityFile(identities),
        ),
        Directory(incomingPath),
        maxBytes: budget,
        accept: (path) =>
            path == backupDatabaseName ||
            path == backupManifestName ||
            path.startsWith(backupMediaPrefix),
      ),
    );
  } on AgeException catch (e) {
    throw BackupException(switch (e.failure) {
      AgeFailure.noMatch =>
        'Ten plik klucza nie otwiera tej kopii. Kopię zaszyfrowano innym kluczem — wybierz plik '
            'klucza z tej samej konfiguracji.',
      AgeFailure.header ||
      AgeFailure.hmac => 'To nie jest plik kopii Grobing albo jest uszkodzony.',
      AgeFailure.payload => 'Plik kopii jest uszkodzony albo niepełny.',
    });
  } on TarFormatException {
    throw const BackupException(
      'Plik kopii ma zawartość, której Grobing nie zapisuje — odtworzenie odrzucone.',
    );
  } on TarBudgetException {
    throw const BackupException(_noSpace);
  }
}

/// ADR-004 pkt 6, on the extracted files: the manifest, every file against it, then the database —
/// `integrity_check`, `user_version`, row counts and the fingerprint (NFR-002). Returns the manifest.
Future<BackupManifest> _verify(
  String incomingPath,
  List<TarEntry> entries,
  int appSchemaVersion,
) => Isolate.run(() async {
  if (entries.isEmpty ||
      entries.last.path != backupManifestName ||
      entries.where((e) => e.path == backupDatabaseName).length != 1) {
    throw const BackupException(_mismatch);
  }
  final File manifestFile = File('$incomingPath/$backupManifestName');
  final BackupManifest manifest;
  try {
    manifest = BackupManifest.fromJson(
      jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>,
    );
  } on Object {
    throw const BackupException(_mismatch);
  }
  if (manifest.formatVersion > backupFormatVersion ||
      manifest.schemaVersion > appSchemaVersion) {
    throw const BackupException(
      'Kopia pochodzi z nowszej wersji Grobing. Zaktualizuj aplikację i spróbuj jeszcze raz.',
    );
  }
  if (manifest.formatVersion != backupFormatVersion ||
      manifest.schemaVersion < 1) {
    throw const BackupException(_mismatch);
  }

  final Map<String, TarEntry> archived = {
    for (final TarEntry e in entries.take(entries.length - 1)) e.path: e,
  };
  if (archived.length != manifest.files.length) {
    throw const BackupException(_mismatch);
  }
  for (final BackupFileEntry f in manifest.files) {
    final TarEntry? a = archived[f.path];
    if (a == null || a.size != f.size || a.sha256 != f.sha256) {
      throw const BackupException(_mismatch);
    }
  }
  await manifestFile.delete();

  final String dbPath = '$incomingPath/$backupDatabaseName';
  final int version;
  try {
    final Database raw = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      version = raw.userVersion;
    } finally {
      raw.close();
    }
  } on SqliteException {
    throw const BackupException(_corruptDatabase);
  }
  if (version != manifest.schemaVersion) throw const BackupException(_mismatch);

  // Read-only, and at its own version, so opening it never migrates or writes anything.
  final _StagedDatabase db = _StagedDatabase(
    NativeDatabase.opened(sqlite3.open(dbPath, mode: OpenMode.readOnly)),
    version,
  );
  try {
    if (!await _integrityOk(db)) {
      throw const BackupException(_corruptDatabase);
    }
    final DataState state = await readDataState(
      db,
      mediaDir: Directory('$incomingPath/media'),
    );
    if (!mapEquals(state.rowCounts, manifest.recordCounts) ||
        state.fingerprint != manifest.dataFingerprint) {
      throw const BackupException(_mismatch);
    }
  } on SqliteException {
    throw const BackupException(_corruptDatabase);
  } finally {
    await db.close();
  }
  return manifest;
});

const String _corruptDatabase =
    'Baza danych w kopii jest uszkodzona (integrity_check) — odtworzenie odrzucone.';

Future<bool> _integrityOk(GeneratedDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA integrity_check')
      .get();
  return rows.length == 1 && rows.single.data.values.single == 'ok';
}

/// The staged database seen through drift without any schema of its own, at the version the file
/// already has — so drift neither creates nor migrates anything.
class _StagedDatabase extends GeneratedDatabase {
  _StagedDatabase(super.executor, this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

String _mb(int bytes) => (bytes / (1024 * 1024)).ceil().toString();

/// A message for the screen — never paths, file contents or the passphrase.
String _describe(Object error) => switch (error) {
  FileSystemException(:final OSError? osError) when osError?.errorCode == 28 =>
    _noSpace,
  _ => 'Odtworzenie nie powiodło się (${error.runtimeType}).',
};

Future<void> _delete(Directory dir) async {
  if (await dir.exists()) await dir.delete(recursive: true);
}
