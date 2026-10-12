import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/sectors_screen.dart';
import 'package:grobing/app/map/plan_downloads.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/sectors.dart';
import 'package:grobing/dev/fictional_photo.dart';
import 'package:grobing/net/overpass_plan_source.dart';

// ISSUE-028 — the author's sectors (05_DESIGN/cmentarz.md v6, elements 4, 15–19), happy path per AC: US-007
// AC-4 a zone on the plan, a sector only in the addresses on the list · What to build 1 marking a zone with
// the crosshair (K1, the author's choice) · What to build 3 renaming, drawing again, removing. The network
// is faked. Invented cemeteries, people and geometry only (family-data.md).

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

const GeoPoint _point = GeoPoint(51.5, 19.5);

const List<PlanArea> _areas = [
  PlanArea([
    GeoPoint(51.498, 19.498),
    GeoPoint(51.498, 19.502),
    GeoPoint(51.502, 19.502),
    GeoPoint(51.502, 19.498),
    GeoPoint(51.498, 19.498),
  ]),
];

const List<GeoPoint> _zone = [
  GeoPoint(51.4990, 19.4990),
  GeoPoint(51.4990, 19.5000),
  GeoPoint(51.5000, 19.5000),
  GeoPoint(51.5000, 19.4990),
];

class _Source implements PlanSource {
  @override
  Future<PlanResult> fetch(GeoPoint point) async => const PlanOffline();
}

class _Tiles extends TileProvider {
  static final MemoryImage _image = MemoryImage(
    fictionalGravestonePng(1, width: 4, height: 4),
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _image;
}

void main() {
  late GrobingDatabase db;
  late int cemetery;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  Future<void> withPlan(WidgetTester tester) async {
    await tester.runAsync(() async {
      cemetery = await addCemetery(
        db,
        name: 'Cmentarz Wymyślony',
        locality: 'Wymyślin',
        point: _point,
      );
      await savePlan(
        db,
        cemetery,
        forPoint: _point,
        areas: _areas,
        paths: const [],
        server: 'overpass.example',
      );
    });
  }

  /// [screen] in the app's frame, animations off — a touch on the plan moves it at once (element 18, K1).
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final PlanDownloads plans = PlanDownloads(database: db, source: _Source());
    addTearDown(plans.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        builder: (context, child) => MapNetwork(
          plans: plans,
          photoReachable: () async => true,
          photoTiles: _Tiles.new,
          child: child!,
        ),
        home: screen,
      ),
    );
  }

  Future<List<Sector>> sectorsInDb(WidgetTester tester) async =>
      (await tester.runAsync(() => watchSectors(db, cemetery).first))!;

  /// Where the crosshair stands on the screen (element 18): the painter's point in the map's room.
  Offset crosshair(WidgetTester tester) {
    final CustomPaint paint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((p) => p.painter.runtimeType.toString() == '_Crosshair');
    final Offset at = (paint.painter! as dynamic).at as Offset;
    return tester.getTopLeft(find.byType(FlutterMap)) + at;
  }

  /// K1: a touch on the plan [by] from the crosshair brings that place under it, then "Dodaj róg".
  Future<void> corner(WidgetTester tester, Offset by) async {
    await tester.tapAt(crosshair(tester) + by);
    // A single tap waits for a possible second one (double tap zooms).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Dodaj róg'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  FilledButton done(WidgetTester tester) =>
      tester.widget(find.widgetWithText(FilledButton, 'Gotowe'));

  testWidgets(
    'What to build 1 (K1) — "Zaznacz kwaterę" → the name → three corners with the crosshair → "Gotowe": the '
    'sector with its zone, selected; "Gotowe" waits for three corners; "Cofnij" takes the last one back',
    (tester) async {
      await withPlan(tester);
      await pumpScreen(
        tester,
        SectorsScreen(database: db, cemeteryId: cemetery),
      );
      await _pumpUntil(
        tester,
        () => _shown(
          find.textContaining('Na tym cmentarzu nie ma jeszcze kwater.'),
        ),
      );
      expect(find.text('Kwatery'), findsOneWidget);
      expect(find.byTooltip('Zamknij kwatery'), findsOneWidget);

      await tester.tap(find.text('Zaznacz kwaterę'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sama nazwa, jak na planie zarządcy, np. B albo 12.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Dalej'));
      await tester.pump();
      expect(find.text('Podaj nazwę kwatery.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Kwatera D');
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      expect(find.text('Kwatera D — strefa'), findsOneWidget);
      expect(find.text('Zaznacz rogi według planu zarządcy'), findsOneWidget);
      expect(find.text('0 rogów — potrzebne co najmniej 3'), findsOneWidget);
      expect(done(tester).onPressed, isNull);

      await corner(tester, const Offset(-60, -40));
      await corner(tester, const Offset(120, 0));
      expect(find.text('2 rogi — potrzebne co najmniej 3'), findsOneWidget);
      expect(done(tester).onPressed, isNull);
      await corner(tester, const Offset(0, 90));
      expect(find.text('3 rogi'), findsOneWidget);
      // The name of the zone from three corners on (element 18), halo and letters.
      expect(find.text('Kwatera D'), findsNWidgets(2));
      await tester.tap(find.text('Cofnij'));
      await tester.pump();
      expect(find.text('2 rogi — potrzebne co najmniej 3'), findsOneWidget);
      await corner(tester, const Offset(0, 90));
      expect(done(tester).onPressed, isNotNull);

      await tester.tap(find.text('Gotowe'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('bez grobów · na planie')),
      );
      expect(find.byTooltip('Zmień nazwę kwatery'), findsOneWidget);
      expect(find.text('Narysuj strefę od nowa'), findsOneWidget);
      expect(find.text('Usuń z planu'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      final List<Sector> saved = await sectorsInDb(tester);
      expect(saved.single.name, 'D');
      expect(saved.single.zone!.toSet().length, 3);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'element 18 — sides that cross: the message, "Gotowe" inactive; ✕ with corners asks "Porzucić '
    'zaznaczanie?", "Porzuć" leaves without a sector',
    (tester) async {
      await withPlan(tester);
      await pumpScreen(
        tester,
        SectorsScreen(database: db, cemeteryId: cemetery),
      );
      // "Zaznacz kwaterę" works once the sectors are read.
      await _pumpUntil(
        tester,
        () => _shown(
          find.textContaining('Na tym cmentarzu nie ma jeszcze kwater.'),
        ),
      );
      await tester.tap(find.text('Zaznacz kwaterę'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'E');
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      // A bow tie: A, then B down-right of A, C right of A, D down of A — sides A–B and C–D cross.
      await corner(tester, const Offset(-50, -50));
      await corner(tester, const Offset(100, 100));
      await corner(tester, const Offset(0, -100));
      await corner(tester, const Offset(-100, 100));
      expect(find.text('4 rogi'), findsOneWidget);
      expect(
        find.text('Boki strefy się przecinają — cofnij ostatni róg.'),
        findsOneWidget,
      );
      expect(done(tester).onPressed, isNull);

      await tester.tap(find.byTooltip('Zamknij zaznaczanie'));
      await tester.pumpAndSettle();
      expect(find.text('Porzucić zaznaczanie?'), findsOneWidget);
      expect(find.text('Zaznaczone rogi przepadną.'), findsOneWidget);
      await tester.tap(find.text('Rysuj dalej'));
      await tester.pumpAndSettle();
      expect(find.text('Kwatera E — strefa'), findsOneWidget);
      await tester.tap(find.byTooltip('Zamknij zaznaczanie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Porzuć'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Na tym cmentarzu nie ma jeszcze kwater.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(await sectorsInDb(tester), isEmpty);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'US-007 AC-4, What to build 3 — the list shows a sector on the plan and one only in an address; ✎ says '
    'what happens to the addresses and renames them; "Narysuj strefę od nowa" shows the old zone; "Usuń z '
    'planu" keeps the sector in its address; a taken name is refused',
    (tester) async {
      await withPlan(tester);
      late int grave;
      await tester.runAsync(() async {
        await addSector(db, cemetery, name: 'B', zone: _zone);
        grave = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
        );
        await setGraveDetails(db, grave, sector: 'B', row: '4');
        final int other = await addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Anna', surname: 'Testowa'),
        );
        await setGraveDetails(db, other, sector: 'C');
      });
      await pumpScreen(
        tester,
        SectorsScreen(database: db, cemeteryId: cemetery),
      );
      await _pumpUntil(tester, () => _shown(find.text('1 grób · na planie')));
      expect(
        find.text('1 grób · bez strefy — tylko w adresach'),
        findsOneWidget,
      );
      // The zone's name on the plan (halo and letters) and its card.
      expect(find.text('Kwatera B'), findsNWidgets(3));
      expect(find.text('Kwatera C'), findsOneWidget);

      await tester.tap(find.text('1 grób · na planie'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Wszystkie kwatery'), findsOneWidget);
      await tester.tap(find.byTooltip('Zmień nazwę kwatery'));
      await tester.pumpAndSettle();
      expect(
        find.text('Adresy 1 grobu zmienią się na „Kwatera B”.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'c');
      await tester.tap(find.text('Zapisz'));
      await tester.pump();
      // A rename cannot merge two sectors, so it asks for another name (ui review).
      expect(
        find.text('Kwatera C już jest na tym cmentarzu — wpisz inną nazwę.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'B1');
      await tester.pump();
      expect(
        find.text('Adresy 1 grobu zmienią się na „Kwatera B1”.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Zapisz'));
      await _pumpUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
      );
      await _pumpUntil(tester, () => _shown(find.text('Kwatera B1')));

      await tester.tap(find.text('Narysuj strefę od nowa'));
      await tester.pumpAndSettle();
      expect(find.text('Kwatera B1 — strefa'), findsOneWidget);
      expect(find.text('Stara strefa jest szara'), findsOneWidget);
      await tester.tap(find.byTooltip('Zamknij zaznaczanie'));
      await tester.pumpAndSettle();
      // No corners: straight back to the sector, without a window.
      expect(find.text('Porzucić zaznaczanie?'), findsNothing);

      await tester.tap(find.text('Usuń z planu'));
      await tester.pumpAndSettle();
      expect(find.text('Usunąć kwaterę B1 z planu?'), findsOneWidget);
      expect(
        find.text('Strefa zniknie z planu. Adresy grobów zostaną.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Usuń'));
      // Back on the list: both sectors live in the addresses only now.
      await _pumpUntil(
        tester,
        () =>
            find
                .text('1 grób · bez strefy — tylko w adresach')
                .evaluate()
                .length ==
            2,
      );

      await tester.tap(find.text('Zaznacz kwaterę'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'b1');
      await tester.tap(find.text('Dalej'));
      await tester.pump();
      expect(
        find.text('Kwatera B1 już jest na liście — wybierz ją tam.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      final GraveDetail? detail = await tester.runAsync<GraveDetail?>(
        () => loadGrave(db, grave),
      );
      expect((detail!.sector, detail.row), ('B1', '4'));
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'element 15, D24 — the cemetery\'s map shows the author\'s zone with its name and "Kwatery", which opens '
    'the sectors\' mode; without a plan (2a) there is no "Kwatery"',
    (tester) async {
      await withPlan(tester);
      await tester.runAsync(
        () => addSector(db, cemetery, name: 'B', zone: _zone),
      );
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: cemetery),
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await _pumpUntil(tester, () => _shown(find.text('Kwatera B')));
      // The zone's name: its halo and its letters.
      expect(find.text('Kwatera B'), findsNWidgets(2));
      final PolygonLayer zones = tester
          .widgetList<PolygonLayer>(find.byType(PolygonLayer))
          .last;
      expect(zones.polygons.single.points.length, 4);
      expect(zones.polygons.single.color, isNull);
      // US-007 AC-4 "przerywaną linią": dashes 5, gaps 4 (D13; the US review asked for it).
      expect(zones.polygons.single.pattern.segments, [5, 4]);
      expect(find.text('Kwatery'), findsOneWidget);
      // A button for a screen reader, with a 48 dp target around the 40 dp pill (ui review, MAJOR).
      expect(
        tester.getSemantics(find.bySemanticsLabel('Kwatery')),
        matchesSemantics(label: 'Kwatery', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSize(find.bySemanticsLabel('Kwatery')).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.text('Kwatery'));
      await tester.pumpAndSettle();
      expect(find.byType(SectorsScreen), findsOneWidget);
      expect(find.byTooltip('Zamknij kwatery'), findsOneWidget);
      await tester.tap(find.byTooltip('Zamknij kwatery'));
      await tester.pumpAndSettle();
      expect(find.byType(SectorsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      late int bare;
      await tester.runAsync(() async {
        bare = await addCemetery(db, name: 'Cmentarz Zmyślony', point: _point);
      });
      await pumpScreen(tester, CemeteryScreen(database: db, cemeteryId: bare));
      await _pumpUntil(
        tester,
        () => _shown(
          find.text('Plan tego cmentarza pobierze się, gdy będzie internet.'),
        ),
      );
      expect(find.text('Kwatery'), findsNothing);
      await cleanUp(tester);
    },
  );
}
