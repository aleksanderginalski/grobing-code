import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';

import '../support/backup_fakes.dart';

// ISSUE-007 AC-3: the "Stan danych" screen. Tests run in debug mode, so the made-up-data button is
// there; its absence in the release build is a manual step (stop #2).
// ISSUE-008 AC-1: the backup section — set-up offer, or the last successful backup and its failure.

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
  late Directory tmp;
  late GrobingDatabase db;
  late DataLocation location;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_screen_test');
    db = GrobingDatabase(NativeDatabase.memory());
    location = DataLocation.inDirectory(Directory('${tmp.path}/data'));
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: DataStateScreen(
          database: db,
          location: location,
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
          ),
        ),
      ),
    );
  }

  Future<void> cleanUp(WidgetTester tester) => tester.runAsync(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  testWidgets(
    'shows schema version, fingerprint and counts; the debug button adds made-up data',
    (tester) async {
      final DataState empty = (await tester.runAsync(
        () => readDataState(db, mediaDir: location.mediaDir),
      ))!;

      await pumpScreen(tester);
      await _pumpUntil(
        tester,
        () => find.text(empty.shortFingerprint).evaluate().isNotEmpty,
      );

      expect(find.text('Wersja schematu'), findsOneWidget);
      expect(
        find.text('5'),
        findsOneWidget,
      ); // the schema version; every count is 0
      expect(find.text('Osoby'), findsOneWidget);
      expect(find.text('Pliki zdjęć'), findsOneWidget);
      expect(find.text('Twierdzenia (źródła)'), findsOneWidget);
      // ISSUE-017: the new table has its Polish label, not "person_media".
      expect(find.text('Zdjęcia osób (łącza)'), findsOneWidget);
      expect(find.text('person_media'), findsNothing);
      expect(find.text('0'), findsNWidgets(13)); // 12 tables + photo files

      // The button writes a file and a transaction: run it on the real clock, not the test's fake one.
      await tester.runAsync(() async {
        await tester.tap(find.text('Wgraj wymyślone dane'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _pumpUntil(
        tester,
        () => find.text(empty.shortFingerprint).evaluate().isEmpty,
      );

      // persons, burials, photo rows, person links and photo files (ISSUE-017: a gravestone, a portrait
      // and a shared "wedding photo")
      expect(find.text('3'), findsNWidgets(5));
      // The schema version, 5 since ISSUE-018 — read in its own row: a count may be 5 too.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Wersja schematu'),
            matching: find.byType(Row),
          ),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );

      await cleanUp(tester);
    },
  );

  testWidgets('without a backup the screen offers the setup', (tester) async {
    await pumpScreen(tester);
    await _pumpUntil(
      tester,
      () => find.text('Skonfiguruj kopię').evaluate().isNotEmpty,
    );

    expect(
      find.textContaining('Kopia nie jest skonfigurowana'),
      findsOneWidget,
    );
    expect(find.text('Zrób kopię teraz'), findsNothing);

    await cleanUp(tester);
  });

  testWidgets(
    'with a backup the screen shows the last successful backup, an honest note and the last failure',
    (tester) async {
      final DateTime success = DateTime(2026, 10, 6, 14, 32);
      final DateTime failure = DateTime(2026, 10, 6, 15, 5);
      await tester.runAsync(
        () => BackupSettingsStore(File('${tmp.path}/data/backup.json')).write(
          BackupSettings(
            recipient: 'age1test',
            documentUri: 'content://fake/kopia',
            lastSuccessAt: success,
            lastFailureAt: failure,
            lastFailure: 'Pliku kopii nie ma już w Dysku.',
          ),
        ),
      );

      await pumpScreen(tester);
      await _pumpUntil(
        tester,
        () => find.text('Ostatnia udana kopia').evaluate().isNotEmpty,
      );

      expect(find.text('2026-10-06 14:32'), findsOneWidget);
      expect(find.textContaining('Grobing nie widzi, kiedy'), findsOneWidget);
      expect(
        find.textContaining('2026-10-06 15:05) nie powiodła się'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Pliku kopii nie ma już w Dysku'),
        findsOneWidget,
      );
      expect(find.text('Zrób kopię teraz'), findsOneWidget);
      expect(find.text('Skonfiguruj kopię od nowa'), findsOneWidget);

      await cleanUp(tester);
    },
  );
}
