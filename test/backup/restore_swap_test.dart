import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/restore_swap.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

// ISSUE-009 AC-4: an interruption while the data is being replaced leaves, at the next start, the old
// data or the new data — never neither. Every step of the swap is interrupted in turn (a throw from
// the test hook stands in for the process dying there), then the start-up recovery runs.

class _Crash implements Exception {}

/// Every place the swap can stop, in order, as `commitRestore` reports them.
const List<String> _steps = [
  'marker',
  'aside:backup.json',
  'in:backup.json',
  'aside:grobing.db',
  'in:grobing.db',
  'aside:media',
  'in:media',
  'committed',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late Directory phone;
  late String oldFingerprint;
  late String newFingerprint;

  Future<String> fingerprintOf(Directory dir) async {
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(File('${dir.path}/grobing.db')),
    );
    try {
      return (await readDataState(
        db,
        mediaDir: Directory('${dir.path}/media'),
      )).fingerprint;
    } finally {
      await db.close();
    }
  }

  /// Data in [dir]: made-up people [batches] times, with their photos.
  Future<void> fill(Directory dir, int batches) async {
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(File('${dir.path}/grobing.db')),
    );
    for (int i = 0; i < batches; i++) {
      await addFictionalData(db, Directory('${dir.path}/media'));
    }
    await db.close();
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_restore_swap_test');
    phone = Directory('${tmp.path}/phone')..createSync();
    // Old data: two batches, a backup setting and a hot journal of the old database.
    await fill(phone, 2);
    oldFingerprint = await fingerprintOf(phone);
    File('${phone.path}/backup.json').writeAsStringSync('{"old": true}');
    File('${phone.path}/grobing.db-journal').writeAsStringSync('old journal');
    File('${phone.path}/grobing.db-wal').writeAsStringSync('old wal');

    // New data, prepared as restore leaves it: one batch, plus the backup setting D3 writes.
    final Directory incoming = restoreIncomingDir(phone)
      ..createSync(recursive: true);
    await fill(incoming, 1);
    newFingerprint = await fingerprintOf(incoming);
    File('${incoming.path}/backup.json').writeAsStringSync('{"new": true}');
    expect(newFingerprint, isNot(oldFingerprint));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// What the next start finds, after recovery: 'old' or 'new' — and no leftovers.
  Future<String> afterRestart() async {
    await completePendingRestore(phone);
    final String fingerprint = await fingerprintOf(phone);
    final String backupJson = File(
      '${phone.path}/backup.json',
    ).readAsStringSync();
    final String which = fingerprint == newFingerprint
        ? 'new'
        : fingerprint == oldFingerprint
        ? 'old'
        : 'neither';
    // The setting always travels with its data.
    expect(backupJson, which == 'new' ? '{"new": true}' : '{"old": true}');
    // The old database's journal never stays next to the new database.
    if (which == 'new') {
      expect(File('${phone.path}/grobing.db-journal').existsSync(), isFalse);
      expect(File('${phone.path}/grobing.db-wal').existsSync(), isFalse);
    }
    expect(File('${phone.path}/$restoreMarkerName').existsSync(), isFalse);
    expect(
      Directory('${phone.path}/$restoreStagingName').existsSync(),
      isFalse,
    );
    expect(Directory('${phone.path}/$restoreOldName').existsSync(), isFalse);
    return which;
  }

  test('the swap reports exactly these steps', () async {
    final List<String> seen = [];
    await commitRestore(phone, onStep: seen.add);
    expect(seen, _steps);
    expect(await afterRestart(), 'new');
  });

  test(
    'interrupted before the commit point (marker half-written) → old data',
    () async {
      File('${phone.path}/$restoreMarkerName.tmp').writeAsStringSync('{"ite');
      expect(await afterRestart(), 'old');
      expect(
        File('${phone.path}/$restoreMarkerName.tmp').existsSync(),
        isFalse,
      );
    },
  );

  for (final String step in _steps) {
    test(
      'interrupted right after "$step" → new data at the next start',
      () async {
        await expectLater(
          commitRestore(
            phone,
            onStep: (s) {
              if (s == step) throw _Crash();
            },
          ),
          throwsA(isA<_Crash>()),
        );
        expect(await afterRestart(), 'new');
      },
    );
  }

  test(
    'the recovery itself interrupted at every step, then run again → new data',
    () async {
      await expectLater(
        commitRestore(
          phone,
          onStep: (s) {
            if (s == 'marker') throw _Crash();
          },
        ),
        throwsA(isA<_Crash>()),
      );
      for (final String step in _steps.skip(1)) {
        try {
          await completePendingRestore(
            phone,
            onStep: (s) {
              if (s == step) throw _Crash();
            },
          );
        } on _Crash {
          // The phone died during recovery; the next start recovers again.
        }
      }
      expect(await afterRestart(), 'new');
    },
  );

  test(
    'without a marker, leftovers are cleared and the live data is untouched',
    () async {
      Directory(
        '${phone.path}/$restoreOldName/media',
      ).createSync(recursive: true);
      expect(await completePendingRestore(phone), isFalse);
      expect(await afterRestart(), 'old');
    },
  );

  test('a restore without photos still replaces the photo directory', () async {
    Directory(
      '${restoreIncomingDir(phone).path}/media',
    ).deleteSync(recursive: true);
    await commitRestore(phone);
    expect(Directory('${phone.path}/media').listSync(), isEmpty);
  });

  test(
    'committing with nothing prepared is refused, nothing changes',
    () async {
      restoreIncomingDir(phone).deleteSync(recursive: true);
      await expectLater(commitRestore(phone), throwsStateError);
      expect(await afterRestart(), 'old');
    },
  );
}
