import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../data/photos.dart';
import 'age/age.dart';
import 'background.dart';
import 'backup_archive.dart';
import 'backup_settings.dart';
import 'data_stamp.dart';
import 'documents.dart';

/// Suggested names in the "save as" window; the user may change them.
const String backupKeyFileName = 'grobing-klucz.age';
const String backupFileName = 'grobing-kopia.age';

/// Where the one-time setup is, for the progress line on screen.
enum BackupSetupStep { protectingKey, savingKey, savingBackup, firstBackup }

/// The backup (ADR-004 pkt 1-3): one encrypted file in the author's Drive, overwritten by every
/// backup. The phone keeps only the public key, so a backup never needs the passphrase; the secret
/// key lives in a separate file, encrypted with the passphrase. Restore = key file + passphrase +
/// backup file (ISSUE-009). Besides the button, the backup runs in the background after the app was
/// left with changed data (ISSUE-010).
class BackupService {
  BackupService({
    required this.database,
    required this.location,
    required this.workDir,
    required this.settings,
    required this.documents,
    required this.lock,
    this.background,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GrobingDatabase database;
  final DataLocation location;

  /// Private scratch space for the snapshot and the encrypted file; emptied before and after use.
  final Directory workDir;
  final BackupSettingsStore settings;
  final DocumentStore documents;

  /// Held by the setup and every backup (ISSUE-010, D3).
  final DataLock lock;

  /// Null where nothing asks for background backups: in the background run itself, and in tests.
  final BackgroundBackups? background;
  final DateTime Function() _clock;

  bool _running = false;

  Future<BackupSettings?> readSettings() => settings.read();

  /// One-time setup: a new key, the key file protected with [passphrase], the backup file, then the
  /// first backup. Returns null when the user closes a "save as" window — nothing is configured then
  /// (a key file saved before that is useless on its own). Running it again replaces the key.
  ///
  /// Holds the data lock throughout (ISSUE-010, D3): the "save as" window counts as leaving the app,
  /// and a background backup finishing with the old key would overwrite the new settings.
  Future<BackupSettings?> setUp(
    String passphrase, {
    void Function(BackupSetupStep step)? onStep,
  }) async {
    if (passphrase.isEmpty) throw const BackupException('Wpisz hasło.');
    await _acquire();
    try {
      if (await _configure(passphrase, onStep) == null) return null;
      onStep?.call(BackupSetupStep.firstBackup);
      return await backUpWhileLocked();
    } finally {
      await lock.release();
    }
  }

  /// Everything of [setUp] before the first backup; null when a window was closed.
  Future<BackupSettings?> _configure(
    String passphrase,
    void Function(BackupSetupStep step)? onStep,
  ) async {
    final DateTime createdAt = _clock();
    try {
      await _resetWorkDir();
      onStep?.call(BackupSetupStep.protectingKey);
      // scrypt (work factor 18) takes ~15 s and ~430 MB in pure Dart (SPIKE-003, M4): off the UI isolate.
      final ({String recipient, Uint8List keyFile}) key =
          await _protectedKeyFileInBackground(passphrase, createdAt);
      final File keyFile = File('${workDir.path}/klucz.age.part');
      await keyFile.writeAsBytes(key.keyFile, flush: true);

      onStep?.call(BackupSetupStep.savingKey);
      final String? keyUri = await documents.createDocument(backupKeyFileName);
      if (keyUri == null) return null;
      await documents.writeFile(keyUri, keyFile);

      onStep?.call(BackupSetupStep.savingBackup);
      final String? backupUri = await documents.createDocument(backupFileName);
      if (backupUri == null) return null;
      await documents.keepAccess(backupUri);

      final BackupSettings? previous = await settings.read();
      if (previous != null && previous.documentUri != backupUri) {
        // The old file stays in Drive; the app just stops holding a permission it no longer uses.
        try {
          await documents.releaseAccess(previous.documentUri);
        } on PlatformException {
          // Already gone — nothing to release.
        }
      }
      final BackupSettings configured = BackupSettings(
        recipient: key.recipient,
        documentUri: backupUri,
      );
      await settings.write(configured);
      return configured;
    } on PlatformException catch (e) {
      throw BackupException(_documentProblem(e));
    } finally {
      await _deleteWorkDir();
    }
  }

  /// Writes a backup now and records the outcome, which the returned settings carry: a failure is a
  /// result to show, not an exception. Throws only when the backup is not configured, already runs, or
  /// another operation holds the data lock (ISSUE-010, D3).
  Future<BackupSettings> backUpNow() async {
    await _acquire();
    try {
      return await backUpWhileLocked();
    } finally {
      await lock.release();
    }
  }

  /// [backUpNow] for a caller that already holds the [lock] — the setup and the background run.
  Future<BackupSettings> backUpWhileLocked({bool inBackground = false}) async {
    final BackupSettings? current = await settings.read();
    if (current == null) {
      throw const BackupException('Kopia nie jest skonfigurowana.');
    }
    if (_running) throw const BackupException('Kopia już trwa.');
    _running = true;
    try {
      final DateTime createdAt = _clock().toUtc();
      // Under the lock and before the stamp: photo files no row names any more go now (ISSUE-016, D3),
      // so their deletion is not a change the stamp sees after this backup.
      await _sweepMedia();
      // Before the snapshot: a change after this point makes the stamps differ, so the next trigger
      // backs it up (ISSUE-010, D2) — at worst once too often, never once too few.
      final String stamp = await dataStamp(location);
      await _resetWorkDir();
      final String snapshotPath = '${workDir.path}/$backupDatabaseName';
      final String outputPath = '${workDir.path}/kopia.age.part';
      final String mediaPath = location.mediaDir.path;
      final String recipient = current.recipient;

      // A consistent copy of the database while the app keeps it open (ADR-004 pkt 2, ADR-005).
      await database.customStatement('VACUUM INTO ?', [snapshotPath]);
      await _writeEncryptedBackupInBackground(
        snapshotPath: snapshotPath,
        mediaPath: mediaPath,
        recipient: recipient,
        outputPath: outputPath,
        createdAt: createdAt,
      );

      if (!await documents.hasAccess(current.documentUri)) {
        throw const BackupException(
          'Aplikacja nie ma już dostępu do pliku kopii. Skonfiguruj kopię od nowa.',
        );
      }
      await documents.writeFile(current.documentUri, File(outputPath));

      final BackupSettings updated = current.succeeded(
        _clock(),
        stamp: stamp,
        inBackground: inBackground,
      );
      await settings.write(updated);
      return updated;
    } on Object catch (e) {
      final BackupSettings updated = current.failed(_clock(), _describe(e));
      await settings.write(updated);
      return updated;
    } finally {
      _running = false;
      await _deleteWorkDir();
    }
  }

  /// True when the backup is configured and the data differs from what the last successful backup
  /// holds (ISSUE-010, D2).
  Future<bool> changedSinceLastBackup() async {
    final BackupSettings? current = await settings.read();
    if (current == null) return false;
    return current.lastSuccessStamp != await dataStamp(location);
  }

  /// Every write to the database asks for a background backup (ISSUE-010, D2) — at the moment the work
  /// arises, so closing the app right after cannot lose it (stop #2: leaving the app alone lost the race
  /// with swiping it away). A burst of writes makes at most one request at a time, and none is lost.
  StreamSubscription<Set<TableUpdate>> watchChanges() =>
      database.tableUpdates().listen((_) => _requestCoalesced());

  bool _requesting = false;
  bool _requestAgain = false;

  Future<void> _requestCoalesced() async {
    if (_requesting) {
      _requestAgain = true;
      return;
    }
    _requesting = true;
    try {
      do {
        _requestAgain = false;
        await requestBackgroundIfChanged();
      } while (_requestAgain);
    } finally {
      _requesting = false;
    }
  }

  /// Writes, leaving and starting the app (ISSUE-010, D2): asks Android for a background backup when
  /// the data changed since the last successful one. Never throws — the app goes on, and the next
  /// trigger asks again.
  Future<void> requestBackgroundIfChanged() async {
    final BackgroundBackups? background = this.background;
    if (background == null) return;
    try {
      if (await changedSinceLastBackup()) await background.request();
    } on Object {
      // Nothing to show: no screen asked for this.
    }
  }

  /// The start trigger (ISSUE-010, D2), asked once the database is open. Opening runs the schema
  /// migrations, which change the file but notify no table — asked before it, the start saw the stamp
  /// of the old version and the migrated data waited for the first write (retro 1, R6). A database that
  /// fails to open asks nothing: the screens show that error.
  Future<void> requestBackgroundOnStart() async {
    try {
      await database.customSelect('SELECT 1').get();
    } on Object {
      return;
    }
    // Photo files left without a row (ISSUE-016, D3) go at start too — when no backup holds the lock;
    // otherwise that backup sweeps them.
    if (await lock.tryAcquire()) {
      try {
        await _sweepMedia();
      } finally {
        await lock.release();
      }
    }
    await requestBackgroundIfChanged();
  }

  /// [sweepOrphanMedia], never failing the caller: a file that stays goes with the next sweep.
  Future<void> _sweepMedia() async {
    try {
      await sweepOrphanMedia(database, location.mediaDir);
    } on Object {
      // Nothing to show; the next backup or start tries again.
    }
  }

  Future<void> _acquire() async {
    if (!await lock.tryAcquire()) {
      throw const BackupException(dataBusyMessage);
    }
  }

  Future<void> _resetWorkDir() async {
    await _deleteWorkDir();
    await workDir.create(recursive: true);
  }

  /// The snapshot is the family's data in the clear: it never outlives the backup that made it.
  Future<void> _deleteWorkDir() async {
    if (await workDir.exists()) await workDir.delete(recursive: true);
  }
}

// The closures sent to Isolate.run are created in these top-level functions, so they capture only
// the strings passed in — never the service, its database connection or the channel.

Future<({String recipient, Uint8List keyFile})> _protectedKeyFileInBackground(
  String passphrase,
  DateTime createdAt,
) => Isolate.run(() => _protectedKeyFile(passphrase, createdAt));

/// Hashing, tar and encryption (~8 MB/s in pure Dart, SPIKE-003 M4) off the UI isolate.
Future<void> _writeEncryptedBackupInBackground({
  required String snapshotPath,
  required String mediaPath,
  required String recipient,
  required String outputPath,
  required DateTime createdAt,
}) => Isolate.run(() async {
  await writeEncryptedBackup(
    snapshot: File(snapshotPath),
    mediaDir: Directory(mediaPath),
    recipient: X25519Recipient.parse(recipient),
    output: File(outputPath),
    createdAt: createdAt,
  );
});

/// Runs in a background isolate: a new identity, its file in the `age-keygen` format, encrypted with
/// the passphrase. Only the public key and the encrypted file leave this function.
Future<({String recipient, Uint8List keyFile})> _protectedKeyFile(
  String passphrase,
  DateTime createdAt,
) async {
  final X25519Identity identity = X25519Identity.generate();
  final BytesBuilder out = BytesBuilder(copy: false);
  await for (final List<int> chunk in ageEncrypt(
    Stream.value(utf8.encode(encodeIdentityFile(identity, createdAt))),
    [ScryptRecipient(passphrase)],
  )) {
    out.add(chunk);
  }
  return (recipient: identity.recipient.encode(), keyFile: out.takeBytes());
}

/// A message for the screen — never paths, file contents or the passphrase.
String _describe(Object error) => switch (error) {
  BackupException(:final String message) => message,
  final PlatformException e => _documentProblem(e),
  FileSystemException(:final OSError? osError) when osError?.errorCode == 28 =>
    'Brak miejsca w telefonie na przygotowanie kopii.',
  _ => 'Kopia nie powiodła się (${error.runtimeType}).',
};

String _documentProblem(PlatformException e) => switch (e.code) {
  'not_found' => 'Pliku kopii nie ma już w Dysku. Skonfiguruj kopię od nowa.',
  'no_access' =>
    'Aplikacja nie ma już dostępu do pliku kopii. Skonfiguruj kopię od nowa.',
  _ => 'Nie udało się zapisać pliku w Dysku (${e.code}).',
};
