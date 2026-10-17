import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_layout.dart';
import 'package:grobing/app/tree/tree_path.dart' show pathLevel;
import 'package:grobing/data/clans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/kinship.dart';
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

  // ---- ISSUE-039 — "Połącz dwie osoby" (drzewo.md element 8, D49) ----

  test(
    'the lowest level that shows the whole path from "Do": Ja → Wanda at level 3',
    () {
      final int wanda = id['Wanda Przykładowa']!;
      final List<KinStep> steps = family.kin.path(ja, wanda)!;
      final List<int> people = [ja, for (final KinStep s in steps) s.personId];
      expect(
        [for (final int n in people) family.people[n]!.givenNames],
        ['Mateusz', 'Kasia', 'Piotr', 'Wanda'],
      );
      final ({int level, Set<int> also}) at = pathLevel(graph, wanda, people);
      expect(at.level, 3);
      expect(at.also, isEmpty);
      expect(people.every(graph.levelsFrom(wanda, 3).containsKey), isTrue);
      expect(people.every(graph.levelsFrom(wanda, 2).containsKey), isFalse);
    },
  );

  test(
    'a path beyond level 4: level 4 and the people it lacks, laid out besides (also)',
    () {
      // From "Ja" to everyone: the paths whose people level 4 from "Do" does not hold all.
      int found = 0;
      for (final int to in family.people.keys) {
        if (to == ja) continue;
        final List<KinStep>? steps = family.kin.path(ja, to);
        if (steps == null) continue;
        final List<int> people = [
          ja,
          for (final KinStep s in steps) s.personId,
        ];
        final ({int level, Set<int> also}) at = pathLevel(graph, to, people);
        if (at.also.isEmpty) continue;
        found++;
        expect(at.level, 4);
        final TreeLayout l = layoutTree(graph, to, 4, also: at.also);
        expect(
          people.every(l.positions.containsKey),
          isTrue,
          reason: 'path to $to',
        );
        expect(l.count, graph.levelsFrom(to, 4).length + at.also.length);
      }
      // The mockup measured 9 of the 105 (drzewo.md → Candidates — ISSUE-039 → Pomiar, W2).
      expect(found, 9);
    },
  );

  test(
    'the path\'s line goes along the family\'s lines: level for a pair, through the rail for a parent',
    () {
      final int wanda = id['Wanda Przykładowa']!;
      final List<KinStep> steps = family.kin.path(ja, wanda)!;
      final TreeLayout l = layoutTree(graph, wanda, 3);
      final List<List<Offset>> runs = l.pathRoute(ja, steps);
      expect(runs, hasLength(steps.length));
      Offset middle(int n) => l.positions[n]! + const Offset(0, 22);
      int from = ja;
      // The rails the tree draws: the level segments of its lines from a parent to the children.
      final List<Offset> pc = l.lines
          .firstWhere((t) => t.kind == TreeLineKind.parentChild)
          .points;
      final Set<double> rails = {
        for (int i = 0; i + 1 < pc.length; i += 2)
          if (pc[i].dy == pc[i + 1].dy) pc[i].dy,
      };
      for (int i = 0; i < steps.length; i++) {
        final List<Offset> run = runs[i];
        expect(run.first, middle(from), reason: 'step $i starts at its person');
        expect(
          run.last,
          middle(steps[i].personId),
          reason: 'step $i ends at the next',
        );
        // Never at a slant: every segment level or upright.
        for (int j = 0; j + 1 < run.length; j++) {
          expect(
            run[j].dx == run[j + 1].dx || run[j].dy == run[j + 1].dy,
            isTrue,
            reason: 'step $i, segment $j',
          );
        }
        switch (steps[i].edge) {
          case KinEdge.partner:
            expect(run, hasLength(2));
            expect(run.first.dy, run.last.dy);
          case KinEdge.child || KinEdge.parent:
            // Along a rail the tree draws.
            expect(
              run.any((p) => rails.contains(p.dy)),
              isTrue,
              reason: 'step $i through a rail',
            );
          case KinEdge.sibling:
            break;
        }
        from = steps[i].personId;
      }
      // Ja → Kasia a pair, then up twice.
      expect(
        [for (final KinStep s in steps) s.edge],
        [KinEdge.partner, KinEdge.parent, KinEdge.parent],
      );
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

  test(
    'ISSUE-044 (wieniec.md D3) — the trace to a partner beyond the view starts past the wreath of a person who '
    'has one, 43 dp from the centre, and at the circle of one who has none',
    () {
      List<Offset> trace(TreeLayout l) => l.lines
          .singleWhere((lines) => lines.kind == TreeLineKind.tracePartner)
          .points;
      FamilyTreeData withChoices(Map<int, WreathChoice> choices) =>
          FamilyTreeData(
            people: family.people,
            unions: family.unions,
            meId: family.meId,
            choices: choices,
            clans: const {
              1: Clan(
                id: 1,
                name: 'Wymyślscy',
                motif: WreathMotif.dab,
                colour: ClanColour.stareZloto,
              ),
            },
          );
      const TreeMetrics wide = TreeMetrics(slot: 96, wreaths: true);
      final int marek = id['Marek Wymyślony']!;
      final int michal = id['Michał Wymyślony']!;

      // Marek's line: his son Michał wears it.
      final TreeLayout wreathed = layoutTree(
        TreeGraph(withChoices({marek: const WreathChoice.clan(1)})),
        ja,
        2,
        metrics: wide,
      );
      final Offset brother = wreathed.positions[michal]!;
      expect(
        trace(wreathed),
        containsAllInOrder([
          Offset(brother.dx - 43, brother.dy + 22),
          Offset(brother.dx - 57, brother.dy + 22),
        ]),
      );

      // "Bez wieńca" at Michał, the others with Marek's line: his trace at his circle again.
      final TreeLayout bare = layoutTree(
        TreeGraph(
          withChoices({
            marek: const WreathChoice.clan(1),
            michal: const WreathChoice.none(),
          }),
        ),
        ja,
        2,
        metrics: wide,
      );
      final Offset bareBrother = bare.positions[michal]!;
      expect(
        trace(bare),
        containsAllInOrder([
          Offset(bareBrother.dx - 22, bareBrother.dy + 22),
          Offset(bareBrother.dx - 36, bareBrother.dy + 22),
        ]),
      );
    },
  );
}
