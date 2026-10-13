import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A glow (a shadow) drawn over a circle tints it: "Ja" fell under 4.5:1 and a profile photo was toned amber
/// (ui review of ISSUE-033 — the tree, the mini tree and the portrait; style-b.md rules 2 and 14). The glow
/// goes under the circle and only the ring over it, so no decoration in the foreground has a shadow.
void expectNoGlowOverContent(WidgetTester tester) {
  final List<DecoratedBox> over = [
    for (final DecoratedBox d in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ))
      if (d.position == DecorationPosition.foreground &&
          d.decoration is BoxDecoration &&
          ((d.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false))
        d,
  ];
  expect(over, isEmpty, reason: 'a glow drawn over its circle');
}
