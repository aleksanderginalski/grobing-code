import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/here_location.dart';
import 'package:grobing/app/grave/pin_screen.dart';
import 'package:grobing/app/map/plan_downloads.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/net/overpass_plan_source.dart';
import 'package:latlong2/latlong.dart';

// ISSUE-029 — the pin at the grave (05_DESIGN/cmentarz.md v7, elements 10, 10a, 11, 12, 12a; grob.md v7, element 4),
// happy path per AC: US-008 AC-1 "gdzie jestem" with the blue dot, the system's question and a refusal · AC-2 a pin
// placed in the dot (GPS) and by hand (the plan), saved with its source and date · AC-3 a pin corrected from its
// candle · AC-4 without the internet · the weak signal (D37) · the person's "Pochówek" (osoba.md D9). The phone's
// position is faked: nothing native, nothing leaves the test. Invented cemeteries, people and points only
// (family-data.md).

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

/// A few frames for the screen's own measuring: the panel's height places "gdzie jestem" a frame later.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

const GeoPoint _point = GeoPoint(51.5, 19.5);
const LatLng _inside = LatLng(51.5001, 19.5002);

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
];

class _Offline implements PlanSource {
  @override
  Future<PlanResult> fetch(GeoPoint point) async => const PlanOffline();
}

/// The phone's location as the test says: what the app may know, the system's answer, the positions.
class _FakeHere implements HereLocation {
  HereAccess now = HereAccess.denied;
  HereAccess answer = HereAccess.precise;
  bool switchedOn = true;
  int asked = 0;
  int appSettings = 0;
  final StreamController<HereSignal> _signals =
      StreamController<HereSignal>.broadcast();

  void send(LatLng p, double accuracy) => _signals.add(HereFix(p, accuracy));

  /// A screen listens — a position sent before it would be lost.
  bool get listening => _signals.hasListener;

  @override
  Future<HereAccess> access() async => now;

  @override
  Future<HereAccess> request() async {
    asked++;
    now = answer == HereAccess.blocked ? HereAccess.denied : answer;
    return answer;
  }

  @override
  Future<bool> enabled() async => switchedOn;

  @override
  Stream<HereSignal> signals() => _signals.stream;

  @override
  Future<void> openAppSettings() async => appSettings++;

  @override
  Future<void> openLocationSettings() async {}
}

/// Opens [screen] from a button, as the cemetery or the grave does, and keeps what it returned.
class _Host extends StatefulWidget {
  const _Host({required this.screen, required this.results});

  final Widget screen;
  final List<Object?> results;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final Object? r = await Navigator.of(context).push<Object?>(
            MaterialPageRoute<Object?>(builder: (_) => widget.screen),
          );
          widget.results.add(r);
        },
        child: const Text('otwórz'),
      ),
    ),
  );
}

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  /// A cemetery with its plan, a sector "B" with a zone, and two invented graves: one with a GPS pin, one
  /// in sector B without a pin. Returns the cemetery and the two graves.
  Future<({int cemetery, int pinned, int bare})> cemeteryWithGraves(
    WidgetTester tester, {
    bool plan = true,
  }) async {
    late int cemetery, pinned, bare;
    await tester.runAsync(() async {
      cemetery = await addCemetery(
        db,
        name: 'Cmentarz Wymyślony',
        locality: 'Wymyślin',
        point: _point,
      );
      if (plan) {
        await savePlan(
          db,
          cemetery,
          forPoint: _point,
          areas: _areas,
          paths: _paths,
          server: 'overpass.example',
        );
      }
      pinned = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
      );
      await setGravePin(
        db,
        pinned,
        // North of the plan: the pill "Kwatery" covers its south-west corner (ISSUE-028).
        const GeoPoint(51.5012, 19.5005),
        PositionSource.gps,
        accuracyM: 7,
        clock: () => DateTime(2026, 10, 12),
      );
      bare = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Piotr', surname: 'Zmyślony'),
      );
      await setGraveDetails(db, bare, sector: 'B', row: '4', plot: '12');
      final int sector = (await db.select(db.sectors).getSingle()).id;
      await (db.update(db.sectors)..where((s) => s.id.equals(sector))).write(
        const SectorsCompanion(
          zone: Value(
            '[51.5002,19.5002,51.5002,19.5008,51.5008,19.5008,51.5008,19.5002]',
          ),
        ),
      );
    });
    return (cemetery: cemetery, pinned: pinned, bare: bare);
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Widget home,
    _FakeHere here, {
    bool network = true,
    double textScale = 1,
    Size size = const Size(1080, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final PlanDownloads plans = PlanDownloads(database: db, source: _Offline());
    addTearDown(plans.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        builder: (context, child) => MapHereLocation(
          location: here,
          child: network
              ? MapNetwork(
                  plans: plans,
                  photoReachable: () async => false,
                  child: child!,
                )
              : child!,
        ),
        home: home,
      ),
    );
  }

  /// The grave's pin as stored. The screen comes off first: a read in `runAsync` with a screen still watching
  /// the database hangs (README → Testy, the second trap).
  Future<GravePin?> pinOf(WidgetTester tester, int grave) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    GravePin? pin;
    await tester.runAsync(() async => pin = (await loadGrave(db, grave))!.pin);
    return pin;
  }

  testWidgets(
    'US-008 AC-1 — "gdzie jestem": off, the system\'s question, then the blue dot with "tu jesteś · ±5 m" and the '
    'button on; on the dot a tap switches it off',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere();
      await pumpApp(
        tester,
        CemeteryScreen(database: db, cemeteryId: ids.cemetery),
        here,
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await _settle(tester);
      expect(find.bySemanticsLabel('Gdzie jestem, wyłączone'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Gdzie jestem, wyłączone'));
      await _pumpUntil(tester, () => here.asked == 1);
      await _pumpUntil(tester, () => _shown(find.text('Szukam pozycji…')));

      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 5);
      await _pumpUntil(tester, () => _shown(find.text('tu jesteś · ±5 m')));
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(
        find.bySemanticsLabel('Gdzie jestem, włączone, ±5 m'),
        findsOneWidget,
      );
      expect(find.text('Szukam pozycji…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.bySemanticsLabel('Gdzie jestem, włączone, ±5 m'));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Gdzie jestem, wyłączone')),
      );
      expect(find.text('tu jesteś · ±5 m'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-008 AC-1 — a refusal: "Bez zgody na lokalizację pinezki postawisz tylko ręcznie."; refused twice: the same '
    'with "Ustawienia" → the app\'s settings; only "Przybliżona": no dot, "tylko przybliżona lokalizacja"; a '
    'position far away: "poza cmentarzem · …"',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..answer = HereAccess.denied;
      await pumpApp(
        tester,
        CemeteryScreen(database: db, cemeteryId: ids.cemetery),
        here,
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Gdzie jestem, wyłączone'));
      await _pumpUntil(
        tester,
        () => _shown(
          find.text(
            'Bez zgody na lokalizację pinezki postawisz tylko ręcznie.',
          ),
        ),
      );
      expect(find.text('Ustawienia'), findsNothing);
      expect(find.bySemanticsLabel('Gdzie jestem, wyłączone'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      here.answer = HereAccess.blocked;
      await tester.tap(find.bySemanticsLabel('Gdzie jestem, wyłączone'));
      await _pumpUntil(tester, () => _shown(find.text('Ustawienia')));
      // The bar slides in; its action takes a touch once it stands.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Ustawienia'));
      await _pumpUntil(tester, () => here.appSettings == 1);
      await tester.pump(const Duration(seconds: 5));

      here.now = HereAccess.approximate;
      await tester.tap(find.bySemanticsLabel('Gdzie jestem, wyłączone'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('tylko przybliżona lokalizacja')),
      );
      // Approximate access: nothing is listened to, no dot is drawn (element 10a (c)).
      await tester.pump(const Duration(milliseconds: 200));
      expect(here.listening, isFalse);
      expect(find.byType(CircleLayer), findsNothing);
      await tester.tap(find.bySemanticsLabel('Gdzie jestem, włączone'));
      await tester.pump(const Duration(milliseconds: 200));

      here.now = HereAccess.precise;
      await tester.tap(find.bySemanticsLabel('Gdzie jestem, wyłączone'));
      await tester.pump();
      await _pumpUntil(tester, () => here.listening);
      here.send(const LatLng(51.6, 19.5), 5);
      await _pumpUntil(
        tester,
        () => _shown(find.textContaining('poza cmentarzem · 11')),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-008 AC-2 — a grave without a pin → "Postaw pinezkę" → mode D: the candle in the dot, "Pinezka: GPS ±5 m" → '
    '"Zapisz pinezkę": the pin saved as GPS with its accuracy and date; the grave view says it',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      await pumpApp(tester, GraveScreen(database: db, graveId: ids.bare), here);
      await _pumpUntil(tester, () => _shown(find.text('Postaw pinezkę')));
      expect(
        find.text('Kwatera B · Rząd 4 · Miejsce 12 · bez pinezki'),
        findsOneWidget,
      );
      await tester.tap(find.text('Postaw pinezkę'));
      await _pumpUntil(tester, () => _shown(find.text('Pinezka grobu')));
      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 5);
      await _pumpUntil(tester, () => _shown(find.text('Pinezka: GPS ±5 m')));
      expect(_rich('Stań przy grobie.'), findsOneWidget);
      expect(find.text('Kwatera B · Rząd 4 · Miejsce 12'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Gdzie jestem, włączone, ±5 m'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Zapisz pinezkę'));
      await _pumpUntil(tester, () => !_shown(find.text('Pinezka grobu')));
      final GravePin pin = (await pinOf(tester, ids.bare))!;
      expect(pin.source, PositionSource.gps);
      expect(pin.accuracyM, 5);
      expect(pin.point.lat, closeTo(_inside.latitude, 1e-9));
      expect(pin.point.lon, closeTo(_inside.longitude, 1e-9));
      expect(pin.recordedAt, isNotNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-008 AC-2 — a finger moves the plan: the pin becomes "postawiona na planie", the card says how to place it '
    'by hand; saved without an accuracy; mode D returns PinSaved for the cemetery to show the grave (D36)',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      final List<Object?> results = [];
      await pumpApp(
        tester,
        _Host(
          results: results,
          screen: PinScreen(
            database: db,
            cemeteryId: ids.cemetery,
            graveId: ids.bare,
          ),
        ),
        here,
      );
      await tester.tap(find.text('otwórz'));
      await _pumpUntil(tester, () => _shown(find.text('Pinezka grobu')));
      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 5);
      await _pumpUntil(tester, () => _shown(find.text('Pinezka: GPS ±5 m')));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.drag(find.byType(FlutterMap), const Offset(-120, -160));
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Pinezka: postawiona na planie')),
      );
      expect(
        _rich('Przesuń plan tak, żeby znicz stał na grobie.'),
        findsOneWidget,
      );
      // A new position no longer moves a pin the author placed.
      await _pumpUntil(tester, () => here.listening);
      here.send(const LatLng(51.5003, 19.5003), 5);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pinezka: postawiona na planie'), findsOneWidget);

      await tester.tap(find.text('Zapisz pinezkę'));
      await _pumpUntil(tester, () => results.isNotEmpty);
      expect(results.single, isA<PinSaved>());
      expect((results.single! as PinSaved).graveId, ids.bare);
      final GravePin pin = (await pinOf(tester, ids.bare))!;
      expect(pin.source, PositionSource.plan);
      expect(pin.accuracyM, isNull);
      expect(pin.point.lat, isNot(closeTo(_inside.latitude, 1e-7)));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D37 — a GPS position worse than 15 m: "Słaby sygnał: ±25 m. Przesuń plan…", saving still possible with "GPS '
    '±25 m"; ✕ leaves without a pin',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      final List<Object?> results = [];
      await pumpApp(
        tester,
        _Host(
          results: results,
          screen: PinScreen(
            database: db,
            cemeteryId: ids.cemetery,
            graveId: ids.bare,
          ),
        ),
        here,
      );
      await tester.tap(find.text('otwórz'));
      await _pumpUntil(tester, () => _shown(find.text('Pinezka grobu')));
      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 25);
      await _pumpUntil(
        tester,
        () => _shown(
          find.text(
            'Słaby sygnał: ±25 m. Przesuń plan tak, żeby znicz stał na grobie.',
          ),
        ),
      );
      expect(find.text('Pinezka: GPS ±25 m'), findsOneWidget);
      final FilledButton save = tester.widget(
        find.widgetWithText(FilledButton, 'Zapisz pinezkę'),
      );
      expect(save.onPressed, isNotNull);

      await tester.tap(find.byTooltip('Anuluj'));
      await _pumpUntil(tester, () => results.isNotEmpty);
      expect(results.single, isNull);
      expect(await pinOf(tester, ids.bare), isNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-008 AC-3 — a candle → B → "Popraw pinezkę" → mode D where the pin is: "Teraz: GPS ±7 m · 12.10.2026", '
    '"Zapisz pinezkę" inactive; "gdzie jestem" → the dot, "Po zapisie: GPS ±5 m" → saved → B with that grave',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      await pumpApp(
        tester,
        CemeteryScreen(database: db, cemeteryId: ids.cemetery),
        here,
      );
      await _pumpUntil(tester, () => _shown(find.text('Plan offline')));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Grób: Jan Wymyślony'));
      await _pumpUntil(tester, () => _shown(find.text('Popraw pinezkę')));
      expect(find.text('Pokaż grób'), findsOneWidget);

      await _settle(tester);
      await tester.tap(find.text('Popraw pinezkę'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Teraz: GPS ±7 m · 12.10.2026')),
      );
      final FilledButton save = tester.widget(
        find.widgetWithText(FilledButton, 'Zapisz pinezkę'),
      );
      expect(save.onPressed, isNull);

      // ui review M2: "gdzie jestem" before any position moves nothing, so "Zapisz" stays inactive.
      // The cemetery under mode D has its own button: mode D's, once the route has come in.
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(PinScreen),
          // The button with its state, not the icon in the card's words.
          matching: find.bySemanticsLabel(RegExp(r'^Gdzie jestem, ')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Teraz: GPS ±7 m · 12.10.2026'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zapisz pinezkę'),
            )
            .onPressed,
        isNull,
      );
      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 5);
      await _pumpUntil(tester, () => _shown(find.text('Po zapisie: GPS ±5 m')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Zapisz pinezkę'));
      await _pumpUntil(tester, () => !_shown(find.text('Pinezka grobu')));
      await _pumpUntil(tester, () => _shown(find.text('Popraw pinezkę')));
      expect(find.text('Pokaż grób'), findsOneWidget);
      final GravePin pin = (await pinOf(tester, ids.pinned))!;
      expect(pin.source, PositionSource.gps);
      expect(pin.accuracyM, 5);
      expect(pin.point.lat, closeTo(_inside.latitude, 1e-9));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-008 AC-4 — without the internet (no map network at all): the plan from the phone, the dot and mode D work '
    'and the pin is saved',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      final List<Object?> results = [];
      await pumpApp(
        tester,
        _Host(
          results: results,
          screen: PinScreen(
            database: db,
            cemeteryId: ids.cemetery,
            graveId: ids.bare,
          ),
        ),
        here,
        network: false,
      );
      await tester.tap(find.text('otwórz'));
      await _pumpUntil(tester, () => _shown(find.text('Pinezka grobu')));
      expect(find.text('© OpenStreetMap'), findsOneWidget);
      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 4);
      await _pumpUntil(tester, () => _shown(find.text('Pinezka: GPS ±4 m')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Zapisz pinezkę'));
      await _pumpUntil(tester, () => results.isNotEmpty);
      expect((await pinOf(tester, ids.bare))!.source, PositionSource.gps);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ui review M3 — a cemetery without a plan and without the photo: no map to stand a pin on, so "Zapisz pinezkę" '
    'waits for the dot, and the pin is saved as GPS',
    (tester) async {
      final ids = await cemeteryWithGraves(tester, plan: false);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      final List<Object?> results = [];
      await pumpApp(
        tester,
        _Host(
          results: results,
          screen: PinScreen(
            database: db,
            cemeteryId: ids.cemetery,
            graveId: ids.bare,
          ),
        ),
        here,
        network: false,
      );
      await tester.tap(find.text('otwórz'));
      await _pumpUntil(
        tester,
        () => _shown(_rich('Planu tego cmentarza nie ma w telefonie.')),
      );
      expect(_rich('Bez planu pinezkę postawisz tylko z GPS'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zapisz pinezkę'),
            )
            .onPressed,
        isNull,
      );
      await _pumpUntil(tester, () => here.listening);
      here.send(const LatLng(51.5001, 19.5001), 6);
      await _pumpUntil(tester, () => _shown(find.text('Pinezka: GPS ±6 m')));
      await tester.tap(find.text('Zapisz pinezkę'));
      await _pumpUntil(tester, () => results.isNotEmpty);
      final GravePin pin = (await pinOf(tester, ids.bare))!;
      expect(pin.source, PositionSource.gps);
      expect(pin.accuracyM, 6);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'grob.md v7 element 4, D14 — a grave with a pin says its source and date and has no "Postaw pinezkę"',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      await pumpApp(
        tester,
        GraveScreen(database: db, graveId: ids.pinned),
        _FakeHere(),
      );
      await _pumpUntil(
        tester,
        () => _shown(find.text('Pinezka: GPS ±7 m · 12.10.2026')),
      );
      expect(find.text('Postaw pinezkę'), findsNothing);
      expect(_rich('Bez adresu kwatery'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'osoba.md D9 — a person\'s "Pochówek" to a grave without a pin: the list with the grave marked and "Ten grób nie '
    'ma jeszcze pinezki — jest zaznaczony na liście."',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      await pumpApp(
        tester,
        CemeteryScreen(
          database: db,
          cemeteryId: ids.cemetery,
          highlightGraveId: ids.bare,
        ),
        _FakeHere(),
      );
      await _pumpUntil(
        tester,
        () => _shown(
          find.text(
            'Ten grób nie ma jeszcze pinezki — jest zaznaczony na liście.',
          ),
        ),
      );
      expect(find.text('Pokaż mapę'), findsNothing); // a semantics label only
      await cleanUp(tester);
    },
  );

  testWidgets(
    'element 12 at 200% on 360 × 640 dp: the card, the panel and both buttons of mode D are on the screen',
    (tester) async {
      final ids = await cemeteryWithGraves(tester);
      final _FakeHere here = _FakeHere()..now = HereAccess.precise;
      await pumpApp(
        tester,
        PinScreen(database: db, cemeteryId: ids.cemetery, graveId: ids.bare),
        here,
        textScale: 2,
        size: const Size(1080, 1920),
      );
      await _pumpUntil(tester, () => _shown(find.text('Pinezka grobu')));
      await _pumpUntil(tester, () => here.listening);
      here.send(_inside, 5);
      await _pumpUntil(tester, () => _shown(find.text('Pinezka: GPS ±5 m')));
      final Size screen =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final String t in [
        'Anuluj',
        'Zapisz pinezkę',
        'Pinezka: GPS ±5 m',
      ]) {
        final Rect r = tester.getRect(find.text(t).last);
        expect(r.bottom, lessThanOrEqualTo(screen.height), reason: t);
        expect(r.right, lessThanOrEqualTo(screen.width), reason: t);
      }
      expect(tester.takeException(), isNull);
      await cleanUp(tester);
    },
  );
}
