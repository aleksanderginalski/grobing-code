import 'package:flutter_test/flutter_test.dart';

/// Two fingers on [target] — apart for a [factor] over 1, together under 1 — the way a hand zooms the tree. Since
/// ISSUE-049 v1.25 (drzewo.md D58) the tree has no zoom buttons: two fingers are the way out. The fingers move along
/// the middle row of [target], 150 dp apart at the most, in ten steps.
Future<void> pinch(WidgetTester tester, Finder target, double factor) async {
  final Offset c = tester.getCenter(target);
  final double from = factor < 1 ? 150 : 150 / factor;
  final double to = from * factor;
  final TestGesture a = await tester.startGesture(c - Offset(from / 2, 0));
  final TestGesture b = await tester.startGesture(c + Offset(from / 2, 0));
  await tester.pump();
  final double step = (to - from) / 2 / 10;
  for (int i = 0; i < 10; i++) {
    await a.moveBy(Offset(-step, 0));
    await b.moveBy(Offset(step, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await tester.pump();
}
