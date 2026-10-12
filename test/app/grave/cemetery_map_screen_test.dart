import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/plan_placeholder.dart';
import 'package:grobing/app/map/plan_downloads.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/dev/fictional_photo.dart';
import 'package:grobing/net/hosts.dart';
import 'package:grobing/net/overpass_plan_source.dart';

// ISSUE-027 — the cemetery as a map (05_DESIGN/cmentarz.md v5), happy path per AC: US-007 AC-1 the plan
// offline · AC-2 the photo from above online, "bez internetu" without · AC-3 the map, one grave, the list
// (and the entry from a person's "Pochówek", D23) · AC-5 no plan, "Pobierz teraz" · the placeholders 2a
// (a)–(e) · W2 (NFR-004, stop #1) · D22. The network is faked: no request leaves the test. Invented
// cemeteries, people and geometry only (family-data.md).

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

const List<PlanPath> _paths = [
  PlanPath([GeoPoint(51.499, 19.5), GeoPoint(51.501, 19.5)], main: true),
  PlanPath([GeoPoint(51.5, 19.499), GeoPoint(51.5, 19.501)], main: false),
];

/// The plans' source: answers what the test says, waits while [gate] is open.
class _Source implements PlanSource {
  _Source(this.answer);

  PlanResult answer;
  Completer<void>? gate;
  int asked = 0;

  @override
  Future<PlanResult> fetch(GeoPoint point) async {
    asked++;
    await gate?.future;
    return answer;
  }
}

/// Tiles of the photo from above, made here: no request leaves the test.
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

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  /// A cemetery with three invented graves: two with a pin inside the plan, one without.
  Future<int> cemeteryWithGraves(
    WidgetTester tester, {
    GeoPoint? point = _point,
    bool plan = true,
    bool pins = true,
  }) async {
    late int id;
    await tester.runAsync(() async {
      id = await addCemetery(
        db,
        name: 'Cmentarz Wymyślony',
        locality: 'Wymyślin',
        point: point,
      );
      if (plan && point != null) {
        await savePlan(
          db,
          id,
          forPoint: point,
          areas: _areas,
          paths: _paths,
          server: 'overpass.example',
        );
      }
      for (final (String given, String surname, GeoPoint? pin) in [
        ('Jan', 'Wymyślony', const GeoPoint(51.4995, 19.4995)),
        ('Anna', 'Testowa', const GeoPoint(51.5005, 19.5005)),
        ('Piotr', 'Zmyślony', null),
      ]) {
        final int grave = await addPersonToNewGrave(
          db,
          cemeteryId: id,
          entry: PersonEntry(givenNames: given, surname: surname),
        );
        if (pins && pin != null) {
          await (db.update(db.graves)..where((g) => g.id.equals(grave))).write(
            GravesCompanion(
              lat: Value(pin.lat),
              lon: Value(pin.lon),
              positionSource: const Value(PositionSource.satellite),
            ),
          );
        }
      }
    });
    return id;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    PlanSource? source,
    bool photoOnline = true,
    double textScale = 1,
    Size size = const Size(1080, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final PlanDownloads plans = PlanDownloads(
      database: db,
      source: source ?? _Source(const PlanOffline()),
    );
    addTearDown(plans.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        builder: (context, child) => MapNetwork(
          plans: plans,
          photoReachable: () async => photoOnline,
          photoTiles: _Tiles.new,
          child: child!,
        ),
        home: screen,
      ),
    );
  }

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets(
    'AC-1 — a cemetery with its plan: the plan drawn, "Plan offline" and "© OpenStreetMap", the switch on '
    '"Plan"; nothing asked of the network',
    (tester) async {
      final int id = await cemeteryWithGraves(tester, pins: false);
      final _Source source = _Source(const PlanServerError());
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: id),
        source: source,
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      expect(find.text('© OpenStreetMap'), findsOneWidget);
      expect(find.bySemanticsLabel('Plan cmentarza'), findsOneWidget);
      expect(find.byType(PolygonLayer), findsOneWidget);
      expect(find.byType(TileLayer), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Plan').first),
        matchesSemantics(
          label: 'Plan',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(source.asked, 0);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 — "Zdjęcie" with a network: GUGiK\'s tiles, "tylko z internetem", "Ortofotomapa: GUGiK"; without '
    'one: "bez internetu", the photo needs the internet, "Wróć do planu" → the plan',
    (tester) async {
      final int id = await cemeteryWithGraves(tester, pins: false);
      await pumpScreen(tester, CemeteryScreen(database: db, cemeteryId: id));
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await tester.tap(find.text('Zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('tylko z internetem')));
      final TileLayer tiles = tester.widget(find.byType(TileLayer));
      expect(tiles.urlTemplate, Hosts.orthophotoTiles);
      expect(tiles.tileProvider, isA<_Tiles>());
      expect(find.text('Ortofotomapa: GUGiK'), findsOneWidget);
      expect(find.text('Plan offline'), findsNothing);
      expect(find.bySemanticsLabel('Zdjęcie cmentarza z góry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: id),
        photoOnline: false,
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await tester.tap(find.text('Zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('bez internetu')));
      expect(find.text('Zdjęcie z góry potrzebuje internetu.'), findsOneWidget);
      expect(find.text('Plan działa bez niego.'), findsOneWidget);
      await tester.tap(find.text('Wróć do planu'));
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3 — at first only the map: a candle for each grave with a pin, the bar with the grave without one; '
    'a candle → the grave\'s sheet with "Pokaż grób"; its handle → the list of all graves, that one '
    'framed; back → the sheet → the map',
    (tester) async {
      final int id = await cemeteryWithGraves(tester);
      await pumpScreen(tester, CemeteryScreen(database: db, cemeteryId: id));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Grób: Jan Wymyślony')),
      );
      expect(find.bySemanticsLabel('Grób: Anna Testowa'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Grób: Piotr')), findsNothing);
      expect(find.text('3 groby · 3 osoby'), findsOneWidget);
      expect(find.text('1 grób bez pinezki — na liście'), findsOneWidget);
      expect(find.text('Pokaż grób'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Grób: Jan Wymyślony'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Pokaż grób'), findsOneWidget);
      expect(find.text('Jan Wymyślony'), findsOneWidget);
      expect(find.text('Bez adresu kwatery'), findsOneWidget);
      expect(find.text('1 osoba'), findsOneWidget);
      expect(find.text('1 grób bez pinezki — na liście'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Pokaż listę grobów'));
      await tester.pumpAndSettle();
      expect(find.text('Bez adresu kwatery · bez pinezki'), findsOneWidget);
      expect(find.text('Anna Testowa'), findsOneWidget);
      final Finder framed = find.ancestor(
        of: find.text('Jan Wymyślony'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Material &&
              w.shape is RoundedRectangleBorder &&
              (w.shape! as RoundedRectangleBorder).side.color ==
                  GrobingColors.amber,
        ),
      );
      expect(framed, findsOneWidget);

      // Back: the list → the sheet it came from → the map.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Pokaż grób'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('1 grób bez pinezki — na liście'), findsOneWidget);

      // The bar opens the list with one tap too (D21), "Dodaj grób" with it.
      await tester.tap(find.bySemanticsLabel('Pokaż listę grobów'));
      await tester.pumpAndSettle();
      expect(find.text('Piotr Zmyślony'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Dodaj grób'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Pokaż mapę'));
      await tester.pumpAndSettle();
      expect(find.text('1 grób bez pinezki — na liście'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D23 — from a person\'s "Pochówek": a grave with a pin opens as one grave (B); without one on the list, '
    'its card framed',
    (tester) async {
      final int id = await cemeteryWithGraves(tester);
      late final List<GraveSummary> graves;
      await tester.runAsync(() async {
        graves = (await loadCemeteryGraves(db, id))!.graves;
      });
      final GraveSummary withPin = graves.firstWhere((g) => g.hasPin);
      final GraveSummary without = graves.firstWhere((g) => !g.hasPin);

      await pumpScreen(
        tester,
        CemeteryScreen(
          database: db,
          cemeteryId: id,
          highlightGraveId: withPin.id,
        ),
      );
      await _pumpUntil(
        tester,
        () => _shown(find.widgetWithText(FilledButton, 'Pokaż grób')),
      );
      await tester.pumpWidget(const SizedBox());

      await pumpScreen(
        tester,
        CemeteryScreen(
          database: db,
          cemeteryId: id,
          highlightGraveId: without.id,
        ),
      );
      await _pumpUntil(tester, () => _shown(find.text('Piotr Zmyślony')));
      expect(find.bySemanticsLabel('Pokaż mapę'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find
                  .ancestor(
                    of: find.text('Piotr Zmyślony'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-5 — a cemetery added without a network: "pobierze się, gdy będzie internet" and "Pobierz teraz"; '
    'tapped without a network → the placeholder stays and a bar says so; the list works',
    (tester) async {
      final int id = await cemeteryWithGraves(tester, plan: false, pins: false);
      final _Source source = _Source(const PlanOffline());
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: id),
        source: source,
      );
      await _pumpUntil(
        tester,
        () => _shown(
          find.text('Plan tego cmentarza pobierze się, gdy będzie internet.'),
        ),
      );
      expect(source.asked, 1);
      expect(find.text('Groby są na liście — pasek na dole.'), findsOneWidget);
      await tester.tap(find.text('Pobierz teraz'));
      await _pumpUntil(
        tester,
        () => _shown(
          find.text('Bez internetu. Plan pobierze się, gdy będzie zasięg.'),
        ),
      );
      expect(source.asked, 2);
      await tester.tap(find.bySemanticsLabel('Pokaż listę grobów'));
      await tester.pumpAndSettle();
      expect(find.text('Jan Wymyślony'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    '2a (a) and (c): "Pobieram plan cmentarza…" while it downloads, then the servers did not answer — the '
    'fact and "Spróbuję znowu później"; a plan that comes is drawn at once',
    (tester) async {
      final int id = await cemeteryWithGraves(tester, plan: false, pins: false);
      final _Source source = _Source(const PlanServerError())
        ..gate = Completer<void>();
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: id),
        source: source,
      );
      await _pumpUntil(
        tester,
        () => _shown(find.text('Pobieram plan cmentarza…')),
      );
      source.gate!.complete();
      await _pumpUntil(
        tester,
        () => _shown(
          find.text('Nie udało się pobrać planu — serwer map nie odpowiada.'),
        ),
      );
      expect(
        find.text('Spróbuję znowu później. Groby są na liście.'),
        findsOneWidget,
      );
      source
        ..gate = null
        ..answer = const PlanFound(
          areas: _areas,
          paths: _paths,
          server: 'overpass.example',
        );
      await tester.tap(find.text('Pobierz teraz'));
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await cleanUp(tester);
    },
  );

  testWidgets(
    '2a (d) not in OpenStreetMap: the fact, and with a network "Pokaż zdjęcie z góry" → the photo around '
    'the point; (e) no point: "Wskaż na mapie", no switch',
    (tester) async {
      late int notInOsm;
      await tester.runAsync(() async {
        notInOsm = await addCemetery(
          db,
          name: 'Cmentarz Wymyślony',
          point: _point,
        );
        await saveNotInOsm(db, notInOsm, forPoint: _point, server: 'x');
      });
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: notInOsm),
      );
      await _pumpUntil(tester, () => _shown(find.text('Pokaż zdjęcie z góry')));
      expect(
        find.text('W OpenStreetMap nie ma planu tego cmentarza.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pokaż zdjęcie z góry'));
      await _pumpUntil(tester, () => _shown(find.byType(TileLayer)));
      await tester.pumpWidget(const SizedBox());

      final int noPoint = await cemeteryWithGraves(
        tester,
        point: null,
        plan: false,
        pins: false,
      );
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: noPoint),
      );
      await _pumpUntil(
        tester,
        () => _shown(
          find.text('Plan pobierze się, gdy wskażesz cmentarz na mapie.'),
        ),
      );
      expect(find.text('Wskaż na mapie'), findsOneWidget);
      expect(find.text('Zdjęcie'), findsNothing);
      expect(find.text('Plan offline'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'W2 (NFR-004, stop #1) — what is read at the cemetery is in the text colour: the bar\'s line of graves '
    'without a pin, the grave\'s address and count, the placeholder\'s lines',
    (tester) async {
      final int id = await cemeteryWithGraves(tester);
      await pumpScreen(tester, CemeteryScreen(database: db, cemeteryId: id));
      await _pumpUntil(
        tester,
        () => _shown(find.text('1 grób bez pinezki — na liście')),
      );
      expect(
        colorOf(tester, '1 grób bez pinezki — na liście'),
        GrobingColors.text,
      );
      await tester.tap(find.bySemanticsLabel('Grób: Anna Testowa'));
      await tester.pumpAndSettle();
      expect(colorOf(tester, 'Bez adresu kwatery'), GrobingColors.text);
      expect(colorOf(tester, '1 osoba'), GrobingColors.text);
      // The source stays muted — not read at a grave.
      expect(colorOf(tester, '© OpenStreetMap'), GrobingColors.textMuted);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D22 — 360 dp wide with large text (160%; at 200% the test font overflows the tab bar of ISSUE-022, which '
    'fits on the emulator): "Plan offline" moves under the switch, on the left, nothing overflows',
    (tester) async {
      final int id = await cemeteryWithGraves(tester, pins: false);
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: id),
        textScale: 1.6,
        size: const Size(1080, 1920),
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      final Rect state = tester.getRect(find.text('Plan offline'));
      final Rect toggle = tester.getRect(find.text('Zdjęcie'));
      expect(state.top, greaterThan(toggle.bottom));
      expect(state.left, lessThan(toggle.left));
      expect(tester.takeException(), isNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ui review, ISSUE-027 — a cemetery without graves: the placeholder does not send to a list that has none '
    '(rule 7); the handles are 48 dp targets (D21)',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final (PlanGap gap, String fact, String? way) in [
        (
          PlanGap.offline,
          'Plan tego cmentarza pobierze się, gdy będzie internet.',
          null,
        ),
        (
          PlanGap.serverError,
          'Nie udało się pobrać planu — serwer map nie odpowiada.',
          'Spróbuję znowu później.',
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlanPlaceholder(
                gap: gap,
                hasGraves: false,
                onDownload: () {},
              ),
            ),
          ),
        );
        expect(find.text(fact), findsOneWidget);
        expect(find.textContaining('Groby są na liście'), findsNothing);
        if (way != null) expect(find.text(way), findsOneWidget);
      }

      final int id = await cemeteryWithGraves(tester);
      await pumpScreen(tester, CemeteryScreen(database: db, cemeteryId: id));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Grób: Jan Wymyślony')),
      );
      await tester.tap(find.bySemanticsLabel('Grób: Jan Wymyślony'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.bySemanticsLabel('Pokaż listę grobów')).height,
        greaterThanOrEqualTo(48),
      );
      await cleanUp(tester);
    },
  );
}
