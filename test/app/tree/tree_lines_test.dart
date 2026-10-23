import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_layout.dart';
import 'package:grobing/app/tree/tree_time.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/kinship.dart';
import 'package:grobing/dev/fictional_family.dart';

// ISSUE-056 — the lines a large family can read (05_DESIGN/drzewo.md v1.31): the rails' floors for the fewest
// crossings (D84), a jump over another family's rail (D83), the places as they were (D86). The numbers come from
// the probe on the app's code before the change (Candidates — ISSUE-056). Made-up people only (family-data.md).

typedef _Seg = (Offset, Offset);

List<_Seg> _parentChild(List<TreeLines> lines) {
  final List<Offset> p = lines
      .firstWhere((l) => l.kind == TreeLineKind.parentChild)
      .points;
  return [for (int i = 0; i + 1 < p.length; i += 2) (p[i], p[i + 1])];
}

bool _slanted(_Seg s) => s.$1.dx != s.$2.dx && s.$1.dy != s.$2.dy;

/// The jumps as runs of points: slanted segments that follow one another.
List<List<Offset>> _arcs(List<_Seg> segs) {
  final List<List<Offset>> arcs = [];
  for (final _Seg s in segs) {
    if (!_slanted(s)) continue;
    if (arcs.isNotEmpty && arcs.last.last == s.$1) {
      arcs.last.add(s.$2);
    } else {
      arcs.add([s.$1, s.$2]);
    }
  }
  return arcs;
}

/// The rails: level segments of the parent–child lines.
List<_Seg> _rails(List<_Seg> segs) => [
  for (final _Seg s in segs)
    if (s.$1.dy == s.$2.dy && s.$1.dx != s.$2.dx) s,
];

void main() {
  late FamilyTreeData family;
  late TreeGraph graph;
  late TreeTime time;
  late int ja;
  late Map<String, int> id;

  setUpAll(() async {
    final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
    await addFictionalFamily(db);
    family = await loadFamilyTree(db);
    graph = TreeGraph(family);
    time = TreeTime(family, now: 2026);
    ja = family.meId!;
    id = {
      for (final TreePerson p in family.people.values)
        '${p.givenNames} ${p.surname}': p.id,
    };
    await db.close();
  });

  test(
    'ISSUE-056 AC-1 (D84, D86) — the drawn crossings from "Ja" 9 / 17 / 22 (before: 9 / 19 / 27), at most 4 floors '
    'in a gap; the places are those of 1.0.3+6',
    () {
      // A fingerprint of every place: the probe matched it against the export of 1.0.3+6 (ISSUE-056 → Dev report).
      int fingerprint(TreeLayout l) {
        int fp = 0;
        for (final MapEntry<int, Offset> e in l.positions.entries) {
          fp =
              (fp * 31 +
                  e.key * 1009 +
                  (e.value.dx * 10).round() * 7 +
                  (e.value.dy * 10).round()) %
              1000000007;
        }
        return fp;
      }

      const List<(int, int, int)> expected = [
        // drawn crossings, the order's own count (straight lines), places
        (9, 3, 250941589),
        (17, 14, 334506659),
        (22, 26, 84118573),
      ];
      for (int level = 1; level <= 3; level++) {
        final TreeLayout l = layoutTree(graph, ja, level);
        expect(
          (l.drawnCrossings, l.crossings, fingerprint(l)),
          expected[level - 1],
          reason: 'level $level',
        );
        // The floors: rails in the gap above a row stand at most 4 high.
        final List<double> rows =
            l.positions.values.map((o) => o.dy).toSet().toList()..sort();
        final Map<double, Set<double>> floors = {};
        for (final _Seg r in _rails(_parentChild(l.lines))) {
          final double row = rows.firstWhere((y) => y > r.$1.dy);
          (floors[row] ??= {}).add(r.$1.dy);
        }
        for (final MapEntry<double, Set<double>> f in floors.entries) {
          expect(
            f.value.length,
            lessThanOrEqualTo(4),
            reason: 'level $level, row ${f.key}',
          );
        }
      }
    },
  );

  test(
    'ISSUE-056 AC-2 (D83) — a drop across another family\'s rail jumps it: half an ellipse 4 dp to the right, from '
    '4 dp above the rail to 4 dp below; rails 7 dp apart share one arc; the rail goes on unbroken; no other slant',
    () {
      final TreeLayout l = layoutTree(graph, ja, 2);
      final List<_Seg> segs = _parentChild(l.lines);
      final List<_Seg> rails = _rails(segs);
      final List<List<Offset>> arcs = _arcs(segs);
      expect(arcs, isNotEmpty);
      int crossed = 0, shared = 0;
      for (final List<Offset> arc in arcs) {
        final Offset a = arc.first, b = arc.last;
        expect(a.dx, b.dx, reason: 'an arc leaves and rejoins its drop');
        expect(arc.length, 13, reason: '12 pieces');
        final double x = a.dx, top = a.dy < b.dy ? a.dy : b.dy;
        final double bottom = a.dy < b.dy ? b.dy : a.dy;
        for (final Offset o in arc) {
          expect(o.dx, inInclusiveRange(x - 1e-9, x + 4 + 1e-9));
        }
        expect(
          arc.map((o) => o.dx).reduce((p, q) => p > q ? p : q),
          closeTo(x + 4, 1e-9),
        );
        // The rails it jumps: whole segments through x — not cut at the jump.
        final List<double> under = [
          for (final _Seg r in rails)
            if (r.$1.dy > top &&
                r.$1.dy < bottom &&
                (r.$1.dx < r.$2.dx ? r.$1.dx : r.$2.dx) < x &&
                (r.$1.dx > r.$2.dx ? r.$1.dx : r.$2.dx) > x)
              r.$1.dy,
        ]..sort();
        expect(under, isNotEmpty, reason: 'an arc at ($x, $top) jumps a rail');
        expect(top, closeTo(under.first - 4, 1e-9));
        expect(bottom, closeTo(under.last + 4, 1e-9));
        for (int i = 0; i + 1 < under.length; i++) {
          expect(under[i + 1] - under[i], lessThan(8));
        }
        crossed += under.length;
        if (under.length > 1) shared++;
      }
      expect(crossed, l.drawnCrossings, reason: 'every crossing has its jump');
      expect(shared, greaterThan(0), reason: 'rails 7 dp apart under one arc');
      expect(
        segs.where(_slanted).length,
        12 * arcs.length,
        reason: 'a drop that crosses nothing stays straight',
      );
    },
  );

  test(
    'ISSUE-056 AC-3 (D83) — the path\'s line goes over the same arc as the line under it, from a person to a person',
    () {
      final TreeLayout l = layoutTree(graph, ja, 1);
      final int jan = id['Jan Wymyślony']!;
      final List<KinStep> steps = family.kin.path(ja, jan)!;
      final List<List<Offset>> runs = l.pathRoute(ja, steps);
      final Set<_Seg> drawn = {
        for (final _Seg s in _parentChild(l.lines)) ...[s, (s.$2, s.$1)],
      };
      int overArcs = 0;
      int from = ja;
      for (int i = 0; i < runs.length; i++) {
        final List<Offset> run = runs[i];
        expect(run.first, l.positions[from]! + const Offset(0, 22));
        expect(run.last, l.positions[steps[i].personId]! + const Offset(0, 22));
        for (int j = 0; j + 1 < run.length; j++) {
          final _Seg s = (run[j], run[j + 1]);
          if (!_slanted(s)) continue;
          expect(
            drawn,
            contains(s),
            reason: 'step $i, piece $j lies on the drawn arc',
          );
          overArcs++;
        }
        from = steps[i].personId;
      }
      expect(overArcs, greaterThan(0), reason: '"Ja" → Jan crosses a rail');
    },
  );

  test(
    'ISSUE-056 AC-3 (D84) — the slider keeps today\'s floors: every rail of a year lies on a rail of today; a jump '
    'only where both lines are that year',
    () {
      final TreeLayout l = layoutTree(graph, ja, 3);
      final List<_Seg> today = _parentChild(l.lines);
      final List<_Seg> railsToday = _rails(today);
      final Set<String> arcsToday = {
        for (final List<Offset> a in _arcs(today)) '$a',
      };
      bool onToday(_Seg r) => railsToday.any(
        (t) =>
            t.$1.dy == r.$1.dy &&
            (t.$1.dx < t.$2.dx ? t.$1.dx : t.$2.dx) <=
                (r.$1.dx < r.$2.dx ? r.$1.dx : r.$2.dx) &&
            (t.$1.dx > t.$2.dx ? t.$1.dx : t.$2.dx) >=
                (r.$1.dx > r.$2.dx ? r.$1.dx : r.$2.dx),
      );
      bool fewer = false;
      for (final int year in [1930, 1950, 1973, 1990, 2010]) {
        final List<_Seg> lines = _parentChild(l.linesAt(time, year));
        for (final _Seg r in _rails(lines)) {
          expect(onToday(r), isTrue, reason: 'a rail of $year at ${r.$1.dy}');
        }
        final List<List<Offset>> arcs = _arcs(lines);
        for (final List<Offset> a in arcs) {
          expect(arcsToday, contains('$a'), reason: 'a jump of $year');
        }
        if (arcs.length < arcsToday.length) fewer = true;
      }
      expect(fewer, isTrue, reason: 'before everyone is born, fewer jumps');
    },
  );
}
