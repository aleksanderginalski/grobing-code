import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';

// ISSUE-047 — the grave first, then its people (lib/data/graves.dart; 05_DESIGN/cmentarz.md v8, grob.md v9,
// osoby.md v3), happy path per AC: AC-1 a grave on its own, with the window's name, address and fee · AC-2 a
// person already in the app, buried nowhere, joins a grave — the same person, nothing else of them changes;
// someone with a grave is refused (D23) · AC-4 a person buried nowhere. Made-up people only (family-data.md).

const PersonEntry _jan = PersonEntry(
  givenNames: 'Jan',
  surname: 'Wymyślony',
  sex: Sex.male,
  birth: QualifiedDate(DateQualifier.about, PartialDate(1890)),
  death: QualifiedDate(DateQualifier.exact, PartialDate(1951, 3, 14)),
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
    'AC-1 — "Nowy grób": a grave without people, with the name, the address and the fee of the '
    'window — the sector by its name, without the words in front',
    () async {
      final int grave = await addGrave(
        db,
        cemetery,
        name: 'Grób rodzinny Wymyślonych',
        sector: 'Kwatera B',
        row: 'Rząd 4',
        plot: '12',
        paidUntil: const PartialDate(2031),
      );
      final GraveDetail? detail = await loadGrave(db, grave);
      expect(detail, isNotNull);
      expect(detail!.name, 'Grób rodzinny Wymyślonych');
      expect(detail.sector, 'B');
      expect(detail.row, '4');
      expect(detail.plot, '12');
      expect(detail.paidUntil, const PartialDate(2031));
      expect(detail.people, isEmpty);
      expect(await count('burials'), 0);
      expect(await count('persons'), 0);
    },
  );

  test(
    'AC-1 — an empty window gives a grave with nothing but its cemetery ("Grób", no address)',
    () async {
      final int grave = await addGrave(db, cemetery);
      final GraveDetail detail = (await loadGrave(db, grave))!;
      expect(detail.name, isNull);
      expect((detail.sector, detail.row, detail.plot), (null, null, null));
      expect(detail.paidUntil, isNull);
      // The cemetery's list counts it, without people (cmentarz.md v8 → States).
      final CemeteryGraves graves = (await loadCemeteryGraves(db, cemetery))!;
      expect(graves.graves, hasLength(1));
      expect(graves.graves.single.people, isEmpty);
    },
  );

  test(
    'AC-4 — a person buried nowhere: the person and their dates, no burial',
    () async {
      final int person = await addPersonWithoutGrave(db, entry: _jan);
      expect(await count('persons'), 1);
      expect(await count('burials'), 0);
      expect(await count('events'), 2);
      final ({List<PersonChoice> all, List<int> inGrave}) choices =
          await loadPersonChoices(db);
      final PersonChoice jan = choices.all.single;
      expect(jan.id, person);
      // Buried nowhere: no grave and no cemetery — "Bez grobu" in the choice (grob.md v9, 11).
      expect((jan.graveName, jan.cemeteryName), (null, null));
    },
  );

  test(
    'AC-2 — someone buried nowhere joins the grave: the same person, with a burial claimed from the '
    'notes; their dates stay as they were',
    () async {
      final int person = await addPersonWithoutGrave(db, entry: _jan);
      final int grave = await addGrave(
        db,
        cemetery,
        name: 'Grób rodzinny Wymyślonych',
      );
      final int claimsBefore = await count('assertions');

      await addExistingPersonToGrave(db, graveId: grave, personId: person);

      expect(await count('persons'), 1, reason: 'no second Jan');
      expect(await count('burials'), 1);
      expect(
        await count('assertions'),
        claimsBefore + 1,
        reason: 'the burial is claimed',
      );
      final GraveDetail detail = (await loadGrave(db, grave))!;
      expect(detail.people.map((p) => p.id), [person]);
      final BuriedPerson jan = detail.people.single;
      expect(jan.entry.givenNames, 'Jan');
      expect(jan.entry.birth, _jan.birth);
      expect(jan.entry.death, _jan.death);
      final ({List<PersonChoice> all, List<int> inGrave}) choices =
          await loadPersonChoices(db, graveId: grave);
      expect(choices.inGrave, [person]);
      expect(choices.all.single.graveName, 'Grób rodzinny Wymyślonych');
    },
  );

  test(
    'D23 — someone with a grave already is refused, in this grave or another; so is no one',
    () async {
      final int first = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: _jan,
      );
      final int jan = (await loadGrave(db, first))!.people.single.id;
      final int other = await addGrave(db, cemetery);

      await expectLater(
        addExistingPersonToGrave(db, graveId: other, personId: jan),
        throwsStateError,
      );
      await expectLater(
        addExistingPersonToGrave(db, graveId: first, personId: jan),
        throwsStateError,
      );
      await expectLater(
        addExistingPersonToGrave(db, graveId: other, personId: 999),
        throwsStateError,
      );
      expect(await count('burials'), 1);
    },
  );
}
