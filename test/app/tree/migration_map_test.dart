import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChannels;
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/app/photo/profile_circle.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/migration_map.dart';
import 'package:grobing/app/tree/tree_screen.dart';
import 'package:grobing/app/tree/tree_time.dart';
import 'package:grobing/data/cemeteries.dart' show GeoPoint;
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart' show PartialDate, QualifiedDate;
import 'package:grobing/data/residences.dart';
import 'package:grobing/dev/fictional_family.dart';
import 'package:grobing/dev/fictional_residences.dart';
import 'package:latlong2/latlong.dart';

import '../../support/a11y.dart';
import '../../support/photo_fakes.dart';

// ISSUE-045 — the migration map, the part "Mapa" of the Drzewo tab (05_DESIGN/mapa-migracji.md v1.1, drzewo.md v1.20 —
// W2), happy path per AC with the made-up family and its made-up residences (lib/dev; family-data.md):
// · the switch "Drzewo | Mapa" (element 1): the year, the tempo and ▶ stay; "Połącz dwie osoby" only on the tree;
// · AC-1 — the people of the year where they lived: a stack spreads, a person goes to the middle, the frame stays (R4);
//   a cluster of close places zooms in; no names of places or countries on the map (the author, 2026-10-17); a country
//   alone with no area (O3); the card's line (element 12);
// · AC-2 (rewritten, D2) — the card says where the person in the middle is in the year shown;
// · AC-3 — presentation: the map landscape, the switch in the controls, the same year on the tree;
// · AC-4 — the world from the app's own data (world_map_data_test.dart), nothing fetched;
// · "Pokaż na mapie" (osoba.md 9a, D22), the empty map, "ja" not chosen, text at 200 % on 360 dp, tap targets (retro 3, R2).

const MethodChannel _external = MethodChannel('grobing/external');

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, [
  String what = '',
]) async {
  for (int i = 0; i < 400; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('condition not met in time: $what');
}

bool _shown(Finder f) => f.evaluate().isNotEmpty;

/// A year written exactly, as a residence's "Od" or "Do".
QualifiedDate _y(int year) =>
    QualifiedDate(DateQualifier.exact, PartialDate(year));

/// A node of the reader by the start of its label: a person ("Marek Wymyślony, …"), a stack ("Testowo: 4 osoby").
Finder _node(String start) => find.byWidgetPredicate(
  (w) => w is Semantics && (w.properties.label?.startsWith(start) ?? false),
);

/// The people of the map: a node says "w środek", the one in the middle "otwórz".
Finder _mapPeople() => find.descendant(
  of: find.byType(MigrationMap),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        (w.properties.hint == 'w środek' || w.properties.hint == 'otwórz'),
  ),
);

/// Poland in the frame (R4): the frame a finger chose, kept while the app runs.
final LatLngBounds _poland = LatLngBounds(
  const LatLng(48.8, 13.5),
  const LatLng(55.2, 26.5),
);

void main() {
  late GrobingDatabase db;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
    treeTempo = TreeTempo.medium;
    migrationArea = null;
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await tester.runAsync(db.close);
  }

  /// The made-up family; with [residences] — its made-up residences too.
  Future<void> seed(WidgetTester tester, {bool residences = true}) async {
    await tester.runAsync(() async {
      await addFictionalFamily(db);
      if (residences) await addFictionalResidences(db);
    });
  }

  Future<int> personNamed(WidgetTester tester, String given, String surname) =>
      tester
          .runAsync(
            () =>
                (db.select(db.persons)..where(
                      (p) =>
                          p.givenNames.equals(given) &
                          p.surname.equals(surname),
                    ))
                    .get()
                    .then((p) => p.first.id),
          )
          .then((id) => id!);

  /// The phone 360 × 800 dp, the Drzewo tab — on its part "Mapa" with [map].
  Future<void> open(
    WidgetTester tester, {
    bool map = true,
    bool waitForMap = true,
    int? focus,
    double text = 1,
    Photos? photos,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: const Scaffold(body: Text('mapa')),
      ),
    );
    openTab(
      tester.element(find.text('mapa')),
      AppTab.tree,
      database: db,
      photos: photos,
      treeFocus: focus,
      treeMap: map,
    );
    await _pumpUntil(tester, () => _shown(find.byType(TreeScreen)));
    if (map && waitForMap) {
      await _pumpUntil(
        tester,
        () => _shown(find.byType(MigrationMap)),
        'the map on opening',
      );
    }
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// A tap in the middle of a node's rectangle.
  Future<void> tapNode(WidgetTester tester, Finder node) async {
    await tester.tapAt(tester.getCenter(node.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets(
    'element 1 (W2) — the switch "Drzewo | Mapa": the map\'s part has no "Połącz dwie osoby", the year and the tempo stay '
    'through a change of part, and ▶ runs on',
    (tester) async {
      await seed(tester);
      await open(tester, map: false);
      expect(find.byTooltip('Połącz dwie osoby'), findsOneWidget);
      expect(find.byType(MigrationMap), findsNothing);

      // A year and a tempo chosen on the tree.
      await tester.drag(find.byType(Slider), const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Tempo historii: średnio — zmień'));
      await tester.pump();
      final String year = tester
          .widget<Slider>(find.byType(Slider))
          .value
          .round()
          .toString();

      await tester.tap(find.byTooltip('Mapa'));
      await _pumpUntil(tester, () => _shown(find.byType(MigrationMap)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byTooltip('Połącz dwie osoby'), findsNothing);
      expect(
        tester.widget<Slider>(find.byType(Slider)).value.round().toString(),
        year,
      );
      expect(find.byTooltip('Tempo historii: szybko — zmień'), findsOneWidget);
      // The card's line of the map's part (element 12).
      expect(find.textContaining('W\u00A0$year: '), findsOneWidget);

      // ▶ on the map, then back to the tree: it runs on.
      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('Drzewo'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MigrationMap), findsNothing);
      expect(find.byTooltip('Zatrzymaj'), findsOneWidget);
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(double.parse(year)),
      );
      await tester.tap(find.byTooltip('Zatrzymaj'));
      await tester.pump();

      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-1, AC-2, R4 — "dziś" in Poland: Testowo\'s stack spreads, a touch puts a person in the middle, the card says '
    'where — and the frame stays; a country alone (Michał in Germany) with no area; no names on the map',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      migrationArea = _poland;
      await seed(tester);
      await open(tester);

      // "Ja" in the middle: the card's line of "dziś".
      expect(find.text('Dziś: Zmyślice, Polska'), findsOneWidget);

      final Finder testowo = _node('Testowo: 4 osoby');
      await _pumpUntil(tester, () => _shown(testowo));
      final Rect before = tester.getRect(testowo.first);
      expect(
        tester.getSemantics(testowo.first),
        matchesSemantics(
          label: 'Testowo: 4 osoby',
          hint: 'rozsuń',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Michał — "Niemcy · cały kraj" alone at the country's point; the reader hears the country.
      expect(
        _node('Michał Wymyślony, Mój brat, dziś Niemcy, cały kraj'),
        findsOneWidget,
      );
      // The author, 2026-10-17: "wystarczą awatary i kontury krajów" — no names of places or countries.
      for (final String name in const [
        'Testowo',
        'Zmyślice',
        'Niemcy',
        'Polska',
        'Litwa',
      ]) {
        expect(
          find.descendant(
            of: find.byType(MigrationMap),
            matching: find.textContaining(name),
          ),
          findsNothing,
          reason: name,
        );
      }

      // The stack spreads: each person has a node, with a first name under the circle.
      await tapNode(tester, testowo);
      final Finder marek = _node('Marek Wymyślony');
      expect(marek, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MigrationMap),
          matching: find.text('Marek'),
        ),
        // The halo and the letters (style-b.md rule 13).
        findsNWidgets(2),
      );

      // Marek to the middle: the card, and the frame where it was (R4 — only fingers move it).
      await tapNode(tester, marek);
      expect(find.text('Marek Wymyślony'), findsWidgets);
      expect(find.text('Dziś: Testowo, Polska'), findsOneWidget);
      expect(tester.getRect(_node('Testowo: 4 osoby').first), before);
      expect(migrationArea, _poland);

      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'the first frame is every place (R4): the towns of Poland, the USA and Germany far apart — the close ones a cluster, '
    'whose touch zooms in to its places',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await seed(tester);
      await open(tester);

      final Finder cluster = find.descendant(
        of: find.byType(MigrationMap),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.hint == 'przybliż',
        ),
      );
      await _pumpUntil(tester, () => _shown(cluster));
      expect(_node('Testowo: 4 osoby'), findsNothing);

      await tapNode(tester, cluster);
      await _pumpUntil(tester, () => _shown(_node('Testowo: 4 osoby')));
      // The zoom is the finger's frame now: kept while the app runs.
      expect(migrationArea, isNotNull);

      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3 — presentation from the map: landscape, the map without the pill; an empty touch shows the controls with the '
    'switch; "Drzewo" there shows the tree in the same year; "Zakończ prezentację" back to the map in portrait',
    (tester) async {
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        _external,
        (call) async => switch (call.method) {
          'openCastSettings' => true,
          _ => null,
        },
      );
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(_external, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      migrationArea = _poland;
      await seed(tester);
      await open(tester);
      await tester.drag(find.byType(Slider), const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      final double year = tester.widget<Slider>(find.byType(Slider)).value;

      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.view.physicalSize = const Size(2400, 1080);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(MigrationMap), findsOneWidget);
      expect(find.byType(GrobingTabBar), findsNothing);
      expect(find.textContaining('na mapie'), findsNothing);
      expect(find.byTooltip('Mapa'), findsNothing);

      // An empty touch — the sea west of Norway, nobody there — shows the controls with the switch.
      await tester.tapAt(const Offset(60, 120));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Zakończ prezentację'), findsOneWidget);
      expect(find.byTooltip('Drzewo'), findsOneWidget);

      await tester.tap(find.byTooltip('Drzewo'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(MigrationMap), findsNothing);
      expect(tester.widget<Slider>(find.byType(Slider)).value, year);

      expect(find.byTooltip('Mapa'), findsOneWidget);
      await tester.tap(find.byTooltip('Mapa'));
      await _pumpUntil(
        tester,
        () => _shown(find.byType(MigrationMap)),
        'the map again in presentation',
      );
      await tester.tap(find.text('Zakończ prezentację'));
      tester.view.physicalSize = const Size(1080, 2400);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(GrobingTabBar), findsOneWidget);
      expect(find.byType(MigrationMap), findsOneWidget);

      await cleanUp(tester);
    },
  );

  testWidgets(
    '"Pokaż na mapie" (osoba.md 9a, D22): in the view of a person with residences, to the map\'s part with them in '
    'the middle; a person without residences has no such button',
    (tester) async {
      await seed(tester);
      final int marek = await personNamed(tester, 'Marek', 'Wymyślony');
      final int bolek = await personNamed(tester, 'Bolesław', 'Testowiak');
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: GrobingTheme.dark,
          home: const Scaffold(body: Text('mapa')),
        ),
      );
      openPersonView(
        tester.element(find.text('mapa')),
        db,
        marek,
        tab: AppTab.tree,
      );
      await _pumpUntil(
        tester,
        () => _shown(find.text('Marek Wymyślony')),
        'the view of Marek',
      );
      await tester.scrollUntilVisible(
        find.text('Pokaż na mapie'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Pokaż na mapie'));
      await _pumpUntil(tester, () => _shown(find.byType(MigrationMap)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Dziś: Testowo, Polska'), findsOneWidget);
      expect(find.text('Marek Wymyślony'), findsWidgets);

      // Bolesław: no residences — no button (the section says how to add one).
      openPersonView(
        tester.element(find.byType(TreeScreen)),
        db,
        bolek,
        tab: AppTab.tree,
      );
      await _pumpUntil(
        tester,
        () => _shown(find.text('Bolesław Testowiak')),
        'the view of Bolesław',
      );
      await tester.scrollUntilVisible(
        find.text('Dodaj miejsce'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Pokaż na mapie'), findsNothing);

      await cleanUp(tester);
    },
  );

  testWidgets(
    'the empty map: people, but nobody with a residence — the words of States, the pill gone',
    (tester) async {
      await seed(tester, residences: false);
      await open(tester);
      expect(
        find.text(
          'Tu pojawią się miejsca, w\u00A0których mieszkała rodzina. Dodasz je w\u00A0widoku osoby.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('na mapie:'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets('"ja" not chosen: the map\'s part says it as the tree does', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(
      () => db
          .update(db.settings)
          .write(const SettingsCompanion(mePersonId: Value(null))),
    );
    await open(tester, waitForMap: false);
    await _pumpUntil(
      tester,
      () => _shown(find.text('Aplikacja nie wie jeszcze, która osoba to Ty.')),
      'the words of no "ja"',
    );
    expect(find.byTooltip('Mapa'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets(
    'element 8 — a move is not cut short by the next year: with ▶ the circle glides on from where it had got to, and '
    'arrives after the last year',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      // The west of Europe in the frame: France, Britain and Spain — nobody else of the family there in 2000–2002,
      // and far from Poland's stacks (a person next to a stack joins it and has no node of their own).
      migrationArea = LatLngBounds(const LatLng(34, -14), const LatLng(60, 30));
      await seed(tester);
      final int marek = await personNamed(tester, 'Marek', 'Wymyślony');
      ResidencePlace country(
        String code,
        String name,
        double lat,
        double lon,
      ) => ResidencePlace.country(
        countryCode: code,
        countryName: name,
        point: GeoPoint(lat, lon),
      );
      // A move every year: France to 2000, Britain in 2001, Spain from 2002 — the labels' points of the data.
      await tester.runAsync(
        () => writeResidences(db, marek, [
          Residence(
            from: null,
            to: _y(2000),
            place: country('FR', 'Francja', 46.696, 2.552),
          ),
          Residence(
            from: _y(2001),
            to: _y(2001),
            place: country('GB', 'Wielka Brytania', 54.403, -2.116),
          ),
          Residence(
            from: _y(2002),
            to: null,
            place: country('ES', 'Hiszpania', 40.091, -3.465),
          ),
        ]),
      );
      await open(tester, focus: marek);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(2000);
      // A frame for the move by hand to start in, and one after it has arrived.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final Finder circle = _node('Marek Wymyślony');
      await _pumpUntil(tester, () => _shown(circle), 'Marek in France');
      Offset where() => tester.getCenter(circle.first);
      final Offset france = where();

      // ▶ at "Średnio": a year in 100 ms, a move in 600 ms.
      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // 2001: to Britain
      await tester.pump(const Duration(milliseconds: 90));
      final Offset before = where();
      expect((before - france).distance, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 10)); // 2002: to Spain
      final Offset after = where();
      // On from where it had got to — about 1 px further; cut short, it jumped to Britain (about 100 px).
      expect((after - before).distance, lessThan(20));

      await tester.tap(find.byTooltip('Zatrzymaj'));
      await tester.pump(const Duration(milliseconds: 300));
      final Offset halfway = where();
      await tester.pump(const Duration(milliseconds: 700));
      final Offset spain = where();
      expect((halfway - after).distance, greaterThan(20));
      expect((spain - halfway).distance, greaterThan(20));
      await tester.pump(const Duration(milliseconds: 200));
      expect(where(), spain);

      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'element 8 — a move starts where the circle was drawn: from its place in a stack, not from the place\'s point',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      migrationArea = _poland;
      await seed(tester);
      final int marek = await personNamed(tester, 'Marek', 'Wymyślony');
      // Marek in Testowo's stack to 2000, then alone in Germany from 2001 (Natural Earth's label point).
      await tester.runAsync(() async {
        final Residence testowo = (await residencesOf(db, marek)).single;
        await writeResidences(db, marek, [
          Residence(
            id: testowo.id,
            from: testowo.from,
            to: _y(2000),
            place: testowo.place,
          ),
          Residence(
            from: _y(2001),
            place: const ResidencePlace.country(
              countryCode: 'DE',
              countryName: 'Niemcy',
              point: GeoPoint(50.962, 9.678),
            ),
          ),
        ]);
      });
      await open(tester, focus: marek);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(2000);
      // A frame for the move by hand to start in, and one after it has arrived.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final Finder stack = _node('Testowo:');
      await _pumpUntil(tester, () => _shown(stack), 'Testowo\'s stack');
      // The one in the middle is the stack's first circle: half a target in from the stack's left edge.
      final Rect box = tester.getRect(stack.first);
      final Offset inStack = Offset(box.left + 24, box.center.dy);

      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // 2001: to Germany
      final Offset first = tester.getCenter(_node('Marek Wymyślony').first);
      // From the stack — from the place's point it started in the stack's middle, 34 dp away.
      expect((first - inStack).distance, lessThan(2));
      await tester.tap(find.byTooltip('Zatrzymaj'));
      await tester.pump(const Duration(milliseconds: 700));

      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D26 — avatars: a profile photo on the map for everyone who has one, "ja" too, not "Ja"; the initials for the others',
    (tester) async {
      final Directory tmp = Directory.systemTemp.createTempSync('map_avatars');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final Photos photos = fakePhotos(tmp);
      migrationArea = _poland;
      await seed(tester);
      await tester.runAsync(() => addFictionalPortraits(db, photos.mediaDir));
      await open(tester, photos: photos);
      await _pumpUntil(tester, () => _shown(_mapPeople()), 'people');

      Finder onMap(Finder f) =>
          find.descendant(of: find.byType(MigrationMap), matching: f);
      // "Ja" (Zmyślice, the first of its stack) — a photo, not the mark; others with a portrait too.
      expect(onMap(find.text('Ja')), findsNothing);
      expect(onMap(find.byType(ProfileCircle)), findsWidgets);
      // Without a photo — the initials (Marek has a portrait, Stanisław in Testowo's stack has not).
      expect(onMap(find.text('SW')), findsOneWidget);

      await cleanUp(tester);
    },
  );

  testWidgets(
    'text 200 % on 360 dp: the switch is its icons alone in both parts — one shape under the finger',
    (tester) async {
      // The test font draws every letter as a square: the bottom bar (lib/app/tabs.dart, not this item's) overflows
      // in it at 200 % and not on a phone (emulator: screenshot r10) — only that overflow is let through, as in
      // tree_screen_test AC-7.
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final String error = details.toString();
        if (error.contains('overflowed') &&
            error.contains('lib/app/tabs.dart')) {
          return;
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      await seed(tester);
      await open(tester, map: false, text: 2);
      Finder words(String part) =>
          find.descendant(of: find.byTooltip(part), matching: find.text(part));
      expect(words('Drzewo'), findsNothing);
      await tester.tap(find.byTooltip('Mapa'));
      await _pumpUntil(tester, () => _shown(find.byType(MigrationMap)));
      expect(words('Mapa'), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanUp(tester);
    },
  );

  testWidgets('tap targets and labels of the map\'s part (retro 3, R2)', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    migrationArea = _poland;
    await seed(tester);
    await open(tester);
    await _pumpUntil(tester, () => _shown(_mapPeople()));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expectEveryButtonTappable(tester);
    semantics.dispose();
    await cleanUp(tester);
  });
}
