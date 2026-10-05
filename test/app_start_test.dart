import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/theme.dart';

// ISSUE-002 AC-8: the app starts on a dark (Style B) start screen.
void main() {
  testWidgets('GrobingApp starts on a dark start screen with the app name', (
    tester,
  ) async {
    await tester.pumpWidget(const GrobingApp());

    expect(find.text('Grobing'), findsOneWidget);

    final BuildContext context = tester.element(find.byType(Scaffold));
    final ThemeData theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, GrobingColors.background);
    expect(theme.colorScheme.primary, GrobingColors.amber);
  });
}
