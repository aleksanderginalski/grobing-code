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
// the family by generation and the partner's family to one side; AC-4 the trace of the family beyond the view.
// ISSUE-049 — the levels by unions (D50, M2): blood costs nothing, every union a level (AC-2, AC-3); the steps of
// the family (D2 until v1.22) stay for the order of the layout and of the names. The port of the mockups gives
// their numbers on the same made-up family. Made-up people only (family-data.md).

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
    'ISSUE-049 AC-2, AC-3 (D50, M2) — the levels by unions from "Ja": the blood with its husbands, wives and '
    'partners; their families a level up; the layout as drzewo-049.html measured it',
    () {
      Set<String> at(int level) => {
        for (final MapEntry<int, int> e in graph.unionLevels(ja).entries)
          if (e.value == level)
            '${family.people[e.key]!.givenNames} ${family.people[e.key]!.surname}',
      };
      // AC-2: the brother, his son and his partner; not her parents — they come at level 2.
      for (final String who in [
        'Michał Wymyślony',
        'Leon Wymyślony',
        'Natalia Zmyślewicz',
        'Kasia Wymyślona',
        'Bartosz Testowicz',
        'Józef Wymyślony',
        'Henryk Zmyślony',
        'Antoni Wymyślony',
      ]) {
        expect(at(1), contains(who), reason: who);
      }
      expect(
        at(2),
        containsAll([
          'Zbigniew Zmyślewicz',
          'Alicja Zmyślewicz',
          'Patrycja Przykładniak',
          'Piotr Przykładowy',
        ]),
      );
      // M2: the husband of Natalia's sister is an end at level 2 — his parents and brother come at level 3 (AC-3).
      expect(at(2), contains('Konrad Przykładniak'));
      expect(at(3), {
        'Ryszard Przykładniak',
        'Dorota Przykładniak',
        'Olaf Przykładniak',
      });
      expect(graph.unionLevelCount(ja), 3);
      expect(
        [for (int k = 1; k <= 3; k++) graph.unionLevelSize(ja, k)],
        [91, 113, 116],
      );

      final List<(int, int, int)> expected = [
        // people, width (dp), crossings — drzewo-049.html, the same algorithm at 80 dp a place
        (91, 2568, 3),
        (113, 3153, 14),
        (116, 3320, 26),
      ];
      for (int level = 1; level <= 3; level++) {
        final TreeLayout l = layoutTree(graph, ja, level);
        expect(
          (l.count, l.spanWidth.round(), l.crossings),
          expected[level - 1],
          reason: 'level $level',
        );
      }
    },
  );

  test(
    'ISSUE-049 (D50) — the blood is up then down: ancestors, their descendants, half-siblings; not a partner; a person '
    'alone has one level; Teofil, with no family, is no one\'s level',
    () {
      final Set<int> blood = graph.bloodOf(ja);
      for (final String who in [
        'Antoni Wymyślony', // a great-great-grandfather
        'Agata Zmyślik', // a cousin of the mother
        'Zdzisław Wymyślewicz', // the grandmother's half-brother
        'Mateusz Wymyślony',
      ]) {
        expect(blood, contains(id[who]), reason: who);
      }
      for (final String who in [
        'Kasia Wymyślona',
        'Natalia Zmyślewicz',
        'Tadeusz Wymyślewicz',
      ]) {
        expect(blood, isNot(contains(id[who])), reason: who);
      }
      final int teofil = id['Teofil Przykładowski']!;
      expect(graph.unionLevels(teofil), {teofil: 1});
      expect(graph.unionLevelCount(teofil), 1);
      expect(graph.unionLevels(ja).containsKey(teofil), isFalse);
      // Everyone else joins "Ja": 116 of the 117.
      expect(graph.unionLevels(ja), hasLength(family.people.length - 1));
    },
  );

  test(
    'D57 — the steps of the family (D2 until v1.22) keep their numbers: they order the layout and the names',
    () {
      expect(
        [for (int k = 1; k <= 6; k++) graph.levelsFrom(ja, k).length],
        [6, 20, 66, 104, 113, 116],
      );
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

  test('AC-4 — the trace: up where the family goes on beyond the level; sideways to a partner beyond it; none with '
      'everyone shown', () {
    List<Offset> trace(TreeLayout l, TreeLineKind kind) =>
        l.lines.singleWhere((lines) => lines.kind == kind).points;
    final TreeLayout one = layoutTree(graph, ja, 1);
    // Kasia's parents come at level 2 (D50): a short line up from her node, 14 dp.
    final Offset wife = one.positions[id['Kasia Wymyślona']]!;
    expect(
      trace(one, TreeLineKind.traceParentChild),
      containsAllInOrder([
        Offset(wife.dx, wife.dy - 2),
        Offset(wife.dx, wife.dy - 16),
      ]),
    );
    // From Tadeusz, Genowefa's second husband: she is his wife on level 1, her first husband Władysław comes
    // at level 2 — a short line sideways from her node, away from the middle (ui review of ISSUE-033).
    final int tadeusz = id['Tadeusz Wymyślewicz']!;
    final TreeLayout fromTadeusz = layoutTree(graph, tadeusz, 1);
    final Offset genowefa = fromTadeusz.positions[id['Genowefa Wymyślewicz']]!;
    final double away = genowefa.dx < fromTadeusz.positions[tadeusz]!.dx
        ? -1
        : 1;
    expect(
      trace(fromTadeusz, TreeLineKind.tracePartner),
      containsAllInOrder([
        Offset(genowefa.dx + away * 22, genowefa.dy + 22),
        Offset(genowefa.dx + away * 36, genowefa.dy + 22),
      ]),
    );

    final TreeLayout all = layoutTree(graph, ja, 3);
    expect(trace(all, TreeLineKind.traceParentChild), isEmpty);
    expect(trace(all, TreeLineKind.tracePartner), isEmpty);
  });

  // ---- ISSUE-039 — "Połącz dwie osoby" (drzewo.md element 8, D49) ----

  test(
    'the lowest level that shows the whole path from "Do": Ja → Wanda at level 1 — Kasia is her great-granddaughter, '
    '"Ja" Kasia\'s husband (D50; at level 3 by the steps of D2 until v1.22)',
    () {
      final int wanda = id['Wanda Przykładowa']!;
      final List<KinStep> steps = family.kin.path(ja, wanda)!;
      final List<int> people = [ja, for (final KinStep s in steps) s.personId];
      expect(
        [for (final int n in people) family.people[n]!.givenNames],
        ['Mateusz', 'Kasia', 'Piotr', 'Wanda'],
      );
      final ({int level, Set<int> also}) at = pathLevel(graph, wanda, people);
      expect(at.level, 1);
      expect(at.also, isEmpty);
    },
  );

  test(
    'ISSUE-049 AC-5 — every path from "Ja" has its level and nothing laid out besides it: the highest level of its '
    'people, from "Do"',
    () {
      final Map<int, int> levels = {};
      for (final int to in family.people.keys) {
        if (to == ja) continue;
        final List<KinStep>? steps = family.kin.path(ja, to);
        if (steps == null) continue;
        final List<int> people = [
          ja,
          for (final KinStep s in steps) s.personId,
        ];
        final ({int level, Set<int> also}) at = pathLevel(graph, to, people);
        expect(at.also, isEmpty, reason: 'path to $to');
        final TreeLayout l = layoutTree(graph, to, at.level);
        expect(
          people.every(l.positions.containsKey),
          isTrue,
          reason: 'path to $to',
        );
        if (at.level > 1) {
          final TreeLayout lower = layoutTree(graph, to, at.level - 1);
          expect(
            people.every(lower.positions.containsKey),
            isFalse,
            reason: 'path to $to, one level lower',
          );
        }
        levels[at.level] = (levels[at.level] ?? 0) + 1;
      }
      // Ja → Ryszard Przykładniak, the father-in-law of Natalia's sister: level 3 from him (drzewo-049.html).
      final int ryszard = id['Ryszard Przykładniak']!;
      final List<int> toRyszard = [
        ja,
        for (final KinStep s in family.kin.path(ja, ryszard)!) s.personId,
      ];
      expect(pathLevel(graph, ryszard, toRyszard).level, 3);
      expect(levels.values.fold(0, (a, b) => a + b), 115);
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
      // From Tadeusz, Genowefa — his wife — has her first husband beyond level 1 (D50): the trace sideways.
      final int tadeusz = id['Tadeusz Wymyślewicz']!;
      final int genowefa = id['Genowefa Wymyślewicz']!;

      final TreeLayout wreathed = layoutTree(
        TreeGraph(withChoices({genowefa: const WreathChoice.clan(1)})),
        tadeusz,
        1,
        metrics: wide,
      );
      final Offset her = wreathed.positions[genowefa]!;
      final double away = her.dx < wreathed.positions[tadeusz]!.dx ? -1 : 1;
      expect(
        trace(wreathed),
        containsAllInOrder([
          Offset(her.dx + away * 43, her.dy + 22),
          Offset(her.dx + away * 57, her.dy + 22),
        ]),
      );

      // Without a wreath: the trace at her circle again.
      final TreeLayout bare = layoutTree(
        TreeGraph(withChoices(const {})),
        tadeusz,
        1,
        metrics: wide,
      );
      final Offset bareHer = bare.positions[genowefa]!;
      final double bareAway = bareHer.dx < bare.positions[tadeusz]!.dx ? -1 : 1;
      expect(
        trace(bare),
        containsAllInOrder([
          Offset(bareHer.dx + bareAway * 22, bareHer.dy + 22),
          Offset(bareHer.dx + bareAway * 36, bareHer.dy + 22),
        ]),
      );
    },
  );

  test(
    'ISSUE-049 (D50) — a cycle in the data does not hang the levels by unions either',
    () {
      const TreePerson a = TreePerson(id: 1, givenNames: 'Adam');
      const TreePerson b = TreePerson(id: 2, givenNames: 'Beata');
      final FamilyTreeData looped = FamilyTreeData(
        people: {1: a, 2: b},
        unions: const [
          TreeUnion(familyId: 1, partners: [1, 2], children: [2]),
        ],
      );
      final TreeGraph g = TreeGraph(looped);
      expect(g.unionLevels(1), {1: 1, 2: 1});
      expect(layoutTree(g, 1, 1).count, 2);
    },
  );
}
