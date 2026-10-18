import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/person/place_picker_screen.dart';
import 'package:grobing/app/person/residence_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/glyphs.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/places.dart';
import 'package:grobing/data/residences.dart';

import '../../support/a11y.dart';
import '../../support/glyphs.dart';
import '../../support/photo_fakes.dart';
import '../../support/place_fakes.dart';

// ISSUE-042 — places of residence on the screens (05_DESIGN/zamieszkanie.md v1; osoba.md 9a, wpis-osoby.md 9b),
// happy path per AC: AC-1 only a country with "około" years, through the form, the window and the choice, to
// the stored row · AC-2 the same residence made a locality, then an address — still one · AC-3 the choice
// from the list in the app (a made-up list, test/support/place_fakes.dart) · D5 written with "Zapisz", a
// removal only then, "Odrzucić wpis?" counts the residences · States: the window's errors, a country hides
// the address, ✕ with changes asks; the choice without text, with results, without any · 9a the view's rows
// and the empty state · retro 3 R2 tap targets and buttons with a tap action · text 200% at 360 dp.
// Made-up people and places only (family-data.md).

const String _nb = '\u00A0';

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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

bool _shown(Finder f) => f.evaluate().isNotEmpty;

const ResidencePlace _country = ResidencePlace.country(
  countryCode: 'XA',
  countryName: 'Kraj Wymyślony',
  point: GeoPoint(49.5, 31.5),
);

const ResidencePlace _zmyslin = ResidencePlace.locality(
  name: 'Zmyślin',
  unit: 'woj. testowe',
  countryCode: 'XB',
  countryName: 'Kraj Przykładowy',
  point: GeoPoint(51.25, 22.5),
  geonamesId: 9000001,
);

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late PlaceList places;
  late int jan;
  final GlobalKey<NavigatorState> navigator = GlobalKey();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_residences');
    db = GrobingDatabase(NativeDatabase.memory());
    places = PlaceList.openFile(
      writeFakePlaceList(tmp, countries: fakeCountries, places: fakePlaces),
    );
  });

  tearDown(() {
    places.close();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still open on Windows; the system cleans the temp directory.
    }
  });

  Future<T> data<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  /// Jan in a grave, with [residences] written.
  Future<void> withJan(
    WidgetTester tester, [
    List<Residence> residences = const [],
  ]) => data(tester, () async {
    final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    final int grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Anna', surname: 'Testowa'),
    );
    jan = await addPersonToGrave(
      db,
      graveId: grave,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
    await writeResidences(db, jan, residences);
  });

  Future<List<ResidenceRow>> stored(WidgetTester tester) => data(
    tester,
    () => (db.select(
      db.residences,
    )..orderBy([(r) => OrderingTerm.asc(r.id)])).get(),
  );

  /// The phone of the emulator (411 dp), or 360 dp with [textScale].
  void phone(WidgetTester tester, {double width = 411}) {
    tester.view.physicalSize = Size(width * 2.625, 914 * 2.625);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {double textScale = 1}) => MaterialApp(
    navigatorKey: navigator,
    theme: GrobingTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );

  /// Jan's correction pushed over a plain screen, so "Zapisz" has where to return.
  Future<void> openCorrection(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    final ({
      BuriedPerson person,
      int? graveId,
      String? graveTitle,
      int peopleCount,
    })?
    found = await data(tester, () => loadPersonForCorrection(db, jan));
    await tester.pumpWidget(
      app(const Scaffold(body: Text('pod spodem')), textScale: textScale),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => PersonFormScreen(
          database: db,
          mode: Correction(
            person: found!.person,
            graveTitle: found.graveTitle,
            peopleCount: found.peopleCount,
            graveId: found.graveId,
          ),
          places: Future.value(places),
        ),
      ),
    );
    await _pumpUntil(tester, () => _shown(find.text('Miejsca zamieszkania')));
    await _settle(tester);
  }

  Future<void> tapScrolled(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await _settle(tester);
    await tester.tap(f);
    await _settle(tester);
  }

  /// The window's date fields in their order: "Od", then "Do".
  Finder dateField(int i) => find.byType(TextField).at(i);

  Future<void> chooseQualifier(WidgetTester tester, int block) async {
    await tester.tap(find.text('dokładnie').at(block));
    await _settle(tester);
    // D3: a period's ends are exact or about — never "przed", "po", "między".
    final Finder items = find.byType(MenuItemButton);
    expect(items, findsNWidgets(2));
    expect(find.text('przed'), findsNothing);
    expect(find.text('między'), findsNothing);
    await tester.tap(find.descendant(of: items, matching: find.text('około')));
    await _settle(tester);
  }

  testWidgets(
    'AC-1 — "Dodaj miejsce" → "około 1930", "około 1945" → the choice → a country, "cały kraj" → "Gotowe" → '
    'the card → "Zapisz": one row at the level "country" with the country\'s point',
    (tester) async {
      phone(tester);
      await withJan(tester);
      await openCorrection(tester);

      await tapScrolled(tester, find.text('Dodaj miejsce'));
      expect(find.text('Miejsce zamieszkania'), findsOneWidget);
      expect(find.text('Usuń to miejsce'), findsNothing); // a new one
      await chooseQualifier(tester, 0);
      await tester.enterText(dateField(0), '1930');
      await chooseQualifier(
        tester,
        0,
      ); // the first left with "dokładnie" is now "Do"
      await tester.enterText(dateField(1), '1945');
      await _settle(tester);
      expect(find.text('→ ok.${_nb}1930$_nb– ok.${_nb}1945'), findsOneWidget);

      await tapScrolled(tester, find.text('Wybierz kraj albo miejscowość'));
      expect(find.byType(PlacePickerScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'kraj w');
      await _settle(tester);
      // v1.1, D8: from 3 letters a country whose name starts with the text stands on top, without a header.
      expect(find.text('Kraje'), findsNothing);
      await tester.tap(find.text('Kraj Wymyślony'));
      await _settle(tester);

      expect(find.text('Kraj Wymyślony ·${_nb}cały kraj'), findsOneWidget);
      expect(find.text('Adres'), findsNothing); // an address needs a locality
      await tester.tap(find.text('Gotowe'));
      await _settle(tester);
      expect(find.text('ok.${_nb}1930$_nb– ok.${_nb}1945'), findsOneWidget);
      expect(find.text('Kraj Wymyślony ·${_nb}cały kraj'), findsOneWidget);
      expect(await stored(tester), isEmpty); // written only with "Zapisz" (D5)

      await tapScrolled(tester, find.text('Zapisz'));
      await _pumpUntil(tester, () => _shown(find.text('pod spodem')));
      final ResidenceRow r = (await stored(tester)).single;
      expect(
        (
          r.personId,
          r.level,
          r.placeName,
          r.countryCode,
          r.lat,
          r.lon,
          r.fromQualifier,
          r.fromYear,
          r.toQualifier,
          r.toYear,
        ),
        (
          jan,
          PlaceLevel.country,
          'Kraj Wymyślony',
          'XA',
          49.5,
          31.5,
          DateQualifier.about,
          1930,
          DateQualifier.about,
          1945,
        ),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 — ✎ on the card → the window with its values → the choice: "Ostatnio wybrane", then a locality told '
    'apart by its unit → an address → "Zapisz": still one row, now an address with the locality\'s point',
    (tester) async {
      phone(tester);
      await withJan(tester, [
        const Residence(
          from: QualifiedDate(DateQualifier.about, PartialDate(1930)),
          to: QualifiedDate(DateQualifier.about, PartialDate(1945)),
          place: _country,
        ),
      ]);
      final int id = (await stored(tester)).single.id;
      await openCorrection(tester);

      await tapScrolled(tester, find.byTooltip('Popraw miejsce'));
      expect(find.text('1930'), findsOneWidget);
      expect(find.text('Usuń to miejsce'), findsOneWidget);
      await tapScrolled(tester, find.text('Kraj Wymyślony ·${_nb}cały kraj'));
      // Element 18: the places chosen lately, before any text.
      await _pumpUntil(tester, () => _shown(find.text('Ostatnio wybrane')));
      expect(find.text('Kraj Wymyślony'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zmys');
      await _settle(tester);
      // Element 19: two of the same name, told apart by the unit and the country.
      expect(find.text('woj. testowe ·${_nb}Kraj Przykładowy'), findsWidgets);
      expect(
        find.text('obw. przykładowy ·${_nb}Kraj Wymyślony'),
        findsOneWidget,
      );
      await tester.tap(find.text('Zmyślin').first);
      await _settle(tester);

      expect(find.text('Zmyślin ·${_nb}Kraj Przykładowy'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Adres'),
        'ul. Przykładowa 3',
      );
      await tester.tap(find.text('Gotowe'));
      await _settle(tester);
      expect(find.byTooltip('Popraw miejsce'), findsOneWidget); // one card
      expect(
        find.text('ul. Przykładowa 3, Zmyślin, Kraj Przykładowy'),
        findsOneWidget,
      );

      await tapScrolled(tester, find.text('Zapisz'));
      await _pumpUntil(tester, () => _shown(find.text('pod spodem')));
      final ResidenceRow r = (await stored(tester)).single;
      expect(
        (r.id, r.level, r.placeName, r.geonamesId, r.lat, r.lon, r.address),
        (
          id,
          PlaceLevel.address,
          'Zmyślin',
          9000001,
          51.25,
          22.5,
          'ul. Przykładowa 3',
        ),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'the window\'s errors — "Wybierz miejsce." and "Koniec nie może być przed początkiem." with their icon; '
    '✕ with something typed asks "Odrzucić zmiany?", "Wróć" stays',
    (tester) async {
      phone(tester);
      await withJan(tester);
      await openCorrection(tester);
      await tapScrolled(tester, find.text('Dodaj miejsce'));

      await tester.tap(find.text('Gotowe'));
      await _settle(tester);
      expect(find.text('Wybierz miejsce.'), findsOneWidget);
      await tester.enterText(dateField(0), '1950');
      await tester.enterText(dateField(1), '1940');
      await tester.tap(find.text('Gotowe'));
      await _settle(tester);
      expect(
        find.text('Koniec nie może być przed początkiem.'),
        findsOneWidget,
      );
      expect(findGlyph(Glyphs.error), findsNWidgets(2));
      expect(find.text('Miejsce zamieszkania'), findsOneWidget); // not closed

      await tester.tap(find.byTooltip('Zamknij'));
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć'));
      await _settle(tester);
      expect(find.text('Miejsce zamieszkania'), findsOneWidget);
      await tester.tap(find.byTooltip('Zamknij'));
      await _settle(tester);
      await tester.tap(find.text('Odrzuć'));
      await _settle(tester);
      expect(find.text('Miejsce zamieszkania'), findsNothing); // closed
      expect(find.text('Miejsca zamieszkania'), findsOneWidget); // the form's
      expect(find.byTooltip('Popraw miejsce'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D5 — "Usuń to miejsce" asks first and takes the card off the form only; leaving the form asks "Odrzucić '
    'wpis?", and "Odrzuć" leaves both rows stored',
    (tester) async {
      phone(tester);
      await withJan(tester, [
        const Residence(
          from: QualifiedDate(DateQualifier.exact, PartialDate(1946)),
          place: _zmyslin,
        ),
        const Residence(place: _country),
      ]);
      await openCorrection(tester);
      // D4: with years first, without them at the end — "Bez lat" on the card.
      expect(find.text('od${_nb}1946'), findsOneWidget);
      expect(find.text('Bez lat'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('od${_nb}1946')).dy,
        lessThan(tester.getTopLeft(find.text('Bez lat')).dy),
      );

      await tapScrolled(tester, find.byTooltip('Popraw miejsce').last);
      await tester.tap(find.text('Usuń to miejsce'));
      await _settle(tester);
      expect(find.text('Usunąć to miejsce zamieszkania?'), findsOneWidget);
      await tester.tap(find.text('Usuń'));
      await _settle(tester);
      expect(find.text('Bez lat'), findsNothing);
      expect(find.byTooltip('Popraw miejsce'), findsOneWidget);
      expect(await stored(tester), hasLength(2));

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(find.text('Odrzucić wpis?'), findsOneWidget);
      await tester.tap(find.text('Odrzuć'));
      await _pumpUntil(tester, () => _shown(find.text('pod spodem')));
      expect(await stored(tester), hasLength(2));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'the choice (B) — without text and without places chosen: the hint alone and the source; nothing found: '
    'element 21; the countries under the localities; back returns nothing',
    (tester) async {
      phone(tester);
      ResidencePlace? chosen;
      bool returned = false;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await Navigator.of(context).push<ResidencePlace>(
                  MaterialPageRoute(
                    builder: (_) => PlacePickerScreen(
                      recent: Future.value(const []),
                      places: Future.value(places),
                    ),
                  ),
                );
                returned = true;
              },
              child: const Text('wybierz'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('wybierz'));
      await _settle(tester);

      expect(find.text('Ostatnio wybrane'), findsNothing);
      expect(
        find.text('Lista miejsc: GeoNames (CC BY 4.0) ·${_nb}Natural Earth'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'qqx');
      await _settle(tester);
      expect(
        find.text(
          'Nie ma na liście? Wybierz kraj i${_nb}wpisz nazwę w$_nb„Nazwa z${_nb}tamtego czasu”.',
        ),
        findsOneWidget,
      );
      // v1.1, D8 — 3 letters: the country whose name starts with them over the localities, without a header;
      // one matched by a later word under them, under "Kraje".
      await tester.enterText(find.byType(TextField), 'wym');
      await _settle(tester);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Wymyślonia'), lessThan(top('Wymyślowo')));
      expect(top('Wymyślowo'), lessThan(top('Kraje')));
      expect(top('Kraje'), lessThan(top('Kraj Wymyślony')));
      // 2 letters: every country under the localities.
      await tester.enterText(find.byType(TextField), 'wy');
      await _settle(tester);
      expect(top('Wymyślowo'), lessThan(top('Kraje')));
      expect(top('Kraje'), lessThan(top('Wymyślonia')));
      expect(top('Wymyślonia'), lessThan(top('Kraj Wymyślony')));

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect((returned, chosen), (true, null));
    },
  );

  testWidgets(
    '9a — the view: rows in the order of the years, the country "cały kraj — miejscowość nieznana", the name of '
    'the time with "dziś: …", the address over its country; a row without years last; no action, a screen '
    'reader hears years and place',
    (tester) async {
      phone(tester);
      await withJan(tester, [
        const Residence(place: _country, nameThen: 'Kraj Dawny'),
        const Residence(
          from: QualifiedDate(DateQualifier.exact, PartialDate(1946)),
          to: QualifiedDate(DateQualifier.exact, PartialDate(1978)),
          place: _zmyslin,
          address: 'ul. Przykładowa 3',
        ),
        const Residence(
          to: QualifiedDate(DateQualifier.about, PartialDate(1925)),
          place: _country,
        ),
        const Residence(
          from: QualifiedDate(DateQualifier.about, PartialDate(1925)),
          to: QualifiedDate(DateQualifier.exact, PartialDate(1945)),
          place: _zmyslin,
          nameThen: 'Zmyślin, Kraj Dawny',
        ),
      ]);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(PersonScreen(database: db, personId: jan)));
      await _pumpUntil(tester, () => _shown(find.text('Miejsca zamieszkania')));
      await _settle(tester);
      await tester.ensureVisible(find.text('Miejsca zamieszkania'));
      await _settle(tester);

      final List<Finder> rows = [
        find.text('do${_nb}ok.${_nb}1925'),
        find.text('ok.${_nb}1925$_nb– 1945'),
        find.text('1946–1978'),
        find.text('Kraj Dawny'),
      ];
      for (int i = 1; i < rows.length; i++) {
        expect(
          tester.getTopLeft(rows[i - 1]).dy,
          lessThan(tester.getTopLeft(rows[i]).dy),
        );
      }
      expect(find.text('cały kraj — miejscowość nieznana'), findsOneWidget);
      expect(find.text('Zmyślin, Kraj Dawny'), findsOneWidget);
      expect(find.text('dziś:${_nb}Zmyślin, Kraj Przykładowy'), findsOneWidget);
      expect(find.text('ul. Przykładowa 3, Zmyślin'), findsOneWidget);
      expect(
        find.text('dziś:${_nb}Kraj Wymyślony — cały kraj'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'ok.${_nb}1925$_nb– 1945: Zmyślin, Kraj Dawny, dziś Zmyślin, Kraj Przykładowy',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'bez lat: Kraj Dawny, dziś Kraj Wymyślony — cały kraj',
        ),
        findsOneWidget,
      );
      expect(find.text('Nie ma jeszcze zapisanych miejsc.'), findsNothing);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    '9a — without places: "Nie ma jeszcze zapisanych miejsc." and "Dodaj miejsce", which opens the correction '
    'with the window over it at once',
    (tester) async {
      phone(tester);
      await withJan(tester);
      await tester.pumpWidget(app(PersonScreen(database: db, personId: jan)));
      await _pumpUntil(tester, () => _shown(find.text('Miejsca zamieszkania')));
      await _settle(tester);

      expect(find.text('Nie ma jeszcze zapisanych miejsc.'), findsOneWidget);
      await tapScrolled(tester, find.text('Dodaj miejsce'));
      await _pumpUntil(tester, () => _shown(find.text('Gotowe')));
      expect(find.text('Od'), findsOneWidget);
      expect(find.text('Wybierz kraj albo miejscowość'), findsOneWidget);
      await tester.tap(find.byTooltip('Zamknij'));
      await _settle(tester);
      expect(find.text('Poprawa wpisu'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'retro 3 R2 — the window, the choice, the form\'s section and the view\'s: tap targets of 48 dp, each with '
    'a label, and every button has a tap action',
    (tester) async {
      phone(tester);
      await withJan(tester, [
        const Residence(
          from: QualifiedDate(DateQualifier.exact, PartialDate(1946)),
          place: _zmyslin,
        ),
      ]);
      final SemanticsHandle semantics = tester.ensureSemantics();
      Future<void> check() async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expectEveryButtonTappable(tester);
      }

      // With photos, as in the app: without them "Dodaj zdjęcie" is disabled (only in tests of other features).
      await tester.pumpWidget(
        app(PersonScreen(database: db, personId: jan, photos: fakePhotos(tmp))),
      );
      await _pumpUntil(tester, () => _shown(find.text('Miejsca zamieszkania')));
      await _settle(tester);
      await tester.ensureVisible(find.text('Miejsca zamieszkania'));
      await _settle(tester);
      await check();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      await openCorrection(tester);
      // The wreath's row (ISSUE-044) first, whole: at the end of the form its button stood 2 dp under the top
      // edge, and a target cut by the edge is under 48 dp for the guideline. Then the section, if it is not
      // on the screen already.
      await tester.ensureVisible(find.text('Dodaj miejsce'));
      await _settle(tester);
      // At the end of the form the wreath's button stands 2 dp past the top edge; 6 dp back down shows it whole,
      // and the section stays on the screen above the list's bottom padding.
      await tester.drag(
        find
            .ancestor(
              of: find.text('Dodaj miejsce'),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 6),
      );
      await _settle(tester);
      await check();
      await tapScrolled(tester, find.byTooltip('Popraw miejsce'));
      await check();
      await tapScrolled(tester, find.text('Zmyślin ·${_nb}Kraj Przykładowy'));
      await tester.enterText(find.byType(TextField), 'zmys');
      await _settle(tester);
      await check();
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'text 200% at 360 dp: the view\'s rows, the cards, the window and the choice lay out without an overflow',
    (tester) async {
      phone(tester, width: 360);
      await withJan(tester, [
        const Residence(
          from: QualifiedDate(DateQualifier.about, PartialDate(1930)),
          to: QualifiedDate(DateQualifier.about, PartialDate(1945)),
          place: _zmyslin,
          nameThen: 'Zmyślin, Kraj Dawny',
          address: 'ul. Przykładowa 3',
        ),
        const Residence(place: _country),
      ]);

      // The bottom bar's labels overflow in the test font, every letter 1 em wide — on the emulator at 200%
      // they fit (ISSUE-042 → Verification). Any other overflow fails the test.
      final List<String> overflows = [];
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (!details.toString().contains('lib/app/tabs.dart')) {
          overflows.add(details.exceptionAsString());
        }
      };
      try {
        await tester.pumpWidget(
          app(PersonScreen(database: db, personId: jan), textScale: 2),
        );
        await _pumpUntil(tester, () => _shown(find.text('Rodzina')));
        await tester.scrollUntilVisible(
          find.text('Kraj Wymyślony'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        // Large text puts the years over the place, as the rows of "Daty" (osoba.md v2.2).
        expect(
          tester.getTopLeft(find.text('ok.${_nb}1930$_nb– ok.${_nb}1945')).dy,
          lessThan(
            tester
                .getTopLeft(find.text('ul. Przykładowa 3, Zmyślin, Kraj Dawny'))
                .dy,
          ),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        FlutterError.onError = previous;
      }
      expect(overflows, isEmpty);

      await openCorrection(tester, textScale: 2);
      await tester.ensureVisible(find.text('Dodaj miejsce'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tapScrolled(tester, find.byTooltip('Popraw miejsce').first);
      expect(tester.takeException(), isNull);
      await tapScrolled(tester, find.text('Zmyślin ·${_nb}Kraj Przykładowy'));
      await tester.enterText(find.byType(TextField), 'zmys');
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Testowo-Zmyślin'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'v1.2 D12 — "od 2024" then "od 2026": the view and the card read "2024–2026" and "od 2026" (a move, not two '
    'homes); the window leaves "Do" empty and says what empty means; nothing written for it',
    (tester) async {
      phone(tester);
      await withJan(tester, [
        const Residence(
          from: QualifiedDate(DateQualifier.exact, PartialDate(2024)),
          place: _country,
        ),
        const Residence(
          from: QualifiedDate(DateQualifier.exact, PartialDate(2026)),
          place: _zmyslin,
        ),
      ]);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(PersonScreen(database: db, personId: jan)));
      await _pumpUntil(tester, () => _shown(find.text('Miejsca zamieszkania')));
      await _settle(tester);
      await tester.ensureVisible(find.text('Miejsca zamieszkania'));
      await _settle(tester);
      expect(find.text('2024–2026'), findsOneWidget);
      expect(find.text('od${_nb}2026'), findsOneWidget);
      expect(find.text('od${_nb}2024'), findsNothing);
      expect(
        find.bySemanticsLabel(
          '2024–2026: Kraj Wymyślony, cały kraj — miejscowość nieznana',
        ),
        findsOneWidget,
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      await openCorrection(tester);
      expect(find.text('2024–2026'), findsOneWidget);
      expect(find.text('od${_nb}2026'), findsOneWidget);
      await tapScrolled(tester, find.byTooltip('Popraw miejsce').first);
      expect(find.text('2024'), findsOneWidget); // "Od" as typed
      expect(find.text('2026'), findsNothing); // "Do" stays empty
      expect(
        find.text('Puste — do początku następnego miejsca.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Zamknij'));
      await _settle(tester);
      expect((await stored(tester)).map((r) => (r.fromYear, r.toYear)), [
        (2024, null),
        (2026, null),
      ]);
      await cleanUp(tester);
    },
  );

  test(
    'element 6 (v1.1, D10) — the card\'s line: the country alone after "dziś" only when the part of the name of '
    'the time before its first comma is today\'s name; "dziś" holds to the name, a line breaks before "·"',
    () {
      String line(String? then, {String? address}) => residenceCardLine(
        Residence(place: _zmyslin, nameThen: then, address: address),
      );

      expect(line(null), 'Zmyślin, Kraj Przykładowy');
      expect(
        line('Zmyślin, Kraj Dawny'),
        'Zmyślin, Kraj Dawny ·${_nb}dziś${_nb}Kraj Przykładowy',
      );
      expect(
        line('zmyslin'),
        'zmyslin ·${_nb}dziś${_nb}Kraj Przykładowy',
      ); // without case and Polish letters
      expect(
        line('Zmyślinek, Kraj Dawny'),
        'Zmyślinek, Kraj Dawny ·${_nb}dziś${_nb}Zmyślin, Kraj Przykładowy',
      );
      expect(
        line('Zmyślin, Kraj Dawny', address: 'ul. Przykładowa 3'),
        'ul. Przykładowa 3, Zmyślin, Kraj Dawny ·${_nb}dziś${_nb}Kraj Przykładowy',
      );
      expect(
        residenceCardLine(const Residence(place: _country)),
        'Kraj Wymyślony ·${_nb}cały kraj',
      );
      expect(
        residenceCardLine(
          const Residence(place: _country, nameThen: 'Kraj Dawny'),
        ),
        'Kraj Dawny ·${_nb}dziś${_nb}Kraj Wymyślony',
      );
      expect(
        residenceLines(
          const Residence(place: _zmyslin, nameThen: 'Zmyślin, Kraj Dawny'),
        ),
        (
          first: 'Zmyślin, Kraj Dawny',
          second: 'dziś:${_nb}Zmyślin, Kraj Przykładowy',
        ),
      );
    },
  );
}
