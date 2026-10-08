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

  test('empty database: schema 7, zero rows in every table, no photos', () async {
    final DataState state = await readDataState(db, mediaDir: media);

    expect(state.schemaVersion, 7);
    // v4 (ISSUE-017): person_media joins the 11 tables of v3, and the fingerprint finds it by itself.
    expect(state.rowCounts, hasLength(12));
    expect(state.rowCounts, contains('person_media'));
    expect(state.rowCounts.values, everyElement(0));
    expect(state.mediaFileCount, 0);
    expect(state.shortFingerprint, hasLength(16));
  });

  test('row counts follow the data', () async {
    await addFictionalData(db, media);

    final DataState state = await readDataState(db, mediaDir: media);

    // ISSUE-019: the father's two unions — with the mother (and their child), and after a parting with a
    // partner and a child buried nowhere: two more people, two families, four partners, two children.
    expect(state.rowCounts['persons'], 5);
    expect(state.rowCounts['families'], 2);
    expect(state.rowCounts['family_partners'], 4);
    expect(state.rowCounts['family_children'], 2);
    expect(state.rowCounts['burials'], 3);
    // One made-up dispute: the father's birth from the notes and from the grandmother (ISSUE-011); the
    // first union's marriage and end, the second's marriage, the second child's birth (ISSUE-019); the
    // second union's "Razem od" before its wedding (ISSUE-025).
    expect(state.rowCounts['events'], 9);
    // A claim on each event and burial, on each family and on each child's link (ADR-011).
    expect(state.rowCounts['assertions'], 16);
    // The gravestone, a portrait and a shared "wedding photo" (ISSUE-017): three rows, three files, and
    // three person links — the shared photo is one row and one file with two links.
    expect(state.rowCounts['media'], 3);
    expect(state.rowCounts['person_media'], 3);
    expect(state.mediaFileCount, 3);
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

    final File photo = media.listSync(recursive: true).whereType<File>().first;
    await photo.writeAsString('inna treść', mode: FileMode.append);
    final DataState after = await readDataState(db, mediaDir: media);

    expect(after.fingerprint, isNot(before.fingerprint));
    expect(after.rowCounts, before.rowCounts);
  });

  test(
    'ISSUE-018 — a changed crop alone changes the fingerprint: the crop is in the backup check',
    () async {
      await addFictionalData(db, media);
      final DataState before = await readDataState(db, mediaDir: media);

      await db.customStatement(
        'UPDATE person_media SET crop_left = crop_left + 1 '
        'WHERE crop_left IS NOT NULL',
      );
      final DataState after = await readDataState(db, mediaDir: media);

      expect(after.fingerprint, isNot(before.fingerprint));
      expect(after.rowCounts, before.rowCounts);
    },
  );

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
      expect(fromCopy.schemaVersion, GrobingDatabase.currentSchemaVersion);
    },
  );

  test(
    'ISSUE-019 — a claim on a family or a child\'s link is in the fingerprint: changing one changes it',
    () async {
      await addFictionalData(db, media);
      final DataState before = await readDataState(db, mediaDir: media);

      await db.customStatement(
        "UPDATE assertions SET status = 'confirmed' WHERE family_child_id IS NOT NULL "
        'AND id = (SELECT min(id) FROM assertions WHERE family_child_id IS NOT NULL)',
      );
      final DataState after = await readDataState(db, mediaDir: media);

      expect(after.fingerprint, isNot(before.fingerprint));
      expect(after.rowCounts, before.rowCounts);
    },
  );
}
