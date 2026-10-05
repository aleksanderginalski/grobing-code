import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/database.dart';

// ISSUE-007 AC-1 and AC-2. All data here is made up (family-data.md).

const List<String> _v1Tables = [
  'burials',
  'cemeteries',
  'events',
  'families',
  'family_children',
  'family_partners',
  'graves',
  'media',
  'persons',
  'settings',
];

Future<Object?> _single(GrobingDatabase db, String sql) async =>
    (await db.customSelect(sql).getSingle()).data.values.single;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('grobing_db_test');
  });

  tearDown(() => tmp.delete(recursive: true));

  group('AC-2 — a fresh database is schema v1', () {
    test(
      'user_version 1, integrity ok, exactly the v1 tables, foreign keys on',
      () async {
        final GrobingDatabase db = GrobingDatabase(
          NativeDatabase(File('${tmp.path}/grobing.db')),
        );
        addTearDown(db.close);

        expect(await _single(db, 'PRAGMA user_version'), 1);
        expect(await _single(db, 'PRAGMA integrity_check'), 'ok');
        expect(await _single(db, 'PRAGMA foreign_keys'), 1);

        final List<String> tables =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'table' "
                      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
                    )
                    .get())
                .map((r) => r.read<String>('name'))
                .toList();
        expect(tables, _v1Tables);
      },
    );

    test(
      'a grave holds several burials, a person at most one (FR-003)',
      () async {
        final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final int cemetery = await db
            .into(db.cemeteries)
            .insert(CemeteriesCompanion.insert(name: 'Cmentarz Wymyślony'));
        // A grave from the notes: cemetery only, no address and no pin.
        final int grave = await db
            .into(db.graves)
            .insert(GravesCompanion.insert(cemeteryId: cemetery));
        final int first = await db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(givenNames: const Value('Pierwsza')),
            );
        final int second = await db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: const Value('Druga')));

        await db
            .into(db.burials)
            .insert(BurialsCompanion.insert(personId: first, graveId: grave));
        await db
            .into(db.burials)
            .insert(BurialsCompanion.insert(personId: second, graveId: grave));
        expect(await db.select(db.burials).get(), hasLength(2));

        await expectLater(
          db
              .into(db.burials)
              .insert(BurialsCompanion.insert(personId: first, graveId: grave)),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('a burial of a person who does not exist is rejected', () async {
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final int cemetery = await db
          .into(db.cemeteries)
          .insert(CemeteriesCompanion.insert(name: 'Cmentarz Wymyślony'));
      final int grave = await db
          .into(db.graves)
          .insert(GravesCompanion.insert(cemeteryId: cemetery));

      await expectLater(
        db
            .into(db.burials)
            .insert(BurialsCompanion.insert(personId: 999, graveId: grave)),
        throwsA(isA<SqliteException>()),
      );
    });

    test('an event belongs to a person or to a family, never both', () async {
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final int person = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(givenNames: const Value('Ktoś')));
      final int family = await db
          .into(db.families)
          .insert(FamiliesCompanion.insert());

      await expectLater(
        db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                type: EventType.birth,
                personId: Value(person),
                familyId: Value(family),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                type: EventType.marriage,
                personId: Value(person),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a date with a qualifier is stored as written (FR-004)', () async {
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final int person = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(givenNames: const Value('Ktoś')));

      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              type: EventType.birth,
              personId: Value(person),
              qualifier: const Value(DateQualifier.between),
              year: const Value(1893),
              yearTo: const Value(1895),
            ),
          );

      final Event event = await db.select(db.events).getSingle();
      expect(event.qualifier, DateQualifier.between);
      expect((event.year, event.month, event.yearTo), (1893, null, 1895));
    });
  });

  group('AC-1 — the bundled SQLite can take the backup snapshot (ADR-004)', () {
    test(
      'SQLite is at least 3.27.0 and VACUUM INTO gives an intact copy with the schema version',
      () async {
        final GrobingDatabase db = GrobingDatabase(
          NativeDatabase(File('${tmp.path}/grobing.db')),
        );
        await db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: const Value('Ktoś')));

        final List<int> version =
            (await _single(db, 'SELECT sqlite_version()') as String)
                .split('.')
                .map(int.parse)
                .toList();
        expect(
          version[0] * 1000000 + version[1] * 1000 + version[2],
          greaterThanOrEqualTo(3027000),
          reason: 'VACUUM INTO needs SQLite 3.27.0',
        );

        final File copyFile = File('${tmp.path}/snapshot.db');
        await db.customStatement('VACUUM INTO ?', [copyFile.path]);
        await db.close();

        final GrobingDatabase copy = GrobingDatabase(NativeDatabase(copyFile));
        addTearDown(copy.close);
        expect(await _single(copy, 'PRAGMA integrity_check'), 'ok');
        expect(await _single(copy, 'PRAGMA user_version'), 1);
        expect(await copy.select(copy.persons).get(), hasLength(1));
      },
    );
  });
}
