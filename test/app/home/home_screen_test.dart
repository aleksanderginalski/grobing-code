import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/home/base_preview_screen.dart';
import 'package:grobing/app/home/cemetery_base.dart';
import 'package:grobing/app/home/cemetery_search.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/home/pick_point_screen.dart';
import 'package:grobing/app/home/poland_map_data.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/candle.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:latlong2/latlong.dart';

import '../../support/backup_fakes.dart';

// ISSUE-014 — the home screen, happy path per AC (05_DESIGN/cmentarze.md):
// AC-1 the map of Poland from bundled data, also empty · AC-2 a candle per cemetery with a point, the
// others in the search · AC-3 search by name or locality, no hits → "Dodaj ręcznie" · AC-4 (narrowed,
// D5) the sheet's counts · AC-5 "Stan danych" under the gear, no start screen · correcting with the
// edit icon (D6) · adding by hand through the window and the pick mode. Made-up cemeteries only.
//
// ISSUE-015 — adding from the bundled database: results with locality and voivodeship, the OSM
// attribution, the preview with its link (nothing leaves before the tap), the window with "Zapisz",
// "Dodany", the limit of 30, loading and error states. The database here is a handful of public
// cemeteries (Powązki, Rakowicki) and made-up ones; the real extract is tested in
// cemetery_base_test.dart.

final PolandMapData _map = PolandMapData.fromJson(
  File(PolandMapData.asset).readAsStringSync(),
);

const GeoPoint _powazki = GeoPoint(52.255, 20.984);

/// Public cemeteries as the extract describes them, and one made-up without a name.
final CemeteryBase _base = CemeteryBase(const [
  BaseCemetery(
    name: 'Cmentarz Powązkowski',
    otherNames: ['Stare Powązki'],
    point: _powazki,
    kind: 'rzymskokatolicki',
    locality: 'Warszawa',
    district: 'Żoliborz',
    voivodeship: 'mazowieckie',
  ),
  BaseCemetery(
    name: 'Cmentarz Powązkowski',
    point: GeoPoint(50.97, 15.65),
    locality: 'Marczów',
    voivodeship: 'dolnośląskie',
  ),
  BaseCemetery(
    name: 'Cmentarz Rakowicki',
    point: GeoPoint(50.0745, 19.952),
    locality: 'Kraków',
    district: 'Krowodrza',
    voivodeship: 'małopolskie',
  ),
  BaseCemetery(
    name: '',
    point: GeoPoint(52.5, 19.5),
    locality: 'Wymyślin',
    voivodeship: 'mazowieckie',
  ),
]);

/// Lets drift's stream and the map settle between frames (widget tests run in a fake clock).
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

void main() {
  late Directory tmp;
  late GrobingDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_home_test');
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

  Future<void> pumpHome(
    WidgetTester tester, {
    Future<CemeteryBase>? base,
    Future<bool> Function(String url)? openUrl,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: HomeScreen(
          database: db,
          location: DataLocation.inDirectory(Directory('${tmp.path}/data')),
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
          ),
          mapData: _map,
          base: base ?? Future.value(_base),
          openUrl: openUrl ?? (_) async => true,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(FlutterMap).evaluate().isNotEmpty,
    );
  }

  Iterable<CandlePin> pins(WidgetTester tester) =>
      tester.widgetList<CandlePin>(find.byType(CandlePin));

  testWidgets(
    'AC-1: an empty app shows the whole map of Poland, no tiles, and one action',
    (tester) async {
      await pumpHome(tester);
      await _pumpUntil(
        tester,
        () => find
            .text('Tu pojawią się cmentarze rodziny.')
            .evaluate()
            .isNotEmpty,
      );

      final PolygonLayer outline = tester.widget(find.byType(PolygonLayer));
      expect(outline.polygons.single.points, hasLength(1332));
      expect(find.byType(TileLayer), findsNothing);
      // A city name is drawn twice: the halo under the letters, then the letters.
      expect(find.text('Warszawa'), findsNWidgets(2));
      expect(
        find.widgetWithText(FilledButton, 'Dodaj cmentarz'),
        findsOneWidget,
      );
      expect(pins(tester), isEmpty);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2: a cemetery with a point is a candle; one without is only in the search',
    (tester) async {
      await tester.runAsync(() async {
        await addCemetery(
          db,
          name: 'Cmentarz Wymyślony',
          locality: 'Miejscowość Testowa',
          point: const GeoPoint(51.0, 20.0),
        );
        await addCemetery(
          db,
          name: 'Cmentarz Próbny',
          locality: 'Wieś Przykładowa',
        );
      });
      await pumpHome(tester);
      await _pumpUntil(tester, () => pins(tester).isNotEmpty);
      expect(pins(tester), hasLength(1));

      await tester.tap(find.text('Szukaj cmentarza'));
      await tester.pumpAndSettle();
      expect(find.text('Twoje cmentarze'), findsOneWidget);
      expect(find.text('Cmentarz Próbny'), findsOneWidget);
      expect(
        find.text('Wieś Przykładowa · 0 grobów · 0 osób · bez punktu na mapie'),
        findsOneWidget,
      );
      expect(find.text('Cmentarz Wymyślony'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 (D8): two cemeteries in one place are one candle with 2, opening a group sheet',
    (tester) async {
      await tester.runAsync(() async {
        await addCemetery(
          db,
          name: 'Cmentarz Pierwszy',
          point: const GeoPoint(51.0, 20.0),
        );
        await addCemetery(
          db,
          name: 'Cmentarz Drugi',
          point: const GeoPoint(51.002, 20.003),
        );
      });
      await pumpHome(tester);
      await _pumpUntil(tester, () => pins(tester).isNotEmpty);
      expect(pins(tester).map((p) => p.count), [2]);

      await tester.tap(find.byType(CandlePin));
      await tester.pumpAndSettle();
      expect(find.text('2 cmentarze w tym miejscu'), findsOneWidget);
      expect(find.text('Cmentarz Pierwszy'), findsOneWidget);
      expect(find.text('Cmentarz Drugi'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3: the search finds by locality without diacritics; no hits → "Dodaj ręcznie"',
    (tester) async {
      await tester.runAsync(
        () => addCemetery(db, name: 'Cmentarz Wymyślony', locality: 'Łódź'),
      );
      await pumpHome(tester);
      await tester.tap(find.text('Szukaj cmentarza'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'lodz');
      await tester.pump();
      expect(find.text('Cmentarz Wymyślony'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'cmentarz leśny');
      await tester.pump();
      expect(
        find.text(
          'Nie ma cmentarza „cmentarz leśny” ani u Ciebie, ani w bazie.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj ręcznie'));
      await tester.pumpAndSettle();
      expect(find.text('Nowy cmentarz'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cmentarz Leśny'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets('AC-4: the sheet of a candle shows graves and distinct people', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final int c = await addCemetery(
        db,
        name: 'Cmentarz Wymyślony',
        locality: 'Miejscowość Testowa',
        point: const GeoPoint(51.0, 20.0),
      );
      final int g1 = await db
          .into(db.graves)
          .insert(GravesCompanion.insert(cemeteryId: c));
      final int g2 = await db
          .into(db.graves)
          .insert(GravesCompanion.insert(cemeteryId: c));
      for (final (String name, int grave) in [
        ('Anna', g1),
        ('Jan', g1),
        ('Ewa', g2),
      ]) {
        final int p = await db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(givenNames: Value('$name Wymyślona')),
            );
        await addBurialWithClaim(db, personId: p, graveId: grave);
      }
    });
    await pumpHome(tester);
    await _pumpUntil(tester, () => pins(tester).isNotEmpty);

    await tester.tap(find.byType(CandlePin));
    await tester.pumpAndSettle();
    expect(find.text('Cmentarz Wymyślony'), findsOneWidget);
    expect(find.text('Miejscowość Testowa'), findsOneWidget);
    expect(find.text('2 groby · 3 osoby'), findsOneWidget);
    expect(find.byTooltip('Popraw cmentarz'), findsOneWidget);
    expect(pins(tester).single.look, PinLook.selected);
    await cleanUp(tester);
  });

  testWidgets(
    'ISSUE-012: "Otwórz cmentarz" in the sheet opens the cemetery screen; back returns to the map with '
    'the sheet still open',
    (tester) async {
      await tester.runAsync(() async {
        await addCemetery(
          db,
          name: 'Cmentarz Wymyślony',
          locality: 'Miejscowość Testowa',
          point: const GeoPoint(51.0, 20.0),
        );
      });
      await pumpHome(tester);
      await _pumpUntil(tester, () => pins(tester).isNotEmpty);
      await tester.tap(find.byType(CandlePin));
      await tester.pumpAndSettle();

      final Finder open = find.widgetWithText(FilledButton, 'Otwórz cmentarz');
      expect(open, findsOneWidget);
      // The candle leads to a place of memory (style-b.md rule 8).
      expect(
        find.descendant(of: open, matching: find.byType(CandleIcon)),
        findsOneWidget,
      );
      await tester.tap(open);
      await _pumpUntil(
        tester,
        () => find
            .text('Na tym cmentarzu nie ma jeszcze grobów.')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.descendant(
          of: find.byType(CemeteryScreen),
          matching: find.text('Cmentarz Wymyślony'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CemeteryScreen), findsNothing);
      expect(find.text('0 grobów · 0 osób'), findsOneWidget);
      expect(open, findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'adding by hand: window → pick mode → tap → "Zapisz" → the candle and its sheet',
    (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Szukaj cmentarza'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cmentarz próbny');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj ręcznie'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Miejscowość (opcjonalnie)'),
        'Wieś Przykładowa',
      );
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      expect(find.byType(PickPointScreen), findsOneWidget);

      // A tap on the map lands after the double-tap timeout.
      final Rect map = tester.getRect(find.byType(FlutterMap));
      await tester.tapAt(map.center);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(pins(tester).single.look, PinLook.selected);
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find.byType(PickPointScreen).evaluate().isEmpty,
      );
      await _pumpUntil(
        tester,
        () => find.text('0 grobów · 0 osób').evaluate().isNotEmpty,
      );

      final CemeterySummary saved = (await tester.runAsync(
        () => watchCemeteries(db).first,
      ))!.single;
      expect(saved.name, 'Cmentarz Próbny');
      expect(saved.locality, 'Wieś Przykładowa');
      expect(
        _map.bounds.contains(LatLng(saved.point!.lat, saved.point!.lon)),
        isTrue,
      );
      expect(find.text('Cmentarz Próbny'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'correcting with the edit icon: "Zapisz bez punktu" takes the candle off the map',
    (tester) async {
      await tester.runAsync(
        () => addCemetery(
          db,
          name: 'Cmentarz Wymyślony',
          point: const GeoPoint(51.0, 20.0),
        ),
      );
      await pumpHome(tester);
      await _pumpUntil(tester, () => pins(tester).isNotEmpty);
      await tester.tap(find.byType(CandlePin));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Popraw cmentarz'));
      await tester.pumpAndSettle();
      expect(find.text('Popraw cmentarz'), findsWidgets);
      expect(
        find.widgetWithText(TextField, 'Cmentarz Wymyślony'),
        findsOneWidget,
      );
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz bez punktu'));
      await _pumpUntil(
        tester,
        () => find.byType(PickPointScreen).evaluate().isEmpty,
      );
      await _pumpUntil(tester, () => pins(tester).isEmpty);

      expect(find.text('Bez punktu na mapie'), findsOneWidget);
      final CemeterySummary c = (await tester.runAsync(
        () => watchCemeteries(db).first,
      ))!.single;
      expect(c.point, isNull);
      await cleanUp(tester);
    },
  );

  testWidgets('AC-5: the app starts on the map; the gear opens "Stan danych"', (
    tester,
  ) async {
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
    await _pumpUntil(
      tester,
      () => find.byType(FlutterMap).evaluate().isNotEmpty,
    );
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Ustawienia'));
    await tester.pumpAndSettle();
    expect(find.byType(DataStateScreen), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets(
    'DoD: adding a cemetery asks for a background backup (ISSUE-010)',
    (tester) async {
      final FakeBackgroundBackups background = FakeBackgroundBackups();
      final BackupSettingsStore settings = BackupSettingsStore(
        File('${tmp.path}/data/backup.json'),
      );
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
          location: DataLocation.inDirectory(Directory('${tmp.path}/data')),
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
            background: background,
          ),
        ),
      );
      await tester.runAsync(() => addCemetery(db, name: 'Cmentarz Wymyślony'));
      await _pumpUntil(tester, () => background.requests >= 1);
      await cleanUp(tester);
    },
  );

  Future<void> search(WidgetTester tester, String text) async {
    await tester.tap(find.text('Szukaj cmentarza'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ISSUE-015 AC-1, AC-2, AC-5: results from the database with locality, district, voivodeship and '
    'denomination; the OSM attribution; "Nie ma go w bazie — dodaj ręcznie"',
    (tester) async {
      await pumpHome(tester);
      await search(tester, 'powazki');

      expect(find.text('Z bazy cmentarzy'), findsOneWidget);
      expect(find.text('Cmentarz Powązkowski'), findsNWidgets(2));
      expect(
        find.text(
          'Warszawa (Żoliborz) ·\u00A0woj. mazowieckie ·\u00A0rzymskokatolicki',
        ),
        findsOneWidget,
      );
      expect(find.text('Marczów ·\u00A0woj. dolnośląskie'), findsOneWidget);
      expect(find.text(osmAttribution), findsOneWidget);
      expect(osmAttribution, 'Dane: © autorzy OpenStreetMap (ODbL)');
      expect(
        find.widgetWithText(TextButton, 'Nie ma go w bazie — dodaj ręcznie'),
        findsOneWidget,
      );

      // By its other name, and an unnamed one by its locality.
      await tester.enterText(find.byType(TextField), 'stare powazki');
      await tester.pumpAndSettle();
      expect(find.text('Cmentarz Powązkowski'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'wymyslin');
      await tester.pumpAndSettle();
      expect(find.text('Cmentarz bez nazwy'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-015 AC-3: the preview — outlined candle and card; nothing is opened before the tap; the '
    'tap opens the satellite photo at the point; no app → a message; back → the same results',
    (tester) async {
      final List<String> opened = [];
      await pumpHome(
        tester,
        openUrl: (url) async {
          opened.add(url);
          return false;
        },
      );
      await search(tester, 'powazki');
      await tester.tap(
        find.text(
          'Warszawa (Żoliborz) ·\u00A0woj. mazowieckie ·\u00A0rzymskokatolicki',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BasePreviewScreen), findsOneWidget);
      expect(find.text('Cmentarz z bazy'), findsOneWidget);
      expect(
        pins(tester).where((p) => p.look == PinLook.outlined),
        hasLength(1),
      );
      expect(
        find.text('Warszawa (Żoliborz) ·\u00A0woj. mazowieckie'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Dodaj ten cmentarz'),
        findsOneWidget,
      );
      expect(opened, isEmpty);

      await tester.tap(find.text('Zobacz zdjęcie satelitarne'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single, contains('center=52.25500,20.98400'));
      expect(opened.single, contains('basemap=satellite'));
      expect(find.text('Nie ma aplikacji, która to otworzy.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BasePreviewScreen), findsNothing);
      expect(find.widgetWithText(TextField, 'powazki'), findsOneWidget);
      expect(find.text('Z bazy cmentarzy'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-015 AC-4: adding from the database — the window with its name and locality and "Zapisz", '
    'a corrected name saved with the point from the database, the candle and its sheet; then '
    '"Dodany" leads to that sheet',
    (tester) async {
      await pumpHome(tester);
      await search(tester, 'powazki');
      await tester.tap(
        find.text(
          'Warszawa (Żoliborz) ·\u00A0woj. mazowieckie ·\u00A0rzymskokatolicki',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj ten cmentarz'));
      await tester.pumpAndSettle();

      expect(find.text('Nowy cmentarz'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Cmentarz Powązkowski'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Warszawa'), findsOneWidget);
      expect(find.text('Dalej'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cmentarz Powązkowski'),
        'Stare Powązki',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      await _pumpUntil(
        tester,
        () => find.text('0 grobów · 0 osób').evaluate().isNotEmpty,
      );
      // The window's closing animation still holds the typed name.
      await tester.pumpAndSettle();

      final CemeterySummary saved = (await tester.runAsync(
        () => watchCemeteries(db).first,
      ))!.single;
      expect(
        (saved.name, saved.locality, saved.point),
        ('Stare Powązki', 'Warszawa', _powazki),
      );
      expect(pins(tester).single.look, PinLook.selected);
      expect(find.text('Stare Powązki'), findsOneWidget);

      await search(tester, 'powazki');
      expect(find.text('Dodany'), findsOneWidget);
      await tester.tap(find.text('Dodany'));
      await _pumpUntil(
        tester,
        () => find.byType(CemeterySearchScreen).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Stare Powązki'), findsOneWidget);
      expect(find.text('0 grobów · 0 osób'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-015 D8: more than 30 hits → 30 shown and "Pokazuję 30 z 35 — dopisz miejscowość."',
    (tester) async {
      await pumpHome(
        tester,
        base: Future.value(
          CemeteryBase([
            for (int i = 0; i < 35; i++)
              BaseCemetery(
                name: 'Cmentarz Wymyślony $i',
                point: const GeoPoint(52.0, 20.0),
                locality: 'Wymyślin',
                voivodeship: 'mazowieckie',
              ),
          ]),
        ),
      );
      await search(tester, 'wymyslony');
      await tester.scrollUntilVisible(
        find.text('Pokazuję 30 z 35 — dopisz miejscowość.'),
        400,
        // The list's own Scrollable, not the text field's.
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('Pokazuję 30 z 35 — dopisz miejscowość.'),
        findsOneWidget,
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-015 States: a slow database shows a thin progress bar; a broken one says so, while your '
    'cemeteries and adding by hand still work',
    (tester) async {
      await tester.runAsync(
        () => addCemetery(db, name: 'Cmentarz Wymyślony', locality: 'Wymyślin'),
      );
      final Completer<CemeteryBase> slow = Completer();
      await pumpHome(tester, base: slow.future);
      await tester.tap(find.text('Szukaj cmentarza'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wymyslin');
      await tester.pump();
      slow.completeError(StateError('the bundled file is damaged'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Cmentarz Wymyślony'), findsOneWidget);
      expect(
        find.text('Baza cmentarzy jest niedostępna — dodaj ręcznie.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Dodaj ręcznie'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-015 (ui review): the window opens over the preview — "Anuluj" stays there; a failed save '
    'says so with its icon and the window comes back with what was typed',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      int attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: GrobingTheme.dark,
          home: BasePreviewScreen(
            cemetery: _base.search('rakowicki').shown.single,
            mapData: _map,
            onSave: (values) async {
              attempts++;
              throw StateError('disk full');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj ten cmentarz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(find.byType(BasePreviewScreen), findsOneWidget);
      expect(find.text('Nowy cmentarz'), findsNothing);
      expect(attempts, 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj ten cmentarz'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cmentarz Rakowicki'),
        'Cmentarz na Rakowicach',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Zapisz'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.byType(BasePreviewScreen), findsOneWidget);
      expect(
        find.text('Nie udało się zapisać. Spróbuj jeszcze raz.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj ten cmentarz'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Cmentarz na Rakowicach'),
        findsOneWidget,
      );
    },
  );
}
