import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/data/photos.dart';

// ISSUE-022 — the people of the Osoby tab and the setting "ja" (05_DESIGN/osoby.md, ustawienia.md
// element 1; data-model.md, Setting "ja"). Made-up people only (family-data.md).

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'loadPeople: everyone, also without a grave, with the first birth and death and the profile photo',
    () async {
      final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(
          givenNames: 'Anna',
          surname: 'Wymyślona',
          birthSurname: 'Zmyślona',
          birth: QualifiedDate(DateQualifier.about, PartialDate(1890)),
          death: QualifiedDate(DateQualifier.exact, PartialDate(1951, 3, 14)),
        ),
      );
      expect(grave, isPositive);
      final int jan = await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              givenNames: const Value('Jan'),
              surname: const Value('Wymyślony'),
            ),
          );
      // A second, later birth of Jan from another source: the list shows the first one (ADR-006 D3).
      for (final int year in [1921, 1925]) {
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                type: EventType.birth,
                personId: Value(jan),
                qualifier: const Value(DateQualifier.exact),
                year: Value(year),
              ),
            );
      }
      final int photo = await db
          .into(db.media)
          .insert(MediaCompanion.insert(relativePath: 'zdjecia/jan.jpg'));
      await db
          .into(db.personMedia)
          .insert(
            PersonMediaCompanion.insert(
              personId: jan,
              mediaId: photo,
              position: 0,
              cropLeft: const Value(10),
              cropTop: const Value(20),
              cropWidth: const Value(100),
              cropHeight: const Value(100),
            ),
          );

      final List<PersonListEntry> people = await loadPeople(db);
      expect(people, hasLength(2));
      final PersonListEntry a = people.firstWhere((p) => p.id != jan);
      expect(
        (a.givenNames, a.surname, a.birthSurname),
        ('Anna', 'Wymyślona', 'Zmyślona'),
      );
      expect(
        a.birth,
        const QualifiedDate(DateQualifier.about, PartialDate(1890)),
      );
      expect(
        a.death,
        const QualifiedDate(DateQualifier.exact, PartialDate(1951, 3, 14)),
      );
      expect(a.profile, isNull);
      final PersonListEntry j = people.firstWhere((p) => p.id == jan);
      expect(
        j.birth,
        const QualifiedDate(DateQualifier.exact, PartialDate(1921)),
      );
      expect(j.death, isNull);
      expect(j.profile?.relativePath, 'zdjecia/jan.jpg');
      expect(
        j.profile?.crop,
        const PhotoCrop(left: 10, top: 20, width: 100, height: 100),
      );
    },
  );

  test('watchPeople follows a new person', () async {
    final Stream<List<PersonListEntry>> people = watchPeople(db);
    expect((await people.first), isEmpty);
    await db
        .into(db.persons)
        .insert(PersonsCompanion.insert(givenNames: const Value('Ewa')));
    expect(
      await people
          .firstWhere((p) => p.isNotEmpty)
          .then((p) => p.single.givenNames),
      'Ewa',
    );
  });

  test(
    'AC-4 data: "ja" is none until chosen; setMe writes the one settings row, again to change it',
    () async {
      final int ewa = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(givenNames: const Value('Ewa')));
      final int jan = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(givenNames: const Value('Jan')));
      expect(await watchMe(db).first, isNull);

      await setMe(db, ewa);
      expect(await watchMe(db).first, ewa);
      await setMe(db, jan);
      expect(await watchMe(db).first, jan);

      final List<Setting> rows = await db.select(db.settings).get();
      expect(rows.map((r) => (r.id, r.mePersonId)), [(1, jan)]);
    },
  );

  test('setMe refuses a person who is not there (the foreign key)', () async {
    expect(() => setMe(db, 999), throwsA(isA<SqliteException>()));
  });
}
