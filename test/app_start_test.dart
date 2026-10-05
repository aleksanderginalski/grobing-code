import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/database.dart';

// ISSUE-002 AC-8: the app starts on a dark (Style B) start screen.
// ISSUE-007: the start screen leads to "Stan danych".
void main() {
  testWidgets(
    'GrobingApp starts on a dark start screen with the app name and "Stan danych"',
    (tester) async {
      final Directory tmp = Directory.systemTemp.createTempSync(
        'grobing_app_test',
      );
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());

      await tester.pumpWidget(
        GrobingApp(
          database: db,
          location: DataLocation(
            databaseFile: File('${tmp.path}/unused.db'),
            mediaDir: Directory('${tmp.path}/media'),
          ),
        ),
      );

      expect(find.text('Grobing'), findsOneWidget);
      expect(find.text('Stan danych'), findsOneWidget);

      final BuildContext context = tester.element(find.byType(Scaffold));
      final ThemeData theme = Theme.of(context);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, GrobingColors.background);
      expect(theme.colorScheme.primary, GrobingColors.amber);

      await tester.runAsync(() async {
        await db.close();
        await tmp.delete(recursive: true);
      });
    },
  );
}
