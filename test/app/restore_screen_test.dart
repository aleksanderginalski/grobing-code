import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/restore_screen.dart';
import 'package:grobing/backup/age/age.dart';
import 'package:grobing/backup/backup_archive.dart';
import 'package:grobing/backup/restore_swap.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

import '../support/backup_fakes.dart';

// ISSUE-009 on screen: "Stan danych" → "Odtwórz z kopii" → backup file, key file, passphrase →
// the app reopens on the restored data with a notice (AC-1, D3); a phone with data is warned first
// and "Anuluj" changes nothing (D4); a refusal says the data is untouched (AC-2).

const String _passphrase = 'hasło-testowe';

/// Lets real file, isolate and database work finish between frames (widget tests run in a fake clock).
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (int i = 0; i < 1000; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('condition not met in time');
}

/// Unmounts the app and lets drift finish closing the home screen's stream query: it does so on a
/// timer of the test's fake clock, and closing the database waits for it (ISSUE-014).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late Directory phone;
  late FakeDocumentStore drive;
  late String sourceFingerprint;

  /// Every database the app opened, closed at the end (an open file cannot be deleted on Windows).
  final List<GrobingDatabase> opened = [];

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_restore_screen_test');
    phone = Directory('${tmp.path}/phone')..createSync();
    drive = FakeDocumentStore(
      Directory('${tmp.path}/drive'),
      openAnswers: ['kopia.age', 'klucz.age'],
    );

    // A backup of made-up data and its key file (cheap scrypt), as two files in "Drive".
    final Directory source = Directory('${tmp.path}/source')..createSync();
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(File('${source.path}/grobing.db')),
    );
    await addFictionalData(db, Directory('${source.path}/media'));
    sourceFingerprint = (await readDataState(
      db,
      mediaDir: Directory('${source.path}/media'),
    )).fingerprint;
    await db.customStatement('VACUUM INTO ?', ['${tmp.path}/snapshot.db']);
    await db.close();
    final X25519Identity identity = X25519Identity.generate();
    final BytesBuilder key = BytesBuilder();
    await for (final List<int> c in ageEncrypt(
      Stream.value(
        utf8.encode(encodeIdentityFile(identity, DateTime.utc(2026, 10, 6))),
      ),
      [ScryptRecipient(_passphrase, workFactor: 10)],
    )) {
      key.add(c);
    }
    drive.fileFor(FakeDocumentStore.uriOf('klucz.age'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(key.takeBytes());
    await writeEncryptedBackup(
      snapshot: File('${tmp.path}/snapshot.db'),
      mediaDir: Directory('${source.path}/media'),
      recipient: identity.recipient,
      output: drive.fileFor(FakeDocumentStore.uriOf('kopia.age')),
      createdAt: DateTime.utc(2026, 10, 6, 12),
    );
  });

  tearDown(() async {
    for (final GrobingDatabase db in opened) {
      await db.close();
    }
    opened.clear();
    tmp.deleteSync(recursive: true);
  });

  /// The app's data in [phone], opened the way `main.dart` opens it.
  Future<AppData> open() async {
    await completePendingRestore(phone);
    final DataLocation location = DataLocation.inDirectory(phone);
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(location.databaseFile),
    );
    await db.customSelect('SELECT 1').get();
    opened.add(db);
    return (
      database: db,
      location: location,
      backup: backupServiceIn(tmp, db, drive),
      restore: restoreServiceIn(phone, db, drive),
    );
  }

  Future<AppData> pumpApp(WidgetTester tester, {bool withData = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final AppData data = (await tester.runAsync(() async {
      final AppData data = await open();
      if (withData) {
        await addFictionalData(data.database, data.location.mediaDir);
        await addFictionalData(data.database, data.location.mediaDir);
      }
      return data;
    }))!;
    await tester.pumpWidget(
      GrobingApp(
        database: data.database,
        location: data.location,
        backup: data.backup,
        restore: data.restore,
        reopen: open,
      ),
    );
    await tester.tap(find.byTooltip('Ustawienia'));
    await _pumpUntil(
      tester,
      () => find.text('Odtwórz z kopii').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Odtwórz z kopii'));
    await _pumpUntil(
      tester,
      () => find.byType(RestoreScreen).evaluate().isNotEmpty,
    );
    return data;
  }

  Future<void> pickBothAndType(WidgetTester tester, String passphrase) async {
    await tester.tap(find.text('Wybierz plik kopii'));
    await _pumpUntil(
      tester,
      () => find.textContaining('kopia.age ·').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Wybierz plik klucza'));
    await _pumpUntil(
      tester,
      () => find.textContaining('klucz.age ·').evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField), passphrase);
    await tester.pump();
  }

  FilledButton restoreButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Odtwórz'));

  testWidgets(
    'fresh phone: "Odtwórz" waits for both files and the passphrase, then the app reopens on '
    '"Stan danych" with the notice and the restored fingerprint; back leads to the start',
    (tester) async {
      final AppData before = await pumpApp(tester);

      // Nothing on the phone: no warning.
      expect(find.textContaining('W telefonie są już dane'), findsNothing);
      expect(find.textContaining('wpisz „grobing”'), findsOneWidget);
      expect(restoreButton(tester).onPressed, isNull);

      await pickBothAndType(tester, _passphrase);
      expect(restoreButton(tester).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Odtwórz'));
      await _pumpUntil(
        tester,
        () => find
            .textContaining('Odtworzono kopię z dnia')
            .evaluate()
            .isNotEmpty,
      );

      final String short = sourceFingerprint.substring(0, 16);
      expect(find.byType(DataStateScreen), findsOneWidget);
      expect(
        find.textContaining('Odcisk danych w kopii: $short'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Kopia działa dalej tym samym kluczem'),
        findsOneWidget,
      );
      // The screen reads the restored data from disk: the same fingerprint.
      await _pumpUntil(tester, () => find.text(short).evaluate().isNotEmpty);

      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      expect(opened, hasLength(2));
      expect(opened.first, same(before.database));
      await _unmount(tester);
    },
  );

  testWidgets(
    'phone with data: a warning, then a dialog with the counts; "Anuluj" starts nothing',
    (tester) async {
      final AppData data = await pumpApp(tester, withData: true);

      expect(find.textContaining('W telefonie są już dane'), findsOneWidget);
      await pickBothAndType(tester, _passphrase);
      await tester.tap(find.widgetWithText(FilledButton, 'Odtwórz'));
      await tester.pumpAndSettle();

      expect(find.text('Zastąpić dane w telefonie?'), findsOneWidget);
      expect(
        find.textContaining('osoby 10, groby 4, cmentarze 2'),
        findsOneWidget,
      );
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();

      expect(find.byType(RestoreScreen), findsOneWidget);
      // Only the window info was read — neither the key file nor the backup file.
      expect(drive.readBudgets, isEmpty);
      expect(
        Directory('${phone.path}/$restoreStagingName').existsSync(),
        isFalse,
      );

      expect(data.restore.databaseClosed, isFalse);
      await _unmount(tester);
    },
  );

  testWidgets(
    'a wrong passphrase is refused on screen; the data is untouched',
    (tester) async {
      final AppData data = await pumpApp(tester);
      await pickBothAndType(tester, 'złe hasło');

      await tester.tap(find.widgetWithText(FilledButton, 'Odtwórz'));
      await _pumpUntil(
        tester,
        () => find.textContaining('nietknięte').evaluate().isNotEmpty,
      );

      expect(find.textContaining('Złe hasło'), findsOneWidget);
      expect(find.byType(RestoreScreen), findsOneWidget);
      expect(data.restore.databaseClosed, isFalse);
      await _unmount(tester);
    },
  );
}
