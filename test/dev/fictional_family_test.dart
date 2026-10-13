import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_layout.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/dev/fictional_family.dart';

// ISSUE-033, the plan's first step (SPIKE-002 D6) — the made-up family of the debug and profile builds has
// the shape SPIKE-002 measured (→ Rekomendacja, numbers only): 106 people, 38 unions, 6 generations born
// 1868–2019, 31 dead and 75 living, 39 without parents in the data, 3 people in two unions, 2 pairs
// "razem" (one later married). Surnames from the invented stems only (family-data.md, retro 3 R7).

const List<String> _stems = ['Wymyśl', 'Zmyśl', 'Testow', 'Przykład'];

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the shape of the real family, as SPIKE-002 gave it', () async {
    expect(await addFictionalFamily(db), isTrue);
    final FamilyTreeData family = await loadFamilyTree(db);

    expect(family.people, hasLength(106));
    expect(family.unions, hasLength(38));
    expect(family.people.values.where((p) => p.dead), hasLength(31));
    final Set<int> children = {
      for (final TreeUnion u in family.unions) ...u.children,
    };
    expect(
      family.people.keys.where((id) => !children.contains(id)),
      hasLength(39),
    );
    final Map<int, int> unionsOf = {};
    for (final TreeUnion u in family.unions) {
      for (final int p in u.partners) {
        unionsOf[p] = (unionsOf[p] ?? 0) + 1;
      }
    }
    expect(unionsOf.values.where((n) => n == 2), hasLength(3));
    final List<int> years = [
      for (final TreePerson p in family.people.values) p.birth!.from.year,
    ]..sort();
    expect((years.first, years.last), (1868, 2019));
    // Two pairs began "razem"; one of them married later, the other did not.
    final List<Event> together = await (db.select(
      db.events,
    )..where((e) => e.type.equalsValue(EventType.together))).get();
    expect(together, hasLength(2));
    expect(family.unions.where((u) => !u.married), hasLength(1));
    // Six generations from "Ja" with everyone shown.
    expect(layoutTree(TreeGraph(family), family.meId!, 5).generations, 6);
  });

  test('surnames only from the invented stems', () async {
    await addFictionalFamily(db);
    for (final Person p in await db.select(db.persons).get()) {
      for (final String? surname in [p.surname, p.birthSurname]) {
        if (surname == null) continue;
        expect(
          _stems.any(surname.startsWith),
          isTrue,
          reason: '$surname is not from an invented stem',
        );
      }
    }
  });

  test('its "Ja" becomes "ja"; a second call adds nothing', () async {
    expect(await addFictionalFamily(db), isTrue);
    final int? me = await watchMe(db).first;
    final Person ja = await (db.select(
      db.persons,
    )..where((p) => p.id.equals(me!))).getSingle();
    expect((ja.givenNames, ja.surname), ('Mateusz', 'Wymyślony'));

    expect(await addFictionalFamily(db), isFalse);
    expect(await db.select(db.persons).get(), hasLength(106));
  });

  test('a "ja" already chosen stays', () async {
    final int someone = await db
        .into(db.persons)
        .insert(PersonsCompanion.insert());
    await setMe(db, someone);
    await addFictionalFamily(db);
    expect(await watchMe(db).first, someone);
  });
}
