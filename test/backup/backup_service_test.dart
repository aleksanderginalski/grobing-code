import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/age/age.dart';
import 'package:grobing/backup/backup_archive.dart';
import 'package:grobing/backup/backup_service.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

import '../support/backup_fakes.dart';

// ISSUE-008 AC-1: one-time setup (key file protected with the passphrase, backup file, first backup)
// and "Zrób kopię teraz", with the system "save as" window and Drive replaced by files. What reaches
// "Drive" must open with the key file + passphrase and carry the live data's fingerprint.

const String _passphrase = 'hasło-testowe Żółć';

Future<Uint8List> _decrypt(File file, List<AgeIdentity> identities) async {
  final BytesBuilder out = BytesBuilder();
  await for (final List<int> c in ageDecrypt(file.openRead(), identities)) {
    out.add(c);
  }
  return out.takeBytes();
}

/// The manifest: the last file in the tar, found by its name in the header.
BackupManifest _manifestOf(Uint8List tar) {
  int offset = 0;
  while (true) {
    final String name = ascii
        .decode(tar.sublist(offset, offset + 100))
        .replaceAll('\x00', '');
    final int size = int.parse(
      ascii.decode(tar.sublist(offset + 124, offset + 135)),
      radix: 8,
    );
    if (name == backupManifestName) {
      return BackupManifest.fromJson(
        jsonDecode(utf8.decode(tar.sublist(offset + 512, offset + 512 + size)))
            as Map<String, Object?>,
      );
    }
    offset += 512 + (size + 511) ~/ 512 * 512;
  }
}

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late DataLocation location;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_backup_service_test');
    location = DataLocation.inDirectory(Directory('${tmp.path}/data'));
    db = GrobingDatabase(NativeDatabase.memory());
    await addFictionalData(db, location.mediaDir);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test(
    'setup: key file opens with the passphrase, the first backup opens with that key and carries '
    'the live fingerprint; no secret is kept and no scratch file is left',
    () async {
      final FakeDocumentStore drive = FakeDocumentStore(
        Directory('${tmp.path}/drive'),
      );
      final DateTime now = DateTime.utc(2026, 10, 6, 12);
      final BackupService backup = backupServiceIn(
        tmp,
        db,
        drive,
        clock: () => now,
      );
      final List<BackupSetupStep> steps = [];

      final BackupSettings? settings = await backup.setUp(
        _passphrase,
        onStep: steps.add,
      );

      expect(settings, isNotNull);
      expect(settings!.lastSuccessAt, now);
      expect(settings.lastAttemptFailed, isFalse);
      expect(steps, BackupSetupStep.values);
      expect(drive.suggestedNames, [backupKeyFileName, backupFileName]);
      // Only the backup file keeps a permission; the key file is written once.
      expect(drive.kept, {settings.documentUri});

      // Key file: an age file to the passphrase, work factor 18, holding the identity.
      final File keyFile = drive.fileFor('content://fake/$backupKeyFileName');
      expect(
        utf8.decode(
          keyFile.readAsBytesSync().sublist(0, 60),
          allowMalformed: true,
        ),
        contains('-> scrypt '),
      );
      final List<X25519Identity> identities = parseIdentityFile(
        utf8.decode(await _decrypt(keyFile, [ScryptIdentity(_passphrase)])),
      );
      expect(identities.single.recipient.encode(), settings.recipient);

      // Backup file: opens with that identity; the manifest has the live data's fingerprint.
      final Uint8List tar = await _decrypt(
        drive.fileFor(settings.documentUri),
        identities,
      );
      final DataState live = await readDataState(
        db,
        mediaDir: location.mediaDir,
      );
      expect(_manifestOf(tar).dataFingerprint, live.fingerprint);

      // Nothing secret on the phone, nothing left in the scratch space.
      final String stored = File(
        '${tmp.path}/data/backup.json',
      ).readAsStringSync();
      expect(stored, isNot(contains(_passphrase)));
      expect(stored, isNot(contains('AGE-SECRET-KEY')));
      expect(stored, contains(settings.recipient));
      expect(Directory('${tmp.path}/cache/backup').existsSync(), isFalse);
    },
  );

  for (final (String window, List<String?> answers) in [
    ('key file', [null]),
    ('backup file', [backupKeyFileName, null]),
  ]) {
    test('closing the $window window configures nothing', () async {
      final FakeDocumentStore drive = FakeDocumentStore(
        Directory('${tmp.path}/drive'),
        answers: answers,
      );
      final BackupService backup = backupServiceIn(tmp, db, drive);

      expect(await backup.setUp(_passphrase), isNull);
      expect(await backup.readSettings(), isNull);
      expect(drive.kept, isEmpty);
      expect(Directory('${tmp.path}/cache/backup').existsSync(), isFalse);
    });
  }

  /// A photo file no `media` row names, last modified [age] ago (ISSUE-016, D3).
  File orphan(String name, Duration age) =>
      File('${location.mediaDir.path}/groby/9/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3])
        ..setLastModifiedSync(DateTime.now().subtract(age));

  group('ISSUE-016 D3 — the sweep at start', () {
    test(
      'takes the lock, removes a file without a row older than an hour, keeps a fresh one',
      () async {
        final FakeDataLock lock = FakeDataLock();
        final File old = orphan('stare.jpg', const Duration(hours: 2));
        final File fresh = orphan('swieze.jpg', Duration.zero);

        await backupServiceIn(
          tmp,
          db,
          FakeDocumentStore(Directory('${tmp.path}/drive')),
          lock: lock,
        ).requestBackgroundOnStart();

        expect(old.existsSync(), isFalse);
        expect(fresh.existsSync(), isTrue);
        expect(lock.acquired, 1);
        expect(lock.held, isFalse);
      },
    );

    test('leaves the files alone while a backup holds the lock', () async {
      final FakeDataLock lock = FakeDataLock()..held = true;
      final File old = orphan('stare.jpg', const Duration(hours: 2));

      await backupServiceIn(
        tmp,
        db,
        FakeDocumentStore(Directory('${tmp.path}/drive')),
        lock: lock,
      ).requestBackgroundOnStart();

      expect(old.existsSync(), isTrue);
      expect(lock.held, isTrue, reason: 'the backup\'s lock is not released');
    });
  });

  group('"Zrób kopię teraz"', () {
    late FakeDocumentStore drive;
    late BackupService backup;
    late DateTime now;

    setUp(() async {
      drive = FakeDocumentStore(Directory('${tmp.path}/drive'));
      now = DateTime.utc(2026, 10, 6, 12);
      backup = backupServiceIn(tmp, db, drive, clock: () => now);
      await backup.setUp(_passphrase);
    });

    test(
      'ISSUE-016 D3 — sweeps photo files without a row before its stamp: the old one goes, the '
      'fresh one is backed up, and nothing looks changed afterwards',
      () async {
        final File old = orphan('stare.jpg', const Duration(hours: 2));
        final File fresh = orphan('swieze.jpg', Duration.zero);
        now = DateTime.utc(2026, 10, 6, 13);

        final BackupSettings settings = await backup.backUpNow();

        expect(settings.lastAttemptFailed, isFalse);
        expect(old.existsSync(), isFalse);
        expect(fresh.existsSync(), isTrue);
        expect(await backup.changedSinceLastBackup(), isFalse);
      },
    );

    test(
      'overwrites the file with the current data and records the time',
      () async {
        final File file = drive.fileFor(
          (await backup.readSettings())!.documentUri,
        );
        final int before = file.lengthSync();
        await addFictionalData(db, location.mediaDir);
        now = DateTime.utc(2026, 10, 6, 13);

        final BackupSettings settings = await backup.backUpNow();

        expect(settings.lastSuccessAt, now);
        expect(file.lengthSync(), greaterThan(before));
        expect(Directory('${tmp.path}/cache/backup').existsSync(), isFalse);
      },
    );

    test(
      'a failed write is recorded and shown, the last success stays',
      () async {
        drive.writeError = PlatformException(code: 'not_found');
        now = DateTime.utc(2026, 10, 6, 13);

        final BackupSettings settings = await backup.backUpNow();

        expect(settings.lastSuccessAt, DateTime.utc(2026, 10, 6, 12));
        expect(settings.lastAttemptFailed, isTrue);
        expect(settings.lastFailure, contains('Skonfiguruj kopię od nowa'));
        expect((await backup.readSettings())!.lastAttemptFailed, isTrue);
      },
    );

    test(
      'lost access to the file is a recorded failure, not a crash',
      () async {
        drive.kept.clear();
        now = DateTime.utc(2026, 10, 6, 13);
        final BackupSettings settings = await backup.backUpNow();
        expect(settings.lastAttemptFailed, isTrue);
        expect(settings.lastFailure, contains('nie ma już dostępu'));
      },
    );
  });

  test('backing up before setup is refused', () async {
    final BackupService backup = backupServiceIn(
      tmp,
      db,
      FakeDocumentStore(Directory('${tmp.path}/drive')),
    );
    await expectLater(backup.backUpNow(), throwsA(isA<BackupException>()));
  });
}
