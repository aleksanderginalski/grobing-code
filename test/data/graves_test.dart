import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';

// ISSUE-012 — the data behind the transcription screens (lib/data/graves.dart), happy path per AC:
// US-002 AC-1 several people in one grave · AC-2 names, birth surname, "kim była" · AC-3 dates with
// their qualifier · AC-4 every date and burial with a claim from the notes, "kim była" with one source
// line · AC-5 a grave with only its cemetery and people · the grave's name (D4) · the correction in
// place (D1) · all or nothing. Made-up people only (family-data.md).

const QualifiedDate _about1890 = QualifiedDate(
  DateQualifier.about,
  PartialDate(1890),
);
const QualifiedDate _died = QualifiedDate(
  DateQualifier.exact,
  PartialDate(1951, 3, 14),
);
const QualifiedDate _between = QualifiedDate(
  DateQualifier.between,
  PartialDate(1893),
  PartialDate(1895),
);

const PersonEntry _jan = PersonEntry(
  givenNames: 'Jan',
  surname: 'Wymyślony',
  bio: 'Kowal, wymyślony do testów.',
  birth: _about1890,
  death: _died,
);
const PersonEntry _anna = PersonEntry(
  givenNames: 'Anna',
  surname: 'Wymyślona',
  birthSurname: 'Zmyślona',
  birth: _between,
);

void main() {
  late GrobingDatabase db;
  late int cemetery;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    cemetery = await addCemetery(
      db,
      name: 'Cmentarz Wymyślony',
      locality: 'Miejscowość Testowa',
    );
  });

  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  test(
    'AC-1, AC-2, AC-5 — a new grave with its first person, then a second: the grave shows both in '
    'the order entered, with no address and no pin',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: _jan,
      );
      await addPersonToGrave(db, graveId: grave, entry: _anna);

      final GraveDetail g = (await loadGrave(db, grave))!;
      expect(g.cemeteryName, 'Cmentarz Wymyślony');
      expect(g.cemeteryLocality, 'Miejscowość Testowa');
      expect(
        (g.name, g.sector, g.row, g.plot, g.hasPin),
        (null, null, null, null, false),
      );
      expect(g.people.map((p) => p.givenNames), ['Jan', 'Anna']);
      final BuriedPerson anna = g.people.last;
      expect((anna.surname, anna.birthSurname), ('Wymyślona', 'Zmyślona'));
      expect(g.people.first.bio, 'Kowal, wymyślony do testów.');

      final CemeteryGraves c = (await loadCemeteryGraves(db, cemetery))!;
      expect(c.graves, hasLength(1));
      expect(c.graves.single.people.map((p) => p.givenNames), ['Jan', 'Anna']);
      expect(c.personCount, 2);
    },
  );

  test('AC-3 — dates come back with their qualifier and precision', () async {
    final int grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: _jan,
    );
    await addPersonToGrave(db, graveId: grave, entry: _anna);
    final GraveDetail g = (await loadGrave(db, grave))!;
    expect(g.people.first.birth.date, _about1890);
    expect(g.people.first.death.date, _died);
    expect(g.people.first.burial.date, isNull);
    expect(g.people.last.birth.date, _between);
  });

  test(
    'AC-4 — every date and every burial written here has exactly one claim: the notes, CLAIMED; '
    '"kim była" gets the source line "notatki" unless another is given, none without a text',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(
          givenNames: 'Jan',
          surname: 'Wymyślony',
          bio: 'Kowal.',
          birth: _about1890,
          death: _died,
          burial: QualifiedDate(DateQualifier.exact, PartialDate(1951, 3, 18)),
        ),
      );
      await addPersonToGrave(
        db,
        graveId: grave,
        entry: const PersonEntry(
          givenNames: 'Anna',
          bio: 'Nauczycielka.',
          bioSource: 'ciocia, list',
        ),
      );
      await addPersonToGrave(db, graveId: grave, entry: _anna);

      final List<Assertion> claims = await db.select(db.assertions).get();
      expect(claims, hasLength(4 + 3)); // four dates, three burials
      expect(
        claims.map((c) => (c.sourceKind, c.sourceDetail, c.status)).toSet(),
        {(SourceKind.notes, null, AssertionStatus.claimed)},
      );
      for (final Event e in await db.select(db.events).get()) {
        expect(claims.where((c) => c.eventId == e.id), hasLength(1));
      }
      for (final Burial b in await db.select(db.burials).get()) {
        expect(claims.where((c) => c.burialId == b.id), hasLength(1));
      }
      final List<Person> people = await db.select(db.persons).get();
      expect(people.map((p) => p.bioSource), ['notatki', 'ciocia, list', null]);
    },
  );

  test(
    'all or nothing — an entry refused in the middle leaves no grave, person, burial, date or claim',
    () async {
      Future<List<int>> all() async => [
        for (final String t in [
          'graves',
          'persons',
          'burials',
          'events',
          'assertions',
        ])
          await count(t),
      ];
      final List<int> before = await all();
      await expectLater(
        addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(
            givenNames: 'Jan',
            birth: _about1890,
            // A second bound without "między": refused after the person and the burial are written.
            death: QualifiedDate(
              DateQualifier.exact,
              PartialDate(1950),
              PartialDate(1951),
            ),
          ),
        ),
        throwsArgumentError,
      );
      expect(await all(), before);
      await expectLater(
        addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: '  ', surname: ''),
        ),
        throwsArgumentError,
      );
      expect(await all(), before);
    },
  );

  test(
    'D4 — the grave\'s name: set, trimmed, the title on the cemetery screen; blank takes it away',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: _jan,
      );
      await setGraveName(db, grave, '  Grób rodzinny Wymyślonych ');
      expect((await loadGrave(db, grave))!.name, 'Grób rodzinny Wymyślonych');
      expect(
        (await loadCemeteryGraves(db, cemetery))!.graves.single.name,
        'Grób rodzinny Wymyślonych',
      );
      await setGraveName(db, grave, '   ');
      expect((await loadGrave(db, grave))!.name, isNull);
    },
  );

  test(
    'D1 — a correction changes the values in their rows and keeps the claims; a cleared date goes '
    'with its only claim; a new date gets its claim',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: _jan,
      );
      final BuriedPerson jan = (await loadGrave(db, grave))!.people.single;
      final Event birthBefore = (await firstEvent(
        db,
        personId: jan.id,
        type: EventType.birth,
      ))!;
      final List<Assertion> claimsBefore = await db.select(db.assertions).get();

      await updatePersonEntry(
        db,
        jan.id,
        const PersonEntry(
          givenNames: 'Jan',
          surname: 'Wymyślony',
          birth: QualifiedDate(DateQualifier.about, PartialDate(1891)),
          burial: QualifiedDate(DateQualifier.after, PartialDate(1951)),
        ),
      );

      final BuriedPerson after = (await loadGrave(db, grave))!.people.single;
      expect(after.birth.date!.from, const PartialDate(1891));
      expect(after.death.date, isNull);
      expect(after.burial.date!.qualifier, DateQualifier.after);
      expect((after.bio, after.bioSource), (null, null));

      final Event birthAfter = (await firstEvent(
        db,
        personId: jan.id,
        type: EventType.birth,
      ))!;
      expect(birthAfter.id, birthBefore.id); // the same row, corrected
      final List<Assertion> claims = await db.select(db.assertions).get();
      // The birth's claim stays as it was; the death's went with it; the burial date has a new one.
      final Assertion birthClaim = claims.singleWhere(
        (c) => c.eventId == birthBefore.id,
      );
      expect(
        birthClaim.recordedAt,
        claimsBefore.singleWhere((c) => c.eventId == birthBefore.id).recordedAt,
      );
      expect((await db.select(db.events).get()).map((e) => e.type).toSet(), {
        EventType.birth,
        EventType.burial,
      });
      expect(claims, hasLength(3)); // birth, burial date, the burial itself
    },
  );

  test(
    'D1 — a date backed by two sources is read-only: the correction leaves it whatever it is sent',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Ojciec', surname: 'Wymyślony'),
      );
      final int person = (await loadGrave(db, grave))!.people.single.id;
      // A made-up dispute (US-004): the notes and the grandmother give different birth years.
      await addEventWithClaim(
        db,
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(person),
          qualifier: const Value(DateQualifier.about),
          year: const Value(1890),
        ),
        source: const ClaimSource(status: AssertionStatus.contradicted),
      );
      await addEventWithClaim(
        db,
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(person),
          qualifier: const Value(DateQualifier.exact),
          year: const Value(1892),
        ),
        source: const ClaimSource(
          kind: SourceKind.grandmother,
          status: AssertionStatus.contradicted,
        ),
      );

      final BuriedPerson before = (await loadGrave(db, grave))!.people.single;
      expect(before.birth.claimCount, 2);
      expect(before.birth.correctable, isFalse);
      expect(
        before.birth.date,
        _about1890,
      ); // the first one written (ADR-006 D3)

      await updatePersonEntry(
        db,
        person,
        const PersonEntry(givenNames: 'Ojciec', surname: 'Wymyślony'),
      );
      final List<Event> births = await db.select(db.events).get();
      expect(births.map((e) => e.year), [1890, 1892]);
    },
  );

  test(
    'the cemetery screen\'s list: graves in the order entered, people per grave, a person whose '
    'sources disagree on the grave counted once',
    () async {
      final int first = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: _jan,
      );
      final int second = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: _anna,
      );
      // Jan's other grave, from another source (ADR-006 D2).
      final int jan = (await loadGrave(db, first))!.people.single.id;
      await addBurialWithClaim(db, personId: jan, graveId: second);

      final CemeteryGraves c = (await loadCemeteryGraves(db, cemetery))!;
      expect(c.graves.map((g) => g.id), [first, second]);
      expect(c.graves.last.people.map((p) => p.givenNames), ['Anna', 'Jan']);
      expect(c.personCount, 2);
      expect(await loadCemeteryGraves(db, cemetery + 100), isNull);
    },
  );

  test('the views follow every write', () async {
    final List<CemeteryGraves?> seen = [];
    final sub = watchCemeteryGraves(db, cemetery).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await addPersonToNewGrave(db, cemeteryId: cemetery, entry: _jan);
    await pumpEventQueue();
    expect(seen.first!.graves, isEmpty);
    expect(seen.last!.graves.single.people.single.givenNames, 'Jan');
  });
}
