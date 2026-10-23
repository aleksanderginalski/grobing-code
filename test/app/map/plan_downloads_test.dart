import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/map/plan_downloads.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/net/overpass_plan_source.dart';

// ISSUE-027 D3 — the plans' downloads: one at a time, the opened cemetery first, (a)/(b)/(c) in memory only,
// "not in OpenStreetMap" kept and not asked again. A fake source: no network (family-data.md: invented
// cemeteries and geometry).

const List<PlanArea> _areas = [
  PlanArea([
    GeoPoint(51.498, 19.498),
    GeoPoint(51.498, 19.502),
    GeoPoint(51.502, 19.502),
    GeoPoint(51.498, 19.498),
  ]),
];

class _Source implements PlanSource {
  _Source(this.answer);

  /// What each point gets.
  PlanResult Function(GeoPoint point) answer;
  final List<GeoPoint> asked = [];

  /// When set, each fetch waits for it — to see the state while downloading.
  Completer<void>? gate;

  @override
  Future<PlanResult> fetch(GeoPoint point) async {
    asked.add(point);
    await gate?.future;
    return answer(point);
  }
}

PlanResult _found(GeoPoint _) =>
    const PlanFound(areas: _areas, paths: [], server: 'overpass.example');

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> cemetery(double lat, {bool point = true}) => addCemetery(
    db,
    name: 'Cmentarz Wymyślony $lat',
    point: point ? GeoPoint(lat, 19.5) : null,
  );

  test(
    'AC-1 — download: "Pobieram plan" while it runs, then the plan kept and the state gone',
    () async {
      final int id = await cemetery(51.5);
      final _Source source = _Source(_found)..gate = Completer<void>();
      final PlanDownloads plans = PlanDownloads(database: db, source: source);
      final Future<PlanDownload?> result = plans.download(id);
      await pumpEventQueue();
      expect(plans.states.value[id], PlanDownload.downloading);
      source.gate!.complete();
      expect(await result, isNull);
      expect(plans.states.value[id], isNull);
      expect((await watchCemeteryPlan(db, id).first)!.status, PlanStatus.ok);
    },
  );

  test(
    'AC-5 — no internet: (b) for this one and every other waiting, nothing kept, so the next start asks '
    'again; then with the internet back, all are kept',
    () async {
      final int a = await cemetery(51.5);
      final int b = await cemetery(51.6);
      final _Source source = _Source((_) => const PlanOffline());
      final PlanDownloads plans = PlanDownloads(database: db, source: source);
      await plans.downloadAll();
      await pumpEventQueue();
      expect(plans.states.value, {
        a: PlanDownload.offline,
        b: PlanDownload.offline,
      });
      // Offline for one — the rest is not asked (no point).
      expect(source.asked.length, 1);
      expect(await cemeteriesWithoutPlan(db), hasLength(2));

      source.answer = _found;
      await plans.downloadAll();
      await pumpEventQueue(times: 50);
      expect(plans.states.value, isEmpty);
      expect(await cemeteriesWithoutPlan(db), isEmpty);
    },
  );

  test('the servers did not answer: (c), nothing kept', () async {
    final int id = await cemetery(51.5);
    final PlanDownloads plans = PlanDownloads(
      database: db,
      source: _Source((_) => const PlanServerError()),
    );
    expect(await plans.download(id), PlanDownload.serverError);
    expect(plans.states.value[id], PlanDownload.serverError);
    expect(await watchCemeteryPlan(db, id).first, isNull);
  });

  test(
    '(d) not in OpenStreetMap is kept — the next start does not ask the server again; a cemetery without '
    'a point is never asked about (e)',
    () async {
      final int id = await cemetery(51.5);
      await cemetery(51.6, point: false);
      final _Source source = _Source(
        (_) => const PlanNotInOsm(server: 'overpass.example'),
      );
      final PlanDownloads plans = PlanDownloads(database: db, source: source);
      await plans.downloadAll();
      await pumpEventQueue(times: 50);
      expect(
        (await watchCemeteryPlan(db, id).first)!.status,
        PlanStatus.notInOsm,
      );
      await plans.downloadAll();
      await pumpEventQueue(times: 50);
      expect(source.asked, [const GeoPoint(51.5, 19.5)]);
    },
  );

  test(
    'the cemetery opened on the screen goes first; one download at a time, in order',
    () async {
      await cemetery(51.5);
      await cemetery(51.6);
      final int opened = await cemetery(51.7);
      final _Source source = _Source(_found)..gate = Completer<void>();
      final PlanDownloads plans = PlanDownloads(database: db, source: source);
      unawaited(plans.downloadAll());
      await pumpEventQueue();
      // The first is already running; the opened one jumps ahead of the second.
      unawaited(plans.download(opened));
      await pumpEventQueue();
      source.gate!.complete();
      await pumpEventQueue(times: 100);
      expect(source.asked.map((p) => p.lat), [51.5, 51.7, 51.6]);
    },
  );

  group('ISSUE-052 — a slow server and trying again (cmentarz.md D39, D40)', () {
    test(
      'D39: a download running past slowAfter turns "slow" — for the one running and every one waiting '
      'behind it; an empty queue starts quick again',
      () async {
        final int a = await cemetery(51.5);
        final int b = await cemetery(51.6);
        final _Source source = _Source(_found)..gate = Completer<void>();
        final PlanDownloads plans = PlanDownloads(
          database: db,
          source: source,
          slowAfter: const Duration(milliseconds: 40),
        );
        addTearDown(plans.close);
        unawaited(plans.downloadAll());
        await pumpEventQueue();
        expect(plans.states.value, {
          a: PlanDownload.downloading,
          b: PlanDownload.downloading,
        });
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(plans.states.value, {
          a: PlanDownload.slow,
          b: PlanDownload.slow,
        });
        source.gate!.complete();
        await pumpEventQueue(times: 100);
        expect(plans.states.value, isEmpty);
        expect(await cemeteriesWithoutPlan(db), isEmpty);

        // A new run of the queue says "downloading" again, not "slow".
        final int c = await cemetery(51.7);
        source.gate = Completer<void>();
        unawaited(plans.download(c));
        await pumpEventQueue();
        expect(plans.states.value[c], PlanDownload.downloading);
        source.gate!.complete();
        await pumpEventQueue(times: 100);
      },
    );

    test(
      'D40 / AC-3: after (c) the cemetery is tried again by itself after the first wait, and its plan is '
      'kept without a tap; the waits grow and the last repeats',
      () async {
        final int id = await cemetery(51.5);
        int calls = 0;
        final _Source source = _Source(
          (point) => ++calls < 3 ? const PlanServerError() : _found(point),
        );
        final PlanDownloads plans = PlanDownloads(
          database: db,
          source: source,
          retryDelays: const [
            Duration(milliseconds: 30),
            Duration(milliseconds: 60),
          ],
        );
        addTearDown(plans.close);
        expect(await plans.download(id), PlanDownload.serverError);
        expect(plans.states.value[id], PlanDownload.serverError);
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(source.asked, hasLength(1), reason: 'not before the wait');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await pumpEventQueue(times: 50);
        expect(source.asked, hasLength(2));
        expect(plans.states.value[id], PlanDownload.serverError);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await pumpEventQueue(times: 50);
        expect(source.asked, hasLength(3));
        expect(plans.states.value[id], isNull);
        expect((await watchCemeteryPlan(db, id).first)!.status, PlanStatus.ok);
      },
    );

    test(
      'D40: a plan kept meanwhile (the background, B1) is not asked for again when the wait ends',
      () async {
        final int id = await cemetery(51.5);
        final _Source source = _Source((_) => const PlanServerError());
        final PlanDownloads plans = PlanDownloads(
          database: db,
          source: source,
          retryDelays: const [Duration(milliseconds: 30)],
        );
        addTearDown(plans.close);
        await plans.download(id);
        await savePlan(
          db,
          id,
          forPoint: const GeoPoint(51.5, 19.5),
          areas: _areas,
          paths: const [],
          server: 'overpass.example',
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await pumpEventQueue(times: 50);
        expect(source.asked, hasLength(1));
      },
    );

    test('close() cancels the waiting tries', () async {
      final int id = await cemetery(51.5);
      final _Source source = _Source((_) => const PlanServerError());
      final PlanDownloads plans = PlanDownloads(
        database: db,
        source: source,
        retryDelays: const [Duration(milliseconds: 30)],
      );
      await plans.download(id);
      plans.close();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue(times: 50);
      expect(source.asked, hasLength(1));
    });

    test(
      'the defaults are the measured ones: "slow" after 15 s, tries after 2, 5, 10, then every 15 min',
      () {
        final PlanDownloads plans = PlanDownloads(
          database: db,
          source: _Source(_found),
        );
        addTearDown(plans.close);
        expect(plans.slowAfter, const Duration(seconds: 15));
        expect(plans.retryDelays, const [
          Duration(minutes: 2),
          Duration(minutes: 5),
          Duration(minutes: 10),
          Duration(minutes: 15),
        ]);
      },
    );
  });

  test(
    'a cemetery with its plan already kept: download asks nothing',
    () async {
      final int id = await cemetery(51.5);
      await savePlan(
        db,
        id,
        forPoint: const GeoPoint(51.5, 19.5),
        areas: _areas,
        paths: const [],
        server: 'x',
      );
      final _Source source = _Source(_found);
      final PlanDownloads plans = PlanDownloads(database: db, source: source);
      expect(await plans.download(id), isNull);
      expect(source.asked, isEmpty);
    },
  );
}
