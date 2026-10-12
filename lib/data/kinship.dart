import 'package:drift/drift.dart';

import 'database.dart';

/// One step on a path through the family: to a parent, a child, a sibling — a child of the same family
/// — or a partner (ISSUE-025 D2: R, D, B, P).
enum KinEdge { parent, child, sibling, partner }

/// One person on the path from "ja" (05_DESIGN/osoba.md element 7): who they are, how the person before
/// reaches them, and — for a partner — whether the pair married (żona / mąż, else partnerka / partner).
class KinStep {
  const KinStep({
    required this.personId,
    required this.edge,
    this.married = false,
  });

  final int personId;
  final KinEdge edge;
  final bool married;

  @override
  bool operator ==(Object other) =>
      other is KinStep &&
      other.personId == personId &&
      other.edge == edge &&
      other.married == married;

  @override
  int get hashCode => Object.hash(personId, edge, married);

  @override
  String toString() => 'KinStep($personId, ${edge.name}, married: $married)';
}

/// Everyone's ties in one place: the whole family as a graph of people (ISSUE-024). Computed, never
/// written — the data model keeps families, not paths (data-model.md).
class KinGraph {
  KinGraph._(this._ties);

  /// Person → the people one step away, each with how and whether it is a married pair.
  final Map<int, List<KinStep>> _ties;

  /// The graph from the families written: their partners and their children.
  static Future<KinGraph> load(GrobingDatabase db) async {
    final Map<int, List<int>> partners = {};
    for (final FamilyPartner fp in await db.select(db.familyPartners).get()) {
      (partners[fp.familyId] ??= []).add(fp.personId);
    }
    final Map<int, List<int>> children = {};
    for (final FamilyChildrenData fc in await (db.select(
      db.familyChildren,
    )..orderBy([(c) => OrderingTerm.asc(c.id)])).get()) {
      (children[fc.familyId] ??= []).add(fc.personId);
    }
    final Set<int> married = {
      for (final Event e in await (db.select(
        db.events,
      )..where((e) => e.type.equalsValue(EventType.marriage))).get())
        ?e.familyId,
    };
    return KinGraph.of(
      partners: partners,
      children: children,
      married: married,
    );
  }

  /// The graph from families given as plain maps: family → its partners, family → its children, the
  /// families with a wedding.
  factory KinGraph.of({
    required Map<int, List<int>> partners,
    required Map<int, List<int>> children,
    Set<int> married = const {},
  }) {
    final Map<int, List<KinStep>> ties = {};
    void tie(int from, KinStep step) {
      if (from == step.personId) return;
      final List<KinStep> list = ties[from] ??= [];
      if (!list.contains(step)) list.add(step);
    }

    for (final int family in {...partners.keys, ...children.keys}) {
      final List<int> pair = partners[family] ?? const [];
      final List<int> kids = children[family] ?? const [];
      final bool wed = married.contains(family);
      for (final int a in pair) {
        for (final int b in pair) {
          tie(a, KinStep(personId: b, edge: KinEdge.partner, married: wed));
        }
        for (final int c in kids) {
          tie(a, KinStep(personId: c, edge: KinEdge.child));
          tie(c, KinStep(personId: a, edge: KinEdge.parent));
        }
      }
      for (final int a in kids) {
        for (final int b in kids) {
          tie(a, KinStep(personId: b, edge: KinEdge.sibling));
        }
      }
    }
    return KinGraph._(ties);
  }

  /// The path from [from] to [to], without [from]: the fewest steps; of those, the fewest partner steps;
  /// of those, the one whose people's ids read first in order (ISSUE-025 D2) — so the same family always
  /// gives the same path. Empty when they are the same person; null when nothing joins them.
  List<KinStep>? path(int from, int to) {
    if (from == to) return const [];
    // Breadth first, a layer at a time: every person of a layer is as many steps away. A person reached
    // from several of the layer before keeps the best way in by the two rules after length.
    final Map<int, ({List<KinStep> steps, int partners, List<int> ids})> best =
        {from: (steps: const [], partners: 0, ids: const [])};
    List<int> layer = [from];
    while (layer.isNotEmpty && !best.containsKey(to)) {
      final Map<int, ({List<KinStep> steps, int partners, List<int> ids})>
      next = {};
      for (final int u in layer) {
        final ({List<KinStep> steps, int partners, List<int> ids}) way =
            best[u]!;
        for (final KinStep s in _ties[u] ?? const <KinStep>[]) {
          if (best.containsKey(s.personId)) continue;
          final candidate = (
            steps: [...way.steps, s],
            partners: way.partners + (s.edge == KinEdge.partner ? 1 : 0),
            ids: [...way.ids, s.personId],
          );
          final current = next[s.personId];
          if (current == null || _better(candidate, current)) {
            next[s.personId] = candidate;
          }
        }
      }
      best.addAll(next);
      layer = next.keys.toList()..sort();
    }
    return best[to]?.steps;
  }

  static bool _better(
    ({List<KinStep> steps, int partners, List<int> ids}) a,
    ({List<KinStep> steps, int partners, List<int> ids}) b,
  ) {
    if (a.partners != b.partners) return a.partners < b.partners;
    for (int i = 0; i < a.ids.length && i < b.ids.length; i++) {
      if (a.ids[i] != b.ids[i]) return a.ids[i] < b.ids[i];
    }
    // The same people — a pair who are partners and something else too: the step that is not a partner.
    return a.steps.last.edge != KinEdge.partner &&
        b.steps.last.edge == KinEdge.partner;
  }
}
