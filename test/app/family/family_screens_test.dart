import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/graves.dart';

// ISSUE-025 — the family screens (05_DESIGN/rodzina.md v2 C, D, E and Role names; wpis-osoby.md v5.6
// 9a), happy path per AC of US-003, rewritten for the union wizard: AC-1 a union and its child from the
// person's form · AC-2 a second union, each card with its own children · AC-3 the union's timeline
// ("razem od 1980 · ślub 1985") · AC-5 search first, then create · a wedding without a date · the
// summary (D) · the parents' wizard (P1) · roles from sex and the wedding · closing the wizard (C0).
// Made-up people only (family-data.md).

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

/// [f] inside the sheet from below (the wizard, the summary, "Dodaj dziecko") — the form under it has
/// fields and buttons of the same names ("Imiona", "Zapisz", the ♀ ♂ of 4a).
Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

Finder _sheetText(String text) => _inSheet(find.text(text));

/// The text of the sheet's field labelled [label].
String _sheetField(WidgetTester tester, String label) => tester
    .widget<TextField>(_inSheet(find.widgetWithText(TextField, label)))
    .controller!
    .text;

/// Whether the sheet's ♀ or ♂ ("Kobieta", "Mężczyzna") is checked, as the screen reader hears it.
bool? _sexChecked(WidgetTester tester, String label) => tester
    .widget<Semantics>(
      _inSheet(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
      ),
    )
    .properties
    .checked;

/// [finders] stand on the screen in this order, top to bottom.
void _expectTopToBottom(WidgetTester tester, List<Finder> finders) {
  for (int i = 1; i < finders.length; i++) {
    expect(
      tester.getTopLeft(finders[i - 1]).dy,
      lessThan(tester.getTopLeft(finders[i]).dy),
      reason: '${finders[i - 1]} should stand above ${finders[i]}',
    );
  }
}

void main() {
  late GrobingDatabase db;

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
    // 411 × 914 dp, the emulator's phone. At 360 dp the summary's foot ("Usuń związek" · "Gotowe")
    // overflows in the test font, whose every letter is 1 em wide — see the report of ISSUE-025's qa.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: GrobingTheme.dark, home: screen),
    );
  }

  Future<T> data<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  /// Someone without a grave.
  Future<int> addPerson(String given, String surname, [Sex? sex]) => db
      .into(db.persons)
      .insert(
        PersonsCompanion.insert(
          givenNames: Value(given),
          surname: Value(surname),
          sex: Value(sex),
        ),
      );

  /// A grave with Maria (♀) and Jan (♂), in that order.
  Future<({int grave, int maria, int jan})> graveOfTwo(WidgetTester tester) =>
      data(tester, () async {
        final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
        final int grave = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(
            givenNames: 'Maria',
            surname: 'Wymyślona',
            sex: Sex.female,
          ),
        );
        final int maria = (await loadGrave(db, grave))!.people.single.id;
        final int jan = await addPersonToGrave(
          db,
          graveId: grave,
          entry: const PersonEntry(
            givenNames: 'Jan',
            surname: 'Wymyślony',
            sex: Sex.male,
          ),
        );
        return (grave: grave, maria: maria, jan: jan);
      });

  /// The families [personId] is a partner in, in the order written.
  Future<List<int>> unionsOf(WidgetTester tester, int personId) =>
      data(tester, () async {
        final List<FamilyPartner> rows =
            await (db.select(db.familyPartners)
                  ..where((p) => p.personId.equals(personId))
                  ..orderBy([(p) => OrderingTerm.asc(p.familyId)]))
                .get();
        return [for (final FamilyPartner p in rows) p.familyId];
      });

  /// The events of [familyId] by type, each with the number of its claims.
  Future<Map<EventType, ({Event event, int claims})>> familyEvents(
    WidgetTester tester,
    int familyId,
  ) => data(tester, () async {
    final List<Event> events = await (db.select(
      db.events,
    )..where((e) => e.familyId.equals(familyId))).get();
    return {
      for (final Event e in events)
        e.type: (
          event: e,
          claims: (await (db.select(
            db.assertions,
          )..where((a) => a.eventId.equals(e.id))).get()).length,
        ),
    };
  });

  Future<int> count<T extends HasResultSet, R>(
    WidgetTester tester,
    ResultSetImplementation<T, R> table,
  ) => data(tester, () async => (await db.select(table).get()).length);

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
    await _pumpUntil(
      tester,
      () =>
          _shown(find.text('Dodaj partnera')) ||
          _shown(find.text('Dodaj kolejnego partnera')),
    );
  }

  /// Waits for [f] (a read, a write, a sheet opening), then for the animations.
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    await _pumpUntil(tester, () => _shown(f));
    await tester.pumpAndSettle();
  }

  /// Waits for the sheet to close — the wizard and "Dodaj dziecko" close themselves after the write.
  Future<void> sheetGone(WidgetTester tester) async {
    await _pumpUntil(tester, () => !_shown(find.byType(BottomSheet)));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, String text) =>
      tapVisible(tester, _sheetText(text));

  Future<void> typeInSheet(
    WidgetTester tester,
    Finder field,
    String text,
  ) async {
    await tester.enterText(field, text);
    await tester.pump();
  }

  /// The search of the person list, or the one date field of a date step.
  Future<void> typeInOnlyField(WidgetTester tester, String text) =>
      typeInSheet(tester, _inSheet(find.byType(TextField)), text);

  /// "Dodaj partnera" (or "Dodaj kolejnego partnera") → the list of people, loaded.
  Future<void> openPartnerWizard(
    WidgetTester tester, {
    required String waitForPerson,
    String button = 'Dodaj partnera',
  }) async {
    await tapVisible(tester, find.text(button));
    await waitFor(tester, _sheetText(waitForPerson));
  }

  testWidgets(
    'US-003 AC-1 — from the correction form: "Dodaj partnera" → the person from "W tym grobie" → '
    '"Małżeństwo" with its year → "Nic więcej — zapisz" gives the partner\'s card with "Mąż"; "Dodaj '
    'dziecko" on the card with a new person typed in the search gives the chip under it; the family, '
    'the child\'s link and the wedding are written with their claims',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);
      // 9a, empty: the header and the two ways in, no cards.
      expect(find.text('Rodzina'), findsOneWidget);
      expect(find.text('Dodaj rodziców'), findsOneWidget);
      expect(find.text('Dodaj partnera'), findsOneWidget);
      expect(find.text('Partnerzy'), findsNothing);

      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      expect(_sheetText('Dodaj partnera · krok 1 z 3'), findsOneWidget);
      expect(_sheetText('Z kim w związku?'), findsOneWidget);
      // Under the question, and her own row in the grave.
      expect(_sheetText('Maria Wymyślona'), findsNWidgets(2));
      expect(_sheetText('ta osoba'), findsOneWidget);
      expect(_sheetText('W tym grobie'), findsOneWidget);
      await tapInSheet(tester, 'Jan Wymyślony');

      // C2: two choices, no date block and no "Dalej" before one is made.
      expect(_sheetText('Jaki to był związek?'), findsOneWidget);
      expect(_sheetText('Dodaj partnera · krok 2 z 3'), findsOneWidget);
      expect(_sheetText('Maria i Jan'), findsOneWidget);
      expect(_sheetText('Dalej'), findsNothing);
      await tapInSheet(tester, 'Małżeństwo');
      expect(_sheetText('Ślub'), findsOneWidget);
      await typeInOnlyField(tester, '1950');
      expect(_sheetText('→ 1950'), findsOneWidget);
      await tapInSheet(tester, 'Dalej');

      // C3: the timeline over the question; no second wedding.
      expect(_sheetText('Co było dalej?'), findsOneWidget);
      expect(_sheetText('Dodaj partnera · krok 3 z 3'), findsOneWidget);
      expect(_sheetText('Maria i Jan · ślub 1950'), findsOneWidget);
      expect(_sheetText('Wzięli ślub'), findsNothing);
      await tapInSheet(tester, 'Nic więcej — zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('Jan Wymyślony'));
      expect(find.text('Partnerzy'), findsOneWidget);
      expect(find.text('bez dat · Mąż'), findsOneWidget);
      expect(find.text('ślub 1950'), findsOneWidget);
      expect(find.text('Dodaj partnera'), findsNothing);
      expect(find.text('Dodaj kolejnego partnera'), findsOneWidget);

      // E: "Dodaj dziecko" on the card — search first, then a new person.
      await tapVisible(tester, find.text('Dodaj dziecko'));
      await waitFor(tester, _sheetText('W tym grobie'));
      expect(_sheetText('Dziecko tej pary'), findsOneWidget);
      expect(_sheetText('Maria i Jan'), findsOneWidget);
      // The pair is in the family already.
      expect(_sheetText('już w tej rodzinie'), findsNWidgets(2));
      await typeInOnlyField(tester, 'Anna');
      expect(_sheetText('Nie ma osoby pasującej do „Anna”.'), findsOneWidget);
      await tapInSheet(tester, 'Nowa osoba: „Anna”');
      expect(_sheetText('Nowe dziecko'), findsOneWidget);
      expect(_sheetField(tester, 'Imiona'), 'Anna');
      // The suggestion: the surname of the first in the pair; the sex from "-a".
      expect(_sheetField(tester, 'Nazwisko'), 'Wymyślona');
      expect(_sexChecked(tester, 'Kobieta'), isTrue);
      expect(_sexChecked(tester, 'Mężczyzna'), isFalse);
      await tapInSheet(tester, 'Dodaj');
      await sheetGone(tester);
      await waitFor(tester, find.text('Córka: Anna'));
      expect(find.text('Dzieci z tego związku'), findsOneWidget);
      _expectTopToBottom(tester, [
        find.text('Jan Wymyślony'),
        find.text('Córka: Anna'),
        find.text('Dodaj dziecko'),
        find.text('Dodaj kolejnego partnera'),
      ]);

      await leaveScreen(tester);
      final List<int> unions = await unionsOf(tester, g.maria);
      expect(unions, hasLength(1));
      final FamilyDetail family = (await data(
        tester,
        () => loadFamily(db, unions.single),
      ))!;
      expect(family.partners.map((p) => p.id), [g.maria, g.jan]);
      expect(family.children.map((c) => (c.givenNames, c.surname, c.sex)), [
        ('Anna', 'Wymyślona', Sex.female),
      ]);
      expect(family.married, isTrue);
      expect(
        family.marriage.date,
        const QualifiedDate(DateQualifier.exact, PartialDate(1950)),
      );
      expect(family.together.date, isNull);
      expect(family.ended, isFalse);
      // Maria, Jan and the new child — no one twice (AC-5).
      expect(await count(tester, db.persons), 3);
      // The union and the child's link have their claims (AC-4, ADR-011), and so does the wedding.
      final int claims = await data(
        tester,
        () async =>
            (await (db.select(db.assertions)..where(
                      (a) =>
                          a.familyId.isNotNull() | a.familyChildId.isNotNull(),
                    ))
                    .get())
                .length,
      );
      expect(claims, 2);
      final Map<EventType, ({Event event, int claims})> events =
          await familyEvents(tester, unions.single);
      expect(events.keys, [EventType.marriage]);
      expect(events[EventType.marriage]!.claims, 1);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-003 AC-2 — "Dodaj kolejnego partnera": the first partner is "już partner tej osoby" in "Z kim?" '
    'and cannot be chosen; a second union ("Razem" 1960, "Związek się zakończył" 1965) gives a second '
    'card, and each card has its own children — a child of the first union "ma już rodziców" (D5)',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      final int anna = await data(tester, () async {
        final int anna = await addPerson('Anna', 'Zmyślona', Sex.female);
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(g.jan), ExistingMember(g.maria)],
            children: const [
              NewMember(
                givenNames: 'Kuba',
                surname: 'Wymyślony',
                sex: Sex.male,
              ),
            ],
            marriage: const QualifiedDate(
              DateQualifier.exact,
              PartialDate(1950),
            ),
          ),
        );
        return anna;
      });
      await openCorrection(tester, g.jan);
      expect(find.text('Maria Wymyślona'), findsOneWidget);
      expect(find.text('Syn: Kuba'), findsOneWidget);

      await openPartnerWizard(
        tester,
        button: 'Dodaj kolejnego partnera',
        waitForPerson: 'Anna Zmyślona',
      );
      expect(_sheetText('Kolejny partner · krok 1 z 3'), findsOneWidget);
      expect(_sheetText('już partner tej osoby'), findsOneWidget);
      expect(_sheetText('ta osoba'), findsOneWidget);
      await tapInSheet(tester, 'Maria Wymyślona');
      expect(_sheetText('Z kim w związku?'), findsOneWidget);

      await tapInSheet(tester, 'Anna Zmyślona');
      await tapInSheet(tester, 'Razem');
      expect(_sheetText('Razem od'), findsOneWidget);
      await typeInOnlyField(tester, '1960');
      await tapInSheet(tester, 'Dalej');
      expect(_sheetText('Jan i Anna · razem od 1960'), findsOneWidget);
      expect(_sheetText('Wzięli ślub'), findsOneWidget);
      await tapInSheet(tester, 'Związek się zakończył');
      expect(_sheetText('Kiedy związek się zakończył?'), findsOneWidget);
      expect(_sheetText('Koniec związku'), findsOneWidget);
      await typeInOnlyField(tester, '1965');
      await tapInSheet(tester, 'Zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('Anna Zmyślona'));
      expect(find.text('razem od 1960 · koniec 1965'), findsOneWidget);
      expect(find.text('bez dat · Partnerka'), findsOneWidget);
      expect(find.text('bez dat · Żona'), findsOneWidget);

      // "Dodaj dziecko" on the second card: the child of Jan and Anna.
      await tapVisible(tester, find.text('Dodaj dziecko').last);
      await waitFor(tester, _sheetText('Nowa osoba'));
      expect(_sheetText('Jan i Anna'), findsOneWidget);
      expect(_sheetText('już w tej rodzinie'), findsNWidgets(2));
      // D5: Kuba is a child of the first union and cannot be chosen here.
      expect(_sheetText('ma już rodziców'), findsOneWidget);
      await tapInSheet(tester, 'Kuba Wymyślony');
      expect(_sheetText('Dziecko tej pary'), findsOneWidget);
      await typeInOnlyField(tester, 'Zosia');
      await tapInSheet(tester, 'Nowa osoba: „Zosia”');
      expect(_sheetField(tester, 'Nazwisko'), 'Wymyślony');
      await tapInSheet(tester, 'Dodaj');
      await sheetGone(tester);
      await waitFor(tester, find.text('Córka: Zosia'));
      // Each card with its children: by the first date of the union, its chips under it.
      expect(find.text('Dzieci z tego związku'), findsNWidgets(2));
      _expectTopToBottom(tester, [
        find.text('Maria Wymyślona'),
        find.text('Syn: Kuba'),
        find.text('Anna Zmyślona'),
        find.text('Córka: Zosia'),
      ]);

      await leaveScreen(tester);
      final List<int> unions = await unionsOf(tester, g.jan);
      expect(unions, hasLength(2));
      final FamilyDetail first = (await data(
        tester,
        () => loadFamily(db, unions[0]),
      ))!;
      final FamilyDetail second = (await data(
        tester,
        () => loadFamily(db, unions[1]),
      ))!;
      expect(first.partners.map((p) => p.id).toSet(), {g.jan, g.maria});
      expect(first.children.map((c) => c.givenNames), ['Kuba']);
      expect(second.partners.map((p) => p.id).toSet(), {g.jan, anna});
      expect(second.children.map((c) => (c.givenNames, c.surname, c.sex)), [
        ('Zosia', 'Wymyślony', Sex.female),
      ]);
      expect(
        second.together.date,
        const QualifiedDate(DateQualifier.exact, PartialDate(1960)),
      );
      expect(second.married, isFalse);
      expect(second.ended, isTrue);
      expect(
        second.end.date,
        const QualifiedDate(DateQualifier.exact, PartialDate(1965)),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-003 AC-3, ISSUE-025 AC-3 — "Razem" 1980 → "Wzięli ślub" 1985 → "Nic więcej — zapisz": the card '
    'says "razem od 1980 · ślub 1985" and "Mąż"; a wedding before "Razem od" is refused and the step '
    'stays',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);
      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      await tapInSheet(tester, 'Jan Wymyślony');
      await tapInSheet(tester, 'Razem');
      await typeInOnlyField(tester, '1980');
      await tapInSheet(tester, 'Dalej');
      expect(_sheetText('Maria i Jan · razem od 1980'), findsOneWidget);

      await tapInSheet(tester, 'Wzięli ślub');
      expect(_sheetText('Kiedy był ślub?'), findsOneWidget);
      await typeInOnlyField(tester, '1975');
      await tapInSheet(tester, 'Dalej');
      expect(_sheetText('Ślub nie może być przed „Razem od”.'), findsOneWidget);
      expect(_sheetText('Kiedy był ślub?'), findsOneWidget);
      await typeInOnlyField(tester, '1985');
      expect(_sheetText('Ślub nie może być przed „Razem od”.'), findsNothing);
      await tapInSheet(tester, 'Dalej');

      // Back on C3, which offers no second wedding.
      expect(_sheetText('Co było dalej?'), findsOneWidget);
      expect(
        _sheetText('Maria i Jan · razem od 1980 · ślub 1985'),
        findsOneWidget,
      );
      expect(_sheetText('Wzięli ślub'), findsNothing);
      await tapInSheet(tester, 'Nic więcej — zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('razem od 1980 · ślub 1985'));
      expect(find.text('Jan Wymyślony'), findsOneWidget);
      expect(find.text('bez dat · Mąż'), findsOneWidget);

      await leaveScreen(tester);
      final int family = (await unionsOf(tester, g.maria)).single;
      final Map<EventType, ({Event event, int claims})> events =
          await familyEvents(tester, family);
      expect(events.keys.toSet(), {EventType.together, EventType.marriage});
      expect(
        QualifiedDate.ofEvent(events[EventType.together]!.event),
        const QualifiedDate(DateQualifier.exact, PartialDate(1980)),
      );
      expect(
        QualifiedDate.ofEvent(events[EventType.marriage]!.event),
        const QualifiedDate(DateQualifier.exact, PartialDate(1985)),
      );
      expect(events[EventType.together]!.claims, 1);
      expect(events[EventType.marriage]!.claims, 1);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-025 — a wedding without a date: "Małżeństwo" → "Nie znam daty" gives the card "Małżeństwo" and '
    '"Żona"; the wedding is an event without a date, and it stays when the summary adds "Razem od"',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.jan);
      await openPartnerWizard(tester, waitForPerson: 'Maria Wymyślona');
      await tapInSheet(tester, 'Maria Wymyślona');
      await tapInSheet(tester, 'Małżeństwo');
      await tapInSheet(tester, 'Nie znam daty');
      expect(_sheetText('Jan i Maria · Małżeństwo'), findsOneWidget);
      await tapInSheet(tester, 'Nic więcej — zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('Maria Wymyślona'));
      expect(find.text('Małżeństwo'), findsOneWidget);
      expect(find.text('bez dat · Żona'), findsOneWidget);

      // D: ✎ → "Razem od" 1940 → "Zapisz" → "Gotowe".
      await tapVisible(tester, find.byTooltip('Popraw związek'));
      await waitFor(tester, _sheetText('Gotowe'));
      expect(_sheetText('Jan i Maria'), findsOneWidget);
      expect(_sheetText('bez daty'), findsOneWidget);
      await tapInSheet(tester, 'Razem od');
      expect(_sheetText('Od kiedy byli razem?'), findsOneWidget);
      // "Razem od" without a date is no "Razem od".
      expect(_sheetText('Nie znam daty'), findsNothing);
      await typeInOnlyField(tester, '1940');
      await tapInSheet(tester, 'Zapisz');
      await waitFor(tester, _sheetText('Gotowe'));
      expect(_sheetText('1940'), findsOneWidget);
      expect(_sheetText('bez daty'), findsOneWidget);
      await tapInSheet(tester, 'Gotowe');
      await sheetGone(tester);
      await waitFor(tester, find.text('razem od 1940 · ślub'));
      expect(find.text('bez dat · Żona'), findsOneWidget);

      await leaveScreen(tester);
      final int family = (await unionsOf(tester, g.jan)).single;
      final Map<EventType, ({Event event, int claims})> events =
          await familyEvents(tester, family);
      expect(events.keys.toSet(), {EventType.together, EventType.marriage});
      final Event wedding = events[EventType.marriage]!.event;
      expect(
        (wedding.qualifier, wedding.year, wedding.month, wedding.day),
        (null, null, null, null),
      );
      expect(events[EventType.marriage]!.claims, 1);
      expect(
        QualifiedDate.ofEvent(events[EventType.together]!.event),
        const QualifiedDate(DateQualifier.exact, PartialDate(1940)),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D — the summary: "Razem od" added, "To nie było małżeństwo" turns "Mąż" into "Partner", ✕ takes a '
    'child out of the family; "Usuń związek" asks ("Zostaw" keeps it), then the card goes and the '
    'people stay',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await data(
        tester,
        () => saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(g.maria), ExistingMember(g.jan)],
            children: const [
              NewMember(
                givenNames: 'Kuba',
                surname: 'Wymyślony',
                sex: Sex.male,
              ),
            ],
            marriage: const QualifiedDate(
              DateQualifier.exact,
              PartialDate(1950),
            ),
          ),
        ),
      );
      await openCorrection(tester, g.maria);
      expect(find.text('bez dat · Mąż'), findsOneWidget);
      expect(find.text('Syn: Kuba'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Popraw związek'));
      await waitFor(tester, _sheetText('Gotowe'));
      expect(_sheetText('Związek'), findsOneWidget);
      expect(_sheetText('Maria i Jan'), findsOneWidget);
      expect(_sheetText('Partner'), findsOneWidget);
      expect(_sheetText('Jan Wymyślony'), findsOneWidget);
      expect(_sheetText('1950'), findsOneWidget);
      // "Razem od" and "Koniec" are empty.
      expect(_sheetText('Dodaj'), findsNWidgets(2));
      expect(_sheetText('Dzieci z tego związku'), findsOneWidget);
      expect(_sheetText('Kuba Wymyślony'), findsOneWidget);

      // "Razem od" 1945.
      await tapInSheet(tester, 'Razem od');
      await typeInOnlyField(tester, '1945');
      await tapInSheet(tester, 'Zapisz');
      await waitFor(tester, _sheetText('Gotowe'));
      expect(_sheetText('1945'), findsOneWidget);

      // "Ślub" with its date, and "To nie było małżeństwo".
      await tapInSheet(tester, 'Ślub');
      expect(_sheetText('Kiedy był ślub?'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(_inSheet(find.byType(TextField)))
            .controller!
            .text,
        '1950',
      );
      await tapInSheet(tester, 'To nie było małżeństwo');
      await waitFor(tester, _sheetText('Gotowe'));
      expect(_sheetText('1950'), findsNothing);
      expect(_sheetText('Dodaj'), findsNWidgets(2));

      // ✕ by the child: out of this family, not out of the app.
      await tapVisible(tester, _inSheet(find.byTooltip('Usuń z tej rodziny')));
      await _pumpUntil(tester, () => !_shown(_sheetText('Kuba Wymyślony')));
      await tester.pumpAndSettle();

      await tapInSheet(tester, 'Gotowe');
      await sheetGone(tester);
      await waitFor(tester, find.text('bez dat · Partner'));
      expect(find.text('razem od 1945'), findsOneWidget);
      expect(find.text('Syn: Kuba'), findsNothing);

      // "Usuń związek": the window; "Zostaw" keeps the union.
      await tapVisible(tester, find.byTooltip('Popraw związek'));
      await waitFor(tester, _sheetText('Gotowe'));
      await tapInSheet(tester, 'Usuń związek');
      expect(find.text('Usunąć związek?'), findsOneWidget);
      expect(find.textContaining('Osoby zostają w aplikacji'), findsOneWidget);
      await tester.tap(find.text('Zostaw'));
      await tester.pumpAndSettle();
      expect(find.text('Usunąć związek?'), findsNothing);
      expect(_sheetText('Gotowe'), findsOneWidget);
      await tapInSheet(tester, 'Usuń związek');
      await tester.tap(find.text('Usuń'));
      await sheetGone(tester);
      await waitFor(tester, find.text('Dodaj partnera'));
      expect(find.text('Jan Wymyślony'), findsNothing);
      expect(find.text('Partnerzy'), findsNothing);

      await leaveScreen(tester);
      expect(await count(tester, db.families), 0);
      expect(await count(tester, db.familyPartners), 0);
      expect(await count(tester, db.familyChildren), 0);
      // Maria, Jan and Kuba stay.
      expect(await count(tester, db.persons), 3);
      final int familyRows = await data(
        tester,
        () async =>
            (await (db.select(
              db.events,
            )..where((e) => e.familyId.isNotNull())).get()).length +
            (await (db.select(db.assertions)..where(
                      (a) =>
                          a.familyId.isNotNull() | a.familyChildId.isNotNull(),
                    ))
                    .get())
                .length,
      );
      expect(familyRows, 0);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-003 AC-5 — "Z kim?" searches first: the keyboard is in the search, "Nowa osoba" stands first, '
    'this grave\'s people next ("ta osoba" cannot be chosen), then the others; someone found by the '
    'search (without Polish letters) is used, not written twice',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      final int piotr = await data(
        tester,
        () => addPerson('Piotr', 'Zmyślony', Sex.male),
      );
      await openCorrection(tester, g.maria);
      await openPartnerWizard(tester, waitForPerson: 'Piotr Zmyślony');
      expect(
        tester
            .widget<EditableText>(_inSheet(find.byType(EditableText)))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(_sheetText('Szukaj osoby albo wpisz nową'), findsOneWidget);
      // Maria's name stands under the question too; her row is the last of the two.
      final Finder mariaRow = _sheetText('Maria Wymyślona').last;
      _expectTopToBottom(tester, [
        _sheetText('Z kim w związku?'),
        _sheetText('Nowa osoba'),
        _sheetText('W tym grobie'),
        mariaRow,
        _sheetText('Jan Wymyślony'),
        _sheetText('Inne osoby'),
        _sheetText('Piotr Zmyślony'),
      ]);
      expect(_sheetText('ta osoba'), findsOneWidget);
      await tapVisible(tester, mariaRow);
      expect(_sheetText('Z kim w związku?'), findsOneWidget);

      await typeInOnlyField(tester, 'zmyslony');
      expect(_sheetText('Nowa osoba: „zmyslony”'), findsOneWidget);
      expect(_sheetText('W tym grobie'), findsNothing);
      expect(_sheetText('Jan Wymyślony'), findsNothing);
      expect(_sheetText('Piotr Zmyślony'), findsOneWidget);
      await tapInSheet(tester, 'Piotr Zmyślony');
      expect(_sheetText('Maria i Piotr'), findsOneWidget);
      await tapInSheet(tester, 'Razem');
      await tapInSheet(tester, 'Nie znam daty');
      expect(_sheetText('Maria i Piotr · Razem'), findsOneWidget);
      await tapInSheet(tester, 'Nic więcej — zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('Piotr Zmyślony'));
      expect(find.text('Razem'), findsOneWidget);
      expect(find.text('bez dat · Partner'), findsOneWidget);

      await leaveScreen(tester);
      expect(await count(tester, db.persons), 3);
      final int union = (await unionsOf(tester, g.maria)).single;
      final FamilyDetail family = (await data(
        tester,
        () => loadFamily(db, union),
      ))!;
      expect(family.partners.map((p) => p.id), [g.maria, piotr]);
      expect(family.married, isFalse);
      expect(family.together.date, isNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'C1\' — an empty search keeps "Nowa osoba: „Kuba”": the new person starts from it with the keyboard '
    'in "Imiona", `next` goes to "Nazwisko" (suggested from this person), ♂ is suggested for "Kuba" (an '
    '-a exception); the saved partner has that name and sex',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);
      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      await typeInOnlyField(tester, 'Kuba');
      expect(_sheetText('Nie ma osoby pasującej do „Kuba”.'), findsOneWidget);
      await tapInSheet(tester, 'Nowa osoba: „Kuba”');

      expect(_sheetText('Nowa osoba'), findsOneWidget);
      final Finder given = _inSheet(find.widgetWithText(TextField, 'Imiona'));
      final Finder surname = _inSheet(
        find.widgetWithText(TextField, 'Nazwisko'),
      );
      expect(tester.widget<TextField>(given).controller!.text, 'Kuba');
      expect(tester.widget<TextField>(given).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(surname).controller!.text, 'Wymyślona');
      expect(_sexChecked(tester, 'Mężczyzna'), isTrue);
      expect(_sexChecked(tester, 'Kobieta'), isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(surname).focusNode!.hasFocus, isTrue);
      await typeInSheet(tester, surname, 'Wymyślony');
      await tapInSheet(tester, 'Dalej');

      expect(_sheetText('Jaki to był związek?'), findsOneWidget);
      expect(_sheetText('Maria i Kuba'), findsOneWidget);
      await tapInSheet(tester, 'Razem');
      await typeInOnlyField(tester, '1990');
      await tapInSheet(tester, 'Dalej');
      await tapInSheet(tester, 'Nic więcej — zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('Kuba Wymyślony'));
      expect(find.text('bez dat · Partner'), findsOneWidget);
      expect(find.text('razem od 1990'), findsOneWidget);

      await leaveScreen(tester);
      final List<Person> people = await data(
        tester,
        () => db.select(db.persons).get(),
      );
      expect(people, hasLength(3));
      final Person kuba = people.singleWhere((p) => p.givenNames == 'Kuba');
      expect((kuba.surname, kuba.sex), ('Wymyślony', Sex.male));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'P1 — "Dodaj rodziców": "Nowa osoba" as the mother is ♀ before any name is typed; "Zofia" → "Dalej" '
    '→ the father\'s new person is ♂; back, and "Nie wiem — zapisz" writes the mother and the child at '
    'once: the chip "Matka: Zofia", and "Dodaj rodziców" goes; the parents\' summary says "Mama" and has '
    'no ✕ by "ta osoba"',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);
      await tapVisible(tester, find.text('Dodaj rodziców'));
      await waitFor(tester, _sheetText('Jan Wymyślony'));
      expect(_sheetText('Dodaj rodziców · krok 1 z 4'), findsOneWidget);
      expect(_sheetText('Kto jest mamą?'), findsOneWidget);
      expect(_sheetText('Nie wiem'), findsOneWidget);

      await tapInSheet(tester, 'Nowa osoba');
      expect(_sheetText('Nowa osoba — mama'), findsOneWidget);
      expect(_sheetField(tester, 'Imiona'), '');
      // Preset, not suggested: there is no name to suggest from yet.
      expect(_sexChecked(tester, 'Kobieta'), isTrue);
      await typeInSheet(
        tester,
        _inSheet(find.widgetWithText(TextField, 'Imiona')),
        'Zofia',
      );
      expect(_sexChecked(tester, 'Kobieta'), isTrue);
      expect(_sheetField(tester, 'Nazwisko'), 'Wymyślona');
      await tapInSheet(tester, 'Dalej');

      expect(_sheetText('Kto jest tatą?'), findsOneWidget);
      expect(_sheetText('Dodaj rodziców · krok 2 z 4'), findsOneWidget);
      expect(_sheetText('Mama: Zofia'), findsOneWidget);
      await waitFor(tester, _sheetText('Nowa osoba'));
      await tapInSheet(tester, 'Nowa osoba');
      expect(_sheetText('Nowa osoba — tata'), findsOneWidget);
      expect(_sexChecked(tester, 'Mężczyzna'), isTrue);
      expect(_sexChecked(tester, 'Kobieta'), isFalse);
      await tapVisible(tester, _inSheet(find.byTooltip('Wstecz')));
      await waitFor(tester, _sheetText('Nie wiem — zapisz'));
      expect(_sheetText('Kto jest tatą?'), findsOneWidget);
      await tapInSheet(tester, 'Nie wiem — zapisz');
      await sheetGone(tester);
      await waitFor(tester, find.text('Matka: Zofia'));
      expect(find.text('Rodzice'), findsOneWidget);
      expect(find.text('Dodaj rodziców'), findsNothing);

      // D for the parents: "Mama" from her sex, the second parent to add, and no ✕ by "ta osoba".
      await tapVisible(tester, find.byTooltip('Popraw związek rodziców'));
      await waitFor(tester, _sheetText('Gotowe'));
      expect(_sheetText('Związek rodziców'), findsOneWidget);
      expect(_sheetText('Mama'), findsOneWidget);
      expect(_sheetText('Zofia Wymyślona'), findsOneWidget);
      expect(_sheetText('Rodzic'), findsOneWidget);
      expect(_sheetText('Maria Wymyślona · ta osoba'), findsOneWidget);
      expect(_inSheet(find.byTooltip('Usuń z tej rodziny')), findsNothing);
      await tapInSheet(tester, 'Gotowe');
      await sheetGone(tester);

      await leaveScreen(tester);
      final PersonRelations r = await data(
        tester,
        () => loadRelations(db, g.maria),
      );
      expect(r.parents.map((p) => (p.givenNames, p.surname, p.sex)), [
        ('Zofia', 'Wymyślona', Sex.female),
      ]);
      expect(r.unions, isEmpty);
      final FamilyDetail parents = (await data(
        tester,
        () => loadFamily(db, r.parentsFamilyId!),
      ))!;
      expect(parents.children.map((c) => c.id), [g.maria]);
      expect(parents.married, isFalse);
      // Maria, Jan and the mother — no father written.
      expect(await count(tester, db.persons), 3);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'P1 — "Nie wiem" for the mother → "Kto jest tatą?" is "krok 2 z 2", and choosing him writes the '
    'father and the child at once: no union to tell with one parent (rodzina.md C-r2; ui review)',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);
      await tapVisible(tester, find.text('Dodaj rodziców'));
      await waitFor(tester, _sheetText('Jan Wymyślony'));
      await tapInSheet(tester, 'Nie wiem');
      expect(_sheetText('Kto jest tatą?'), findsOneWidget);
      expect(_sheetText('Dodaj rodziców · krok 2 z 2'), findsOneWidget);
      expect(_sheetText('Nie wiem — zapisz'), findsNothing);
      await waitFor(tester, _sheetText('Jan Wymyślony'));
      await tapInSheet(tester, 'Jan Wymyślony');
      await sheetGone(tester);
      await waitFor(tester, find.text('Rodzice'));
      expect(find.text('Jaki to był związek?'), findsNothing);
      expect(find.text('Dodaj rodziców'), findsNothing);

      await leaveScreen(tester);
      final PersonRelations r = await data(
        tester,
        () => loadRelations(db, g.maria),
      );
      expect(r.parents.map((p) => p.id), [g.jan]);
      final FamilyDetail parents = (await data(
        tester,
        () => loadFamily(db, r.parentsFamilyId!),
      ))!;
      expect(parents.children.map((c) => c.id), [g.maria]);
      expect(parents.married, isFalse);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'Role names — from sex and the wedding: "Matka", "Mąż", "Syn", "Córka"; without a sex the neutral '
    '"Rodzic", "Małżonek", "Partner", "Dziecko"; cards by the union\'s first date; a chip opens the '
    'relative\'s entry, whose section says "Ojciec" and "Matka"',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await data(tester, () async {
        final int zofia = await addPerson('Zofia', 'Wymyślona', Sex.female);
        final int kim = await addPerson('Kim', 'Wymyślone');
        final int alex = await addPerson('Alex', 'Testowe');
        final int sam = await addPerson('Sam', 'Przykładowe');
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(zofia), ExistingMember(kim)],
            children: [ExistingMember(g.maria)],
            marriage: const QualifiedDate(
              DateQualifier.about,
              PartialDate(1920),
            ),
          ),
        );
        // Written in this order; the one with a date comes first on the screen.
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(g.maria), ExistingMember(sam)],
            children: const [],
          ),
        );
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(g.maria), ExistingMember(alex)],
            children: const [],
            married: true,
          ),
        );
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(g.maria), ExistingMember(g.jan)],
            children: const [
              NewMember(
                givenNames: 'Kuba',
                surname: 'Wymyślony',
                sex: Sex.male,
              ),
              NewMember(
                givenNames: 'Anna',
                surname: 'Wymyślona',
                sex: Sex.female,
              ),
              NewMember(givenNames: 'Robin', surname: 'Wymyślone'),
            ],
            marriage: const QualifiedDate(
              DateQualifier.exact,
              PartialDate(1950),
            ),
          ),
        );
      });
      await openCorrection(tester, g.maria);
      await waitFor(tester, find.text('Matka: Zofia'));
      expect(find.text('Rodzice · ślub ok. 1920'), findsOneWidget);
      expect(find.byTooltip('Popraw związek rodziców'), findsOneWidget);
      expect(find.text('Rodzic: Kim'), findsOneWidget);
      expect(find.text('Dodaj rodziców'), findsNothing);

      expect(find.text('bez dat · Mąż'), findsOneWidget);
      expect(find.text('bez dat · Małżonek'), findsOneWidget);
      expect(find.text('bez dat · Partner'), findsOneWidget);
      expect(find.text('ślub 1950'), findsOneWidget);
      expect(find.text('Małżeństwo'), findsOneWidget);
      expect(find.text('Razem'), findsOneWidget);
      expect(find.byTooltip('Popraw związek'), findsNWidgets(3));
      expect(find.text('Syn: Kuba'), findsOneWidget);
      expect(find.text('Córka: Anna'), findsOneWidget);
      expect(find.text('Dziecko: Robin'), findsOneWidget);
      expect(find.text('Dodaj kolejnego partnera'), findsOneWidget);
      // By the union's first date; those without one last, in the order written.
      _expectTopToBottom(tester, [
        find.text('Jan Wymyślony'),
        find.text('Syn: Kuba'),
        find.text('Sam Przykładowe'),
        find.text('Alex Testowe'),
      ]);

      // A chip opens the relative's entry over this form.
      await tapVisible(tester, find.text('Syn: Kuba'));
      await waitFor(tester, find.text('Ojciec: Jan'));
      expect(find.text('Matka: Maria'), findsOneWidget);
      expect(find.text('Rodzice · ślub 1950'), findsOneWidget);
      expect(find.text('bez grobu w aplikacji'), findsOneWidget);
      expect(find.text('Dodaj rodziców'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'C0 — ← and ✕ on the first step close at once; ← goes a step back; after the first step ✕ asks '
    '"Przerwać dodawanie?": "Wróć" stays on the step, "Przerwij" closes and writes nothing',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);

      // Step 1: ← closes without asking (ui review: ← on every step, C0) — and so does ✕.
      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      await tapVisible(tester, _inSheet(find.byTooltip('Wstecz')));
      expect(find.text('Przerwać dodawanie?'), findsNothing);
      await sheetGone(tester);
      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      await tapVisible(tester, _inSheet(find.byTooltip('Zamknij')));
      expect(find.text('Przerwać dodawanie?'), findsNothing);
      await sheetGone(tester);

      // Step 2: ← back to step 1.
      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      await tapInSheet(tester, 'Jan Wymyślony');
      expect(_sheetText('Jaki to był związek?'), findsOneWidget);
      await tapVisible(tester, _inSheet(find.byTooltip('Wstecz')));
      await waitFor(tester, _sheetText('Jan Wymyślony'));
      expect(_sheetText('Z kim w związku?'), findsOneWidget);

      // Step 2 with a date typed: ✕ asks.
      await tapInSheet(tester, 'Jan Wymyślony');
      await tapInSheet(tester, 'Małżeństwo');
      await typeInOnlyField(tester, '1950');
      await tapVisible(tester, _inSheet(find.byTooltip('Zamknij')));
      expect(find.text('Przerwać dodawanie?'), findsOneWidget);
      expect(find.text('To, co podałeś, nie zapisze się.'), findsOneWidget);
      await tester.tap(find.text('Wróć'));
      await tester.pumpAndSettle();
      expect(find.text('Przerwać dodawanie?'), findsNothing);
      expect(_sheetText('Jaki to był związek?'), findsOneWidget);
      expect(_sheetText('→ 1950'), findsOneWidget);

      await tapVisible(tester, _inSheet(find.byTooltip('Zamknij')));
      await tester.tap(find.text('Przerwij'));
      await sheetGone(tester);
      expect(find.text('Partnerzy'), findsNothing);
      expect(find.text('Dodaj partnera'), findsOneWidget);

      await leaveScreen(tester);
      expect(await count(tester, db.families), 0);
      expect(await count(tester, db.persons), 2);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'C0 — the sheet stands in one place: the same top on every step, and the keyboard shrinks what is '
    'inside it, never moves it (the author at stop #2 of ISSUE-025)',
    (tester) async {
      final ({int grave, int maria, int jan}) g = await graveOfTwo(tester);
      await openCorrection(tester, g.maria);
      await openPartnerWizard(tester, waitForPerson: 'Jan Wymyślony');
      double top() => tester.getTopLeft(find.byType(BottomSheet)).dy;
      final double first = top();

      await tapInSheet(tester, 'Jan Wymyślony');
      expect(_sheetText('Jaki to był związek?'), findsOneWidget);
      expect(top(), first, reason: 'the next step, no keyboard');

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(top(), first, reason: 'the keyboard up');
      // The step's buttons stay above it once the date is asked for.
      await tapInSheet(tester, 'Małżeństwo');
      expect(top(), first);
      expect(_inSheet(find.text('Dalej')), findsOneWidget);
      final double keyboardTop =
          tester.view.physicalSize.height / 2.625 - 900 / 2.625;
      expect(
        tester.getBottomLeft(_inSheet(find.text('Dalej'))).dy,
        lessThanOrEqualTo(keyboardTop),
      );

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(top(), first, reason: 'the keyboard down');
      await tapVisible(tester, _inSheet(find.byTooltip('Zamknij')));
      await tapVisible(tester, find.text('Przerwij'));
      await sheetGone(tester);
      await cleanUp(tester);
    },
  );

  testWidgets('a new person has no "Rodzina" yet (rodzina.md D2)', (
    tester,
  ) async {
    final int cemetery = await data(
      tester,
      () => addCemetery(db, name: 'Cmentarz Wymyślony'),
    );
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
    expect(find.text('Dodaj partnera'), findsNothing);
    expect(find.text('Dodaj rodziców'), findsNothing);
    await cleanUp(tester);
  });
}
