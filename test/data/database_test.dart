import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/database.dart';

// ISSUE-007 AC-1 and AC-2; the schema is v2 since ISSUE-011 (assertions, burials per claimed grave).
// All data here is made up (family-data.md).

// v11 (ISSUE-028, ADR-016) adds sectors; v10 (ISSUE-027, ADR-015) adds cemetery_plans to the tables of v7; v9 (ISSUE-023) — a photo may point at a
// cemetery; v8 (ISSUE-024) — a photo link got its
// background mark; v7 (ISSUE-025) — persons got a sex; v6 (ISSUE-019) gave family_children an id and let
// assertions cite a family or a child's link (ADR-011).
const List<String> _v13Tables = [
  'assertions',
  'burials',
  'cemeteries',
  'cemetery_plans',
  'events',
  'families',
  'family_children',
  'family_partners',
  'graves',
  'media',
  'person_media',
  'persons',
  'residences',
  'sectors',
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

  group('AC-2 — a fresh database is at the current schema', () {
    test(
      'user_version 13, integrity ok, exactly the v13 tables (v12 added a column, v13 residences), foreign keys on, the crop and the background '
      'on the photo link, claims on families and on children\'s links, a person\'s sex, a photo\'s '
      'cemetery, a pin with its date',
      () async {
        final GrobingDatabase db = GrobingDatabase(
          NativeDatabase(File('${tmp.path}/grobing.db')),
        );
        addTearDown(db.close);

        expect(await _single(db, 'PRAGMA user_version'), 13);
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
        expect(tables, _v13Tables);
        final List<String> linkColumns =
            (await db.customSelect('PRAGMA table_info(person_media)').get())
                .map((r) => r.read<String>('name'))
                .toList();
        expect(
          linkColumns,
          containsAll([
            'crop_left',
            'crop_top',
            'crop_width',
            'crop_height',
            'is_background',
          ]),
        );
        Future<List<String>> columns(String table) async => [
          for (final QueryRow r
              in await db.customSelect('PRAGMA table_info($table)').get())
            r.read<String>('name'),
        ];
        expect(
          await columns('family_children'),
          containsAll(['id', 'family_id', 'person_id']),
        );
        expect(
          await columns('assertions'),
          containsAll(['family_id', 'family_child_id']),
        );
        expect(await columns('persons'), contains('sex'));
        expect(
          await columns('media'),
          containsAll(['grave_id', 'cemetery_id']),
        );
        expect(
          await columns('graves'),
          containsAll([
            'position_source',
            'position_accuracy_m',
            'position_recorded_at',
          ]),
        );
        // ISSUE-042 (ADR-020): a residence's period, level and place in words, the name of the time and the address.
        expect(
          await columns('residences'),
          containsAll([
            'person_id',
            'from_qualifier',
            'from_year',
            'to_qualifier',
            'to_year',
            'level',
            'place_name',
            'place_unit',
            'country_code',
            'country_name',
            'lat',
            'lon',
            'geonames_id',
            'name_then',
            'address',
          ]),
        );
      },
    );

    test(
      'ISSUE-024 (ADR-013) — one background per person: the partial index refuses a second, and allows '
      'one for each person and any number of links that are not one',
      () async {
        final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final int ewa = await db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: const Value('Ewa')));
        final int jan = await db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: const Value('Jan')));
        Future<int> photo(String name) => db
            .into(db.media)
            .insert(MediaCompanion.insert(relativePath: 'wymyslone/$name.jpg'));
        final int a = await photo('a');
        final int b = await photo('b');
        final int c = await photo('c');
        Future<void> link(int person, int media, int position, bool bg) => db
            .into(db.personMedia)
            .insert(
              PersonMediaCompanion.insert(
                personId: person,
                mediaId: media,
                position: position,
                isBackground: Value(bg),
              ),
            );
        await link(ewa, a, 0, true);
        await link(ewa, b, 1, false);
        await link(ewa, c, 2, false);
        await link(jan, a, 0, true); // the same photo is Jan's background too
        await expectLater(
          (db.update(db.personMedia)
                ..where((l) => l.personId.equals(ewa) & l.mediaId.equals(b)))
              .write(const PersonMediaCompanion(isBackground: Value(true))),
          throwsA(isA<SqliteException>()),
        );
        expect(
          await (db.select(
            db.personMedia,
          )..where((l) => l.isBackground.equals(true))).get(),
          hasLength(2),
        );
      },
    );

    test(
      'a grave holds several burials (FR-003); a second grave for a person is a second claimed '
      'burial, the same grave twice is refused (ADR-006 D2)',
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

        final int otherGrave = await db
            .into(db.graves)
            .insert(GravesCompanion.insert(cemeteryId: cemetery));
        await db
            .into(db.burials)
            .insert(
              BurialsCompanion.insert(personId: first, graveId: otherGrave),
            );
        expect(await db.select(db.burials).get(), hasLength(3));
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
        expect(
          await _single(copy, 'PRAGMA user_version'),
          GrobingDatabase.currentSchemaVersion,
        );
        expect(await copy.select(copy.persons).get(), hasLength(1));
      },
    );
  });
}
