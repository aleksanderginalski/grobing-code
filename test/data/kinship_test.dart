import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/kinship.dart';

// ISSUE-024 AC-3 — the path from "ja" through the family (lib/data/kinship.dart; osoba.md element 7): the
// fewest steps, then the fewest partner steps, then the lowest ids in order (ISSUE-025 D2); a sibling is
// one step (children of the same family), a half-sibling two. Made-up families only (family-data.md).

KinStep _s(int id, KinEdge edge, {bool married = false}) =>
    KinStep(personId: id, edge: edge, married: married);

void main() {
  // 1 Ja — 2 Mama (with 3 Tata, married) — 4 Babcia (with 5 Dziadek, married, parents of 2 and 6);
  // 6 Wuj (brother of 2); 7 Żona of 1 (married), 8 her father; 9 a half-brother: son of 3 with 10, not
  // married.
  final KinGraph graph = KinGraph.of(
    partners: {
      1: [3, 2], // family 1: Tata, Mama
      2: [4, 5], // family 2: Babcia, Dziadek
      3: [1, 7], // family 3: Ja, Żona
      4: [8], // family 4: her father alone
      5: [3, 10], // family 5: Tata with another partner
    },
    children: {
      1: [1],
      2: [2, 6],
      4: [7],
      5: [9],
    },
    married: {1, 2, 3},
  );

  test('the same person — no steps; nothing between — null', () {
    expect(graph.path(1, 1), isEmpty);
    expect(graph.path(1, 42), isNull);
  });

  test('a grandmother: Ja → mama → her mother', () {
    expect(graph.path(1, 4), [_s(2, KinEdge.parent), _s(4, KinEdge.parent)]);
  });

  test(
    'a mother\'s brother: through the mother and their shared family — a sibling is one step',
    () {
      expect(graph.path(1, 6), [_s(2, KinEdge.parent), _s(6, KinEdge.sibling)]);
    },
  );

  test(
    'a wife and her father; the partner step says whether the pair married',
    () {
      expect(graph.path(1, 7), [_s(7, KinEdge.partner, married: true)]);
      expect(graph.path(1, 8), [
        _s(7, KinEdge.partner, married: true),
        _s(8, KinEdge.parent),
      ]);
    },
  );

  test(
    'a half-brother: two steps through the father, not a sibling; his mother is the father\'s '
    'partner, not married',
    () {
      expect(graph.path(1, 9), [_s(3, KinEdge.parent), _s(9, KinEdge.child)]);
      expect(graph.path(1, 10), [
        _s(3, KinEdge.parent),
        _s(10, KinEdge.partner),
      ]);
    },
  );

  test(
    'of two paths as long, the one with fewer partner steps — even when the other has lower ids',
    () {
      // 1 is married to 2; 3 is 1's parent; 4 is the parent of both 2 and 3. From 1 to 4: through 2 (a
      // partner, then a parent — ids 2, 4) or through 3 (two parents — ids 3, 4): no partner step wins.
      final KinGraph g = KinGraph.of(
        partners: {
          1: [1, 2],
          2: [3],
          3: [4],
        },
        children: {
          2: [1],
          3: [2, 3],
        },
        married: {1},
      );
      expect(g.path(1, 4), [_s(3, KinEdge.parent), _s(4, KinEdge.parent)]);
    },
  );

  test(
    'of two paths as long and as many partner steps, the one whose ids read first',
    () {
      // 1 is the parent of 21 and 22, who are both parents of 20: through 21 or 22 — 21.
      final KinGraph g = KinGraph.of(
        partners: {
          1: [21, 22],
          2: [1],
        },
        children: {
          1: [20],
          2: [21, 22],
        },
      );
      expect(g.path(1, 20), [_s(21, KinEdge.child), _s(20, KinEdge.child)]);
    },
  );

  test(
    'the graph from the database: families, partners, children and the wedding',
    () async {
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Future<int> person(String given, Sex sex) => db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              givenNames: Value(given),
              surname: const Value('Wymyślony'),
              sex: Value(sex),
            ),
          );
      final int ja = await person('Ja', Sex.male);
      final int mama = await person('Anna', Sex.female);
      final int babcia = await person('Maria', Sex.female);
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(babcia)],
          children: [ExistingMember(mama)],
        ),
      );
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(mama)],
          children: [ExistingMember(ja)],
        ),
      );
      final KinGraph loaded = await KinGraph.load(db);
      expect(loaded.path(ja, babcia), [
        _s(mama, KinEdge.parent),
        _s(babcia, KinEdge.parent),
      ]);
    },
  );
}
