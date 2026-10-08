import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/people/me_picker_screen.dart';
import 'package:grobing/app/people/people_list.dart';
import 'package:grobing/app/people/people_screen.dart';
import 'package:grobing/app/settings/export_placeholder_screen.dart';
import 'package:grobing/app/settings/hand_over_note_screen.dart';
import 'package:grobing/app/settings/settings_screen.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/tree_placeholder_screen.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/people.dart';

import '../support/backup_fakes.dart';

// ISSUE-022 — the app's skeleton, happy path per AC (05_DESIGN/osoby.md, ustawienia.md, cmentarze.md
// element 18): AC-1 the bottom bar on the viewing screens and not in a form, the tabs' stacks · AC-2 the
// Osoby tab — "Ja" on top, A–Z by surname in Polish order, the search from the start of a word · AC-3
// the settings under the gear, "Stan danych" a level down · AC-4 choosing "ja". Also D2 (a card opens the
// entry), D4 (the hand-over note), the backup rows and the app's version. Made-up people only.

/// Lets drift's streams and writes settle between frames (widget tests run in a fake clock).
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (int i = 0; i < 400; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('condition not met in time');
}

bool _shown(Finder f) => f.evaluate().isNotEmpty;

/// The tab the bar on the screen marks active.
AppTab _activeTab(WidgetTester tester) =>
    tester.widget<GrobingTabBar>(find.byType(GrobingTabBar)).active;

void main() {
  late Directory tmp;
  late GrobingDatabase db;

  /// Ids of the made-up people, by given name.
  late Map<String, int> ids;
  late int cemetery;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_skeleton_test');
    db = GrobingDatabase(NativeDatabase.memory());
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // drift closes the stream query on a timer of the fake clock, and closing the database waits for it.
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
  }

  /// Six made-up people: one in a grave, the rest without; Polish letters in the surnames (L before Ł),
  /// a birth surname, someone without a surname.
  Future<void> addPeople(WidgetTester tester) async {
    await tester.runAsync(() async {
      cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
      await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(
          givenNames: 'Maria',
          surname: 'Wymyślona',
          birth: QualifiedDate(DateQualifier.exact, PartialDate(1926, 3, 1)),
          death: QualifiedDate(DateQualifier.exact, PartialDate(2010)),
        ),
      );
      Future<void> person(String given, String? surname, [String? birth]) => db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              givenNames: Value(given),
              surname: Value(surname),
              birthSurname: Value(birth),
            ),
          );
      await person('Jan', 'Wymyślony');
      await person('Ewa', 'Lis');
      await person('Jan', 'Łukasik');
      await person('Anna', 'Testowa', 'Lisowska');
      await person('Zofia', null, 'Nowak');
      await person('Józef', null);
      ids = {
        for (final Person p in await db.select(db.persons).get())
          '${p.givenNames} ${p.surname ?? ''}'.trim(): p.id,
      };
    });
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: GrobingTheme.dark, home: screen),
    );
  }

  SettingsScreen settingsScreen() => SettingsScreen(
    database: db,
    location: DataLocation.inDirectory(Directory('${tmp.path}/data')),
    backup: backupServiceIn(
      tmp,
      db,
      FakeDocumentStore(Directory('${tmp.path}/drive')),
    ),
  );

  group('AC-1 — the bottom bar', () {
    testWidgets(
      'on the map with Mapa active; Osoby and Drzewo open their screens, back returns to the map; '
      '"Mapa" from a cemetery returns to the map of Poland',
      (tester) async {
        await addPeople(tester);
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          GrobingApp(
            database: db,
            location: DataLocation.inDirectory(Directory('${tmp.path}/data')),
            backup: backupServiceIn(
              tmp,
              db,
              FakeDocumentStore(Directory('${tmp.path}/drive')),
            ),
          ),
        );
        await _pumpUntil(tester, () => _shown(find.byType(FlutterMap)));

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(_activeTab(tester), AppTab.map);
        expect(find.text('Mapa'), findsOneWidget);
        expect(find.text('Osoby'), findsOneWidget);
        expect(find.text('Drzewo'), findsOneWidget);
        final SemanticsHandle semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.text('Mapa')),
          isSemantics(isSelected: true, isButton: true, hasTapAction: true),
        );
        expect(
          tester.getSemantics(find.text('Osoby')),
          isSemantics(isSelected: false, isButton: true, hasTapAction: true),
        );
        semantics.dispose();

        await tester.tap(find.text('Osoby'));
        await _pumpUntil(tester, () => _shown(find.byType(PeopleScreen)));
        expect(_activeTab(tester), AppTab.people);

        await tester.tap(find.text('Drzewo'));
        await _pumpUntil(
          tester,
          () => _shown(find.byType(TreePlaceholderScreen)),
        );
        expect(_activeTab(tester), AppTab.tree);
        expect(
          find.textContaining('Drzewo powstanie po SPIKE-002'),
          findsOneWidget,
        );
        expect(find.byType(PeopleScreen, skipOffstage: false), findsNothing);

        // Back from a tab's main screen returns to the map — the fixed start destination.
        await tester.binding.handlePopRoute();
        await _pumpUntil(tester, () => _shown(find.byType(HomeScreen)));
        expect(find.byType(TreePlaceholderScreen), findsNothing);
        expect(_activeTab(tester), AppTab.map);

        // A cemetery opened from the map keeps Mapa active; "Mapa" brings back the map of Poland.
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CemeteryScreen(database: db, cemeteryId: cemetery),
              ),
            );
        await _pumpUntil(tester, () => _shown(find.text('Dodaj grób')));
        await tester.pumpAndSettle();
        expect(_activeTab(tester), AppTab.map);
        await tester.tap(find.text('Mapa'));
        await _pumpUntil(
          tester,
          () => !_shown(find.byType(CemeteryScreen, skipOffstage: false)),
        );
        expect(find.byType(HomeScreen), findsOneWidget);
        await cleanUp(tester);
      },
    );

    testWidgets('the grave view has the bar; the person form does not', (
      tester,
    ) async {
      await addPeople(tester);
      final int grave = (await tester.runAsync(
        () => db.select(db.graves).getSingle(),
      ))!.id;
      await pumpScreen(tester, GraveScreen(database: db, graveId: grave));
      await _pumpUntil(tester, () => _shown(find.text('Maria Wymyślona')));
      expect(_activeTab(tester), AppTab.map);

      await tester.tap(find.text('Maria Wymyślona'));
      await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormScreen), findsOneWidget);
      expect(find.byType(GrobingTabBar), findsNothing);
      await cleanUp(tester);
    });
  });

  group('AC-2 — the Osoby tab', () {
    testWidgets(
      '"Ja" on top, everyone A–Z by surname under their letters (L before Ł), the count; '
      'the search from the start of a word, also the birth surname; no hits said in words',
      (tester) async {
        await addPeople(tester);
        await pumpScreen(tester, PeopleScreen(database: db));
        await _pumpUntil(tester, () => _shown(find.text('Ewa Lis')));

        expect(find.text('7 osób'), findsOneWidget);
        expect(find.text('Ja'), findsWidgets);
        expect(find.text('Wybierz, która osoba to Ty'), findsOneWidget);
        final List<String> order = [
          'Wybierz, która osoba to Ty',
          'L',
          'Ewa Lis',
          'Ł',
          'Jan Łukasik',
          'N',
          'Zofia z d. Nowak',
          'T',
          'Anna Testowa z d. Lisowska',
          'W',
          'Maria Wymyślona',
          'Jan Wymyślony',
          'Bez nazwiska',
          'Józef',
        ];
        final List<double> ys = [
          for (final String t in order) tester.getTopLeft(find.text(t)).dy,
        ];
        expect(ys, orderedEquals([...ys]..sort()), reason: '$order');
        expect(find.text('1926–2010'), findsOneWidget);
        expect(find.text('bez dat'), findsNWidgets(6));

        await tester.enterText(find.byType(TextField), 'wymys');
        await tester.pump();
        expect(find.byType(PersonListCard), findsNWidgets(2));
        expect(find.text('Maria Wymyślona'), findsOneWidget);
        expect(find.text('Jan Wymyślony'), findsOneWidget);
        expect(find.text('Wybierz, która osoba to Ty'), findsNothing);
        expect(find.text('W'), findsNothing);

        await tester.enterText(find.byType(TextField), 'LIS');
        await tester.pump();
        expect(
          find.byType(PersonListCard),
          findsNWidgets(2),
          reason: 'Lis and z d. Lisowska',
        );
        expect(find.text('Anna Testowa z d. Lisowska'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'xyz');
        await tester.pump();
        expect(find.text('Nie ma osoby „xyz”.'), findsOneWidget);
        expect(find.byType(PersonListCard), findsNothing);

        await tester.tap(find.byTooltip('Wyczyść'));
        await tester.pump();
        expect(find.byType(PersonListCard), findsNWidgets(7));
        await cleanUp(tester);
      },
    );

    testWidgets(
      'D2: a card opens the entry ("Poprawa wpisu") of a person without a grave; '
      'back returns with the same text in the search',
      (tester) async {
        await addPeople(tester);
        await pumpScreen(tester, PeopleScreen(database: db));
        await _pumpUntil(tester, () => _shown(find.text('Ewa Lis')));
        await tester.enterText(find.byType(TextField), 'luk');
        await tester.pump();

        await tester.tap(find.text('Jan Łukasik'));
        await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
        await tester.pumpAndSettle();
        expect(find.byType(PersonFormScreen), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .controller
              .text,
          'Jan',
        );

        await tester.pageBack();
        await _pumpUntil(tester, () => _shown(find.byType(PeopleScreen)));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'luk',
        );
        expect(find.text('Jan Łukasik'), findsOneWidget);
        await cleanUp(tester);
      },
    );

    testWidgets('an empty base says what will be here', (tester) async {
      await pumpScreen(tester, PeopleScreen(database: db));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Tu pojawią się osoby z grobów i rodzin.')),
      );
      expect(find.byType(PersonListCard), findsNothing);
      await cleanUp(tester);
    });
  });

  group('AC-3 — the settings under the gear', () {
    testWidgets(
      'the sections and rows; "Stan danych" opens today\'s screen; the note and the export placeholder',
      (tester) async {
        await pumpScreen(tester, settingsScreen());
        await _pumpUntil(
          tester,
          () => _shown(find.text('Kopia nie jest skonfigurowana')),
        );
        for (final String t in [
          'Ty w drzewie',
          'Kopia',
          'Skonfiguruj kopię',
          'Odtwórz z kopii',
          'Dla rodziny',
          'Eksport dla rodziny',
          'Notka przekazania',
          'Techniczne',
          'Stan danych',
          'O aplikacji',
          'Grobing $appVersion',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.byType(GrobingTabBar), findsNothing);

        await tester.tap(find.text('Notka przekazania'));
        await tester.pumpAndSettle();
        expect(find.byType(HandOverNoteScreen), findsOneWidget);
        expect(
          find.textContaining('nigdy w tej samej chmurze co kopia'),
          findsOneWidget,
        );
        expect(find.textContaining('program age'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Eksport dla rodziny'));
        await tester.pumpAndSettle();
        expect(find.byType(ExportPlaceholderScreen), findsOneWidget);
        expect(
          find.textContaining('Eksport powstanie z US-006'),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Stan danych'));
        await _pumpUntil(tester, () => _shown(find.text('Odcisk danych')));
        expect(find.byType(DataStateScreen), findsOneWidget);
        await cleanUp(tester);
      },
    );

    testWidgets(
      'a backup set up: the last one in the state green, with when and where',
      (tester) async {
        await tester.runAsync(
          () => BackupSettingsStore(File('${tmp.path}/data/backup.json')).write(
            BackupSettings(
              recipient: 'age1wymyslony',
              documentUri:
                  'content://com.google.android.apps.docs.storage/document/acc%3D1%3Bdoc%3D1',
              lastSuccessAt: DateTime.now(),
              lastSuccessInBackground: true,
            ),
          ),
        );
        await pumpScreen(tester, settingsScreen());
        await _pumpUntil(
          tester,
          () => _shown(find.text('Ostatnia udana kopia')),
        );
        expect(find.textContaining('dziś, '), findsOneWidget);
        expect(find.textContaining('(w tle) · Dysk Google'), findsOneWidget);
        expect(find.text('Zrób kopię teraz'), findsOneWidget);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.cloud_done_outlined)).color,
          GrobingColors.stateOk,
        );
        expect(find.text('Kopia nie jest skonfigurowana'), findsNothing);
        await cleanUp(tester);
      },
    );

    testWidgets(
      'the last backup failed: the error in words with its icon, and the last good one',
      (tester) async {
        await tester.runAsync(
          () => BackupSettingsStore(File('${tmp.path}/data/backup.json')).write(
            BackupSettings(
              recipient: 'age1wymyslony',
              documentUri:
                  'content://com.android.providers.downloads.documents/document/1',
              lastSuccessAt: DateTime(2026, 10, 3, 9, 30),
              lastFailureAt: DateTime.now(),
              lastFailure: 'Brak dostępu do pliku kopii.',
            ),
          ),
        );
        await pumpScreen(tester, settingsScreen());
        await _pumpUntil(
          tester,
          () => _shown(find.text('Ostatnia kopia się nie udała')),
        );
        expect(
          find.textContaining(' — Brak dostępu do pliku kopii.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Ostatnia udana: 03.10.2026, 09:30 · Pobrane'),
          findsOneWidget,
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.sync_problem)).color,
          GrobingColors.error,
        );
        await cleanUp(tester);
      },
    );
  });

  group('AC-4 — choosing "ja"', () {
    testWidgets(
      'settings → "Ja" → the choice → the person is "ja": named in the row and on top of Osoby, '
      'not again in A–Z, found by the search; the choice ticks them next time',
      (tester) async {
        await addPeople(tester);
        await pumpScreen(tester, settingsScreen());
        await _pumpUntil(tester, () => _shown(find.text('Ty w drzewie')));

        await tester.tap(find.textContaining('Od tej osoby liczą się'));
        await _pumpUntil(tester, () => _shown(find.text('Maria Wymyślona')));
        expect(find.byType(MePickerScreen), findsOneWidget);
        expect(find.text('Która osoba to Ty?'), findsOneWidget);
        expect(find.byType(GrobingTabBar), findsNothing);

        await tester.tap(find.text('Maria Wymyślona'));
        await _pumpUntil(
          tester,
          () => _shown(find.textContaining('Maria Wymyślona\nOd tej osoby')),
        );
        await _pumpUntil(tester, () => !_shown(find.byType(MePickerScreen)));
        expect(
          await tester.runAsync(() => watchMe(db).first),
          ids['Maria Wymyślona'],
        );

        await tester.tap(find.textContaining('Od tej osoby liczą się'));
        await _pumpUntil(tester, () => _shown(find.byType(MePickerScreen)));
        await _pumpUntil(tester, () => _shown(find.byType(PersonListCard)));
        final PersonListCard maria = tester.widget<PersonListCard>(
          find.widgetWithText(PersonListCard, 'Maria Wymyślona'),
        );
        expect(maria.selected, isTrue);
        // A choice leads nowhere further: no chevrons, one tick (rule 11; ui review B2).
        expect(
          find.descendant(
            of: find.byType(MePickerScreen),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsNothing,
        );
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(
          tester
              .widgetList<PersonListCard>(find.byType(PersonListCard))
              .where((c) => c.selected),
          hasLength(1),
        );

        // A fresh app: the choice opened above stays on the old navigator otherwise.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await pumpScreen(tester, PeopleScreen(database: db));
        await _pumpUntil(tester, () => _shown(find.text('Ewa Lis')));
        expect(find.text('Maria Wymyślona'), findsOneWidget);
        expect(
          find.widgetWithText(PersonListCard, 'Maria Wymyślona'),
          findsNothing,
          reason: 'only in the "Ja" card',
        );
        expect(find.byType(PersonListCard), findsNWidgets(6));
        expect(find.text('7 osób'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'mar');
        await tester.pump();
        expect(
          find.widgetWithText(PersonListCard, 'Maria Wymyślona'),
          findsOneWidget,
        );
        await cleanUp(tester);
      },
    );

    testWidgets('Osoby: "Ja" not chosen yet opens the choice', (tester) async {
      await addPeople(tester);
      await pumpScreen(tester, PeopleScreen(database: db));
      await _pumpUntil(tester, () => _shown(find.text('Ewa Lis')));
      await tester.tap(find.text('Wybierz, która osoba to Ty'));
      await _pumpUntil(tester, () => _shown(find.byType(MePickerScreen)));
      final Finder inPicker = find.descendant(
        of: find.byType(MePickerScreen),
        matching: find.text('Jan Łukasik'),
      );
      await _pumpUntil(tester, () => _shown(inPicker));
      await tester.pumpAndSettle();
      await tester.tap(inPicker);
      await _pumpUntil(tester, () => _shown(find.byType(PeopleScreen)));
      await _pumpUntil(tester, () => !_shown(find.byType(MePickerScreen)));
      await _pumpUntil(
        tester,
        () => _shown(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Jan Łukasik'),
          ),
        ),
      );
      expect(find.widgetWithText(PersonListCard, 'Jan Łukasik'), findsNothing);
      await cleanUp(tester);
    });
  });
}
