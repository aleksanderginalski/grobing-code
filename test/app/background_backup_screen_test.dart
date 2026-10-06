import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

import '../support/backup_fakes.dart';

// ISSUE-010 AC-1 in the app: leaving the app is the background backup's trigger (D2), and "Stan
// danych" says which backup was the background one and when the background backup runs.

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
  late BackupSettingsStore settings;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_background_screen_test');
    location = DataLocation.inDirectory(Directory('${tmp.path}/data'));
    location.mediaDir.createSync(recursive: true);
    db = GrobingDatabase(NativeDatabase(location.databaseFile));
    settings = BackupSettingsStore(File('${tmp.path}/data/backup.json'));
  });

  Future<void> cleanUp(WidgetTester tester) async {
    // The home screen's stream query closes on a timer of the fake clock; closing the database waits
    // for it (ISSUE-014).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
  }

  testWidgets(
    'leaving the app (paused) with changed data asks for one background backup; other lifecycle '
    'changes do not',
    (tester) async {
      final FakeBackgroundBackups background = FakeBackgroundBackups();
      await tester.runAsync(() async {
        await db.customSelect('SELECT 1').get();
        await settings.write(
          const BackupSettings(
            recipient: 'age1test',
            documentUri: 'content://fake/kopia',
          ),
        );
      });
      await tester.pumpWidget(
        GrobingApp(
          database: db,
          location: location,
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
            background: background,
          ),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(background.requests, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _pumpUntil(tester, () => background.requests == 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(background.requests, 1);

      await cleanUp(tester);
    },
  );

  testWidgets(
    'a write anywhere in the app asks for a background backup (the root watches the database)',
    (tester) async {
      final FakeBackgroundBackups background = FakeBackgroundBackups();
      await tester.runAsync(
        () => settings.write(
          const BackupSettings(
            recipient: 'age1test',
            documentUri: 'content://fake/kopia',
          ),
        ),
      );
      await tester.pumpWidget(
        GrobingApp(
          database: db,
          location: location,
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
            background: background,
          ),
        ),
      );

      await tester.runAsync(() => addFictionalData(db, location.mediaDir));
      await _pumpUntil(tester, () => background.requests >= 1);

      await tester.pumpWidget(const SizedBox());
      await cleanUp(tester);
    },
  );

  testWidgets(
    'a background backup is marked "(w tle)", and the screen says when the background backup runs',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(
        () => settings.write(
          BackupSettings(
            recipient: 'age1test',
            documentUri: 'content://fake/kopia',
            lastSuccessAt: DateTime(2026, 10, 6, 14, 32),
            lastSuccessStamp: 'stamp',
            lastSuccessInBackground: true,
          ),
        ),
      );

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
      await _pumpUntil(
        tester,
        () => find.text('Ostatnia udana kopia').evaluate().isNotEmpty,
      );

      expect(find.text('2026-10-06 14:32 (w tle)'), findsOneWidget);
      expect(
        find.textContaining('ok. 10 minut po ostatniej zmianie'),
        findsOneWidget,
      );
      expect(find.textContaining('co godzinę'), findsOneWidget);
      expect(
        find.textContaining('dokładny termin wyznacza Android'),
        findsOneWidget,
      );

      await cleanUp(tester);
    },
  );
}
