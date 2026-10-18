import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Retro 3, R2: every semantics node flagged as a button has a tap action — a screen reader, Switch Access
/// and Voice Access can press only what has one. Six times (ISSUE-017 … ISSUE-028) a button without it was
/// found only by the ui review. Call with semantics on (`tester.ensureSemantics()`).
void expectEveryButtonTappable(WidgetTester tester) {
  final List<String> without = [];
  void visit(SemanticsNode node) {
    final SemanticsData data = node.getSemanticsData();
    // A button said to be off ("niedostępne" — e.g. someone with a grave in "Kto leży w tym grobie?",
    // grob.md D23) rightly has no tap; every button that is on must have one.
    final bool off = data.flagsCollection.isEnabled == Tristate.isFalse;
    if (data.flagsCollection.isButton &&
        !off &&
        !data.hasAction(SemanticsAction.tap)) {
      without.add(data.label.isEmpty ? data.tooltip : data.label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final RenderView view in tester.binding.renderViews) {
    visit(view.owner!.semanticsOwner!.rootSemanticsNode!);
  }
  expect(without, isEmpty, reason: 'buttons without a tap action: $without');
}
