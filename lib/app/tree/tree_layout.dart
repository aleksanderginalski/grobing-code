import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../data/database.dart' show Sex;
import '../../data/family_tree.dart';
import '../../data/kinship.dart' show KinEdge, KinStep;
import 'tree_time.dart';

// The tree from a person (05_DESIGN/drzewo.md v1.6, elements 3 and 4; ISSUE-033): who is shown at each
// level (D2), and where — the port of the layout SPIKE-002 measured on its mockup (Findings M1: the same
// numbers, 6 → 20 → 66 → 99 people, 0/0/6/9 crossings). Rows by generation, a pair as one block, the
// partner's family to one side (D8), the order in a row by barycentres with the fewest crossings, and the
// places in a row by isotonic regression. Pure Dart: the screen gives the sizes, the tests give a family.

/// Who is related to whom, as the layout asks it.
class TreeGraph {
  TreeGraph(FamilyTreeData data)
    : _sex = {for (final TreePerson p in data.people.values) p.id: p.sex},
      _birthYear = {
        for (final TreePerson p in data.people.values)
          if (p.birth != null) p.id: p.birth!.from.year,
      } {
    int order = 0;
    for (final TreeUnion u in data.unions) {
      final _Union union = _Union(u, order++);
      for (final int p in u.partners) {
        (_unionsOf[p] ??= []).add(union);
      }
      for (final int c in u.children) {
        _parentUnion.putIfAbsent(c, () => union);
      }
    }
    // A person's unions by their start, those without one in the order written (families.dart).
    for (final List<_Union> list in _unionsOf.values) {
      list.sort((a, b) {
        final int? ka = a.u.startKey, kb = b.u.startKey;
        if (ka != kb) {
          if (ka == null) return 1;
          if (kb == null) return -1;
          return ka.compareTo(kb);
        }
        return a.order.compareTo(b.order);
      });
    }
  }

  final Map<int, Sex?> _sex;
  final Map<int, int> _birthYear;
  final Map<int, List<_Union>> _unionsOf = {};
  final Map<int, _Union> _parentUnion = {};

  List<_Union> _unions(int n) => _unionsOf[n] ?? const [];

  /// The parents, the father first (the mockup's order; it decides nothing but which is tried first).
  List<int> parentsOf(int n) {
    final _Union? u = _parentUnion[n];
    if (u == null) return const [];
    final List<int> ps = [...u.u.partners];
    if (ps.length == 2 && _sex[ps[0]] != Sex.male && _sex[ps[1]] == Sex.male) {
      return [ps[1], ps[0]];
    }
    return ps;
  }

  /// The partners, by the start of the union.
  List<int> partnersOf(int n) => [
    for (final _Union u in _unions(n))
      for (final int p in u.u.partners)
        if (p != n) p,
  ];

  List<int> childrenOf(int n) => [
    for (final _Union u in _unions(n)) ...u.u.children,
  ];

  /// The children of either parent but [n], by birth year — half-siblings too.
  List<int> siblingsOf(int n) {
    final Set<int> s = {};
    for (final int p in parentsOf(n)) {
      for (final int c in childrenOf(p)) {
        if (c != n) s.add(c);
      }
    }
    final List<int> list = s.toList();
    return _stable(
      list,
      (a, b) => (_birthYear[a] ?? 99999).compareTo(_birthYear[b] ?? 99999),
    );
  }

  TreeUnion? unionBetween(int a, int b) {
    for (final _Union u in _unions(a)) {
      if (u.u.partners.contains(b)) return u.u;
    }
    return null;
  }

  /// D2: level k adds the parents, partners and children of everyone at level k − 1 and, from k = 2, their
  /// siblings too. Each person once, at their lowest level — so a cycle in the data cannot hang it.
  Map<int, int> levelsFrom(int focus, int maxLevel) {
    final Map<int, int> level = {focus: 0};
    List<int> frontier = [focus];
    for (int k = 1; k <= maxLevel && frontier.isNotEmpty; k++) {
      final List<int> next = [];
      for (final int n in frontier) {
        for (final int x in [
          ...parentsOf(n),
          ...partnersOf(n),
          ...childrenOf(n),
          if (k > 1) ...siblingsOf(n),
        ]) {
          if (!level.containsKey(x)) {
            level[x] = k;
            next.add(x);
          }
        }
      }
      frontier = next;
    }
    return level;
  }
}

class _Union {
  _Union(this.u, this.order);

  final TreeUnion u;
  final int order;
}

/// The sizes of the layout in logical pixels — they grow with the system text (drzewo.md element 4, D20).
class TreeMetrics {
  const TreeMetrics({
    this.slot = 80,
    this.rowHeight = 104,
    this.labelBottom = 68,
  });

  /// A person's place: 80 dp × the text scale, at most 160 dp.
  final double slot;
  final double rowHeight;

  /// From a node's top to under its name — where a lone parent's line to the children starts.
  final double labelBottom;

  static const double node = 44;
  static const double padX = 48;
  static const double padY = 28;
}

enum TreeLineKind {
  married,
  together,
  parentChild,
  traceParentChild,
  tracePartner,

  /// "//" across a pair's line from the end of the union (drzewo.md element 4, D35 — the genogram's sign).
  ended,
}

/// One kind of line as straight segments, start and end in pairs.
class TreeLines {
  const TreeLines(this.kind, this.points);

  final TreeLineKind kind;
  final List<Offset> points;
}

/// The tree laid out: each person's place (the top centre of their node), the lines, the size.
class TreeLayout {
  TreeLayout._({
    required this.focus,
    required this.level,
    required this.positions,
    required this.levels,
    required this.width,
    required this.height,
    required this.spanWidth,
    required this.spanHeight,
    required this.crossings,
    required this.generations,
    required TreeGraph graph,
    required List<(int, int)> pairs,
    required Map<int, int> gen,
    required Set<int> vis,
    required TreeMetrics metrics,
  }) : _graph = graph,
       _pairs = pairs,
       _gen = gen,
       _vis = vis,
       _metrics = metrics;

  final int focus;
  final int level;

  /// Person → the top centre of their node, in the order of the rows from the top, left to right.
  final Map<int, Offset> positions;

  /// Person → their level from [focus] (D2) — the screen's order of the names (D8).
  final Map<int, int> levels;

  /// The lines today — the tree without the slider.
  late final List<TreeLines> lines = linesAt(null, null);

  final TreeGraph _graph;

  /// Neighbours in a row who are a pair — where a pair's line goes.
  final List<(int, int)> _pairs;
  final Map<int, int> _gen;
  final Set<int> _vis;
  final TreeMetrics _metrics;

  /// The lines in [year] on the slider (drzewo.md element 6, ISSUE-037): only people on the tree then, each
  /// pair as it was then, the trace only to family that already is (D37). The places stay — a year never
  /// lays the tree out anew (AC-1: "drzewo nie skacze").
  List<TreeLines> linesAt(TreeTime? time, int? year) {
    bool on(int n) => time == null || time.isOn(n, year);
    PairInYear? pairOf(TreeUnion u) => time == null
        ? PairInYear(married: u.married, ended: u.ended)
        : time.pair(u, year);
    return [
      ..._lines(_graph, _pairs, positions, _gen, _vis, _metrics, on, pairOf),
      ..._traces(_graph, positions, _vis, _metrics, focus, on, pairOf),
    ];
  }

  /// Each union's line to its children on the tree today: where it leaves the parents ([sx]) and the rail it
  /// runs along ([ry]) — the path's line goes the same way (ISSUE-039).
  late final Map<TreeUnion, ({double sx, double ry})> _rails = () {
    final Map<TreeUnion, ({double sx, double ry})> rails = {};
    _lines(
      _graph,
      _pairs,
      positions,
      _gen,
      _vis,
      _metrics,
      (_) => true,
      (u) => PairInYear(married: u.married, ended: u.ended),
      rails: rails,
    );
    return rails;
  }();

  /// The path of "Połącz dwie osoby" as lines on this tree (drzewo.md element 8, D49): one run of points for
  /// each step from [from], along the family's lines — a pair level between the two; a parent and a child
  /// through the line to the children and its rail; siblings through their parents' rail, or a bracket just
  /// above them when their parents are not on the tree. Straight where the tree draws no line between them.
  List<List<Offset>> pathRoute(int from, List<KinStep> steps) {
    final List<List<Offset>> runs = [];
    int a = from;
    for (final KinStep s in steps) {
      runs.add(_stepRoute(a, s.personId, s.edge));
      a = s.personId;
    }
    return runs;
  }

  static Offset _middleOf(Offset place) => Offset(place.dx, place.dy + _half);

  List<Offset> _stepRoute(int a, int b, KinEdge edge) {
    final Offset pa = positions[a]!, pb = positions[b]!;
    switch (edge) {
      case KinEdge.partner:
        return [_middleOf(pa), _middleOf(pb)];
      case KinEdge.child:
        return _down(a, b);
      case KinEdge.parent:
        return _down(b, a).reversed.toList();
      case KinEdge.sibling:
        final double y = _railOf(a)?.ry ?? math.min(pa.dy, pb.dy) - 9;
        return [
          _middleOf(pa),
          Offset(pa.dx, y),
          Offset(pb.dx, y),
          _middleOf(pb),
        ];
    }
  }

  /// From a parent down to a child: along the pair's line to where the line to the children leaves it, down to
  /// the rail, along it, down to the child.
  List<Offset> _down(int parent, int child) {
    final Offset pp = positions[parent]!, pc = positions[child]!;
    final ({double sx, double ry})? rail = _railOf(child);
    if (rail == null) return [_middleOf(pp), _middleOf(pc)];
    return [
      _middleOf(pp),
      if ((rail.sx - pp.dx).abs() > 1) Offset(rail.sx, pp.dy + _half),
      Offset(rail.sx, rail.ry),
      Offset(pc.dx, rail.ry),
      _middleOf(pc),
    ];
  }

  ({double sx, double ry})? _railOf(int child) {
    final _Union? u = _graph._parentUnion[child];
    return u == null ? null : _rails[u.u];
  }

  final double width;
  final double height;

  /// The nodes' extent, without the margins.
  final double spanWidth;
  final double spanHeight;
  final int crossings;
  final int generations;

  int get count => positions.length;
}

const double _gap = 0.3;

/// Lays out [focus]'s family to [level] (D2) and [also] people beyond it — the rest of a path that goes further
/// than level 4 (ISSUE-039, drzewo.md element 8). They must join [focus] through the people shown, as a path's
/// people do.
TreeLayout layoutTree(
  TreeGraph graph,
  int focus,
  int level, {
  TreeMetrics metrics = const TreeMetrics(),
  Set<int> also = const {},
}) {
  final Set<int> vis = {...graph.levelsFrom(focus, level).keys, ...also};
  final Map<int, int> lv = graph.levelsFrom(focus, 99);
  int lvOf(int n) => lv[n] ?? 99;

  // Breadth first from the middle: a generation for everyone, a first place in slots and a side — the
  // partner's family to one side, the person's siblings to the other.
  final Map<int, int> gen = {focus: 0};
  final Map<int, double> xr = {focus: 0};
  final Map<int, int> side = {focus: 0};
  final Map<int, int> bfs = {focus: 0};
  final List<int> queue = [focus];
  int seq = 1;
  void put(int x, int g, double xx, int sd) {
    gen[x] = g;
    xr[x] = xx;
    side[x] = sd;
    bfs[x] = seq++;
    queue.add(x);
  }

  for (int qi = 0; qi < queue.length; qi++) {
    final int n = queue[qi];
    final int g = gen[n]!, sd = side[n]!;
    final double x = xr[n]!;
    final List<int> ps = [
      for (final int p in graph.parentsOf(n))
        if (vis.contains(p)) p,
    ];
    for (int i = 0; i < ps.length; i++) {
      if (!gen.containsKey(ps[i])) {
        put(
          ps[i],
          g - 1,
          x + (ps.length == 2 ? (i > 0 ? 0.5 : -0.5) : 0),
          sd != 0 ? sd : (i > 0 ? 1 : -1),
        );
      }
    }
    final int dP = sd != 0 ? sd : 1;
    final List<int> partners = [
      for (final int s in graph.partnersOf(n))
        if (vis.contains(s)) s,
    ];
    for (int i = 0; i < partners.length; i++) {
      if (!gen.containsKey(partners[i])) {
        put(partners[i], g, x + dP * (i + 1), dP);
      }
    }
    final List<int> cs = [
      for (final int c in graph.childrenOf(n))
        if (vis.contains(c)) c,
    ];
    for (int i = 0; i < cs.length; i++) {
      if (!gen.containsKey(cs[i])) {
        final double off = i - (cs.length - 1) / 2;
        put(
          cs[i],
          g + 1,
          x + 0.5 * dP + off,
          sd != 0 ? sd : (off < 0 ? -1 : 1),
        );
      }
    }
    final int dS = sd != 0 ? sd : -1;
    final List<int> sibs = [
      for (final int s in graph.siblingsOf(n))
        if (vis.contains(s)) s,
    ];
    for (int i = 0; i < sibs.length; i++) {
      if (!gen.containsKey(sibs[i])) {
        put(sibs[i], g, x + dS * (partners.length + i + 1), dS);
      }
    }
  }

  // Rows of units: a chain of partners in one row is one block.
  final Map<int, List<_Unit>> rows = {};
  final Set<int> done = {};
  for (final int n in gen.keys) {
    if (done.contains(n)) continue;
    final int g = gen[n]!;
    final List<int> comp = [];
    final List<int> stack = [n];
    done.add(n);
    while (stack.isNotEmpty) {
      final int m = stack.removeLast();
      comp.add(m);
      for (final int s in graph.partnersOf(m)) {
        if (gen[s] == g && !done.contains(s)) {
          done.add(s);
          stack.add(s);
        }
      }
    }
    List<int> chain;
    if (comp.length <= 2) {
      chain = _stable(comp, (a, b) {
        final int c = xr[a]!.compareTo(xr[b]!);
        return c != 0 ? c : bfs[a]!.compareTo(bfs[b]!);
      });
    } else {
      int degree(int m) =>
          graph.partnersOf(m).where((s) => comp.contains(s)).length;
      int year(int m) {
        final int s = graph.partnersOf(m).firstWhere(comp.contains);
        return graph.unionBetween(m, s)?.startKey ?? 1 << 30;
      }

      final List<int> ends = _stable(
        comp.where((m) => degree(m) == 1).toList(),
        (a, b) => year(a).compareTo(year(b)),
      );
      int cur = ends.isNotEmpty ? ends.first : comp.first;
      chain = [cur];
      final Set<int> seen = {cur};
      while (true) {
        final int? next = graph
            .partnersOf(cur)
            .where((s) => comp.contains(s) && !seen.contains(s))
            .firstOrNull;
        if (next == null) break;
        chain.add(next);
        seen.add(next);
        cur = next;
      }
      // A person in more than two unions breaks the chain into a tree: the rest stand after it.
      for (final int m in comp) {
        if (!seen.contains(m)) chain.add(m);
      }
    }
    final int minLv = chain.map(lvOf).reduce(math.min);
    (rows[g] ??= []).add(
      _Unit(
        members: chain,
        weights: [for (final int m in chain) lvOf(m) == minLv ? 1 : 0.12],
        key: chain.map((m) => xr[m]!).reduce((a, b) => a + b) / chain.length,
        first: chain.map((m) => bfs[m]!).reduce(math.min),
      ),
    );
  }
  final List<int> gs = rows.keys.toList()..sort();
  for (final int g in gs) {
    rows[g] = _stable(rows[g]!, (a, b) {
      final int c = a.key.compareTo(b.key);
      return c != 0 ? c : a.first.compareTo(b.first);
    });
  }

  final Map<int, double> pos = {};
  void pack() {
    for (final int g in gs) {
      double x = 0;
      for (final _Unit u in rows[g]!) {
        for (int i = 0; i < u.members.length; i++) {
          pos[u.members[i]] = x + i;
        }
        u.x = x;
        x += u.members.length + _gap;
      }
    }
  }

  double? midOf(int n) {
    final List<int> ps = [
      for (final int p in graph.parentsOf(n))
        if (vis.contains(p) && gen[p] == gen[n]! - 1) p,
    ];
    if (ps.isEmpty) return null;
    return ps.map((p) => pos[p]!).reduce((a, b) => a + b) / ps.length;
  }

  double weightedMean(List<int> ks) {
    final int mn = ks.map(lvOf).reduce(math.min);
    double a = 0, b = 0;
    for (final int c in ks) {
      final double w = lvOf(c) == mn ? 1 : 0.35;
      a += pos[c]! * w;
      b += w;
    }
    return a / b;
  }

  double? kidsMean(int n) {
    final List<int> ks = [
      for (final int c in graph.childrenOf(n))
        if (vis.contains(c) && gen[c] == gen[n]! + 1) c,
    ];
    return ks.isEmpty ? null : weightedMean(ks);
  }

  int crossings() {
    int total = 0;
    for (final int g in gs) {
      final List<(double, double)> e = [];
      for (final _Unit u in rows[g]!) {
        for (final int c in u.members) {
          final double? t = midOf(c);
          if (t != null) e.add((t, pos[c]!));
        }
      }
      for (int i = 0; i < e.length; i++) {
        for (int j = i + 1; j < e.length; j++) {
          if ((e[i].$1 - e[j].$1) * (e[i].$2 - e[j].$2) < 0) total++;
        }
      }
    }
    return total;
  }

  // The order in each row: barycentres, down and up in turns; the order with the fewest crossings wins.
  pack();
  int best = crossings();
  List<List<_Unit>> bestOrder = [
    for (final int g in gs) [...rows[g]!],
  ];
  for (int it = 0; it < 10; it++) {
    final bool down = it.isEven;
    for (final int g in down ? gs : gs.reversed) {
      for (final _Unit u in rows[g]!) {
        double a = 0, b = 0;
        for (int i = 0; i < u.members.length; i++) {
          final double? t = down ? midOf(u.members[i]) : kidsMean(u.members[i]);
          if (t != null) {
            a += (t - i + (u.members.length - 1) / 2) * u.weights[i];
            b += u.weights[i];
          }
        }
        u.key = b != 0 ? a / b : u.x + (u.members.length - 1) / 2;
      }
      rows[g] = _stable(rows[g]!, (a, b) => a.key.compareTo(b.key));
      pack();
    }
    final int c = crossings();
    if (c < best) {
      best = c;
      bestOrder = [
        for (final int g in gs) [...rows[g]!],
      ];
    }
  }
  for (int i = 0; i < gs.length; i++) {
    rows[gs[i]] = bestOrder[i];
  }
  pack();

  // The places in each row: each block pulled towards its parents' and children's middles, the order
  // kept — isotonic regression, pool adjacent violators.
  for (int it = 0; it < 60; it++) {
    for (final int g in it.isEven ? gs : gs.reversed) {
      final List<_Unit> us = rows[g]!;
      final List<double> d = [], w = [];
      for (final _Unit u in us) {
        double sum = 0, ws = 0;
        for (int i = 0; i < u.members.length; i++) {
          final double? t = midOf(u.members[i]);
          if (t != null) {
            sum += (t - i) * u.weights[i];
            ws += u.weights[i];
          }
        }
        final Set<_Union> own = {
          for (final int m in u.members) ...graph._unions(m),
        };
        for (final _Union pu in own) {
          final List<int> ks = [
            for (final int c in pu.u.children)
              if (vis.contains(c) && gen[c] == g + 1) c,
          ];
          if (ks.isEmpty) continue;
          final List<int> inUnit = [
            for (final int p in pu.u.partners)
              if (u.members.contains(p)) p,
          ];
          if (inUnit.isEmpty) continue;
          final double off =
              inUnit.map(u.members.indexOf).reduce((a, b) => a + b) /
              inUnit.length;
          final double wu = inUnit
              .map((p) => u.weights[u.members.indexOf(p)])
              .reduce(math.max);
          sum += (weightedMean(ks) - off) * wu;
          ws += wu;
        }
        d.add(ws != 0 ? sum / ws : u.x);
        w.add(ws != 0 ? ws : 0.05);
      }
      final List<double> offs = [];
      double o = 0;
      for (final _Unit u in us) {
        offs.add(o);
        o += u.members.length + _gap;
      }
      final List<({double s, double w, int n})> blocks = [];
      for (int i = 0; i < us.length; i++) {
        final double v = d[i] - offs[i];
        blocks.add((s: v * w[i], w: w[i], n: 1));
        while (blocks.length > 1) {
          final a = blocks[blocks.length - 2], b = blocks.last;
          if (a.s / a.w <= b.s / b.w) break;
          blocks
            ..removeLast()
            ..removeLast()
            ..add((s: a.s + b.s, w: a.w + b.w, n: a.n + b.n));
        }
      }
      int i = 0;
      for (final block in blocks) {
        final double v = block.s / block.w;
        for (int k = 0; k < block.n; k++, i++) {
          us[i].x = v + offs[i];
          for (int j = 0; j < us[i].members.length; j++) {
            pos[us[i].members[j]] = us[i].x + j;
          }
        }
      }
    }
  }

  final double minX = pos.values.reduce(math.min);
  final double maxX = pos.values.reduce(math.max);
  final int gmin = gs.first, gmax = gs.last;
  final double slot = metrics.slot;
  final Map<int, Offset> px = {
    for (final int g in gs)
      for (final _Unit u in rows[g]!)
        for (final int m in u.members)
          m: Offset(
            TreeMetrics.padX + (pos[m]! - minX) * slot,
            TreeMetrics.padY + (gen[m]! - gmin) * metrics.rowHeight,
          ),
  };
  final Map<int, Offset> ordered = Map.fromEntries(
    _stable(px.entries.toList(), (a, b) {
      final int c = a.value.dy.compareTo(b.value.dy);
      return c != 0 ? c : a.value.dx.compareTo(b.value.dx);
    }),
  );

  return TreeLayout._(
    focus: focus,
    level: level,
    positions: ordered,
    levels: {for (final int n in px.keys) n: lvOf(n)},
    graph: graph,
    pairs: [
      for (final int g in gs)
        for (final _Unit u in rows[g]!)
          for (int i = 0; i + 1 < u.members.length; i++)
            (u.members[i], u.members[i + 1]),
    ],
    gen: gen,
    vis: vis,
    metrics: metrics,
    width: (maxX - minX) * slot + 2 * TreeMetrics.padX,
    height:
        (gmax - gmin) * metrics.rowHeight +
        2 * TreeMetrics.padY +
        metrics.labelBottom,
    spanWidth: (maxX - minX + 1) * slot,
    spanHeight: (gmax - gmin) * metrics.rowHeight + metrics.labelBottom + 4,
    crossings: best,
    generations: gs.length,
  );
}

class _Unit {
  _Unit({
    required this.members,
    required this.weights,
    required this.key,
    required this.first,
  });

  final List<int> members;
  final List<double> weights;
  double key;
  final int first;
  double x = 0;
}

const double _half = TreeMetrics.node / 2;

/// The relation lines (drzewo.md element 4): a pair — level, between neighbours in a row; parent–child —
/// from the middle of the pair's line (or from under a lone parent) down to a rail and to each child. Rails
/// that would overlap get their own heights, so two families never share one line. Only between people [on]
/// the tree, a pair as [pairOf] says (the slider's year, ISSUE-037). [rails] gets each union's line to the
/// children, for the path's route (ISSUE-039).
List<TreeLines> _lines(
  TreeGraph graph,
  List<(int, int)> pairs,
  Map<int, Offset> px,
  Map<int, int> gen,
  Set<int> vis,
  TreeMetrics metrics,
  bool Function(int) on,
  PairInYear? Function(TreeUnion) pairOf, {
  Map<TreeUnion, ({double sx, double ry})>? rails,
}) {
  final List<Offset> married = [], together = [], parentChild = [], ended = [];
  for (final (int a, int b) in pairs) {
    final TreeUnion? union = graph.unionBetween(a, b);
    if (union == null || !on(a) || !on(b)) continue;
    final PairInYear? pair = pairOf(union);
    if (pair == null) continue;
    final Offset pa = px[a]!, pb = px[b]!;
    final double y = pa.dy + _half;
    (pair.married ? married : together).addAll([
      Offset(pa.dx + _half, y),
      Offset(pb.dx - _half, y),
    ]);
    if (pair.ended) {
      // Two strokes, 12 × 12 dp, across the middle of the line (D35).
      final double x = (pa.dx + pb.dx) / 2;
      ended.addAll([
        Offset(x - 6, y + 6),
        Offset(x - 1, y - 6),
        Offset(x + 1, y + 6),
        Offset(x + 6, y - 6),
      ]);
    }
  }

  final Map<int, List<_Rail>> byGap = {};
  final Set<TreeUnion> unions = {
    for (final int n in px.keys)
      for (final _Union u in graph._unions(n)) u.u,
  };
  for (final TreeUnion u in unions) {
    final List<int> ks = [
      for (final int c in u.children)
        if (vis.contains(c) && px.containsKey(c) && on(c)) c,
    ];
    if (ks.isEmpty) continue;
    final List<int> ps = [
      for (final int p in u.partners)
        if (px.containsKey(p) && gen[p] == gen[ks.first]! - 1 && on(p)) p,
    ];
    if (ps.isEmpty) continue;
    final double sx, sy;
    if (ps.length == 2 &&
        (px[ps[0]]!.dx - px[ps[1]]!.dx).abs() <= metrics.slot + 1) {
      sx = (px[ps[0]]!.dx + px[ps[1]]!.dx) / 2;
      sy = px[ps[0]]!.dy + _half;
    } else {
      final double kx = px[ks.first]!.dx;
      final int p =
          ps.length == 2 &&
              (px[ps[1]]!.dx - kx).abs() < (px[ps[0]]!.dx - kx).abs()
          ? ps[1]
          : ps[0];
      sx = px[p]!.dx;
      sy = px[p]!.dy + metrics.labelBottom;
    }
    (byGap[gen[ks.first]!] ??= []).add(_Rail(u, sx, sy, ks));
  }
  for (final List<_Rail> list in byGap.values) {
    for (final _Rail e in list) {
      final Iterable<double> xs = e.children.map((c) => px[c]!.dx);
      e.lo = math.min(e.sx, xs.reduce(math.min));
      e.hi = math.max(e.sx, xs.reduce(math.max));
    }
    final List<_Rail> sorted = _stable(list, (a, b) => a.lo.compareTo(b.lo));
    final List<double> ends = [];
    for (final _Rail e in sorted) {
      int k = ends.indexWhere((x) => x < e.lo - 6);
      if (k < 0) {
        k = ends.length;
        ends.add(e.hi);
      } else {
        ends[k] = e.hi;
      }
      final double ty = px[e.children.first]!.dy;
      final double ry = ty - 9 - math.min(k, 3) * 7;
      rails?[e.union] = (sx: e.sx, ry: ry);
      parentChild
        ..addAll([Offset(e.sx, e.sy), Offset(e.sx, ry)])
        ..addAll([Offset(e.lo, ry), Offset(e.hi, ry)]);
      for (final int c in e.children) {
        final double x = px[c]!.dx;
        parentChild.addAll([Offset(x, ry), Offset(x, ty)]);
      }
    }
  }
  return [
    TreeLines(TreeLineKind.married, married),
    TreeLines(TreeLineKind.together, together),
    TreeLines(TreeLineKind.parentChild, parentChild),
    TreeLines(TreeLineKind.ended, ended),
  ];
}

class _Rail {
  _Rail(this.union, this.sx, this.sy, this.children);

  final TreeUnion union;
  final double sx;
  final double sy;
  final List<int> children;
  double lo = 0;
  double hi = 0;
}

/// The trace of the family beyond the view (D9): up — parents, down — children, sideways — a partner, 14 dp,
/// away from the middle: left of it to the left, right of it and the middle itself to the right (ui review of
/// ISSUE-033 — always to the right, the trace on the left pointed at the middle and read as a line "razem").
/// From people [on] the tree, to family that is on it too: a child not born yet is no family beyond the
/// view, nor a partner before the union began — as the pair's line (D37; ui review of ISSUE-037).
List<TreeLines> _traces(
  TreeGraph graph,
  Map<int, Offset> px,
  Set<int> vis,
  TreeMetrics metrics,
  int focus,
  bool Function(int) on,
  PairInYear? Function(TreeUnion) pairOf,
) {
  final List<Offset> pc = [], pt = [];
  final double middle = px[focus]!.dx;
  bool away(int x) => !vis.contains(x) && on(x);
  for (final MapEntry<int, Offset> e in px.entries) {
    if (!on(e.key)) continue;
    final Offset p = e.value;
    if (graph.parentsOf(e.key).any(away)) {
      pc.addAll([Offset(p.dx, p.dy - 2), Offset(p.dx, p.dy - 16)]);
    }
    if (graph.childrenOf(e.key).any(away)) {
      pc.addAll([
        Offset(p.dx, p.dy + metrics.labelBottom),
        Offset(p.dx, p.dy + metrics.labelBottom + 14),
      ]);
    }
    if (graph.partnersOf(e.key).any((x) {
      final TreeUnion? union = graph.unionBetween(e.key, x);
      return away(x) && union != null && pairOf(union) != null;
    })) {
      final double side = p.dx < middle ? -1 : 1;
      pt.addAll([
        Offset(p.dx + side * _half, p.dy + _half),
        Offset(p.dx + side * (_half + 14), p.dy + _half),
      ]);
    }
  }
  return [
    TreeLines(TreeLineKind.traceParentChild, pc),
    TreeLines(TreeLineKind.tracePartner, pt),
  ];
}

/// [items] sorted by [compare], equals in the order given — JavaScript's sort, which the mockup's numbers
/// come from, is stable; Dart's is not.
List<T> _stable<T>(List<T> items, int Function(T, T) compare) {
  final List<(int, T)> indexed = [
    for (int i = 0; i < items.length; i++) (i, items[i]),
  ];
  indexed.sort((a, b) {
    final int c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (int, T) e in indexed) e.$2];
}
