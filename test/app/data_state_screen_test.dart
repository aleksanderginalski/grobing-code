import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';

// ISSUE-007 AC-3: the "Stan danych" screen. Tests run in debug mode, so the made-up-data button is
// there; its absence in the release build is a manual step (stop #2).

/// Lets real file and database work finish between frames (widget tests run in a fake clock).
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (int i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('condition not met in time');
}

void main() {
  testWidgets(
    'shows schema version, fingerprint and counts; the debug button adds made-up data',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final Directory tmp = Directory.systemTemp.createTempSync(
        'grobing_screen_test',
      );
      final DataLocation location = DataLocation(
        databaseFile: File('${tmp.path}/unused.db'),
        mediaDir: Directory('${tmp.path}/media'),
      );
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
      final DataState empty = (await tester.runAsync(
        () => readDataState(db, mediaDir: location.mediaDir),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          theme: GrobingTheme.dark,
          home: DataStateScreen(database: db, location: location),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text(empty.shortFingerprint).evaluate().isNotEmpty,
      );

      expect(find.text('Wersja schematu'), findsOneWidget);
      expect(
        find.text('1'),
        findsOneWidget,
      ); // the schema version; every count is 0
      expect(find.text('Osoby'), findsOneWidget);
      expect(find.text('Pliki zdjęć'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(11)); // 10 tables + photo files

      // The button writes a file and a transaction: run it on the real clock, not the test's fake one.
      await tester.runAsync(() async {
        await tester.tap(find.text('Wgraj wymyślone dane'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _pumpUntil(
        tester,
        () => find.text(empty.shortFingerprint).evaluate().isEmpty,
      );

      expect(find.text('3'), findsNWidgets(2)); // persons, burials

      await tester.runAsync(() async {
        await db.close();
        await tmp.delete(recursive: true);
      });
    },
  );
}
