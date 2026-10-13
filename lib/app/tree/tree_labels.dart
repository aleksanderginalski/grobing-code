// The names when the tree is zoomed out (05_DESIGN/drzewo.md v1.6, element 4 — I2, the author's choice at
// stop #1 of ISSUE-033; style-b.md rule 13 v1.25): like the labels of a map, a name keeps its size on the
// screen, and of names that would overlap the one nearer the person in the middle stays — first by level
// (D2), then by the distance across. Fewer names, each one readable; zooming in brings the rest back.

/// One name's box in the tree's own coordinates, at the size it is drawn.
class LabelBox {
  const LabelBox({
    required this.id,
    required this.centerX,
    required this.top,
    required this.width,
    required this.height,
    required this.level,
    required this.distance,
  });

  final int id;
  final double centerX;
  final double top;
  final double width;
  final double height;

  /// The person's level from the middle; the middle itself −1.
  final int level;

  /// How far across from the person in the middle.
  final double distance;
}

/// The names that stay: greedily, the nearest first, each one that does not overlap one already placed
/// (with [gap] on each side).
Set<int> visibleLabels(Iterable<LabelBox> boxes, {double gap = 0}) {
  final List<LabelBox> order = [...boxes]
    ..sort((a, b) {
      final int byLevel = a.level.compareTo(b.level);
      if (byLevel != 0) return byLevel;
      final int byDistance = a.distance.compareTo(b.distance);
      return byDistance != 0 ? byDistance : a.id.compareTo(b.id);
    });
  final List<({double l, double r, double t, double b})> placed = [];
  final Set<int> shown = {};
  for (final LabelBox box in order) {
    final double l = box.centerX - box.width / 2 - gap;
    final double r = box.centerX + box.width / 2 + gap;
    final double t = box.top, b = box.top + box.height;
    final bool hit = placed.any(
      (q) => l < q.r && r > q.l && t < q.b && b > q.t,
    );
    if (hit) continue;
    placed.add((l: l, r: r, t: t, b: b));
    shown.add(box.id);
  }
  return shown;
}
