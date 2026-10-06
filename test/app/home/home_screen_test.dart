import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/data_state_screen.dart';
import 'package:grobing/app/grobing_app.dart';
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

final PolandMapData _map = PolandMapData.fromJson(
  File(PolandMapData.asset).readAsStringSync(),
);

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

  Future<void> pumpHome(WidgetTester tester) async {
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
      expect(find.text('Nie ma cmentarza „cmentarz leśny”.'), findsOneWidget);
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
}
