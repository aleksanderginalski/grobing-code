import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database.dart' show Sex;
import '../../data/family_tree.dart';
import '../../data/kinship.dart';
import '../person/kinship_names.dart';
import '../polish.dart';
import '../theme.dart';
import 'tree_layout.dart';

// "Połącz dwie osoby" on the tree (05_DESIGN/drzewo.md elements 7–10, v1.16; US-011, ISSUE-039): the path
// between two people lit on the same tree — "Do" in the middle (W2 — D45), the lowest level that shows all of
// it (D49), a line in amber along the family's lines, 0.7 s a step (D5), and a banner with the name once it
// reaches "Do" (D6, D47). The screen keeps the state; here are the parts that need no screen.

/// One step of the line: "powoli" (drzewo.md D5).
const Duration pathStepTime = Duration(milliseconds: 700);

/// The banner's time when the phone says nothing longer (element 9; D43 — Android's Snackbar without an
/// action takes "Czas na działanie" the same way).
const Duration pathBannerTime = Duration(seconds: 4);

/// The people, lines and traces off the path while it is lit (element 8): one layer for each group, never an
/// opacity on each person (ISSUE-037 — a layer each, in every frame).
const double pathDim = 0.3;

/// Element 10: two people nothing joins (reguła 9 — what is missing, said calmly).
/// A hard space after the one-letter "w" (style-b.md rule 6).
const String noPathText =
    'Te osoby nie łączą się — w drzewie brakuje rodziny między nimi.';

/// A path lit on the tree: from [from] to [to] through [steps] (`KinGraph.path`), with [also] — people laid out
/// besides the level (element 8, D49); since ISSUE-049 none, as every person of a path has a level (pathLevel).
class TreePath {
  TreePath({
    required this.from,
    required this.to,
    required this.steps,
    this.also = const {},
  }) : people = [from, for (final KinStep s in steps) s.personId];

  final int from;
  final int to;
  final List<KinStep> steps;
  final Set<int> also;

  /// [from], then each person a step reaches, [to] last.
  final List<int> people;

  late final Set<int> members = people.toSet();
}

/// The lowest level from [focus] that shows all of [people] (drzewo.md element 8, D49): the highest of their
/// levels ([TreeGraph.unionLevels], D50). People of one path are joined by the family, so each has a level and
/// nothing is laid out besides it ([also] stays empty since ISSUE-049). The screen goes up to it, never down (D57).
({int level, Set<int> also}) pathLevel(
  TreeGraph graph,
  int focus,
  List<int> people,
) {
  final Map<int, int> levels = graph.unionLevels(focus);
  return (
    level: people.fold(1, (top, n) => math.max(top, levels[n] ?? 1)),
    also: const {},
  );
}

/// The largest scale of a path's frame (F2 — D46, v1.17): a short path is not zoomed in on past it.
const double pathMaxScale = 1.3;

/// What the banner says (elements 9, 10): from "ja" — one line, the card's own name in the author's voice
/// (G2 — D28); from someone else — "Od → Do" over the name without "mój" (O2 — D47); nothing between them —
/// element 10.
({String? top, String text}) pathBannerText(
  FamilyTreeData family,
  int from,
  int to,
  List<KinStep>? steps,
) {
  if (steps == null) return (top: null, text: noPathText);
  Sex? sexOf(int id) => family.people[id]?.sex;
  final bool fromMe = from == family.meId;
  final String name =
      kinshipName(steps, sexOf, mine: fromMe) ??
      'nie wiadomo jeszcze, kim jest dla mnie';
  if (fromMe) return (top: null, text: name);
  String who(int id) {
    if (id == family.meId) return 'Ja';
    final TreePerson? p = family.people[id];
    return p == null ? '' : personName(p.givenNames, p.surname);
  }

  return (top: '${who(from)} → ${who(to)}', text: name);
}

/// The path's line (element 8): amber, 3 dp on the screen at any scale of the tree, drawn step by step as
/// [progress] runs from 0 to 1 — the steps in equal time, however long.
class PathLinePainter extends CustomPainter {
  PathLinePainter({
    required this.runs,
    required this.progress,
    required this.scale,
    this.together = false,
  }) : super(repaint: progress);

  final List<List<Offset>> runs;
  final Animation<double> progress;
  final double scale;

  /// Every run grows at once — the couples of a year's caption (drzewo.md D73), not the steps of a path.
  final bool together;

  @override
  void paint(Canvas canvas, Size size) {
    if (runs.isEmpty) return;
    final Paint paint = Paint()
      ..color = GrobingColors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    double left = progress.value * runs.length;
    final Path path = Path();
    for (final List<Offset> run in runs) {
      if (together) {
        if (progress.value > 0) _addPart(path, run, progress.value);
        continue;
      }
      if (left <= 0) break;
      _addPart(path, run, math.min(1, left));
      left -= 1;
    }
    canvas.drawPath(path, paint);
  }

  /// The first [part] of [run], by its length.
  static void _addPart(Path path, List<Offset> run, double part) {
    double total = 0;
    for (int i = 0; i + 1 < run.length; i++) {
      total += (run[i + 1] - run[i]).distance;
    }
    double rest = total * part;
    path.moveTo(run.first.dx, run.first.dy);
    for (int i = 0; i + 1 < run.length && rest > 0; i++) {
      final Offset a = run[i], b = run[i + 1];
      final double d = (b - a).distance;
      if (d <= rest) {
        path.lineTo(b.dx, b.dy);
        rest -= d;
      } else {
        final Offset c = a + (b - a) * (rest / d);
        path.lineTo(c.dx, c.dy);
        rest = 0;
      }
    }
  }

  @override
  bool shouldRepaint(PathLinePainter old) =>
      old.runs != runs ||
      old.scale != scale ||
      old.progress != progress ||
      old.together != together;
}

/// Elements 9 and 10: at the top of the tree, on the surface — "Od → Do" in muted text when the path is not
/// from "ja", and the name, 16 sp semi-bold; centred, wrapped.
class PathBanner extends StatelessWidget {
  const PathBanner({super.key, this.top, required this.text});

  final String? top;
  final String text;

  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );
  // The line height written out: [heightFor] measures with these styles alone, and the theme's own (1.43 in
  // Material 3) made the banner 13 dp taller at 200 % than measured — it covered the top of the path (found on
  // the emulator, ISSUE-039).
  static const TextStyle topStyle = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 13,
    height: 1.3,
  );
  static const TextStyle textStyle = TextStyle(
    color: GrobingColors.text,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// The banner's height in [width] with [scaler] — the path's frame leaves it free (element 8).
  static double heightFor(
    ({String? top, String text}) banner,
    double width,
    TextScaler scaler,
  ) {
    final double inner = math.max(1, width - padding.horizontal);
    double line(String text, TextStyle style) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: scaler,
      )..layout(maxWidth: inner);
      final double h = painter.height;
      painter.dispose();
      return h;
    }

    final String? top = banner.top;
    return padding.vertical +
        (top == null ? 0 : line(top, topStyle) + 2) +
        line(banner.text, textStyle);
  }

  @override
  Widget build(BuildContext context) {
    final String? top = this.top;
    final Widget box = _box(top);
    // The arrow is no word for a reader: "Od: …, do: …" says the direction (ui review of ISSUE-039).
    return top == null
        ? box
        : Semantics(
            label: 'Od: ${top.replaceFirst(' → ', ', do: ')} — $text',
            excludeSemantics: true,
            child: box,
          );
  }

  Widget _box(String? top) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GrobingColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (top != null) ...[
              Text(top, textAlign: TextAlign.center, style: topStyle),
              const SizedBox(height: 2),
            ],
            Text(text, textAlign: TextAlign.center, style: textStyle),
          ],
        ),
      ),
    );
  }
}
