import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/here_location.dart';
import 'package:grobing/app/polish.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:latlong2/latlong.dart';

// ISSUE-029 — the pin's data and words (lib/data/graves.dart → setGravePin; lib/app/polish.dart; lib/app/grave/
// here_location.dart): US-008 AC-2 a pin saved with its source, accuracy and date; cmentarz.md D33 — the
// accuracy only for a GPS pin; element 14 — the pin's line; 10a — "poza cmentarzem" and the distance; 12a —
// the temporary weak-signal threshold. Made-up cemeteries and people only (family-data.md).

const PersonEntry _jan = PersonEntry(givenNames: 'Jan', surname: 'Wymyślony');

void main() {
  late GrobingDatabase db;
  late int cemetery;
  late int grave;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    cemetery = await addCemetery(
      db,
      name: 'Cmentarz Wymyślony',
      point: const GeoPoint(52.5, 19.5),
    );
    grave = await addPersonToNewGrave(db, cemeteryId: cemetery, entry: _jan);
  });

  tearDown(() => db.close());

  DateTime at() => DateTime(2026, 10, 12, 14, 30);

  test(
    'US-008 AC-2 — a GPS pin is saved with its point, source, the phone\'s accuracy and the date; the '
    'grave view and the cemetery\'s list read it back',
    () async {
      expect((await loadGrave(db, grave))!.hasPin, isFalse);

      await setGravePin(
        db,
        grave,
        const GeoPoint(52.50012, 19.50034),
        PositionSource.gps,
        accuracyM: 4.6,
        clock: at,
      );

      final GravePin pin = (await loadGrave(db, grave))!.pin!;
      expect(pin.point, const GeoPoint(52.50012, 19.50034));
      expect(pin.source, PositionSource.gps);
      expect(pin.accuracyM, 4.6);
      expect(pin.recordedAt, at());
      final GraveSummary summary = (await loadCemeteryGraves(
        db,
        cemetery,
      ))!.graves.single;
      expect(summary.hasPin, isTrue);
      expect(summary.pin, const GeoPoint(52.50012, 19.50034));
      expect(summary.pinned!.source, PositionSource.gps);
    },
  );

  test(
    'D33 — a pin placed by hand on the plan or on the photo keeps no accuracy, whatever is passed; a '
    'correction replaces the point, the source and the date',
    () async {
      await setGravePin(
        db,
        grave,
        const GeoPoint(52.5, 19.5),
        PositionSource.gps,
        accuracyM: 7,
        clock: at,
      );
      await setGravePin(
        db,
        grave,
        const GeoPoint(52.5001, 19.5002),
        PositionSource.plan,
        accuracyM: 7,
        clock: () => DateTime(2026, 11, 2, 10),
      );
      GravePin pin = (await loadGrave(db, grave))!.pin!;
      expect(pin.point, const GeoPoint(52.5001, 19.5002));
      expect(pin.source, PositionSource.plan);
      expect(pin.accuracyM, isNull);
      expect(pin.recordedAt, DateTime(2026, 11, 2, 10));

      await setGravePin(
        db,
        grave,
        const GeoPoint(52.5003, 19.5004),
        PositionSource.satellite,
        clock: at,
      );
      pin = (await loadGrave(db, grave))!.pin!;
      expect(pin.source, PositionSource.satellite);
      expect(pin.accuracyM, isNull);
    },
  );

  test(
    'a pin for a grave that is not there is an error, not a silent no-op',
    () async {
      expect(
        () => setGravePin(db, 999, const GeoPoint(52, 19), PositionSource.plan),
        throwsStateError,
      );
    },
  );

  test(
    'element 14 — the pin\'s line: "GPS ±4 m · 12.10.2026" (whole metres), "postawiona na planie", '
    '"postawiona na zdjęciu z góry"; without a date (pins before v12) no "· date"',
    () {
      final DateTime d = DateTime(2026, 10, 12, 14, 30);
      expect(pinLine(PositionSource.gps, 4.4, d), 'GPS ±4 m · 12.10.2026');
      expect(pinLine(PositionSource.gps, 4.6, d), 'GPS ±5 m · 12.10.2026');
      expect(
        pinLine(PositionSource.plan, null, d),
        'postawiona na planie · 12.10.2026',
      );
      expect(
        pinLine(PositionSource.satellite, null, DateTime(2026, 1, 3)),
        'postawiona na zdjęciu z góry · 03.01.2026',
      );
      expect(pinLine(PositionSource.gps, 6, null), 'GPS ±6 m');
      expect(pinSourceText(PositionSource.gps, null), 'GPS');
      expect(
        addressLine('Kwatera B · Rząd 4 · Miejsce 12', hasPin: true),
        'Kwatera B · Rząd 4 · Miejsce 12',
      );
    },
  );

  test(
    'element 10a — at the cemetery: inside its box grown by 100 m, or within 500 m of its point without a '
    'plan; the distance in metres (tens), 1–10 km with one decimal, whole kilometres beyond',
    () {
      const LatLng sw = LatLng(52.0, 19.0), ne = LatLng(52.01, 19.01);
      const ({LatLng southWest, LatLng northEast}) box = (
        southWest: sw,
        northEast: ne,
      );
      expect(atCemetery(const LatLng(52.005, 19.005), box: box), isTrue);
      // About 55 m north of the box: still at the cemetery.
      expect(atCemetery(const LatLng(52.0105, 19.005), box: box), isTrue);
      // About 1.1 km north: not.
      expect(atCemetery(const LatLng(52.02, 19.005), box: box), isFalse);
      expect(
        atCemetery(const LatLng(52.002, 19.0), point: const LatLng(52.0, 19.0)),
        isTrue,
      );
      expect(
        atCemetery(const LatLng(52.01, 19.0), point: const LatLng(52.0, 19.0)),
        isFalse,
      );
      expect(atCemetery(const LatLng(52.0, 19.0)), isFalse);

      const LatLng middle = LatLng(52.0, 19.0);
      expect(distanceText(const LatLng(52.00575, 19.0), middle), '640 m');
      expect(distanceText(const LatLng(52.0225, 19.0), middle), '2,5 km');
      expect(distanceText(const LatLng(52.9, 19.0), middle), '100 km');
      expect(distanceText(const LatLng(52.00001, 19.0), middle), '10 m');
    },
  );

  test(
    'element 12a, D37 — the weak signal: worse than 15 m (the temporary threshold, one constant)',
    () {
      expect(weakSignalM, 15);
      expect(weakSignal(15), isFalse);
      expect(weakSignal(15.1), isTrue);
      expect(weakSignal(25), isTrue);
      expect(weakSignal(null), isFalse);
    },
  );

  test(
    'NFR-005 — the native location channel never writes to the system log: in real use a position is '
    'where the family lies',
    () {
      final String kotlin = File(
        'android/app/src/main/kotlin/com/grobing/app/HereLocation.kt',
      ).readAsStringSync();
      expect(kotlin, isNot(contains('Log.')));
      expect(kotlin, isNot(contains('println')));
      expect(kotlin, contains('LocationManager.GPS_PROVIDER'));
      expect(kotlin, isNot(contains('NETWORK_PROVIDER')));
      expect(kotlin, isNot(contains('com.google.android.gms')));
    },
  );
}
