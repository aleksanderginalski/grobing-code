import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/home/poland_map.dart';
import 'package:grobing/app/home/poland_map_data.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/candle.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/photos.dart';
import 'package:latlong2/latlong.dart';

import '../../support/backup_fakes.dart';
import '../../support/photo_fakes.dart';

// ISSUE-023 — the map of Poland like R1 and the cemetery's photo (05_DESIGN/cmentarze.md v2.5, elements 3,
// 6a; D28–D30), happy path per AC: AC-1 the sea, the lakes, the neighbours' borders, "Polska" and eleven
// cities from the bundled file, labels apart, the edge of the data never on the screen · AC-2 Poland in the
// middle, gliding above the sheet and back (D2: only at the whole of Poland; "Usuń animacje" jumps) · AC-3
// the cemetery's photo in the sheet: added, opened, changed, deleted. Made-up cemeteries, pictures drawn in
// code (family-data.md). AC-4 (the backup before v9) is in restore_service_test.dart and migration_test.dart.

final PolandMapData _map = PolandMapData.fromJson(
  File(PolandMapData.asset).readAsStringSync(),
);

/// Phones held upright: 411 × 914 dp (`Medium_Phone`) and 360 × 780 dp (a small 19.5:9 phone).
const List<(Size, double)> _phones = [
  (Size(1080, 2400), 2.625),
  (Size(1080, 2340), 3),
];

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

/// A route or a sheet runs to its end.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// The cemetery's sheet (elements 6–8): the surface at elevation 8.
final Finder _sheet = find.byWidgetPredicate(
  (w) => w is Material && w.elevation == 8,
);

final Finder _thumbnail = find.bySemanticsLabel('Zdjęcie cmentarza — otwórz');

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late FakePhotoPicker picker;
  late Photos photos;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_map_r1_test');
    db = GrobingDatabase(NativeDatabase.memory());
    picker = FakePhotoPicker();
    photos = fakePhotos(tmp, picker: picker);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: the image loader may still hold a file; nothing in it is real.
    }
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    PaintingBinding.instance.imageCache.clear();
    await tester.runAsync(db.close);
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    (Size, double) phone = (const Size(1080, 2400), 2.625),
  }) async {
    tester.view.physicalSize = phone.$1;
    tester.view.devicePixelRatio = phone.$2;
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
          photos: photos,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(FlutterMap).evaluate().isNotEmpty,
    );
  }

  Future<int> warsawCemetery(WidgetTester tester) async =>
      (await tester.runAsync(
        () => addCemetery(
          db,
          name: 'Cmentarz Wymyślony',
          locality: 'Wymyślin',
          point: const GeoPoint(52.25, 21.0),
        ),
      ))!;

  MapController mapOf(WidgetTester tester) =>
      MapController.of(tester.element(find.byType(MarkerLayer).first));

  testWidgets(
    'AC-1 — like R1: the sea under Poland\'s land, the lakes over it, rivers in the water line, the '
    'neighbours\' borders as decoration, Poland\'s border in the muted text colour on top, "Polska" and '
    'the eleven cities',
    (tester) async {
      await pumpHome(tester);

      final List<PolygonLayer> areas = tester
          .widgetList<PolygonLayer>(find.byType(PolygonLayer))
          .toList();
      expect(areas, hasLength(3));
      expect(areas[0].polygons, hasLength(_map.water.length));
      expect(
        areas[0].polygons.map((p) => p.color),
        everyElement(GrobingColors.water),
      );
      expect(areas[1].polygons.single.color, GrobingColors.surface);
      expect(areas[1].polygons.single.points, hasLength(1332));
      expect(areas[2].polygons, hasLength(_map.lakes.length));
      // Performance (qa, ISSUE-023): the sea's islands are cut with the even-odd rule. flutter_map's
      // default `Path.combine` cost 2–3 s a frame on the whole sea and froze the app (an ANR at start).
      expect(areas[0].painterFillMethod, PolygonPainterFillMethod.evenOdd);
      expect(areas[2].painterFillMethod, PolygonPainterFillMethod.evenOdd);
      expect(
        areas[2].polygons.map((p) => p.color),
        everyElement(GrobingColors.water),
      );

      final List<Polyline> lines = tester
          .widgetList<PolylineLayer>(find.byType(PolylineLayer))
          .expand((l) => l.polylines)
          .toList();
      expect(
        lines.where(
          (l) => l.color == GrobingColors.waterLine && l.strokeWidth == 1,
        ),
        hasLength(_map.rivers.length),
      );
      expect(
        lines.where(
          (l) =>
              l.color == GrobingColors.outline.withValues(alpha: 0.45) &&
              l.strokeWidth == 0.7,
        ),
        hasLength(_map.borders.length),
      );
      final Polyline border = lines.last;
      expect(border.color, GrobingColors.textMuted);
      expect(border.strokeWidth, 1.4);
      expect(border.points, hasLength(_map.outline.length + 1));

      expect(find.text('Polska'), findsOneWidget);
      for (final MapCity city in _map.cities) {
        // The halo under the letters, then the letters.
        expect(find.text(city.name), findsNWidgets(2), reason: city.name);
      }
      await cleanUp(tester);
    },
  );

  // Whether the labels stand apart is measured on the emulator (ISSUE-023 → Verification: 411 and 360 dp,
  // text 100% and 200%): a widget test draws every letter as a square of the test font, wider than Roboto,
  // so here the map stands alone — the bar and the search would overflow in that font, not on a phone.
  testWidgets(
    'AC-1 — at text 200% the map\'s labels grow only to 1.3× (cities 17 sp, "Polska" 28.6 sp), so they '
    'keep apart; text beside the map grows in full',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final MapController controller = MapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: GrobingTheme.dark,
          home: Scaffold(
            body: Column(
              children: [
                const Text('obok'),
                Expanded(
                  child: PolandMap(data: _map, controller: controller),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      double scaled(Finder text) =>
          MediaQuery.textScalerOf(tester.element(text)).scale(10) / 10;
      for (final MapCity c in _map.cities) {
        expect(scaled(find.text(c.name).last), 1.3, reason: c.name);
      }
      final Text polska = tester.widget(find.text('Polska'));
      expect(polska.textScaler!.scale(10) / 10, 1.3);
      expect(scaled(find.text('obok')), 2);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    },
  );

  // And a short 16:9 phone, 360 × 640 dp, where the room for the sheet makes Poland smallest.
  for (final (Size, double) phone in [
    ..._phones,
    (const Size(720, 1280), 2.0),
  ]) {
    testWidgets(
      'AC-1 — the edge of the data is never on the screen: at the least zoom, with the centre in any '
      'corner of Poland, the view stays inside the sea\'s box (${phone.$1.width ~/ phone.$2} dp wide)',
      (tester) async {
        await pumpHome(tester, phone: phone);
        final MapCamera camera = mapOf(tester).camera;
        final LatLngBounds sea = LatLngBounds.fromPoints([
          for (final MapArea a in _map.water) ...a.outer,
        ]);
        final LatLngBounds poland = _map.bounds;
        for (final LatLng corner in [
          poland.northWest,
          poland.northEast,
          poland.southWest,
          poland.southEast,
        ]) {
          final LatLngBounds view = camera
              .withPosition(center: corner, zoom: camera.minZoom)
              .visibleBounds;
          expect(sea.containsBounds(view), isTrue, reason: '$corner → $view');
        }
        await cleanUp(tester);
      },
    );
  }

  for (final (Size, double) phone in [
    ..._phones,
    (const Size(720, 1280), 2.0),
  ]) {
    testWidgets(
      'AC-1, D26 v2.6 (ui review) — the whole of Poland keeps the whole width, 16 dp at the sides, in the '
      'middle (${phone.$1.width ~/ phone.$2} × ${phone.$1.height ~/ phone.$2} dp): no room for a sheet '
      'shrinks it',
      (tester) async {
        await pumpHome(tester, phone: phone);
        final MapCamera camera = mapOf(tester).camera;
        final Rect area = tester.getRect(find.byType(FlutterMap));
        final double west = camera
            .latLngToScreenOffset(_map.bounds.northWest)
            .dx;
        final double east = camera
            .latLngToScreenOffset(_map.bounds.southEast)
            .dx;
        expect(east - west, closeTo(area.width - 32, 1));
        final double top = camera
            .latLngToScreenOffset(_map.bounds.northWest)
            .dy;
        final double bottom = camera
            .latLngToScreenOffset(_map.bounds.southEast)
            .dy;
        expect((top + bottom) / 2, closeTo(area.height / 2, 1));
        await cleanUp(tester);
      },
    );
  }

  /// Where Poland's box stands on the screen, in the map's own coordinates.
  ({double top, double bottom}) polandOnScreen(WidgetTester tester) {
    final MapCamera camera = mapOf(tester).camera;
    return (
      top: camera.latLngToScreenOffset(_map.bounds.northWest).dy,
      bottom: camera.latLngToScreenOffset(_map.bounds.southEast).dy,
    );
  }

  testWidgets(
    'AC-2 (D30) — without a sheet Poland stands in the middle; a candle → the map glides (not jumps) until '
    'Poland ends 16 dp above the sheet; a tap on the map closes it and Poland glides back to the middle',
    (tester) async {
      await warsawCemetery(tester);
      await pumpHome(tester);
      await _pumpUntil(
        tester,
        () => find.byType(CandlePin).evaluate().isNotEmpty,
      );
      final Rect area = tester.getRect(find.byType(FlutterMap));
      final ({double top, double bottom}) before = polandOnScreen(tester);
      expect((before.top + before.bottom) / 2, closeTo(area.height / 2, 1));
      final LatLng middle = mapOf(tester).camera.center;

      await tester.tap(find.byType(CandlePin));
      await tester.pump();
      // The glide starts after the frame that draws the sheet; its first tick is at 0 ms.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final double during = polandOnScreen(tester).bottom;
      await tester.pump(const Duration(milliseconds: 400));
      final double after = polandOnScreen(tester).bottom;

      expect(_sheet, findsOneWidget);
      final double sheetTop = tester.getRect(_sheet).top - area.top;
      expect(after, closeTo(sheetTop - 16, 1));
      expect(during, lessThan(before.bottom));
      expect(during, greaterThan(after));

      await tester.tapAt(area.topLeft + const Offset(60, 60));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_sheet, findsNothing);
      expect(
        mapOf(tester).camera.center.latitude,
        closeTo(middle.latitude, 1e-6),
      );
      expect(
        mapOf(tester).camera.center.longitude,
        closeTo(middle.longitude, 1e-6),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 (D2) — with "Usuń animacje" in the system the map jumps: Poland is above the sheet at once',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await warsawCemetery(tester);
      await pumpHome(tester);
      await _pumpUntil(
        tester,
        () => find.byType(CandlePin).evaluate().isNotEmpty,
      );
      final Rect area = tester.getRect(find.byType(FlutterMap));

      await tester.tap(find.byType(CandlePin));
      await tester.pump();
      await tester.pump();
      final double sheetTop = tester.getRect(_sheet).top - area.top;
      expect(polandOnScreen(tester).bottom, closeTo(sheetTop - 16, 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 (D2) — closer in, the old rule: the candle stands above the sheet, and closing the sheet leaves '
    'the map where it is',
    (tester) async {
      await warsawCemetery(tester);
      await pumpHome(tester);
      await _pumpUntil(
        tester,
        () => find.byType(CandlePin).evaluate().isNotEmpty,
      );
      final Rect area = tester.getRect(find.byType(FlutterMap));
      final MapController map = mapOf(tester);
      map.move(const LatLng(52.0, 21.0), map.camera.zoom + 3);
      await tester.pump();
      final double zoom = map.camera.zoom;

      await tester.tap(find.byType(CandlePin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final double sheetTop = tester.getRect(_sheet).top - area.top;
      expect(
        map.camera.latLngToScreenOffset(const LatLng(52.25, 21.0)).dy,
        lessThan(sheetTop),
      );
      final LatLng open = map.camera.center;

      await tester.tapAt(area.topLeft + const Offset(60, 60));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_sheet, findsNothing);
      expect(map.camera.zoom, zoom);
      expect(map.camera.center, open);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3 (6a, D3) — a cemetery without a photo: "Dodaj zdjęcie" left of the name, its own button with a '
    'tap action → the sheet "Zdjęcie cmentarza" → the photo in the sheet → the viewer → changed → deleted, '
    'and the field is back',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final int cemetery = await warsawCemetery(tester);
      picker.answers
        ..add(pickedPhoto(Directory('${tmp.path}/cache'), 1))
        ..add(pickedPhoto(Directory('${tmp.path}/cache'), 2));
      await pumpHome(tester);
      await _pumpUntil(
        tester,
        () => find.byType(CandlePin).evaluate().isNotEmpty,
      );
      await tester.tap(find.byType(CandlePin));
      await _settle(tester);

      // Its own node — not merged into the sheet (seen on the emulator) — with the tap Switch Access uses.
      final Finder field = find.bySemanticsLabel('Dodaj zdjęcie');
      expect(field, findsOneWidget);
      expect(
        tester.getSemantics(field),
        isSemantics(label: 'Dodaj zdjęcie', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getCenter(find.text('Dodaj zdjęcie')).dx,
        lessThan(tester.getCenter(find.text('Cmentarz Wymyślony')).dx),
      );

      await tester.tap(find.text('Dodaj zdjęcie'));
      await _settle(tester);
      expect(find.text('Zdjęcie cmentarza'), findsOneWidget);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(tester, () => _thumbnail.evaluate().isNotEmpty);
      expect(find.text('Dodaj zdjęcie'), findsNothing);
      expect(tester.getSize(_thumbnail), const Size(96, 80));

      await tester.tap(_thumbnail);
      await _settle(tester);
      expect(find.text('Zdjęcie cmentarza'), findsWidgets);
      expect(find.text('Cmentarz Wymyślony'), findsWidgets);
      String? shown() => find
          .byType(Image)
          .evaluate()
          .map((e) => (e.widget as Image).image)
          .whereType<FileImage>()
          .map((p) => p.file.path)
          .where((p) => p.contains('cmentarze'))
          .lastOrNull;
      await _pumpUntil(tester, () => shown() != null);
      final String first = shown()!;

      await tester.tap(find.text('Zmień zdjęcie'));
      await _settle(tester);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(tester, () => shown() != null && shown() != first);

      await tester.tap(find.text('Usuń zdjęcie'));
      await _settle(tester);
      expect(find.text('Usunąć zdjęcie?'), findsOneWidget);
      await tester.tap(find.text('Usuń'));
      await _pumpUntil(
        tester,
        () => find.text('Dodaj zdjęcie').evaluate().isNotEmpty,
      );
      expect(_thumbnail, findsNothing);
      semantics.dispose();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(
        await tester.runAsync(() => cemeteryPhotoPath(db, cemetery)),
        isNull,
      );
      // Both files are still there until the sweep (D3): the backup taken meanwhile needs them.
      expect(
        Directory(
          '${photos.mediaDir.path}/cmentarze/$cemetery',
        ).listSync().whereType<File>(),
        hasLength(2),
      );
      await cleanUp(tester);
    },
  );
}
