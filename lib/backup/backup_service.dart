import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../data/database.dart';
import 'age/age.dart';
import 'backup_archive.dart';
import 'backup_settings.dart';
import 'documents.dart';

/// Suggested names in the "save as" window; the user may change them.
const String backupKeyFileName = 'grobing-klucz.age';
const String backupFileName = 'grobing-kopia.age';

/// Where the one-time setup is, for the progress line on screen.
enum BackupSetupStep { protectingKey, savingKey, savingBackup, firstBackup }

/// The backup (ADR-004 pkt 1-3): one encrypted file in the author's Drive, overwritten by every
/// backup. The phone keeps only the public key, so a backup never needs the passphrase; the secret
/// key lives in a separate file, encrypted with the passphrase. Restore = key file + passphrase +
/// backup file (ISSUE-009).
class BackupService {
  BackupService({
    required this.database,
    required this.location,
    required this.workDir,
    required this.settings,
    required this.documents,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GrobingDatabase database;
  final DataLocation location;

  /// Private scratch space for the snapshot and the encrypted file; emptied before and after use.
  final Directory workDir;
  final BackupSettingsStore settings;
  final DocumentStore documents;
  final DateTime Function() _clock;

  bool _running = false;

  Future<BackupSettings?> readSettings() => settings.read();

  /// One-time setup: a new key, the key file protected with [passphrase], the backup file, then the
  /// first backup. Returns null when the user closes a "save as" window — nothing is configured then
  /// (a key file saved before that is useless on its own). Running it again replaces the key.
  Future<BackupSettings?> setUp(
    String passphrase, {
    void Function(BackupSetupStep step)? onStep,
  }) async {
    if (passphrase.isEmpty) throw const BackupException('Wpisz hasło.');
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
      await settings.write(
        BackupSettings(recipient: key.recipient, documentUri: backupUri),
      );
    } on PlatformException catch (e) {
      throw BackupException(_documentProblem(e));
    } finally {
      await _deleteWorkDir();
    }

    onStep?.call(BackupSetupStep.firstBackup);
    return backUpNow();
  }

  /// Writes a backup now and records the outcome, which the returned settings carry: a failure is a
  /// result to show, not an exception. Throws only when the backup is not configured or already runs.
  Future<BackupSettings> backUpNow() async {
    final BackupSettings? current = await settings.read();
    if (current == null) {
      throw const BackupException('Kopia nie jest skonfigurowana.');
    }
    if (_running) throw const BackupException('Kopia już trwa.');
    _running = true;
    try {
      final DateTime createdAt = _clock().toUtc();
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

      final BackupSettings updated = current.succeeded(_clock());
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
