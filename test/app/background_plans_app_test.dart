import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grobing_app.dart';
import 'package:grobing/app/widgets/candle.dart';
import 'package:grobing/backup/background.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/net/overpass_plan_source.dart';

import '../support/backup_fakes.dart';

// ISSUE-052 B1 in the app (05_DESIGN/cmentarz.md D40): leaving the app with a plan missing asks for the plans'
// downloads with the app closed; with none missing it does not. Back in the app, a plan the background stored
// through its own connection — which this one's streams never heard of — marks the plans' table as changed, so
// the screens read it again. Invented cemeteries only.

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (int i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('condition not met in time');
}

class _Plans implements BackgroundPlans {
  int requests = 0;

  @override
  Future<void> requestPlans() async => requests++;
}

class _Offline implements PlanSource {
  @override
  Future<PlanResult> fetch(GeoPoint point) async => const PlanOffline();
}

const GeoPoint _point = GeoPoint(51.5, 19.5);

void main() {
  // The app's connection and the background's, to one file — as on the phone.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late GrobingDatabase db;
  late DataLocation location;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_background_plans_app');
    location = DataLocation.inDirectory(Directory('${tmp.path}/data'));
    location.mediaDir.createSync(recursive: true);
    db = GrobingDatabase(
      NativeDatabase(location.databaseFile, setup: configureConnection),
    );
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
  }

  Future<void> pumpApp(WidgetTester tester, _Plans background) =>
      tester.pumpWidget(
        GrobingApp(
          database: db,
          location: location,
          backup: backupServiceIn(
            tmp,
            db,
            FakeDocumentStore(Directory('${tmp.path}/drive')),
          ),
          planSource: _Offline(),
          backgroundPlans: background,
        ),
      );

  void leave(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void comeBack(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets(
    'B1: leaving the app with a plan missing asks for the background downloads; back, a plan the background '
    'stored meanwhile reaches the screen — the open sheet turns from "pobierze się" to "Plan offline"',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late int id;
      await tester.runAsync(() async {
        id = await addCemetery(db, name: 'Cmentarz Wymyślony', point: _point);
      });
      final _Plans background = _Plans();
      await pumpApp(tester, background);
      // The sheet of its candle: the in-app download found no internet (the fake source).
      await _pumpUntil(
        tester,
        () => find.byType(CandlePin).evaluate().isNotEmpty,
      );
      await tester.tap(find.byType(CandlePin));
      await _pumpUntil(
        tester,
        () => find
            .text('Plan pobierze się, gdy będzie internet.')
            .evaluate()
            .isNotEmpty,
      );

      leave(tester);
      await _pumpUntil(tester, () => background.requests == 1);

      // The worker's engine writes through its own connection, which this one's streams never hear. A second
      // connection in this isolate waits on the first one's lock synchronously (both on one thread, unlike the
      // phone's two engines), so the row goes in by a custom statement — drift does not notify it either.
      await tester.runAsync(
        () => db.customStatement(
          'INSERT INTO cemetery_plans (cemetery_id, status, outline, paths, fetched_at, server) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            id,
            PlanStatus.ok.name,
            encodeAreas(const [
              PlanArea([
                GeoPoint(51.498, 19.498),
                GeoPoint(51.498, 19.502),
                GeoPoint(51.502, 19.502),
                GeoPoint(51.498, 19.498),
              ]),
            ]),
            encodePaths(const []),
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'overpass.example',
          ],
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        find.text('Plan offline'),
        findsNothing,
        reason: 'the other connection notifies nobody here',
      );

      comeBack(tester);
      await _pumpUntil(
        tester,
        () => find.text('Plan offline').evaluate().isNotEmpty,
      );
      await cleanUp(tester);
    },
  );

  testWidgets('B1: with every plan stored, leaving asks for nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await addCemetery(
        db,
        name: 'Cmentarz Testowy',
        point: _point,
      );
      await saveNotInOsm(db, id, forPoint: _point, server: 'overpass.example');
      // Without a point there is nothing to download.
      await addCemetery(db, name: 'Cmentarz Próbny');
    });
    final _Plans background = _Plans();
    await pumpApp(tester, background);
    leave(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(background.requests, 0);
    await cleanUp(tester);
  });
}
