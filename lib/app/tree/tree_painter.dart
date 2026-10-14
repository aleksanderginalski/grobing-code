import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';

import '../theme.dart';
import 'tree_layout.dart';

/// The relation lines and the trace of the wider family (05_DESIGN/drzewo.md element 4, D9; style-b.md v1.24):
/// parent–child in its colour, stepped down; a married pair level and solid; a pair "razem" dashed 5/4; the
/// trace dashed 3/3 at 60 % opacity. The kind is carried by the shape too, not by colour alone (SC 1.4.1).
///
/// The end of a union — "//" across the pair's line, in the partners' colour (D35).
///
/// The paths — the dashes as well — are built once per layout and year, not in every frame: SPIKE-002 M3 found
/// the change of level stuttering on the raster thread, with dashed lines measured anew in each frame.
class TreeLinesPainter extends CustomPainter {
  TreeLinesPainter(this.lines) : _paths = _build(lines);

  final List<TreeLines> lines;
  final List<(Path, Paint)> _paths;

  /// The same lines, kind by kind and point by point — the slider's year changes them only now and then.
  static bool same(List<TreeLines> a, List<TreeLines> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].kind != b[i].kind || !listEquals(a[i].points, b[i].points)) {
        return false;
      }
    }
    return true;
  }

  static List<(Path, Paint)> _build(List<TreeLines> all) => [
    for (final TreeLines lines in all)
      if (lines.points.isNotEmpty) (_path(lines), _paint(lines.kind)),
  ];

  static Paint _paint(TreeLineKind kind) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = switch (kind) {
      TreeLineKind.parentChild || TreeLineKind.traceParentChild => 1.6,
      _ => 2,
    }
    ..color = switch (kind) {
      TreeLineKind.parentChild => GrobingColors.relParentChild,
      TreeLineKind.traceParentChild => GrobingColors.relParentChild.withValues(
        alpha: 0.6,
      ),
      TreeLineKind.married ||
      TreeLineKind.together ||
      TreeLineKind.ended => GrobingColors.relPartners,
      TreeLineKind.tracePartner => GrobingColors.relPartners.withValues(
        alpha: 0.6,
      ),
    };

  static Path _path(TreeLines lines) {
    final (double dash, double space)? pattern = switch (lines.kind) {
      TreeLineKind.together => (5, 4),
      TreeLineKind.traceParentChild || TreeLineKind.tracePartner => (3, 3),
      _ => null,
    };
    final Path path = Path();
    for (int i = 0; i + 1 < lines.points.length; i += 2) {
      final Offset a = lines.points[i], b = lines.points[i + 1];
      if (pattern == null) {
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
        continue;
      }
      final double length = (b - a).distance;
      if (length == 0) continue;
      final Offset unit = (b - a) / length;
      for (double d = 0; d < length; d += pattern.$1 + pattern.$2) {
        final Offset from = a + unit * d;
        final double to = d + pattern.$1 < length ? d + pattern.$1 : length;
        path
          ..moveTo(from.dx, from.dy)
          ..lineTo(a.dx + unit.dx * to, a.dy + unit.dy * to);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (Path path, Paint paint) in _paths) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(TreeLinesPainter old) => old.lines != lines;
}
