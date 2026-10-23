import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/home/cemetery_edit.dart';
import 'package:grobing/app/home/poland_map_data.dart';
import 'package:grobing/app/person/clan_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/deletion.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/deletion.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/dev/fictional_data.dart';

import '../support/a11y.dart';

// ISSUE-053 — the screens of a deletion (lib/app/widgets/deletion.dart; 05_DESIGN/brand/style-b.md rule 16, K2 "4 s"):
// "Usuń …" only in a correction — "Popraw grób" (grob.md 3d), "Popraw cmentarz" (cmentarze.md 15a), the end of the
// person's correction (wpis-osoby.md 12a over 12; "ja" has the fact instead), the screen "Ród" (wieniec.md F7); the
// window says what goes and what stays; the bar with "Cofnij" on the screen one comes back to — 4 s, as long as
// "Czas na działanie" asks, and until touched with a screen reader. The pin's 12b is in pin_screens_test.dart, the
// data in test/data/deletion_test.dart. Made-up people only (family-data.md): the batch of `addFictionalData`.

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

/// The hard space of style-b.md rule 6, built so no tool turns it into a literal in this file.
final String _nb = String.fromCharCode(0xA0);

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
  });

  Future<void> withBatch(WidgetTester tester) async {
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('grobing_deletion_screens');
      await addFictionalData(db, Directory('${tmp.path}/media'));
    });
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
  }

  /// Takes the screens down before the test reads the database (README → Testy, a read with a screen watching
  /// hangs), then reads it.
  Future<T> read<T>(WidgetTester tester, Future<T> Function() query) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    late T value;
    await tester.runAsync(() async => value = await query());
    return value;
  }

  Future<int> idOf(WidgetTester tester, String givenNames) async {
    late int id;
    await tester.runAsync(
      () async => id = (await (db.select(
        db.persons,
      )..where((p) => p.givenNames.equals(givenNames))).getSingle()).id,
    );
    return id;
  }

  /// A phone of 360 × 800 dp with a screen under the one tested — where a deletion comes back to.
  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        navigatorKey: navigator,
        home: const Scaffold(body: Center(child: Text('Pod spodem'))),
      ),
    );
  }

  /// Scrolls the person's correction to its end, where 12a and 12 are.
  Future<void> toTheEnd(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();
  }

  group('grob.md 3d — "Usuń grób"', () {
    testWidgets(
      '"Nowy grób" has no "Usuń grób"; "Popraw grób" has it on the first line at the left, "Anuluj" · "Zapisz" '
      'under it at the right',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: GrobingTheme.dark,
            home: Scaffold(
              body: GraveDialog(
                grave: null,
                sectors: const [],
                save: ({name, sector, row, plot, paidUntil}) async {},
              ),
            ),
          ),
        );
        expect(find.text('Usuń grób'), findsNothing);

        await withBatch(tester);
        await pumpHome(tester);
        late int grave;
        await tester.runAsync(() async {
          grave =
              (await (db.select(db.graves)..where(
                        (g) => g.name.equals('Grób rodzinny Wymyślonych'),
                      ))
                      .getSingle())
                  .id;
        });
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => GraveScreen(database: db, graveId: grave),
          ),
        );
        // The card's name is rich text with the dates: the view is in once its pencil is.
        await _pumpUntil(tester, () => _shown(find.byTooltip('Popraw grób')));
        // The route slides in from the right: taps go where it ends up.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byTooltip('Popraw grób'));
        await _pumpUntil(tester, () => _shown(find.text('Usuń grób')));
        Rect button(String label) => tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is TextButton),
          ),
        );
        final Rect delete = button('Usuń grób');
        expect(delete.bottom, lessThanOrEqualTo(button('Anuluj').top));
        expect(delete.left, lessThan(button('Anuluj').left));
        expect(button('Zapisz').right, greaterThan(delete.right));
        await cleanUp(tester);
      },
    );

    testWidgets(
      'AC-3 — the window names the people who stay; "Usuń" closes the grave on the screen under it with the bar '
      '"Usunięto grób." — 4 s, then the bar is gone and so is the grave; its people are in the app, buried nowhere',
      (tester) async {
        await withBatch(tester);
        await pumpHome(tester);
        late int grave;
        await tester.runAsync(() async {
          grave =
              (await (db.select(db.graves)..where(
                        (g) => g.name.equals('Grób rodzinny Wymyślonych'),
                      ))
                      .getSingle())
                  .id;
        });
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => GraveScreen(database: db, graveId: grave),
          ),
        );
        // The card's name is rich text with the dates: the view is in once its pencil is.
        await _pumpUntil(tester, () => _shown(find.byTooltip('Popraw grób')));
        // The route slides in from the right: taps go where it ends up.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byTooltip('Popraw grób'));
        await _pumpUntil(tester, () => _shown(find.text('Usuń grób')));
        await tester.tap(find.text('Usuń grób'));
        await _pumpUntil(tester, () => _shown(find.text('Usunąć grób?')));
        expect(
          find.text(
            '„Grób rodzinny Wymyślonych” zniknie z${_nb}cmentarza razem ze${_nb}zdjęciem nagrobka.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Osoby z${_nb}tego grobu zostają w${_nb}aplikacji — bez grobu: Ojciec 1 Wymyślony, '
            'Matka 1 Wymyślona.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Usuń'));
        await _pumpUntil(tester, () => _shown(find.text('Usunięto grób.')));
        await _pumpUntil(tester, () => !_shown(find.byType(GraveScreen)));
        expect(find.text('Pod spodem'), findsOneWidget);
        // K2: 4 s, then the bar goes by itself (Flutter 3.41 keeps a bar with an action without `persist: false`).
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Usunięto grób.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('Usunięto grób.'), findsNothing);

        final ({int graves, int people}) left = await read(
          tester,
          () async => (
            graves: (await (db.select(
              db.graves,
            )..where((g) => g.id.equals(grave))).get()).length,
            people: (await db.select(db.persons).get()).length,
          ),
        );
        expect(left, (graves: 0, people: 5));
        await cleanUp(tester);
      },
    );
  });

  group('wpis-osoby.md 12a, 12 — the end of the person\'s correction', () {
    testWidgets(
      'with a grave: "Usuń z grobu" above "Usuń osobę"; without a grave: only "Usuń osobę"; "ja": the fact '
      'instead of "Usuń osobę"',
      (tester) async {
        await withBatch(tester);
        final int father = await idOf(tester, 'Ojciec 1');
        final int partner = await idOf(tester, 'Partnerka 1');
        final int mother = await idOf(tester, 'Matka 1');
        await tester.runAsync(() => setMe(db, mother));
        await pumpHome(tester);

        Future<void> open(int person) async {
          openPersonEntry(navigator.currentContext!, db, person);
          await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
          await _pumpUntil(
            tester,
            () =>
                _shown(find.text('Usuń osobę')) ||
                _shown(find.textContaining('To Ty („ja”)')),
          );
          await toTheEnd(tester);
        }

        await open(father);
        expect(find.text('Usuń z${_nb}grobu'), findsOneWidget);
        expect(
          tester.getRect(find.text('Usuń z${_nb}grobu')).bottom,
          lessThan(tester.getRect(find.text('Usuń osobę')).top),
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();

        await open(partner);
        expect(find.text('Usuń osobę'), findsOneWidget);
        expect(find.text('Usuń z${_nb}grobu'), findsNothing);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();

        await open(mother);
        expect(find.text('Usuń osobę'), findsNothing);
        expect(
          find.text(
            'To Ty („ja”) — tego wpisu nie da się usunąć. Inną osobę jako „ja” wskażesz w${_nb}Ustawieniach.',
          ),
          findsOneWidget,
        );
        expect(find.text('Usuń z${_nb}grobu'), findsOneWidget);
        await cleanUp(tester);
      },
    );

    testWidgets(
      'AC-4 — "Usuń osobę": the window lists the burial, both unions with who stays and the shared photo; '
      '"Usuń" closes the correction to the screen under it, with the bar "Usunięto: Ojciec 1 Wymyślony."; '
      '"Cofnij" brings him back',
      (tester) async {
        await withBatch(tester);
        final int father = await idOf(tester, 'Ojciec 1');
        await pumpHome(tester);
        openPersonEntry(navigator.currentContext!, db, father);
        await _pumpUntil(tester, () => _shown(find.text('Usuń osobę')));
        await toTheEnd(tester);
        await tester.tap(find.text('Usuń osobę'));
        await _pumpUntil(tester, () => _shown(find.text('Usunąć osobę?')));
        expect(
          find.text('Ojciec 1 Wymyślony zniknie z${_nb}aplikacji razem z:'),
          findsOneWidget,
        );
        expect(
          find.text(
            'pochówkiem w${_nb}grobie „Grób rodzinny Wymyślonych” — grób zostaje,',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            '2${_nb}związkami — Matka 1 Wymyślona, Partnerka 1 Zmyślona i${_nb}dzieci zostają.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Zdjęcia z${_nb}innymi osobami zostają przy nich.'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(TextButton, 'Usuń'));
        await _pumpUntil(
          tester,
          () => _shown(find.text('Usunięto: Ojciec 1 Wymyślony.')),
        );
        await _pumpUntil(tester, () => !_shown(find.byType(PersonFormScreen)));
        expect(find.text('Pod spodem'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Cofnij'));
        await tester.pump(const Duration(milliseconds: 100));
        final int people = await read(
          tester,
          () async => (await db.select(db.persons).get()).length,
        );
        expect(people, 5);
        await cleanUp(tester);
      },
    );

    testWidgets(
      'AC-6 — "Usuń z grobu": the window says who stays and where they can be added; "Usuń" closes the correction '
      'with the bar "Usunięto z grobu: …"; the person stays, buried nowhere',
      (tester) async {
        await withBatch(tester);
        final int father = await idOf(tester, 'Ojciec 1');
        await pumpHome(tester);
        openPersonEntry(navigator.currentContext!, db, father);
        await _pumpUntil(tester, () => _shown(find.text('Usuń osobę')));
        await toTheEnd(tester);
        await tester.tap(find.text('Usuń z${_nb}grobu'));
        await _pumpUntil(
          tester,
          () => _shown(find.text('Usunąć z${_nb}grobu?')),
        );
        expect(
          find.text(
            'Ojciec 1 Wymyślony zostaje w${_nb}aplikacji z${_nb}datami, rodziną i${_nb}zdjęciami — bez grobu '
            '„Grób rodzinny Wymyślonych”.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Usuń'));
        await _pumpUntil(
          tester,
          () => _shown(find.text('Usunięto z${_nb}grobu: Ojciec 1 Wymyślony.')),
        );
        await _pumpUntil(tester, () => !_shown(find.byType(PersonFormScreen)));
        final ({int people, int burials}) left = await read(
          tester,
          () async => (
            people: (await db.select(db.persons).get()).length,
            burials: (await (db.select(
              db.burials,
            )..where((b) => b.personId.equals(father))).get()).length,
          ),
        );
        expect(left, (people: 5, burials: 0));
        await cleanUp(tester);
      },
    );
  });

  group('wieniec.md F7 — "Usuń ród"', () {
    testWidgets(
      'only on the screen "Ród" of a line, not "Nowy ród"; from the sheet: the window says how many have the '
      'wreath, "Usuń" closes the screen and the sheet, the bar is on the screen under them',
      (tester) async {
        await withBatch(tester);
        final int father = await idOf(tester, 'Ojciec 1');
        await pumpHome(tester);
        showWreathSheet(navigator.currentContext!, db, father);
        await _pumpUntil(
          tester,
          () => _shown(find.text('Wieniec rodu — Ojciec')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nowy ród'));
        await tester.pumpAndSettle();
        expect(find.text('Nowy ród'), findsWidgets);
        expect(find.text('Usuń ród'), findsNothing);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();

        final Finder line = find.ancestor(
          of: find.text('Wymyślscy 1'),
          matching: find.byType(InkWell),
        );
        await tester.tap(
          find.descendant(
            of: line.first,
            matching: find.byTooltip('Popraw ród'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).last, const Offset(0, -4000));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Usuń ród'));
        await tester.pumpAndSettle();
        expect(find.text('Usunąć ród „Wymyślscy 1”?'), findsOneWidget);
        expect(
          find.textContaining('Wieniec tego rodu zniknie u$_nb'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Usuń'));
        await _pumpUntil(
          tester,
          () => _shown(find.text('Usunięto ród „Wymyślscy 1”.')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ClanScreen), findsNothing);
        expect(find.text('Wieniec rodu — Ojciec'), findsNothing);
        expect(find.text('Pod spodem'), findsOneWidget);
        await cleanUp(tester);
      },
    );
  });

  group('cmentarze.md 15a — "Usuń cmentarz"', () {
    testWidgets(
      'a correction\'s window has it; "Usuń" calls back to leave what showed the cemetery and shows the bar; '
      '"Cofnij" calls back with its id',
      (tester) async {
        await withBatch(tester);
        await pumpHome(tester);
        late Cemetery cemetery;
        await tester.runAsync(
          () async => cemetery = await db.select(db.cemeteries).getSingle(),
        );
        bool left = false;
        int? back;
        editCemetery(
          navigator.currentContext!,
          database: db,
          mapData: PolandMapData.load(),
          others: const [],
          cemetery: (
            id: cemetery.id,
            name: cemetery.name,
            locality: cemetery.locality,
            point: null,
          ),
          onDeleted: () => left = true,
          onRestored: (id) => back = id,
        );
        await _pumpUntil(tester, () => _shown(find.text('Usuń cmentarz')));
        await tester.tap(find.text('Usuń cmentarz'));
        await _pumpUntil(tester, () => _shown(find.text('Usunąć cmentarz?')));
        expect(
          find.text(
            'Osoby z${_nb}tych grobów (3) zostają w${_nb}aplikacji — bez grobu.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Usuń'));
        await _pumpUntil(
          tester,
          () => _shown(find.text('Usunięto cmentarz „Cmentarz Wymyślony 1”.')),
        );
        expect(left, isTrue);
        // The window leaves with its own transition, under the bar already shown.
        await _pumpUntil(tester, () => !_shown(find.text('Popraw cmentarz')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Cofnij'));
        await _pumpUntil(tester, () => back != null);
        expect(back, cemetery.id);
        await cleanUp(tester);
      },
    );
  });

  group('style-b.md rule 16 — the window and the bar', () {
    late DeletionSnapshot snapshot;

    Future<void> deleteOne(WidgetTester tester) async {
      await withBatch(tester);
      await tester.runAsync(() async {
        snapshot = await deletePerson(
          db,
          (await (db.select(
            db.persons,
          )..where((p) => p.givenNames.equals('Dziecko 1'))).getSingle()).id,
        );
      });
    }

    Future<void> showBar(WidgetTester tester) async {
      await pumpHome(tester);
      showUndoBar(
        ScaffoldMessenger.of(navigator.currentContext!),
        database: db,
        message: 'Usunięto: Dziecko 1 Wymyślone.',
        snapshot: snapshot,
      );
      await _pumpUntil(
        tester,
        () => _shown(find.text('Usunięto: Dziecko 1 Wymyślone.')),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets(
      'with a screen reader on, the bar stays until it is touched (SC 2.2.1) — after 10 s it is still there',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await deleteOne(tester);
        await showBar(tester);
        await tester.pump(const Duration(seconds: 10));
        expect(find.text('Usunięto: Dziecko 1 Wymyślone.'), findsOneWidget);
        await cleanUp(tester);
      },
    );

    testWidgets(
      '"Czas na działanie" of 10 s keeps the bar 10 s, not 4 — asked as for controls, the bar has "Cofnij"',
      (tester) async {
        final List<Object?> asked = [];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('grobing/external'),
          (call) async {
            if (call.method != 'recommendedTimeout') return null;
            asked.add(call.arguments);
            return 10000;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('grobing/external'),
            null,
          ),
        );
        await deleteOne(tester);
        await showBar(tester);
        expect(asked, [
          {'ms': 4000, 'controls': true},
        ]);
        await tester.pump(const Duration(seconds: 6));
        expect(find.text('Usunięto: Dziecko 1 Wymyślone.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('Usunięto: Dziecko 1 Wymyślone.'), findsNothing);
        await cleanUp(tester);
      },
    );

    testWidgets(
      'the window and the bar meet the tap target and label guidelines; every button has a tap action; "Cofnij" '
      'puts the person back',
      (tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await deleteOne(tester);
        await pumpHome(tester);
        confirmDeletion<Object>(
          navigator.currentContext!,
          title: 'Usunąć osobę?',
          content: const [
            DeletionText('Dziecko 1 Wymyślone zniknie z aplikacji.'),
            DeletionNote('Zdjęcia z innymi osobami zostają przy nich.'),
          ],
          delete: () async => Object(),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expectEveryButtonTappable(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
        await tester.pumpAndSettle();

        await showBar(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expectEveryButtonTappable(tester);
        await tester.tap(find.text('Cofnij'));
        await tester.pump(const Duration(milliseconds: 100));
        final int people = await read(
          tester,
          () async => (await db.select(db.persons).get()).length,
        );
        expect(people, 5);
        semantics.dispose();
        await cleanUp(tester);
      },
    );
  });
}
