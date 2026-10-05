import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

// ISSUE-007 AC-3: the "Stan danych" numbers and the fingerprint that backup and restore are checked
// against (NFR-002 → Method). All data here is made up (family-data.md).

void main() {
  late Directory tmp;
  late Directory media;
  late GrobingDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('grobing_state_test');
    media = Directory('${tmp.path}/media');
    db = GrobingDatabase(NativeDatabase(File('${tmp.path}/grobing.db')));
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test(
    'empty database: schema 1, zero rows in every table, no photos',
    () async {
      final DataState state = await readDataState(db, mediaDir: media);

      expect(state.schemaVersion, 1);
      expect(state.rowCounts, hasLength(10));
      expect(state.rowCounts.values, everyElement(0));
      expect(state.mediaFileCount, 0);
      expect(state.shortFingerprint, hasLength(16));
    },
  );

  test('row counts follow the data', () async {
    await addFictionalData(db, media);

    final DataState state = await readDataState(db, mediaDir: media);

    expect(state.rowCounts['persons'], 3);
    expect(state.rowCounts['families'], 1);
    expect(state.rowCounts['burials'], 3);
    expect(state.rowCounts['events'], 4);
    expect(state.mediaFileCount, 1);
  });

  test(
    'the same data gives the same fingerprint; one changed value changes it',
    () async {
      final DataState empty = await readDataState(db, mediaDir: media);
      await addFictionalData(db, media);
      final DataState first = await readDataState(db, mediaDir: media);
      final DataState again = await readDataState(db, mediaDir: media);

      expect(first.fingerprint, isNot(empty.fingerprint));
      expect(again.fingerprint, first.fingerprint);

      await (db.update(db.persons)..where((p) => p.id.equals(1))).write(
        const PersonsCompanion(bio: Value('Inny opis.')),
      );
      final DataState changed = await readDataState(db, mediaDir: media);
      expect(changed.fingerprint, isNot(first.fingerprint));
    },
  );

  test('a changed photo file changes the fingerprint', () async {
    await addFictionalData(db, media);
    final DataState before = await readDataState(db, mediaDir: media);

    final File photo = media.listSync(recursive: true).whereType<File>().single;
    await photo.writeAsString('inna treść', mode: FileMode.append);
    final DataState after = await readDataState(db, mediaDir: media);

    expect(after.fingerprint, isNot(before.fingerprint));
    expect(after.rowCounts, before.rowCounts);
  });

  test(
    'a VACUUM INTO snapshot has the same fingerprint: it measures content, not the file',
    () async {
      await addFictionalData(db, media);
      final DataState original = await readDataState(db, mediaDir: media);

      final File snapshot = File('${tmp.path}/snapshot.db');
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);
      final GrobingDatabase copy = GrobingDatabase(NativeDatabase(snapshot));
      addTearDown(copy.close);

      final DataState fromCopy = await readDataState(copy, mediaDir: media);
      expect(fromCopy.fingerprint, original.fingerprint);
      expect(fromCopy.schemaVersion, 1);
    },
  );
}
