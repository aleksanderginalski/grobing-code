import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/grave_person_choice_screen.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/people/people_screen.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';

import '../../support/a11y.dart';

// ISSUE-047 — the grave first, then its people (05_DESIGN/cmentarz.md v8, grob.md v9, osoby.md v3,
// wpis-osoby.md v6), happy path per AC: AC-1 "Dodaj grób" → "Nowy grób" → the grave, empty; "Anuluj" leaves
// none · AC-2 "Dodaj osobę" → "Kto leży w tym grobie?" → someone buried nowhere joins the grave; who has a
// grave is greyed with where they lie (D23) · AC-4 Osoby → "Dodaj osobę: „…”" → "Nowa osoba" → their view.
// AC-3 is in grave_screens_test.dart (the transcription). Made-up people only (family-data.md).

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

void main() {
  late GrobingDatabase db;
  late int cemetery;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  /// Takes the screens down before the test reads the database itself (grave_screens_test.dart).
  Future<void> leaveScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: GrobingTheme.dark, home: screen),
    );
  }

  Future<void> withCemetery(WidgetTester tester) async {
    await tester.runAsync(() async {
      cemetery = await addCemetery(
        db,
        name: 'Cmentarz Wymyślony',
        locality: 'Miejscowość Testowa',
      );
    });
  }

  testWidgets(
    'AC-1 — "Dodaj grób" opens "Nowy grób", not the form of a person: "Anuluj" leaves no grave; a name and '
    '"Zapisz" open the grave, empty, with "Dodaj osobę"; back, its card in the list says "bez wpisanych osób"',
    (tester) async {
      await withCemetery(tester);
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: cemetery),
      );
      await _pumpUntil(
        tester,
        () => _shown(find.text('Na tym cmentarzu nie ma jeszcze grobów.')),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj grób'));
      await tester.pumpAndSettle();
      expect(find.text('Nowy grób'), findsOneWidget);
      expect(find.byType(PersonFormScreen), findsNothing);
      // The name has the keyboard at once (cmentarz.md 9a).
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
      await tester.pumpAndSettle();
      expect(find.text('Nowy grób'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj grób'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Grób rodzinny Wymyślonych',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('W tym grobie nie ma jeszcze wpisanych osób.')),
      );
      // The window goes with its own transition, over the grave already opened.
      await _pumpUntil(tester, () => find.text('Nowy grób').evaluate().isEmpty);
      expect(find.byType(GraveScreen), findsOneWidget);
      expect(find.text('Grób rodzinny Wymyślonych'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Dodaj osobę'),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(GraveScreen),
          matching: find.byType(BackButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CemeteryScreen), findsOneWidget);
      await _pumpUntil(tester, () => _shown(find.text('1 grób · 0 osób')));
      await tester.tap(find.bySemanticsLabel('Pokaż listę grobów'));
      await tester.pumpAndSettle();
      expect(find.text('Grób rodzinny Wymyślonych'), findsOneWidget);
      expect(find.text('bez wpisanych osób'), findsOneWidget);

      await leaveScreen(tester);
      await tester.runAsync(() async {
        expect(await db.select(db.graves).get(), hasLength(1));
        expect(await db.select(db.persons).get(), isEmpty);
      });
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2, D22, D23 — "Dodaj osobę" → "Kto leży w tym grobie?": "Nowa osoba" first, then "Bez grobu" to choose '
    'and "W grobach" greyed with where they lie; a greyed row does nothing; Jan, buried nowhere, joins the '
    'grave at once — the same Jan — and the grave shows him',
    (tester) async {
      await withCemetery(tester);
      late int here;
      late int janId;
      await tester.runAsync(() async {
        here = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Józef', surname: 'Wymyślony'),
        );
        final int other = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Maria', surname: 'Zmyślona'),
        );
        await setGraveName(db, other, 'Grób rodzinny Zmyślonych');
        janId = await addPersonWithoutGrave(
          db,
          entry: const PersonEntry(
            givenNames: 'Jan',
            surname: 'Wymyślony',
            birth: QualifiedDate(DateQualifier.exact, PartialDate(1890)),
          ),
        );
      });
      await pumpScreen(tester, GraveScreen(database: db, graveId: here));
      await _pumpUntil(tester, () => _shown(find.text('Józef Wymyślony')));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Dodaj osobę'));
      await tester.pumpAndSettle();
      expect(find.text('Kto leży w tym grobie?'), findsOneWidget);
      await _pumpUntil(tester, () => _shown(find.text('Bez grobu')));
      final Finder choice = find.byType(GravePersonChoiceScreen);
      Finder inChoice(Finder f) => find.descendant(of: choice, matching: f);
      expect(inChoice(find.text('Nowa osoba')), findsOneWidget);
      expect(inChoice(find.text('Jan Wymyślony')), findsOneWidget);
      expect(inChoice(find.text('ur. 1890')), findsOneWidget);
      expect(inChoice(find.text('W grobach')), findsOneWidget);
      expect(
        inChoice(find.text('w grobie: Grób rodzinny Zmyślonych')),
        findsOneWidget,
      );
      expect(inChoice(find.text('już w tym grobie')), findsOneWidget);
      // "Bez grobu" stands above "W grobach" (D22: the ones to choose first).
      expect(
        tester.getTopLeft(inChoice(find.text('Bez grobu'))).dy,
        lessThan(tester.getTopLeft(inChoice(find.text('W grobach'))).dy),
      );

      // Retro 3, R2: tap targets, labels, and a tap behind every button that is on.
      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();

      // A greyed row cannot be chosen (D23).
      await tester.tap(inChoice(find.text('Maria Zmyślona')));
      await tester.pumpAndSettle();
      expect(choice, findsOneWidget);

      // The search narrows it; the person buried nowhere joins the grave.
      await tester.enterText(inChoice(find.byType(TextField)), 'jan');
      await tester.pump();
      expect(inChoice(find.text('Nowa osoba: „jan”')), findsOneWidget);
      expect(inChoice(find.text('Maria Zmyślona')), findsNothing);
      await tester.tap(inChoice(find.text('Jan Wymyślony')));
      await _pumpUntil(tester, () => choice.evaluate().isEmpty);
      await _pumpUntil(tester, () => _shown(find.text('Jan Wymyślony')));
      expect(find.text('Józef Wymyślony'), findsOneWidget);

      await leaveScreen(tester);
      await tester.runAsync(() async {
        expect(await db.select(db.persons).get(), hasLength(3));
        final GraveDetail detail = (await loadGrave(db, here))!;
        expect(detail.people.map((p) => p.id), contains(janId));
        expect(
          (await (db.select(
            db.burials,
          )..where((b) => b.personId.equals(janId))).get()).map(
            (b) => b.graveId,
          ),
          [here],
        );
      });
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-4, D10 — Osoby: "Dodaj osobę" under the list; "Ksenia" finds no one and the button says '
    '„Dodaj osobę: „Ksenia””; it opens "Nowa osoba" · "bez grobu w aplikacji" with "Ksenia"; "Zapisz" opens '
    'her view; back, she is on the list, buried nowhere',
    (tester) async {
      await tester.runAsync(() async {
        await addPersonWithoutGrave(
          db,
          entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
        );
      });
      await pumpScreen(tester, PeopleScreen(database: db));
      await _pumpUntil(tester, () => _shown(find.text('Jan Wymyślony')));
      expect(find.widgetWithText(FilledButton, 'Dodaj osobę'), findsOneWidget);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();

      await tester.enterText(find.byType(TextField).first, 'Ksenia');
      await tester.pump();
      expect(find.text('Nie ma osoby „Ksenia”.'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Dodaj osobę: „Ksenia”'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nowa osoba'), findsOneWidget);
      expect(find.text('bez grobu w aplikacji'), findsOneWidget);
      final Finder form = find.byType(PersonFormScreen);
      final Finder names = find
          .descendant(of: form, matching: find.byType(TextField))
          .first;
      expect(tester.widget<TextField>(names).controller!.text, 'Ksenia');
      await tester.enterText(
        find.descendant(of: form, matching: find.byType(TextField)).at(1),
        'Zmyślona',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      await _pumpUntil(tester, () => _shown(find.text('Ksenia Zmyślona')));
      await _pumpUntil(tester, () => form.evaluate().isEmpty);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PeopleScreen), findsOneWidget);
      await _pumpUntil(tester, () => _shown(find.text('Ksenia Zmyślona')));

      await leaveScreen(tester);
      await tester.runAsync(() async {
        expect(await db.select(db.persons).get(), hasLength(2));
        expect(await db.select(db.burials).get(), isEmpty);
      });
      await cleanUp(tester);
    },
  );
}
