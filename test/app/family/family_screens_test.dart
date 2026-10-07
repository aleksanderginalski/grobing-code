import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/family/family_sheet_screen.dart';
import 'package:grobing/app/family/person_picker_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/graves.dart';

// ISSUE-019 — the family screens (05_DESIGN/rodzina.md v1.1 A and B, wpis-osoby.md v5.1 9a), happy path
// per AC of US-003: AC-1 a family on one sheet, a new person on the way · AC-2 two unions, each with its
// children · AC-3 the dates in the union's label · AC-5 a person from the grave · the chip to an entry
// without a grave · D4 children by birth · the sheet's own rules and windows. Made-up people only
// (family-data.md).

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

  /// The screen goes before the test touches the database itself (grave_screens_test → leaveScreen).
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

  Future<T> data<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  /// A grave with Maria and Jan; returns the grave.
  Future<int> graveOfTwo(WidgetTester tester) => data(tester, () async {
    cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    final int grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Maria', surname: 'Wymyślona'),
    );
    await addPersonToGrave(
      db,
      graveId: grave,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
    return grave;
  });

  Future<void> openCorrection(WidgetTester tester, int personId) async {
    final ({
      BuriedPerson person,
      int? graveId,
      String? graveTitle,
      int peopleCount,
    })?
    found = await data(tester, () => loadPersonForCorrection(db, personId));
    await pumpScreen(
      tester,
      PersonFormScreen(
        database: db,
        mode: Correction(
          person: found!.person,
          graveTitle: found.graveTitle,
          peopleCount: found.peopleCount,
          graveId: found.graveId,
        ),
      ),
    );
    await _pumpUntil(tester, () => _shown(find.text('Dodaj związek')));
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'AC-1, AC-5 — "Dodaj związek" from the form: the partner from "W tym grobie", a new child typed in '
    'the search; `next` goes from "Imiona" to "Nazwisko"; "Zapisz" returns to the form, whose section '
    'shows the partner and the child at once',
    (tester) async {
      final int grave = await graveOfTwo(tester);
      final int maria = (await data(
        tester,
        () => loadGrave(db, grave),
      ))!.people.first.id;
      await openCorrection(tester, maria);
      // 9a, empty: the header and the two ways in.
      expect(find.text('Rodzina'), findsOneWidget);
      expect(find.text('Dodaj rodziców'), findsOneWidget);

      await tapVisible(tester, find.text('Dodaj związek'));
      expect(find.byType(FamilySheetScreen), findsOneWidget);
      expect(find.text('Nowa rodzina'), findsOneWidget);
      expect(find.textContaining('ta osoba'), findsOneWidget);

      await tester.tap(find.text('Dodaj osobę do pary'));
      await _pumpUntil(tester, () => _shown(find.text('Jan Wymyślony')));
      expect(find.byType(PersonPickerScreen), findsOneWidget);
      expect(find.text('W tym grobie'), findsOneWidget);
      // "Ta osoba" is there, but cannot be chosen, and says why in words (SC 1.4.1).
      expect(find.text('już w tej rodzinie'), findsOneWidget);
      await tester.tap(find.text('Jan Wymyślony'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonPickerScreen), findsNothing);
      // Two in the pair: no more "Dodaj osobę do pary".
      expect(find.text('Dodaj osobę do pary'), findsNothing);

      await tapVisible(tester, find.text('Dodaj dziecko'));
      await _pumpUntil(tester, () => _shown(find.text('Nowa osoba')));
      await tester.enterText(find.byType(TextField), 'Anna');
      await tester.pump();
      await tester.tap(find.text('Nowa osoba: „Anna”'));
      await tester.pumpAndSettle();
      final Finder given = find.widgetWithText(TextField, 'Imiona');
      final Finder surname = find.widgetWithText(TextField, 'Nazwisko');
      expect(tester.widget<TextField>(given).controller!.text, 'Anna');
      expect(tester.widget<TextField>(given).focusNode!.hasFocus, isTrue);
      // The suggestion: the surname of the first in the pair.
      expect(tester.widget<TextField>(surname).controller!.text, 'Wymyślona');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(surname).focusNode!.hasFocus, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find.byType(FamilySheetScreen).evaluate().isEmpty,
      );
      await _pumpUntil(tester, () => _shown(find.text('Dziecko: Anna')));
      expect(find.text('Partner: Jan'), findsOneWidget);
      expect(find.text('Związek'), findsOneWidget);

      await leaveScreen(tester);
      final ({int persons, int claims}) after = await data(
        tester,
        () async => (
          persons: (await db.select(db.persons).get()).length,
          claims:
              (await (db.select(db.assertions)..where(
                        (a) =>
                            a.familyId.isNotNull() |
                            a.familyChildId.isNotNull(),
                      ))
                      .get())
                  .length,
        ),
      );
      expect(
        after.persons,
        3,
      ); // Maria, Jan and the new child — no one twice (AC-5)
      expect(after.claims, 2); // the union and the child's link (AC-4)
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2, AC-3, D4 — two unions by marriage date, each with its children by birth; a child\'s chip opens '
    'an entry without a grave, which shows its parents; saving it comes back',
    (tester) async {
      final int father = await data(tester, () async {
        Future<int> person(String given) => db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(
                givenNames: Value(given),
                surname: const Value('Wymyślony'),
              ),
            );
        final int f = await person('Ojciec');
        final int first = await person('Pierwsza');
        final int second = await person('Druga');
        final int late = await person('Późne');
        final int early = await person('Wczesne');
        await addEventWithClaim(
          db,
          EventsCompanion.insert(
            type: EventType.birth,
            personId: Value(early),
            qualifier: const Value(DateQualifier.exact),
            year: const Value(1921),
          ),
        );
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(f), ExistingMember(second)],
            children: [ExistingMember(late)],
            marriage: const QualifiedDate(
              DateQualifier.exact,
              PartialDate(1930),
            ),
          ),
        );
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(f), ExistingMember(first)],
            children: [ExistingMember(early)],
            marriage: const QualifiedDate(
              DateQualifier.about,
              PartialDate(1920),
            ),
            end: const QualifiedDate(DateQualifier.before, PartialDate(1928)),
          ),
        );
        return f;
      });
      await openCorrection(tester, father);
      // The father has no grave.
      expect(find.text('bez grobu w aplikacji'), findsOneWidget);

      final Finder labels = find.textContaining('Związek');
      expect(tester.widgetList<Text>(labels).map((t) => t.data), [
        'Związek · ślub ok. 1920 · koniec przed 1928',
        'Związek · ślub 1930',
      ]);
      expect(find.text('Partner: Pierwsza'), findsOneWidget);
      expect(find.text('Partner: Druga'), findsOneWidget);
      // AC-2: one "Dodaj związek" — another union is another family.
      expect(find.text('Dodaj związek'), findsOneWidget);

      await tapVisible(tester, find.text('Dziecko: Wczesne'));
      await _pumpUntil(tester, () => _shown(find.text('Rodzic: Ojciec')));
      expect(
        find.byType(PersonFormScreen, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(find.text('Rodzic: Pierwsza'), findsOneWidget);
      // With parents: no "Dodaj rodziców".
      expect(find.text('Dodaj rodziców'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz').last);
      await _pumpUntil(
        tester,
        () =>
            find
                .byType(PersonFormScreen, skipOffstage: false)
                .evaluate()
                .length ==
            1,
      );
      expect(find.text('Partner: Pierwsza'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'the sheet\'s rules: without a pair it says what is missing and writes nothing; back with a change '
    'asks first; "Usuń rodzinę" asks, then the family goes and the people stay',
    (tester) async {
      final ({int child, int a, int b}) people = await data(tester, () async {
        Future<int> person(String given) => db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: Value(given)));
        return (
          child: await person('Dziecko'),
          a: await person('A'),
          b: await person('B'),
        );
      });

      // "Dodaj rodziców": the person among the children, the pair empty.
      await pumpScreen(
        tester,
        FamilySheetScreen(
          database: db,
          personId: people.child,
          personName: 'Dziecko',
          start: FamilyStart.asChild,
        ),
      );
      await _pumpUntil(tester, () => _shown(find.text('Dodaj osobę do pary')));
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dodaj osobę do pary — rodzina to para i jej dzieci.'),
        findsOneWidget,
      );
      await leaveScreen(tester);
      expect(
        await data(
          tester,
          () async => (await db.select(db.families).get()).length,
        ),
        0,
      );

      final int family = await data(
        tester,
        () => saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(people.a), ExistingMember(people.b)],
            children: [ExistingMember(people.child)],
          ),
        ),
      );
      await pumpScreen(
        tester,
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => FamilySheetScreen(
              database: db,
              personId: people.a,
              personName: 'A',
              familyId: family,
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => _shown(find.text('Usuń rodzinę')));
      expect(find.text('Rodzina'), findsOneWidget);

      // A change, then back: the window, with the safe action.
      await tester.tap(find.byTooltip('Usuń z rodziny').first);
      await tester.pumpAndSettle();
      final NavigatorState navigator = tester.state(
        find.byType(Navigator).last,
      );
      navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Odrzucić zmiany w rodzinie?'), findsOneWidget);
      await tester.tap(find.text('Wróć do rodziny'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Usuń rodzinę'));
      expect(find.text('Usunąć rodzinę?'), findsOneWidget);
      expect(find.textContaining('Osoby zostają w aplikacji'), findsOneWidget);
      await tester.tap(find.text('Usuń'));
      await _pumpUntil(
        tester,
        () => find.byType(FamilySheetScreen).evaluate().isEmpty,
      );
      await leaveScreen(tester);
      final ({int families, int persons}) left = await data(
        tester,
        () async => (
          families: (await db.select(db.families).get()).length,
          persons: (await db.select(db.persons).get()).length,
        ),
      );
      expect(left, (families: 0, persons: 3));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'B — a child with parents elsewhere says "ma już rodziców" and cannot be chosen (D5); an empty '
    'search result keeps "Nowa osoba"',
    (tester) async {
      final ({int a, int b, int taken}) people = await data(tester, () async {
        Future<int> person(String given) => db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(
                givenNames: Value(given),
                surname: const Value('Testowy'),
              ),
            );
        final int a = await person('A');
        final int b = await person('B');
        final int taken = await person('Zajęte');
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(b)],
            children: [ExistingMember(taken)],
          ),
        );
        return (a: a, b: b, taken: taken);
      });
      PickedMember? picked;
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await Navigator.of(context).push(
              MaterialPageRoute<PickedMember>(
                builder: (_) => PersonPickerScreen(
                  database: db,
                  title: 'Dodaj dziecko',
                  inFamily: {people.a},
                  forChild: true,
                ),
              ),
            ),
            child: const Text('otwórz'),
          ),
        ),
      );
      await tester.tap(find.text('otwórz'));
      await _pumpUntil(tester, () => _shown(find.text('ma już rodziców')));
      expect(find.text('już w tej rodzinie'), findsOneWidget);
      await tester.tap(find.text('Zajęte Testowy'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonPickerScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Nikt');
      await tester.pump();
      expect(find.text('Nie ma osoby pasującej do „Nikt”.'), findsOneWidget);
      await tester.tap(find.text('Nowa osoba: „Nikt”'));
      await tester.pumpAndSettle();
      expect(picked, isA<PickedNew>());
      expect((picked! as PickedNew).text, 'Nikt');
      await cleanUp(tester);
    },
  );

  testWidgets('a new person has no "Rodzina" yet (rodzina.md D2)', (
    tester,
  ) async {
    await data(tester, () async {
      cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    });
    await pumpScreen(
      tester,
      PersonFormScreen(
        database: db,
        mode: NewGrave(
          cemeteryId: cemetery,
          cemeteryName: 'Cmentarz Wymyślony',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rodzina'), findsNothing);
    expect(find.text('Dodaj związek'), findsNothing);
    await cleanUp(tester);
  });

  testWidgets(
    'AC-3 on the sheet — "około" for the marriage and "po" for the end of the union, typed in their '
    'date blocks, are saved with their qualifiers (US-003 review, remark 1)',
    (tester) async {
      final ({int a, int b}) people = await data(tester, () async {
        Future<int> person(String given) => db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: Value(given)));
        return (a: await person('A'), b: await person('B'));
      });
      final int family = await data(
        tester,
        () => saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(people.a), ExistingMember(people.b)],
            children: const [],
          ),
        ),
      );
      await pumpScreen(
        tester,
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => FamilySheetScreen(
              database: db,
              personId: people.a,
              personName: 'A',
              familyId: family,
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => _shown(find.text('Dodaj koniec związku')));

      Future<void> qualifier(int block, String label) async {
        await tester.tap(find.byType(MenuAnchor).at(block));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, label));
        await tester.pumpAndSettle();
      }

      await qualifier(0, 'około');
      await tester.enterText(
        find.widgetWithText(TextField, 'rok albo dd.mm.rrrr').first,
        '1948',
      );
      await tester.pump();
      expect(find.text('→ ok. 1948'), findsOneWidget);
      await tapVisible(tester, find.text('Dodaj koniec związku'));
      await qualifier(1, 'po');
      await tester.enterText(
        find.widgetWithText(TextField, 'rok albo dd.mm.rrrr').last,
        '1960',
      );
      await tester.pump();
      expect(find.text('→ po 1960'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find.byType(FamilySheetScreen).evaluate().isEmpty,
      );
      await leaveScreen(tester);
      final FamilyDetail saved = (await data(
        tester,
        () => loadFamily(db, family),
      ))!;
      expect(
        saved.marriage.date,
        const QualifiedDate(DateQualifier.about, PartialDate(1948)),
      );
      expect(
        saved.end.date,
        const QualifiedDate(DateQualifier.after, PartialDate(1960)),
      );
      await cleanUp(tester);
    },
  );
}
