import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';

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
          const GravesCompanion(
            sector: Value('B'),
            row: Value('3'),
            plot: Value('12'),
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
    'AC-1, AC-2, AC-3, AC-4 — "Dodaj grób" → the first person with "około" and a full date → the grave '
    'replaces the form; "Dodaj osobę" → the surname suggested and selected, "między" with its second '
    'field and preview, a wrong year refused, then saved: both people in the grave, every fact with '
    'its claim from the notes',
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
      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj grób'));
      await tester.pumpAndSettle();
      expect(find.text('Osoba w grobie'), findsOneWidget);
      expect(find.text('Cmentarz Wymyślony · nowy grób'), findsOneWidget);
      // Focus and the keyboard in "Imiona" at once.
      expect(tester.widget<TextField>(_field(0)).focusNode!.hasFocus, isTrue);

      await tester.enterText(_field(0), 'Jan');
      await tester.enterText(_field(1), 'Wymyślony');
      await chooseQualifier(tester, 0, 'około');
      // The chosen qualifier carries a check, not only the accent (ui review, SC 1.4.1).
      await tester.tap(find.byType(MenuAnchor).at(0));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.widgetWithText(MenuItemButton, 'około'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
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
      expect(find.text('Źródło: notatki'), findsOneWidget);
      expect(
        find.text('Daty i miejsce pochówku zapiszą się ze źródłem: notatki.'),
        findsOneWidget,
      );
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

      // The next person.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Dodaj osobę'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cmentarz Wymyślony · w grobie: 1 osoba'),
        findsOneWidget,
      );
      await tester.enterText(_field(0), 'Anna');
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
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
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

      await leaveScreen(tester);
      await tester.runAsync(() async {
        final List<Assertion> claims = await db.select(db.assertions).get();
        expect(claims, hasLength(4 + 2)); // four dates, two burials
        expect(claims.map((c) => (c.sourceKind, c.status)).toSet(), {
          (SourceKind.notes, AssertionStatus.claimed),
        });
        final List<Person> people = await db.select(db.persons).get();
        expect(people.map((p) => p.bioSource), ['notatki', null]);
      });
      await cleanUp(tester);
    },
  );

  testWidgets(
    '`next` goes field by field to "Kim była" past the qualifiers — also when it is off the screen',
    (tester) async {
      await withCemetery(tester);
      await pumpScreen(
        tester,
        PersonFormScreen(
          database: db,
          mode: NewGrave(cemeteryId: cemetery, cemeteryName: 'Cmentarz'),
        ),
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
                    builder: (_) => PersonFormScreen(
                      database: db,
                      mode: NewGrave(
                        cemeteryId: cemetery,
                        cemeteryName: 'Cmentarz Wymyślony',
                      ),
                    ),
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
    'D1 — a person in the grave opens "Poprawa wpisu" with the values; a corrected year shows in the '
    'grave; a date two sources gave is shown and not editable',
    (tester) async {
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
            burial: QualifiedDate(
              DateQualifier.exact,
              PartialDate(1951, 3, 18),
            ),
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
            source: ClaimSource(
              kind: kind,
              status: AssertionStatus.contradicted,
            ),
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
      await tester.pumpAndSettle();
      expect(find.text('Poprawa wpisu'), findsOneWidget);
      // Read against the notes first: no keyboard; the dates keep their source (ui review).
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.focusNode.hasFocus,
        ),
        findsNothing,
      );
      expect(
        find.text(
          'Poprawa nie zmienia źródła dat. Nowa data zapisze się ze '
          'źródłem: notatki.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Kilka źródeł — tej daty tu nie poprawisz.'),
        findsOneWidget,
      );
      expect(find.text('1890'), findsOneWidget); // the birth, read-only
      // Fields: names(0), surname(1), birth surname(2), death(3), bio(4); the birth is read-only.
      expect(tester.widget<TextField>(_field(0)).controller!.text, 'Jan');
      expect(tester.widget<TextField>(_field(3)).controller!.text, '1951');
      await tester.enterText(_field(3), '1952');
      await save(tester, GraveScreen);
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
    },
  );
}
