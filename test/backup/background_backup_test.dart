import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show QueryRow, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/age/age.dart';
import 'package:grobing/backup/background.dart';
import 'package:grobing/backup/background_backup.dart';
import 'package:grobing/backup/backup_archive.dart';
import 'package:grobing/backup/backup_service.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/backup/data_stamp.dart';
import 'package:grobing/backup/restore_service.dart';
import 'package:grobing/backup/restore_swap.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

import '../support/backup_fakes.dart';

// ISSUE-010: the background backup.
// AC-1: after a change of data a backup is made in the background without the passphrase; without a
//       change nothing is written (D2). It never touches a restore in progress, an unfinished restore
//       or a database at another schema version (D3), and it restores like any other backup (DoD).
// D3:   one operation on the data at a time — "Zrób kopię teraz", the setup and a restore refuse while
//       the lock is taken; two connections to one database wait for each other instead of failing.
// Data: made-up people only (`fictional_data.dart`).

const String _passphrase = 'hasło-testowe Żółć';

/// "Now" for the background run: a day after the test wrote its files, so the data has been quiet for
/// long enough (D2) unless a test sets the clock itself.
final DateTime _now = DateTime.now().toUtc().add(const Duration(days: 1));

/// The first unsaved change of a quiet session: recent enough that the cap does not decide.
final DateTime _firstChange = _now.subtract(const Duration(minutes: 1));

Future<Uint8List> _decrypt(File file, AgeIdentity identity) async {
  final BytesBuilder out = BytesBuilder();
  await for (final List<int> c in ageDecrypt(file.openRead(), [identity])) {
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

/// The phone's database file opened the way the app opens it, but in this isolate.
GrobingDatabase _open(File file) =>
    GrobingDatabase(NativeDatabase(file, setup: configureConnection));

void main() {
  // Two connections to one file are the point here (the app and the background backup), each in its
  // own isolate on the phone; drift's warning is about sharing one executor, which no test does.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late Directory dataDir;
  late DataLocation location;
  late FakeDocumentStore drive;
  late FakeDataLock lock;
  late X25519Identity identity;
  late BackupSettingsStore settings;
  late String backupUri;

  Directory workDir() => Directory('${tmp.path}/cache/backup');
  File backupFile() => drive.fileFor(backupUri);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_background_test');
    dataDir = Directory('${tmp.path}/data')..createSync();
    location = DataLocation.inDirectory(dataDir);
    drive = FakeDocumentStore(Directory('${tmp.path}/drive'));
    lock = FakeDataLock();
    settings = BackupSettingsStore(File('${dataDir.path}/backup.json'));

    // The app with made-up data, closed — as when the worker starts it in the background.
    final GrobingDatabase db = _open(location.databaseFile);
    await addFictionalData(db, location.mediaDir);
    await db.close();

    // A backup configured as setup leaves it (the key's scrypt runs in ISSUE-008's tests, not here):
    // the public key, the Drive file with a kept permission, no backup made yet.
    identity = X25519Identity.generate();
    backupUri = FakeDocumentStore.uriOf(backupFileName);
    backupFile().createSync(recursive: true);
    drive.kept.add(backupUri);
    await settings.write(
      BackupSettings(
        recipient: identity.recipient.encode(),
        documentUri: backupUri,
      ),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<BackgroundRun> run({
    DateTime? now,
    DateTime? firstChangeAt,
    int? schemaVersion,
    GrobingDatabase Function(File file)? openDatabase,
  }) => runBackgroundBackup(
    dataDir: dataDir,
    workDir: workDir(),
    lock: lock,
    documents: drive,
    firstChangeAt: firstChangeAt ?? _firstChange,
    schemaVersion: schemaVersion ?? GrobingDatabase.currentSchemaVersion,
    openDatabase: openDatabase ?? GrobingDatabase.atFile,
    clock: () => now ?? _now,
  );

  Future<BackgroundOutcome> runInBackground({
    int? schemaVersion,
    GrobingDatabase Function(File file)? openDatabase,
  }) async => (await run(
    schemaVersion: schemaVersion,
    openDatabase: openDatabase,
  )).outcome;

  Future<DataState> stateOnDisk() async {
    final GrobingDatabase db = _open(location.databaseFile);
    try {
      return await readDataState(db, mediaDir: location.mediaDir);
    } finally {
      await db.close();
    }
  }

  group('data stamp (D2)', () {
    test('opening, reading, VACUUM INTO and closing leave it alone', () async {
      final String before = await dataStamp(location);
      final GrobingDatabase db = _open(location.databaseFile);
      await readDataState(db, mediaDir: location.mediaDir);
      await db.customStatement('VACUUM INTO ?', ['${tmp.path}/snapshot.db']);
      await db.close();
      expect(await dataStamp(location), before);
    });

    test(
      'a committed write changes it — also when size and modification time stay the same '
      '(the SQLite file change counter)',
      () async {
        final File file = location.databaseFile;
        final GrobingDatabase db = _open(file);
        await db.customStatement(
          "UPDATE persons SET given_names = 'Aaaa' WHERE id = 1",
        );
        await db.close();
        final int size = file.lengthSync();
        final DateTime modified = file.lastModifiedSync();
        final String before = await dataStamp(location);

        final GrobingDatabase again = _open(file);
        await again.customStatement(
          "UPDATE persons SET given_names = 'Bbbb' WHERE id = 1",
        );
        await again.close();
        file.setLastModifiedSync(modified);

        expect(file.lengthSync(), size);
        expect(file.lastModifiedSync(), modified);
        expect(await dataStamp(location), isNot(before));
      },
    );

    test('a photo added or removed changes it', () async {
      final String before = await dataStamp(location);
      final File photo = File('${location.mediaDir.path}/nowe/zdjecie.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final String added = await dataStamp(location);
      expect(added, isNot(before));
      photo.deleteSync();
      expect(await dataStamp(location), isNot(added));
    });
  });

  group('AC-1 — the background run', () {
    test(
      'changed data → a backup without the passphrase, marked "in the background", that opens '
      'with the key and carries the data on disk',
      () async {
        final DataState source = await stateOnDisk();

        expect(await runInBackground(), BackgroundOutcome.done);

        final BackupSettings after = (await settings.read())!;
        expect(after.lastSuccessAt, _now);
        expect(after.lastSuccessInBackground, isTrue);
        expect(after.lastSuccessStamp, await dataStamp(location));
        expect(after.lastAttemptFailed, isFalse);
        final BackupManifest manifest = _manifestOf(
          await _decrypt(backupFile(), identity),
        );
        expect(manifest.dataFingerprint, source.fingerprint);
        expect(manifest.recordCounts, source.rowCounts);
        // No snapshot in the clear left behind, the lock free again.
        expect(workDir().existsSync(), isFalse);
        expect(lock.held, isFalse);
        expect(lock.acquired, 1);
      },
    );

    test('no change since the last backup → nothing written', () async {
      expect(await runInBackground(), BackgroundOutcome.done);
      final List<int> written = backupFile().readAsBytesSync();
      final String settingsAfter = File(
        '${dataDir.path}/backup.json',
      ).readAsStringSync();

      expect(await runInBackground(), BackgroundOutcome.done);

      // age encryption is randomised: a new backup would change every byte.
      expect(backupFile().readAsBytesSync(), written);
      expect(
        File('${dataDir.path}/backup.json').readAsStringSync(),
        settingsAfter,
      );
    });

    test(
      'after a backup from the button, the same data is not backed up again',
      () async {
        final GrobingDatabase db = _open(location.databaseFile);
        final BackupService button = BackupService(
          database: db,
          location: location,
          workDir: workDir(),
          settings: settings,
          documents: drive,
          lock: lock,
          clock: () => _now,
        );
        await button.backUpNow();
        await db.close();
        final List<int> written = backupFile().readAsBytesSync();

        expect(await runInBackground(), BackgroundOutcome.done);
        expect(backupFile().readAsBytesSync(), written);
        expect((await settings.read())!.lastSuccessInBackground, isFalse);
      },
    );

    test(
      'the app open at the same time (a second connection) → backup made, app goes on',
      () async {
        final GrobingDatabase app = GrobingDatabase.atFile(
          location.databaseFile,
        );
        await addFictionalData(app, location.mediaDir);

        expect(await runInBackground(), BackgroundOutcome.done);

        expect((await settings.read())!.lastSuccessInBackground, isTrue);
        // The app's connection still writes.
        await addFictionalData(app, location.mediaDir);
        await app.close();
        expect(
          await dataStamp(location),
          isNot((await settings.read())!.lastSuccessStamp),
        );
      },
    );

    test('data changed while the backup ran → "again"', () async {
      final _ChangingDrive changing = _ChangingDrive(drive, () async {
        final GrobingDatabase app = _open(location.databaseFile);
        await addFictionalData(app, location.mediaDir);
        await app.close();
      });
      final BackgroundRun result = await runBackgroundBackup(
        dataDir: dataDir,
        workDir: workDir(),
        lock: lock,
        documents: changing,
        firstChangeAt: _firstChange,
        clock: () => _now,
      );

      // The next backup waits for the data to go quiet again.
      expect(result, (outcome: BackgroundOutcome.again, wait: backupQuiet));
      expect(
        (await settings.read())!.lastSuccessStamp,
        isNot(await dataStamp(location)),
      );
    });

    test(
      'Drive refuses → "retry", the failure recorded for the screen, the lock free',
      () async {
        drive.writeError = PlatformException(code: 'write_failed');

        expect(await runInBackground(), BackgroundOutcome.retry);

        final BackupSettings after = (await settings.read())!;
        expect(after.lastAttemptFailed, isTrue);
        expect(after.lastFailure, contains('Nie udało się zapisać'));
        expect(after.lastSuccessStamp, isNull);
        expect(lock.held, isFalse);
        expect(workDir().existsSync(), isFalse);
      },
    );

    test(
      'the lock taken (restore, setup, the button) → "retry", nothing touched',
      () async {
        lock.held = true;
        final String settingsBefore = File(
          '${dataDir.path}/backup.json',
        ).readAsStringSync();

        expect(await runInBackground(), BackgroundOutcome.retry);

        expect(backupFile().lengthSync(), 0);
        expect(
          File('${dataDir.path}/backup.json').readAsStringSync(),
          settingsBefore,
        );
        expect(lock.held, isTrue, reason: 'the other holder keeps it');
      },
    );

    test(
      'a restore marker → done without a backup; the marker is the app start\'s',
      () async {
        final File marker = File('${dataDir.path}/$restoreMarkerName')
          ..writeAsStringSync('{"items":["grobing.db"]}');
        final DataState before = await stateOnDisk();

        expect(await runInBackground(), BackgroundOutcome.done);

        expect(marker.existsSync(), isTrue);
        expect(backupFile().lengthSync(), 0);
        expect((await settings.read())!.lastSuccessAt, isNull);
        expect((await stateOnDisk()).fingerprint, before.fingerprint);
        expect(lock.held, isFalse);
      },
    );

    test(
      'a database at another schema version → done without a backup and without migrating',
      () async {
        bool opened = false;
        expect(
          await runInBackground(
            schemaVersion: 2,
            openDatabase: (file) {
              opened = true;
              return GrobingDatabase.atFile(file);
            },
          ),
          BackgroundOutcome.done,
        );

        expect(opened, isFalse);
        expect(backupFile().lengthSync(), 0);
        final GrobingDatabase db = _open(location.databaseFile);
        final QueryRow row = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        await db.close();
        expect(row.read<int>('user_version'), 1);
        expect(lock.held, isFalse);
      },
    );

    test('no backup configured → done, the lock never taken', () async {
      File('${dataDir.path}/backup.json').deleteSync();
      expect(await runInBackground(), BackgroundOutcome.done);
      expect(lock.acquired, 0);
    });

    test(
      'próbne odtworzenie: a backup made in the background restores on a fresh phone with the '
      'source fingerprint',
      () async {
        final DataState source = await stateOnDisk();
        expect(await runInBackground(), BackgroundOutcome.done);

        // The key file the setup would have written, with a cheap scrypt for speed.
        final BytesBuilder keyFile = BytesBuilder();
        await for (final List<int> c in ageEncrypt(
          Stream.value(utf8.encode(encodeIdentityFile(identity, _now))),
          [ScryptRecipient(_passphrase, workFactor: 10)],
        )) {
          keyFile.add(c);
        }
        final String keyUri = FakeDocumentStore.uriOf(backupKeyFileName);
        drive.fileFor(keyUri)
          ..createSync(recursive: true)
          ..writeAsBytesSync(keyFile.takeBytes());

        final Directory fresh = Directory('${tmp.path}/fresh')..createSync();
        final GrobingDatabase freshDb = _open(File('${fresh.path}/grobing.db'));
        await freshDb.customSelect('SELECT 1').get();
        final RestoreResult result =
            await restoreServiceIn(fresh, freshDb, drive).restore(
              backupUri: backupUri,
              keyUri: keyUri,
              passphrase: _passphrase,
            );

        expect(result.dataFingerprint, source.fingerprint);
        final GrobingDatabase restored = _open(
          File('${fresh.path}/grobing.db'),
        );
        final DataState onDisk = await readDataState(
          restored,
          mediaDir: Directory('${fresh.path}/media'),
        );
        await restored.close();
        expect(onDisk.fingerprint, source.fingerprint);
        expect(onDisk.rowCounts, source.rowCounts);
      },
    );
  });

  group('D2 — one backup per session: the run waits for the data to go quiet', () {
    late DateTime lastChange;

    setUp(() async => lastChange = (await lastDataChange(location))!);

    Future<void> expectNothingWritten() async {
      expect(backupFile().lengthSync(), 0);
      expect((await settings.read())!.lastSuccessAt, isNull);
      expect(lock.held, isFalse);
    }

    test(
      'changed a minute ago → "later", for the rest of the 10 minutes; nothing written',
      () async {
        final DateTime now = lastChange.add(const Duration(minutes: 1));
        expect(await run(now: now, firstChangeAt: now), (
          outcome: BackgroundOutcome.later,
          wait: const Duration(minutes: 9),
        ));
        await expectNothingWritten();
      },
    );

    test('quiet for 10 minutes → the backup', () async {
      final DateTime now = lastChange.add(backupQuiet);
      expect(
        (await run(now: now, firstChangeAt: now)).outcome,
        BackgroundOutcome.done,
      );
      expect((await settings.read())!.lastSuccessInBackground, isTrue);
    });

    test(
      'still changing, but the first unsaved change is an hour old → the backup (cap)',
      () async {
        final DateTime now = lastChange.add(const Duration(minutes: 1));
        expect(
          (await run(now: now, firstChangeAt: now.subtract(backupCap))).outcome,
          BackgroundOutcome.done,
        );
        expect((await settings.read())!.lastSuccessInBackground, isTrue);
      },
    );

    test('the wait never runs past the cap', () async {
      final DateTime now = lastChange.add(const Duration(minutes: 1));
      expect(
        await run(
          now: now,
          firstChangeAt: now.subtract(const Duration(minutes: 55)),
        ),
        (outcome: BackgroundOutcome.later, wait: const Duration(minutes: 5)),
      );
    });

    test(
      'a clock that moved back (the change "in the future") never makes it wait',
      () async {
        final DateTime now = lastChange.subtract(const Duration(hours: 1));
        expect(
          (await run(now: now, firstChangeAt: now)).outcome,
          BackgroundOutcome.done,
        );
      },
    );

    test(
      'nothing changed since the last backup → done, without waiting for anything',
      () async {
        expect((await run()).outcome, BackgroundOutcome.done);
        final DateTime now = lastChange.add(const Duration(seconds: 30));
        expect(await run(now: now, firstChangeAt: now), (
          outcome: BackgroundOutcome.done,
          wait: Duration.zero,
        ));
      },
    );
  });

  group(
    'AC-1 — triggers: leaving and starting the app ask only when the data changed',
    () {
      late GrobingDatabase db;
      late FakeBackgroundBackups background;
      late BackupService service;

      setUp(() {
        db = _open(location.databaseFile);
        background = FakeBackgroundBackups();
        service = BackupService(
          database: db,
          location: location,
          workDir: workDir(),
          settings: settings,
          documents: drive,
          lock: lock,
          background: background,
          clock: () => _now,
        );
      });

      tearDown(() => db.close());

      test(
        'changed since the last backup (here: none yet) → one request',
        () async {
          await service.requestBackgroundIfChanged();
          expect(background.requests, 1);
        },
      );

      test(
        'right after a backup → no request; after a change → a request',
        () async {
          await service.backUpNow();
          await service.requestBackgroundIfChanged();
          expect(background.requests, 0);

          await addFictionalData(db, location.mediaDir);
          await service.requestBackgroundIfChanged();
          expect(background.requests, 1);
        },
      );

      test('backup not configured → no request', () async {
        File('${dataDir.path}/backup.json').deleteSync();
        await service.requestBackgroundIfChanged();
        expect(background.requests, 0);
      });

      test('a failing request never reaches the app', () async {
        background.error = PlatformException(code: 'request_failed');
        await expectLater(service.requestBackgroundIfChanged(), completes);
      });

      test(
        'settings written before ISSUE-010 (no stamp) read as "changed"',
        () async {
          File('${dataDir.path}/backup.json').writeAsStringSync(
            jsonEncode({
              'recipient': identity.recipient.encode(),
              'document_uri': backupUri,
              'last_success_at': '2026-10-06T08:42:03.580794Z',
              'last_failure_at': null,
              'last_failure': null,
            }),
          );
          final BackupSettings old = (await settings.read())!;
          expect(old.lastSuccessStamp, isNull);
          expect(old.lastSuccessInBackground, isFalse);
          expect(await service.changedSinceLastBackup(), isTrue);
        },
      );

      test(
        'every write asks (stop #2: the request is stored before the app can be closed); a burst '
        'of writes makes few requests and loses none',
        () async {
          final StreamSubscription<Object?> changes = service.watchChanges();
          await addFictionalData(db, location.mediaDir);
          for (int i = 0; i < 100 && background.requests == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(background.requests, inInclusiveRange(1, 2));

          // After a backup the next write asks again; a cancelled watch asks no more.
          await service.backUpNow();
          final int before = background.requests;
          await addFictionalData(db, location.mediaDir);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(background.requests, greaterThan(before));

          await changes.cancel();
          final int cancelled = background.requests;
          await addFictionalData(db, location.mediaDir);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(background.requests, cancelled);
        },
      );
    },
  );

  group('D3 — one operation on the data at a time', () {
    late GrobingDatabase db;

    setUp(() => db = _open(location.databaseFile));
    tearDown(() => db.close());

    BackupService buttonService() => BackupService(
      database: db,
      location: location,
      workDir: workDir(),
      settings: settings,
      documents: drive,
      lock: lock,
      clock: () => _now,
    );

    test(
      '"Zrób kopię teraz" while the background backup runs → refused, nothing written',
      () async {
        lock.held = true;
        await expectLater(
          buttonService().backUpNow(),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'message',
              dataBusyMessage,
            ),
          ),
        );
        expect(backupFile().lengthSync(), 0);
        expect((await settings.read())!.lastSuccessAt, isNull);
        expect(lock.held, isTrue);
      },
    );

    test(
      'setup while the lock is taken → refused before any window opens',
      () async {
        File('${dataDir.path}/backup.json').deleteSync();
        lock.held = true;
        final FakeDocumentStore windows = FakeDocumentStore(
          Directory('${tmp.path}/drive2'),
        );
        await expectLater(
          BackupService(
            database: db,
            location: location,
            workDir: workDir(),
            settings: settings,
            documents: windows,
            lock: lock,
          ).setUp(_passphrase),
          throwsA(isA<BackupException>()),
        );
        expect(windows.suggestedNames, isEmpty);
        expect(await settings.read(), isNull);
      },
    );

    test(
      'a restore while the lock is taken → refused, the phone untouched',
      () async {
        lock.held = true;
        final DataState before = await readDataState(
          db,
          mediaDir: location.mediaDir,
        );
        final RestoreService restore = restoreServiceIn(
          dataDir,
          db,
          drive,
          lock: lock,
        );
        await expectLater(
          restore.restore(
            backupUri: backupUri,
            keyUri: FakeDocumentStore.uriOf(backupKeyFileName),
            passphrase: _passphrase,
          ),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'message',
              dataBusyMessage,
            ),
          ),
        );
        expect(restore.databaseClosed, isFalse);
        expect(
          Directory('${dataDir.path}/$restoreStagingName').existsSync(),
          isFalse,
        );
        expect(
          (await readDataState(db, mediaDir: location.mediaDir)).fingerprint,
          before.fingerprint,
        );
      },
    );

    test(
      'the lock is released after every outcome: success, failure, closed window, refused '
      'restore',
      () async {
        await buttonService().backUpNow();
        expect(lock.held, isFalse);

        drive.writeError = PlatformException(code: 'write_failed');
        await buttonService().backUpNow();
        expect(lock.held, isFalse);
        drive.writeError = null;

        // The "save as" window closed during a new setup.
        await BackupService(
          database: db,
          location: location,
          workDir: workDir(),
          settings: settings,
          documents: FakeDocumentStore(
            Directory('${tmp.path}/drive3'),
            answers: [null],
          ),
          lock: lock,
        ).setUp(_passphrase);
        expect(lock.held, isFalse);

        // A restore refused for a missing backup file.
        await expectLater(
          restoreServiceIn(dataDir, db, drive, lock: lock).restore(
            backupUri: FakeDocumentStore.uriOf('nie-ma.age'),
            keyUri: FakeDocumentStore.uriOf('nie-ma-klucza.age'),
            passphrase: _passphrase,
          ),
          throwsA(isA<BackupException>()),
        );
        expect(lock.held, isFalse);
      },
    );
  });

  group('D3 — two connections to one database (busy_timeout)', () {
    /// Holds a read transaction — the lock `VACUUM INTO` keeps while it copies — until [release].
    Future<void> holdReadLock(
      GrobingDatabase reader,
      Completer<void> holding,
      Future<void> release,
    ) => reader.transaction(() async {
      await reader.customSelect('SELECT count(*) FROM persons').get();
      holding.complete();
      await release;
    });

    test(
      'a write in the app waits for the backup\'s read lock instead of failing',
      () async {
        final GrobingDatabase backup = GrobingDatabase.atFile(
          location.databaseFile,
        );
        final GrobingDatabase app = GrobingDatabase.atFile(
          location.databaseFile,
        );
        final Completer<void> holding = Completer<void>();
        final Completer<void> release = Completer<void>();
        final Future<void> reading = holdReadLock(
          backup,
          holding,
          release.future,
        );
        await holding.future;

        final Future<void> writing = addFictionalData(app, location.mediaDir);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        release.complete();

        await reading;
        await expectLater(writing, completes);
        await backup.close();
        await app.close();
      },
    );

    test(
      'control: without busy_timeout the same write fails at once (database is locked)',
      () async {
        final GrobingDatabase backup = GrobingDatabase.atFile(
          location.databaseFile,
        );
        final GrobingDatabase bare = GrobingDatabase(
          NativeDatabase.createInBackground(location.databaseFile),
        );
        final Completer<void> holding = Completer<void>();
        final Completer<void> release = Completer<void>();
        final Future<void> reading = holdReadLock(
          backup,
          holding,
          release.future,
        );
        await holding.future;

        Object? failure;
        try {
          await addFictionalData(bare, location.mediaDir);
        } on Object catch (e) {
          failure = e;
        }
        release.complete();
        await reading;
        await backup.close();
        await bare.close();

        expect(failure, isNotNull);
        expect(failure.toString(), contains('database is locked'));
      },
    );

    test(
      'VACUUM INTO from a second connection while the app keeps writing → every snapshot and '
      'the database pass integrity_check',
      () async {
        final GrobingDatabase app = GrobingDatabase.atFile(
          location.databaseFile,
        );
        final GrobingDatabase backup = GrobingDatabase.atFile(
          location.databaseFile,
        );
        final Future<void> writes = () async {
          for (int i = 0; i < 10; i++) {
            await addFictionalData(app, location.mediaDir);
          }
        }();
        final List<String> snapshots = [];
        for (int i = 0; i < 5; i++) {
          final String path = '${tmp.path}/snapshot-$i.db';
          await backup.customStatement('VACUUM INTO ?', [path]);
          snapshots.add(path);
        }
        await writes;
        await app.close();
        await backup.close();

        for (final String path in [location.databaseFile.path, ...snapshots]) {
          final GrobingDatabase check = _open(File(path));
          final List<QueryRow> rows = await check
              .customSelect('PRAGMA integrity_check')
              .get();
          await check.close();
          expect(rows.single.data.values.single, 'ok', reason: path);
        }
      },
    );
  });
}

/// "Drive" that changes the phone's data while the backup is being written to it.
class _ChangingDrive extends FakeDocumentStore {
  _ChangingDrive(FakeDocumentStore inner, this.change) : super(inner.root) {
    kept.addAll(inner.kept);
  }

  final Future<void> Function() change;

  @override
  Future<void> writeFile(String uri, File file) async {
    await change();
    await super.writeFile(uri, file);
  }
}
