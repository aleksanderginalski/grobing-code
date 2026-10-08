import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/database.dart';

import 'support/backup_fakes.dart';

/// The whole app on an empty database; the returned function unmounts it and removes its files.
Future<Future<void> Function()> _pumpApp(WidgetTester tester) async {
  final Directory tmp = Directory.systemTemp.createTempSync('grobing_app_test');
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

  return () async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
  };
}

// ISSUE-002 AC-8: the app starts dark (Style B). ISSUE-014: on the map of Poland, the start screen gone;
// "Stan danych" (ISSUE-007) under the gear. ISSUE-021 AC-1: Flutter's own texts in Polish.
void main() {
  testWidgets(
    'GrobingApp starts dark, on the home screen with the app name, the search and the gear',
    (tester) async {
      final Future<void> Function() cleanUp = await _pumpApp(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Grobing'), findsOneWidget);
      expect(find.text('Szukaj cmentarza'), findsOneWidget);
      expect(find.byTooltip('Ustawienia'), findsOneWidget);

      final BuildContext context = tester.element(find.byType(Scaffold));
      final ThemeData theme = Theme.of(context);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, GrobingColors.background);
      expect(theme.colorScheme.primary, GrobingColors.amber);

      await cleanUp();
    },
  );

  testWidgets(
    "ISSUE-021 AC-1, D1 — Flutter's own texts (back button, text menu, closing a sheet) speak Polish, "
    'whatever the language of the phone',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final Future<void> Function() cleanUp = await _pumpApp(tester);

      final BuildContext context = tester.element(find.byType(Scaffold));
      expect(Localizations.localeOf(context), const Locale('pl'));
      final MaterialLocalizations texts = MaterialLocalizations.of(context);
      expect(texts.backButtonTooltip, 'Wstecz');
      expect(texts.pasteButtonLabel, 'Wklej');
      expect(texts.copyButtonLabel, 'Kopiuj');
      expect(texts.selectAllButtonLabel, 'Zaznacz wszystko');
      expect(texts.closeButtonTooltip, 'Zamknij');

      await cleanUp();
    },
  );
}
