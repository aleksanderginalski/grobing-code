import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/dates.dart' show badDateMessage;
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/grave_person_choice_screen.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/glyphs.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/sectors.dart';

import '../../support/a11y.dart';
import '../../support/glyphs.dart';

// ISSUE-012 — the transcription screens (05_DESIGN/cmentarz.md, grob.md, wpis-osoby.md v2), happy path
// per AC: US-002 AC-1 a grave shows everyone in it · AC-2 names, birth surname, "kim była" · AC-3 the
// qualifiers, with "między" and the preview · AC-4 the source line · AC-5 no address, no pin · the
// grave's name (D4) · the correction (D1) · the `next` order and leaving with something typed. Made-up
// people only (family-data.md).

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

Finder _field(int i) => find.byType(TextField).at(i);

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

  /// Takes the screen down before the test touches the database itself: a screen's stream re-runs its
  /// query in the fake clock's zone and holds the database lock, so a write or read from `runAsync`
  /// next to it waits for ever (seen: the first run of these tests hung).
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

  Future<void> chooseQualifier(
    WidgetTester tester,
    int block,
    String label,
  ) async {
    await tester.tap(find.byType(MenuAnchor).at(block));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, Type next) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await _pumpUntil(tester, () => find.byType(next).evaluate().isNotEmpty);
    await _pumpUntil(
      tester,
      () => find.byType(PersonFormScreen).evaluate().isEmpty,
    );
  }

  testWidgets(
    'the cemetery screen: empty — what will be here and "Dodaj grób"; filled — a named grave titled '
    'by its name with its people below, an unnamed one by its people, the missing address and pin '
    'said as a fact (AC-5), the counts above',
    (tester) async {
      await withCemetery(tester);
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: cemetery),
      );
      await _pumpUntil(
        tester,
        () => find
            .text('Na tym cmentarzu nie ma jeszcze grobów.')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Cmentarz Wymyślony'), findsOneWidget);
      expect(find.text('Miejscowość Testowa'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Dodaj grób'), findsOneWidget);

      await leaveScreen(tester);
      await tester.runAsync(() async {
        final int named = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
        );
        await addPersonToGrave(
          db,
          graveId: named,
          entry: const PersonEntry(givenNames: 'Anna', surname: 'Wymyślona'),
        );
        await setGraveName(db, named, 'Grób rodzinny Wymyślonych');
        final int other = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Maria', surname: 'Próbna'),
        );
        await (db.update(db.graves)..where((g) => g.id.equals(other))).write(
          GravesCompanion(
            sectorId: Value(await sectorForAddress(db, cemetery, 'B')),
            row: const Value('3'),
            plot: const Value('12'),
          ),
        );
      });
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: cemetery),
      );
      await _pumpUntil(
        tester,
        () => find.text('2 groby · 3 osoby').evaluate().isNotEmpty,
      );
      // ISSUE-027: the list is state C, behind the bar of graves (05_DESIGN/cmentarz.md v5).
      expect(find.text('2 groby bez pinezki — na liście'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Pokaż listę grobów'));
      await tester.pumpAndSettle();
      expect(find.text('Grób rodzinny Wymyślonych'), findsOneWidget);
      expect(find.text('Jan Wymyślony, Anna Wymyślona'), findsOneWidget);
      expect(find.text('Bez adresu kwatery · bez pinezki'), findsOneWidget);
      expect(find.text('Maria Próbna'), findsOneWidget);
      expect(
        find.text('Kwatera B · Rząd 3 · Miejsce 12 · bez pinezki'),
        findsOneWidget,
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'names that do not fit in two lines end with "i jeszcze N" (cmentarz.md, element 3a)',
    (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 200,
            child: NamesText(
              names: [
                'Jan Wymyślony',
                'Anna Wymyślona',
                'Józef Wymyślony',
                'Maria Wymyślona',
                'Piotr Wymyślony',
                'Ewa Wymyślona',
              ],
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
      // The test font is wider than Roboto, so how many names fit is not the point; the rule is: the
      // names shown and "i jeszcze N" add up to all six, the first name is shown, two lines at most.
      final String shown = tester.widget<Text>(find.byType(Text)).data!;
      final RegExpMatch m = RegExp(
        r'^(.+) i jeszcze (\d+)$',
      ).firstMatch(shown)!;
      expect(m.group(1)!.split(', ').length + int.parse(m.group(2)!), 6);
      expect(shown, startsWith('Jan Wymyślony'));
      expect(
        tester.getSize(find.byType(Text)).height,
        lessThanOrEqualTo(2 * 16 * 1.5),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-1, AC-2, AC-3, AC-4 — "Dodaj grób" → "Nowy grób" → the grave, empty → "Dodaj osobę" → "Nowa osoba: '
    '„Jan”" → the first person with "około" and a full date → the grave replaces the form; "Dodaj osobę" → '
    '„Anna” → the surname suggested and selected, "między" with its second field and preview, a wrong year '
    'refused, then saved: both people in the grave, every fact with its claim from the notes (ISSUE-047: '
    'the grave first, then its people)',
    (tester) async {
      await withCemetery(tester);
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: cemetery),
      );
      // "Dodaj grób" is inactive until the cemetery is read.
      await _pumpUntil(
        tester,
        () => find
            .text('Na tym cmentarzu nie ma jeszcze grobów.')
            .evaluate()
            .isNotEmpty,
      );
      // ISSUE-047 (cmentarz.md D38, grob.md D22): the grave on its own, then its first person from it.
      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj grób'));
      await tester.pumpAndSettle();
      expect(find.text('Nowy grób'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find
            .text('W tym grobie nie ma jeszcze wpisanych osób.')
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Dodaj osobę'));
      await tester.pumpAndSettle();
      expect(find.text('Kto leży w tym grobie?'), findsOneWidget);
      await tester.enterText(_field(0), 'Jan');
      await _pumpUntil(
        tester,
        () => find.text('Nowa osoba: „Jan”').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Nowa osoba: „Jan”'));
      await tester.pumpAndSettle();
      expect(find.text('Osoba w grobie'), findsOneWidget);
      // An empty grave: its title alone, no count (wpis-osoby.md v6).
      expect(
        find.descendant(
          of: find.byType(PersonFormScreen),
          matching: find.text('Cmentarz Wymyślony'),
        ),
        findsOneWidget,
      );
      // The name typed in the search, with focus and the keyboard in "Imiona" at once.
      expect(tester.widget<TextField>(_field(0)).controller!.text, 'Jan');
      expect(tester.widget<TextField>(_field(0)).focusNode!.hasFocus, isTrue);
      await tester.pump();
      // ISSUE-025 AC-1: the sex is suggested from the given name — ♂ checked, ♀ not.
      _expectSex(tester, 'Mężczyzna', checked: true);
      _expectSex(tester, 'Kobieta', checked: false);
      await tester.enterText(_field(1), 'Wymyślony');
      await chooseQualifier(tester, 0, 'około');
      // The chosen qualifier carries a check, not only the accent (ui review, SC 1.4.1).
      await tester.tap(find.byType(MenuAnchor).at(0));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.widgetWithText(MenuItemButton, 'około'),
          matching: findGlyph(Glyphs.check),
        ),
        findsOneWidget,
      );
      expect(findGlyph(Glyphs.check), findsOneWidget);
      await tester.tap(find.byType(MenuAnchor).at(0));
      await tester.pumpAndSettle();
      await tester.enterText(_field(3), '1890');
      await tester.enterText(_field(4), '14.03.1951');
      await tester.pump();
      expect(find.text('→ ok. 1890'), findsOneWidget);
      expect(find.text('→ 14.03.1951'), findsOneWidget);
      // No burial date in the form (D7): names(0), surname(1), birth surname(2), birth(3), death(4), bio(5).
      expect(find.text('Pochówek'), findsNothing);
      await tester.enterText(_field(5), 'Kowal, wymyślony do testów.');
      await tester.pump();
      // ISSUE-025 AC-5: no source on the screen — neither by "kim była" nor by the dates (SPIKE-004 D28).
      expect(find.textContaining('Źródło'), findsNothing);
      expect(find.textContaining('ze źródłem'), findsNothing);
      expect(find.text('Zmień'), findsNothing);
      await save(tester, GraveScreen);

      await _pumpUntil(
        tester,
        () => find.text('Jan Wymyślony').evaluate().isNotEmpty,
      );
      expect(find.text('Grób'), findsOneWidget);
      expect(find.text('ok. 1890 – 14.03.1951'), findsOneWidget);
      expect(
        find.textContaining('Bez adresu kwatery · bez pinezki'),
        findsOneWidget,
      );

      // The next person: typed in the search, then "Nowa osoba".
      await tester.tap(find.widgetWithText(OutlinedButton, 'Dodaj osobę'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'Anna');
      await _pumpUntil(
        tester,
        () => find.text('Nowa osoba: „Anna”').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Nowa osoba: „Anna”'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cmentarz Wymyślony · w grobie: 1 osoba'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(_field(0)).controller!.text, 'Anna');
      await tester.pump();
      _expectSex(tester, 'Kobieta', checked: true); // AC-1: "Anna" → ♀
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final TextEditingController surname = tester
          .widget<TextField>(_field(1))
          .controller!;
      expect(surname.text, 'Wymyślony');
      expect(
        (surname.selection.start, surname.selection.end),
        (0, 'Wymyślony'.length),
      );
      await tester.enterText(_field(1), 'Wymyślona');
      await tester.enterText(_field(2), 'Zmyślona');
      await chooseQualifier(tester, 0, 'między');
      // "między" adds the second field: from(3), to(4), death(5), bio(6).
      await tester.enterText(_field(3), '1893');
      await tester.enterText(_field(4), '1895');
      await tester.enterText(_field(5), '196');
      await tester.pump();
      expect(find.text('→ między 1893 a 1895'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Nie rozumiem tej daty — wpisz rok, mm.rrrr albo dd.mm.rrrr.',
        ),
        findsOneWidget,
      );
      expect(findGlyph(Glyphs.error), findsOneWidget);
      expect(find.byType(PersonFormScreen), findsOneWidget);

      await tester.enterText(_field(5), '1960');
      await save(tester, GraveScreen);
      await _pumpUntil(
        tester,
        () => find.text('Anna Wymyślona z d. Zmyślona').evaluate().isNotEmpty,
      );
      expect(find.text('między 1893 a 1895 – 1960'), findsOneWidget);
      expect(find.text('Jan Wymyślony'), findsOneWidget);

      // Back from the grave goes to the cemetery, not to the form.
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CemeteryScreen), findsOneWidget);
      expect(find.byType(PersonFormScreen), findsNothing);
      expect(find.byType(GravePersonChoiceScreen), findsNothing);

      await leaveScreen(tester);
      await tester.runAsync(() async {
        final List<Assertion> claims = await db.select(db.assertions).get();
        expect(claims, hasLength(4 + 2)); // four dates, two burials
        expect(claims.map((c) => (c.sourceKind, c.status)).toSet(), {
          (SourceKind.notes, AssertionStatus.claimed),
        });
        final List<Person> people = await db.select(db.persons).get();
        expect(people.map((p) => p.bioSource), ['notatki', null]);
        // ISSUE-025 AC-1: the suggested sex is saved with the person.
        expect(people.map((p) => p.sex), [Sex.male, Sex.female]);
      });
      await cleanUp(tester);
    },
  );

  testWidgets(
    '`next` goes field by field to "Kim była" past the qualifiers — also when it is off the screen',
    (tester) async {
      await pumpScreen(
        tester,
        PersonFormScreen(database: db, mode: const NewPerson()),
      );
      await tester.pumpAndSettle();
      for (int i = 0; i < 5; i++) {
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        final EditableText focused = tester.widget<EditableText>(
          find.byWidgetPredicate(
            (w) => w is EditableText && w.focusNode.hasFocus,
          ),
        );
        expect(
          focused.controller,
          tester.widget<TextField>(_field(i + 1)).controller,
          reason: 'after next #${i + 1}',
        );
      }
      // The last one is "Kim była": several lines, Enter is a new line.
      expect(tester.widget<TextField>(_field(5)).minLines, 3);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'back with something typed asks "Odrzucić wpis?": "Wróć do wpisu" stays, "Odrzuć" leaves and '
    'writes nothing; back with nothing typed just leaves',
    (tester) async {
      await withCemetery(tester);
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PersonFormScreen(database: db, mode: const NewPerson()),
                  ),
                ),
                child: const Text('otwórz'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('otwórz'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormScreen), findsNothing);
      expect(find.text('Odrzucić wpis?'), findsNothing);

      await tester.tap(find.text('otwórz'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'Ewa');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Odrzucić wpis?'), findsOneWidget);
      expect(find.text('Wpisane dane nie zostaną zapisane.'), findsOneWidget);
      await tester.tap(find.text('Wróć do wpisu'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odrzuć'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormScreen), findsNothing);
      await tester.runAsync(() async {
        expect(await db.select(db.persons).get(), isEmpty);
        expect(await db.select(db.graves).get(), isEmpty);
      });
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D4 — the pencil names the grave: the title changes; a blank name brings back "Grób"',
    (tester) async {
      await withCemetery(tester);
      late int grave;
      await tester.runAsync(() async {
        grave = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
        );
      });
      await pumpScreen(tester, GraveScreen(database: db, graveId: grave));
      await _pumpUntil(tester, () => find.text('Grób').evaluate().isNotEmpty);
      expect(
        find.text('Cmentarz Wymyślony · Miejscowość Testowa'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Popraw grób'));
      await tester.pumpAndSettle();
      expect(
        find.text('Zostaw puste, jeśli grób nie ma nazwy.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Nazwa grobu'),
        'Grób rodzinny Wymyślonych',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      // The window closes once the name is written; the field itself shows the name until then.
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
      );
      await _pumpUntil(
        tester,
        () => find.text('Grób rodzinny Wymyślonych').evaluate().isNotEmpty,
      );

      await tester.tap(find.byTooltip('Popraw grób'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Nazwa grobu'), '');
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
      );
      await _pumpUntil(tester, () => find.text('Grób').evaluate().isNotEmpty);
      expect(find.text('Grób rodzinny Wymyślonych'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-028 D3, grob.md v6 — "Wpisz adres" under the missing address: the cemetery\'s sector as a chip '
    'fills "Kwatera", the row and the plot are typed, the address shows in full; a sector no grave has yet '
    'is announced as new',
    (tester) async {
      await withCemetery(tester);
      late int grave;
      await tester.runAsync(() async {
        final int other = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Anna', surname: 'Testowa'),
        );
        await setGraveDetails(db, other, sector: 'B');
        grave = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
        );
      });
      await pumpScreen(tester, GraveScreen(database: db, graveId: grave));
      await _pumpUntil(
        tester,
        () => find.text('Wpisz adres').evaluate().isNotEmpty,
      );
      expect(find.text('Uzupełnisz przy wizycie.'), findsNothing);

      await tester.tap(find.text('Wpisz adres'));
      await tester.pumpAndSettle();
      expect(find.text('Adres zarządcy'), findsOneWidget);
      expect(
        find.text('Z wyszukiwarki zarządcy. Zostaw puste, czego nie wiesz.'),
        findsOneWidget,
      );
      ChoiceChip chip() =>
          tester.widget(find.widgetWithText(ChoiceChip, 'Kwatera B'));
      expect(chip().selected, isFalse);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Kwatera B'));
      await tester.pump();
      expect(chip().selected, isTrue);
      await tester.enterText(find.widgetWithText(TextField, 'Rząd'), '4');
      await tester.enterText(
        find.widgetWithText(TextField, 'Miejsce'),
        'Miejsce 12',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find
            .text('Kwatera B · Rząd 4 · Miejsce 12 · bez pinezki')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Wpisz adres'), findsNothing);

      await tester.tap(find.byTooltip('Popraw grób'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'B'), 'D');
      await tester.pump();
      expect(chip().selected, isFalse);
      expect(
        find.text(
          'Nowa kwatera „D” — powstanie bez strefy; zaznaczysz ją w „Kwaterach”.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      await cleanUp(tester);
    },
  );

  testWidgets('D1, ISSUE-024 AC-1 — a person in the grave opens their view, not the form; ✎ opens "Poprawa wpisu" '
      'with the values; a corrected year shows in the view and the grave; a date two sources gave is shown '
      'and not editable', (tester) async {
    await withCemetery(tester);
    late int grave;
    await tester.runAsync(() async {
      grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(
          givenNames: 'Jan',
          surname: 'Wymyślony',
          death: QualifiedDate(DateQualifier.exact, PartialDate(1951)),
          // From before D7 or another source: the form has no burial date, a correction keeps it.
          burial: QualifiedDate(DateQualifier.exact, PartialDate(1951, 3, 18)),
        ),
      );
      final int jan = (await loadGrave(db, grave))!.people.single.id;
      // A made-up dispute over the birth (US-004): the notes and the grandmother.
      for (final (int year, SourceKind kind) in [
        (1890, SourceKind.notes),
        (1892, SourceKind.grandmother),
      ]) {
        await addEventWithClaim(
          db,
          EventsCompanion.insert(
            type: EventType.birth,
            personId: Value(jan),
            qualifier: const Value(DateQualifier.exact),
            year: Value(year),
          ),
          source: ClaimSource(kind: kind, status: AssertionStatus.contradicted),
        );
      }
    });
    await pumpScreen(tester, GraveScreen(database: db, graveId: grave));
    await _pumpUntil(
      tester,
      () => find.text('Jan Wymyślony').evaluate().isNotEmpty,
    );
    expect(find.text('1890–1951 · poch. 18.03.1951'), findsOneWidget);

    await tester.tap(find.text('Jan Wymyślony'));
    await _pumpUntil(
      tester,
      () => find.byType(PersonScreen).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 500));
    // The view first (style-b.md rule 15): the name in the header, no form yet.
    expect(find.byType(PersonFormScreen), findsNothing);
    await _pumpUntil(
      tester,
      () => find.text('1890–1951').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Popraw wpis'));
    await tester.pumpAndSettle();
    expect(find.text('Poprawa wpisu'), findsOneWidget);
    // Read against the notes first: no keyboard (ui review). No line about the dates' source any more
    // (ISSUE-025 AC-5, SPIKE-004 D28).
    expect(
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
      findsNothing,
    );
    expect(find.textContaining('Poprawa nie zmienia źródła'), findsNothing);
    expect(
      find.text('Kilka źródeł — tej daty tu nie poprawisz.'),
      findsOneWidget,
    );
    expect(find.text('1890'), findsOneWidget); // the birth, read-only
    // Fields: names(0), surname(1), birth surname(2), death(3), bio(4); the birth is read-only.
    expect(tester.widget<TextField>(_field(0)).controller!.text, 'Jan');
    expect(tester.widget<TextField>(_field(3)).controller!.text, '1951');
    await tester.enterText(_field(3), '1952');
    // "Zapisz" returns to the view, which shows the new year (rule 10), then back to the grave.
    await save(tester, PersonScreen);
    await _pumpUntil(
      tester,
      () => find.text('1890–1952').evaluate().isNotEmpty,
    );
    await tester.pageBack();
    await _pumpUntil(
      tester,
      () => find.text('1890–1952 · poch. 18.03.1951').evaluate().isNotEmpty,
    );
    await leaveScreen(tester);
    await tester.runAsync(() async {
      final List<Event> births = await (db.select(
        db.events,
      )..where((e) => e.type.equalsValue(EventType.birth))).get();
      expect(births.map((e) => e.year), [1890, 1892]);
    });
    await cleanUp(tester);
  });

  testWidgets(
    'ISSUE-025 AC-1, D-płeć — a correction of someone without a sex starts from the suggestion, so back '
    'with nothing changed asks nothing; a sex written is never changed by typing a name',
    (tester) async {
      await withCemetery(tester);
      late ({
        BuriedPerson person,
        int? graveId,
        String? graveTitle,
        int peopleCount,
      }) maria,
          kuba;
      await tester.runAsync(() async {
        final int grave = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Maria', surname: 'Wymyślona'),
        );
        await addPersonToGrave(
          db,
          graveId: grave,
          entry: const PersonEntry(
            givenNames: 'Kuba',
            surname: 'Wymyślony',
            sex: Sex.male,
          ),
        );
        final List<Person> people = await db.select(db.persons).get();
        maria = (await loadPersonForCorrection(db, people[0].id))!;
        kuba = (await loadPersonForCorrection(db, people[1].id))!;
      });
      expect(maria.person.sex, isNull);

      Widget opener(
        ({
          BuriedPerson person,
          int? graveId,
          String? graveTitle,
          int peopleCount,
        })
        p,
      ) => Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PersonFormScreen(
                  database: db,
                  mode: Correction(
                    person: p.person,
                    graveTitle: p.graveTitle,
                    peopleCount: p.peopleCount,
                    graveId: p.graveId,
                  ),
                ),
              ),
            ),
            child: const Text('otwórz'),
          ),
        ),
      );

      // Maria, no sex written: ♀ suggested from her name; back with nothing changed just leaves.
      await pumpScreen(tester, opener(maria));
      await tester.tap(find.text('otwórz'));
      await tester.pumpAndSettle();
      _expectSex(tester, 'Kobieta', checked: true);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Odrzucić wpis?'), findsNothing);
      expect(find.byType(PersonFormScreen), findsNothing);

      // Kuba, ♂ written: a name that would suggest ♀ does not change it.
      await pumpScreen(tester, opener(kuba));
      await tester.tap(find.text('otwórz'));
      await tester.pumpAndSettle();
      _expectSex(tester, 'Mężczyzna', checked: true);
      await tester.enterText(_field(0), 'Kunegunda');
      await tester.pump();
      _expectSex(tester, 'Mężczyzna', checked: true);
      _expectSex(tester, 'Kobieta', checked: false);

      await cleanUp(tester);
    },
  );

  group('ISSUE-043 — the fee "paid until" (grob.md v8, element 7, 3c)', () {
    Finder feeField() => find.widgetWithText(TextField, 'Opłacone do');
    bool feeFocused(WidgetTester tester) =>
        tester.widget<TextField>(feeField()).focusNode!.hasFocus;

    Future<int> graveWithJan(WidgetTester tester) async {
      await withCemetery(tester);
      late int grave;
      await tester.runAsync(() async {
        grave = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
        );
      });
      return grave;
    }

    testWidgets(
      'AC-1, AC-2, W1 — at the very bottom, under "Dodaj osobę": "nie wiadomo" and "Wpisz"; "Wpisz" opens the window '
      'with the numeric keyboard in "Opłacone do"; "2031" and done → "Opłacone do 2031" without "Wpisz"; ✎ corrects '
      'it to a date that has passed, shown plain',
      (tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final int grave = await graveWithJan(tester);
        await pumpScreen(tester, GraveScreen(database: db, graveId: grave));
        await _pumpUntil(
          tester,
          () => find.text('nie wiadomo').evaluate().isNotEmpty,
        );

        // AC-2 (W1): the row says the date is missing, and makes none up.
        expect(find.text('Opłacone do'), findsOneWidget);
        expect(find.text('Wpisz'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Opłacone do')).dy,
          greaterThan(tester.getBottomLeft(find.text('Dodaj osobę')).dy),
        );
        expect(
          find.bySemanticsLabel('Opłacone do: nie wiadomo'),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Wpisz datę opłaty')),
          isSemantics(isButton: true, hasTapAction: true),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expectEveryButtonTappable(tester);

        // AC-1 through "Wpisz": the keyboard is in the fee field, digits and a separator.
        await tester.tap(find.text('Wpisz'));
        await tester.pumpAndSettle();
        expect(feeFocused(tester), isTrue);
        expect(
          tester.widget<TextField>(feeField()).keyboardType,
          TextInputType.datetime,
        );
        expect(
          find.text(
            'Rok albo data z naklejki na grobie lub z pokwitowania. '
            'Zostaw puste, jeśli nie wiesz.',
          ),
          findsOneWidget,
        );
        await tester.enterText(feeField(), '2031');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _pumpUntil(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
        );
        await _pumpUntil(tester, () => find.text('2031').evaluate().isNotEmpty);
        expect(find.text('Wpisz'), findsNothing);
        expect(find.bySemanticsLabel('Opłacone do 2031'), findsOneWidget);

        // The correction is under ✎ (D17): the field holds the date; a date that has passed is a fact (D19).
        await tester.tap(find.byTooltip('Popraw grób'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, '2031'), findsOneWidget);
        await tester.enterText(feeField(), '03.2019');
        await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
        await _pumpUntil(
          tester,
          () =>
              find.text('03.2019').evaluate().isNotEmpty &&
              find.byType(AlertDialog).evaluate().isEmpty,
        );
        expect(
          tester.widget<Text>(find.text('03.2019')).style?.color,
          GrobingColors.text,
        );
        semantics.dispose();
        await leaveScreen(tester);
        final GraveDetail? saved = await tester.runAsync<GraveDetail?>(
          () => loadGrave(db, grave),
        );
        expect(saved?.paidUntil, const PartialDate(2019, 3));
        await cleanUp(tester);
      },
    );

    testWidgets(
      'D18 — all or nothing: "2301" and "13.2031" keep the window open with their message under the field and save '
      'nothing, not the name typed either; the message goes as the date changes; Miejsce `next` goes to the fee',
      (tester) async {
        final int grave = await graveWithJan(tester);
        await pumpScreen(tester, GraveScreen(database: db, graveId: grave));
        await _pumpUntil(
          tester,
          () => find.text('nie wiadomo').evaluate().isNotEmpty,
        );

        await tester.tap(find.byTooltip('Popraw grób'));
        await tester.pumpAndSettle();
        // `next` from "Miejsce" goes to "Opłacone do", the last field (3b, v8).
        await tester.tap(find.widgetWithText(TextField, 'Miejsce'));
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(feeFocused(tester), isTrue);

        await tester.enterText(
          find.widgetWithText(TextField, 'Nazwa grobu'),
          'Grób rodzinny Wymyślonych',
        );
        await tester.enterText(feeField(), '2301');
        await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text('Tak odległa data to raczej pomyłka — sprawdź rok.'),
          findsOneWidget,
        );
        expect(findGlyph(Glyphs.error), findsOneWidget);
        expect(feeFocused(tester), isTrue);

        await tester.enterText(feeField(), '13.2031');
        await tester.pump();
        expect(
          find.text('Tak odległa data to raczej pomyłka — sprawdź rok.'),
          findsNothing,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
        await tester.pumpAndSettle();
        expect(find.text(badDateMessage), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
        await tester.pumpAndSettle();
        expect(find.text('Grób'), findsOneWidget);
        await leaveScreen(tester);
        final GraveDetail? saved = await tester.runAsync<GraveDetail?>(
          () => loadGrave(db, grave),
        );
        expect((saved?.name, saved?.paidUntil), (null, null));
        await cleanUp(tester);
      },
    );

    // Whether the row's label, value and "Wpisz" fit at 200% on 360 dp is measured on the emulator (Dev report →
    // Emulator pass: 162 + 88 dp of 328): the test font draws every letter as a square, wider than Roboto, and the
    // tab bar under the grave would overflow in it, not on a phone (as in map_r1_and_cemetery_photo_test). Here
    // the window stands alone.
    testWidgets(
      '200% text on 360 dp, the window from "Wpisz": with the keyboard up, the fee field with its floating label '
      'lies in what the window shows, above the keyboard (dev pass: it stayed under the window\'s edge)',
      (tester) async {
        tester.view.physicalSize = const Size(720, 1280);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const GraveDetail grave = GraveDetail(
          id: 1,
          cemeteryId: 1,
          cemeteryName: 'Cmentarz Wymyślony',
          people: [],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: GrobingTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => GraveDialog(
                        grave: grave,
                        sectors: const [],
                        focus: GraveField.paidUntil,
                        save: ({name, sector, row, plot, paidUntil}) async {},
                      ),
                    ),
                    child: const Text('otwórz'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('otwórz'));
        await tester.pumpAndSettle();
        expect(feeFocused(tester), isTrue);

        // The numeric keyboard: 300 dp of the 640.
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await tester.pumpAndSettle();
        // The decorator holds the hint under the field too (six lines here), so what must show is the floating
        // label and the line typed in — at the top of the window, the hint under it as far as it goes.
        final Rect label = tester.getRect(
          find.descendant(of: feeField(), matching: find.text('Opłacone do')),
        );
        final Rect typed = tester.getRect(
          find.descendant(of: feeField(), matching: find.byType(EditableText)),
        );
        final Rect window = tester.getRect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(label.top, greaterThanOrEqualTo(window.top));
        expect(typed.bottom, lessThanOrEqualTo(window.bottom));
        expect(typed.bottom, lessThanOrEqualTo(640 - 300));
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(db.close);
      },
    );
  });
}

/// ISSUE-025 AC-1: the sex icon named [label] ("Kobieta", "Mężczyzna") is chosen — or not — as the screen
/// reader hears it, and it can be pressed (Switch Access, ISSUE-021).
void _expectSex(WidgetTester tester, String label, {required bool checked}) =>
    expect(
      tester.getSemantics(find.bySemanticsLabel(label)),
      isSemantics(isChecked: checked, hasTapAction: true),
    );
