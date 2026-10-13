import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_layout.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/dev/fictional_family.dart';

// ISSUE-033 — the tree's layout (05_DESIGN/drzewo.md elements 3 and 4): US-009 AC-1 "Ja" in the middle with
// the family by generation and the partner's family to one side; AC-3 the levels of D2; AC-4 the trace of the
// family beyond the view. The port of SPIKE-002's mockup gives its numbers (Findings M1) on the same made-up
// family. Made-up people only (family-data.md).

void main() {
  late FamilyTreeData family;
  late TreeGraph graph;
  late int ja;
  late Map<String, int> id;

  setUpAll(() async {
    final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
    await addFictionalFamily(db);
    family = await loadFamilyTree(db);
    graph = TreeGraph(family);
    ja = family.meId!;
    id = {
      for (final TreePerson p in family.people.values)
        '${p.givenNames} ${p.surname}': p.id,
    };
    await db.close();
  });

  test(
    'AC-3 — the levels from "Ja" and the layout are SPIKE-002 M1, number for number',
    () {
      final List<(int, int, int, int)> expected = [
        // people, generations, width (dp), crossings
        (6, 3, 212, 0),
        (20, 4, 864, 0),
        (66, 5, 1960, 6),
        (99, 6, 2663, 9),
        (106, 6, 2960, 10),
      ];
      for (int level = 1; level <= 5; level++) {
        final TreeLayout l = layoutTree(graph, ja, level);
        expect(
          (l.count, l.generations, l.spanWidth.round(), l.crossings),
          expected[level - 1],
          reason: 'level $level',
        );
      }
    },
  );

  test(
    'AC-1 — "Ja" in the middle of level 2: parents, wife, children, siblings, grandparents',
    () {
      final TreeLayout l = layoutTree(graph, ja, 2);
      expect(l.focus, ja);
      expect(l.levels[ja], 0);
      for (final String who in [
        'Marek Wymyślony', // the father
        'Ewa Wymyślona', // the mother
        'Kasia Wymyślona', // the wife
        'Ignacy Wymyślony', // the son
        'Michał Wymyślony', // the brother
        'Joanna Testowicz', // the sister
        'Józef Wymyślony', // the father's father
        'Henryk Zmyślony', // the mother's father
        'Piotr Przykładowy', // the wife's father
      ]) {
        expect(l.positions.containsKey(id[who]), isTrue, reason: who);
      }
      // Rows by generation: the parents above "Ja", the children below.
      final double y = l.positions[ja]!.dy;
      expect(l.positions[id['Marek Wymyślony']]!.dy, lessThan(y));
      expect(l.positions[id['Ignacy Wymyślony']]!.dy, greaterThan(y));
      expect(l.positions[id['Kasia Wymyślona']]!.dy, y);
    },
  );

  test(
    'AC-1 — every pair stands side by side, and the wife\'s family to one side (D8)',
    () {
      final TreeLayout l = layoutTree(graph, ja, 4);
      for (final TreeUnion u in family.unions) {
        if (u.partners.length < 2) continue;
        final Offset? a = l.positions[u.partners[0]];
        final Offset? b = l.positions[u.partners[1]];
        if (a == null || b == null) continue;
        expect(a.dy, b.dy, reason: 'union ${u.familyId} in one row');
        expect(
          (a.dx - b.dx).abs(),
          closeTo(80, 0.001),
          reason: 'union ${u.familyId} side by side',
        );
      }
      final TreeLayout two = layoutTree(graph, ja, 2);
      double x(String who) => two.positions[id[who]]!.dx;
      expect(x('Kasia Wymyślona'), greaterThan(x('Mateusz Wymyślony')));
      expect(x('Piotr Przykładowy'), greaterThan(x('Marek Wymyślony')));
      expect(x('Agnieszka Przykładowa'), greaterThan(x('Ewa Wymyślona')));
    },
  );

  test(
    'AC-4 — the trace: up, down and sideways where the family goes on; none with everyone shown',
    () {
      List<Offset> trace(TreeLayout l, TreeLineKind kind) =>
          l.lines.singleWhere((lines) => lines.kind == kind).points;
      final TreeLayout one = layoutTree(graph, ja, 1);
      final Offset father = one.positions[id['Marek Wymyślony']]!;
      final List<Offset> upDown = trace(one, TreeLineKind.traceParentChild);
      // Marek's parents are beyond level 1: a short line up from his node, 14 dp.
      expect(
        upDown,
        containsAllInOrder([
          Offset(father.dx, father.dy - 2),
          Offset(father.dx, father.dy - 16),
        ]),
      );
      // At level 2 the brother's partner is beyond the view: a short line sideways from his node, 14 dp,
      // away from the middle — he stands left of "Ja", so to the left (ui review of ISSUE-033).
      final TreeLayout two = layoutTree(graph, ja, 2);
      final Offset brother = two.positions[id['Michał Wymyślony']]!;
      expect(brother.dx, lessThan(two.positions[ja]!.dx));
      expect(
        trace(two, TreeLineKind.tracePartner),
        containsAllInOrder([
          Offset(brother.dx - 22, brother.dy + 22),
          Offset(brother.dx - 36, brother.dy + 22),
        ]),
      );

      final TreeLayout all = layoutTree(graph, ja, 5);
      expect(trace(all, TreeLineKind.traceParentChild), isEmpty);
      expect(trace(all, TreeLineKind.tracePartner), isEmpty);
    },
  );

  test(
    'a cycle in the data does not hang the layout (ISSUE-019 → Manual: no check of cycles yet)',
    () {
      // A person in a pair with their own child — the case seen in the author's test data.
      const TreePerson a = TreePerson(id: 1, givenNames: 'Adam');
      const TreePerson b = TreePerson(id: 2, givenNames: 'Beata');
      final FamilyTreeData looped = FamilyTreeData(
        people: {1: a, 2: b},
        unions: const [
          TreeUnion(familyId: 1, partners: [1, 2], children: [2]),
        ],
      );
      final TreeLayout l = layoutTree(TreeGraph(looped), 1, 4);
      expect(l.count, 2);
    },
  );
}
