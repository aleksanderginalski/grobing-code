import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/kinship.dart';
import 'package:grobing/data/people.dart';

// ISSUE-033 — the family as the tree reads it, all at once and read only (lib/data/family_tree.dart): the
// partners in the order written, the children by birth (those without a date last), the wedding, a union's
// start for ordering ("razem" first, else the wedding), "dead" from a death or a burial, and "ja". Made-up
// people only (family-data.md).

QualifiedDate _year(int y) =>
    QualifiedDate(DateQualifier.exact, PartialDate(y));

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> person(String given, {Sex? sex, int? born}) async {
    final int id = await db
        .into(db.persons)
        .insert(
          PersonsCompanion.insert(
            givenNames: Value(given),
            surname: const Value('Testowy'),
            sex: Value(sex),
          ),
        );
    if (born != null) {
      await addEventWithClaim(
        db,
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(id),
          qualifier: const Value(DateQualifier.exact),
          year: Value(born),
        ),
      );
    }
    return id;
  }

  test(
    'unions: partners as written, children by birth, the wedding and the start of "razem"',
    () async {
      final int adam = await person('Adam', sex: Sex.male, born: 1925);
      final int beata = await person('Beata', sex: Sex.female, born: 1928);
      final int younger = await person('Cezary', born: 1955);
      final int older = await person('Danuta', born: 1952);
      final int undated = await person('Emil');
      final int filip = await person('Filip', sex: Sex.male);
      final int married = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(adam), ExistingMember(beata)],
          children: [
            ExistingMember(younger),
            ExistingMember(undated),
            ExistingMember(older),
          ],
          marriage: _year(1950),
        ),
      );
      final int together = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(beata), ExistingMember(filip)],
          children: const [],
          together: _year(1960),
        ),
      );

      final FamilyTreeData family = await loadFamilyTree(db);
      final TreeUnion first = family.unions.singleWhere(
        (u) => u.familyId == married,
      );
      expect(first.partners, [adam, beata]);
      expect(first.children, [older, younger, undated]);
      expect(first.married, isTrue);
      expect(first.startKey, 19500000);
      final TreeUnion second = family.unions.singleWhere(
        (u) => u.familyId == together,
      );
      expect(second.married, isFalse);
      expect(second.startKey, 19600000);
      expect(family.people[adam]!.birth!.from.year, 1925);
      expect(family.people[filip]!.sex, Sex.male);
      // The paths for "kim jest dla Ciebie" come from the same data.
      expect(family.kin.path(older, adam), [
        KinStep(personId: adam, edge: KinEdge.parent),
      ]);
    },
  );

  test(
    'dead: a death or a burial, with a date or without; "ja" when chosen',
    () async {
      final int died = await person('Gustaw');
      await addEventWithClaim(
        db,
        EventsCompanion.insert(type: EventType.death, personId: Value(died)),
      );
      final int buried = await person('Halina');
      final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
      final int grave = await db
          .into(db.graves)
          .insert(GravesCompanion.insert(cemeteryId: cemetery));
      await addBurialWithClaim(db, personId: buried, graveId: grave);
      final int living = await person('Igor', born: 1990);

      FamilyTreeData family = await loadFamilyTree(db);
      expect(family.people[died]!.dead, isTrue);
      expect(family.people[buried]!.dead, isTrue);
      expect(family.people[living]!.dead, isFalse);
      expect(family.meId, isNull);

      await setMe(db, living);
      family = await loadFamilyTree(db);
      expect(family.meId, living);
    },
  );

  test('again after a write: watchFamilyTree follows the database', () async {
    final Stream<FamilyTreeData> stream = watchFamilyTree(db);
    final List<int> counts = [];
    final sub = stream.listen((f) => counts.add(f.people.length));
    await pumpEventQueue();
    await person('Jan');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(counts.first, 0);
    expect(counts.last, 1);
  });
}
