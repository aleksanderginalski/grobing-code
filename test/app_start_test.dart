import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/database.dart';

import 'support/backup_fakes.dart';

// ISSUE-002 AC-8: the app starts dark (Style B). ISSUE-014: on the map of Poland, the start screen gone;
// "Stan danych" (ISSUE-007) under the gear.
void main() {
  testWidgets(
    'GrobingApp starts dark, on the home screen with the app name, the search and the gear',
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
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
          ),
        ),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Grobing'), findsOneWidget);
      expect(find.text('Szukaj cmentarza'), findsOneWidget);
      expect(find.byTooltip('Ustawienia'), findsOneWidget);

      final BuildContext context = tester.element(find.byType(Scaffold));
      final ThemeData theme = Theme.of(context);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, GrobingColors.background);
      expect(theme.colorScheme.primary, GrobingColors.amber);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        await db.close();
        await tmp.delete(recursive: true);
      });
    },
  );
}
