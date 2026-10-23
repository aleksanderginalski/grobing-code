import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../data/cemeteries.dart';
import '../../data/cemetery_plans.dart';
import '../../data/database.dart';
import '../../net/hosts.dart';
import '../../net/overpass_plan_source.dart';

/// What the cemetery screen shows while a plan is not stored (05_DESIGN/cmentarz.md, element 2a): being
/// downloaded (a) — [slow] once the server has kept the queue waiting long enough to say so (D39) — no
/// internet (b), the servers did not answer (c). Only in memory — a failed download writes nothing, so it
/// is tried again (ISSUE-027 D3, ISSUE-052 D40).
enum PlanDownload { downloading, slow, offline, serverError }

/// Cemeteries' plans, downloaded in the app: when a cemetery with a point is saved, when its point changes,
/// when the app starts or comes back, when a cemetery without a plan is opened, and on "Pobierz teraz". One
/// download at a time, in the order asked, one cemetery after another (Overpass's fair use); a cemetery
/// opened on the screen goes first. A cemetery the servers did not answer for is tried again by itself after
/// [retryDelays] (D40). With the app closed the background takes over (`background_plans.dart`, B1).
class PlanDownloads {
  PlanDownloads({
    required this.database,
    required this.source,
    this.slowAfter = const Duration(seconds: 15),
    this.retryDelays = const [
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 15),
    ],
  });

  final GrobingDatabase database;
  final PlanSource source;

  /// How long a download runs before the screen says the server is slow today (D39): on a good day the
  /// outline came in about 3 s (ISSUE-027), at the first real use every answer took over 20 s.
  final Duration slowAfter;

  /// The waits before trying a cemetery again after (c), one after another; the last one repeats.
  final List<Duration> retryDelays;

  final ValueNotifier<Map<int, PlanDownload>> _states = ValueNotifier(const {});

  /// The state of every cemetery whose plan is not stored and was asked for in this run of the app.
  ValueListenable<Map<int, PlanDownload>> get states => _states;

  final LinkedHashMap<int, GeoPoint> _queue = LinkedHashMap();
  final Map<int, Completer<PlanDownload?>> _waiting = {};
  bool _running = false;
  bool _closed = false;

  /// The server kept a download of this run of the queue past [slowAfter]: every cemetery waiting in the
  /// queue says so, until the queue is empty — a cemetery behind a slow one waits for it as well.
  bool _slow = false;
  Timer? _slowTimer;
  final Map<int, Timer> _retries = {};
  final Map<int, int> _failures = {};

  /// Every cemetery with a point and without a plan (start and return of the app).
  Future<void> downloadAll() async {
    for (final ({int id, GeoPoint point}) c in await cemeteriesWithoutPlan(
      database,
    )) {
      _enqueue(c.id, c.point, first: false);
    }
    _run();
  }

  /// One cemetery, ahead of the others: what the download ended with — null when the plan (or "not in
  /// OpenStreetMap") was stored, or the cemetery has no point any more.
  Future<PlanDownload?> download(int cemeteryId) async {
    final List<({int id, GeoPoint point})> missing =
        await cemeteriesWithoutPlan(database);
    final GeoPoint? point = [
      for (final ({int id, GeoPoint point}) c in missing)
        if (c.id == cemeteryId) c.point,
    ].firstOrNull;
    if (point == null) return null;
    final Future<PlanDownload?> result =
        (_waiting[cemeteryId] ??= Completer<PlanDownload?>()).future;
    _enqueue(cemeteryId, point, first: true);
    _run();
    return result;
  }

  void _enqueue(int id, GeoPoint point, {required bool first}) {
    if (_closed) return;
    _retries.remove(id)?.cancel();
    if (first) {
      _queue.remove(id);
      final Map<int, GeoPoint> rest = Map.of(_queue);
      _queue
        ..clear()
        ..[id] = point
        ..addAll(rest);
    } else {
      _queue.putIfAbsent(id, () => point);
    }
    _set(id, _waitingState);
  }

  PlanDownload get _waitingState =>
      _slow ? PlanDownload.slow : PlanDownload.downloading;

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_closed) {
        final int id = _queue.keys.first;
        final GeoPoint point = _queue.remove(id)!;
        _slowTimer = Timer(slowAfter, () {
          _slow = true;
          for (final int waiting in [id, ..._queue.keys]) {
            _set(waiting, PlanDownload.slow);
          }
        });
        final PlanDownload? outcome = await _one(id, point);
        _slowTimer?.cancel();
        _set(id, outcome);
        _waiting.remove(id)?.complete(outcome);
        if (outcome == PlanDownload.serverError) {
          _retryLater(id);
        } else {
          _failures.remove(id);
        }
        // No internet for one, none for the rest: they wait for the next start or return of the app.
        if (outcome == PlanDownload.offline) {
          for (final int other in [..._queue.keys]) {
            _queue.remove(other);
            _set(other, PlanDownload.offline);
            _waiting.remove(other)?.complete(PlanDownload.offline);
          }
        }
      }
    } finally {
      _running = false;
      _slow = false;
    }
  }

  /// (c) promises "Spróbuję sam" (D40): the cemetery goes back to the queue after the next wait, if its
  /// plan is still missing then — the background or another start may have got it meanwhile.
  void _retryLater(int id) {
    if (_closed || retryDelays.isEmpty) return;
    final int failures = _failures[id] = (_failures[id] ?? 0) + 1;
    final Duration wait =
        retryDelays[(failures - 1).clamp(0, retryDelays.length - 1)];
    _retries.remove(id)?.cancel();
    _retries[id] = Timer(wait, () async {
      _retries.remove(id);
      if (_closed) return;
      final GeoPoint? point = [
        for (final ({int id, GeoPoint point}) c in await cemeteriesWithoutPlan(
          database,
        ))
          if (c.id == id) c.point,
      ].firstOrNull;
      if (point == null || _closed) return;
      _enqueue(id, point, first: false);
      _run();
    });
  }

  Future<PlanDownload?> _one(int id, GeoPoint point) async {
    try {
      switch (await source.fetch(point)) {
        case PlanFound(:final areas, :final paths, :final server):
          await savePlan(
            database,
            id,
            forPoint: point,
            areas: areas,
            paths: paths,
            server: server,
          );
          return null;
        case PlanNotInOsm(:final server):
          await saveNotInOsm(database, id, forPoint: point, server: server);
          return null;
        case PlanOffline():
          return PlanDownload.offline;
        case PlanServerError():
          return PlanDownload.serverError;
      }
    } on Object catch (e, stack) {
      // A fault of the app, not of the network; the screen says the servers did not answer, and the next
      // start tries again. Logged without the point: where the family lies is not for the log.
      debugPrint('Plan download failed: ${e.runtimeType}');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      return PlanDownload.serverError;
    }
  }

  void _set(int id, PlanDownload? state) {
    if (_closed || _states.value[id] == state) return;
    final Map<int, PlanDownload> next = Map.of(_states.value);
    if (state == null) {
      next.remove(id);
    } else {
      next[id] = state;
    }
    _states.value = Map.unmodifiable(next);
  }

  /// After a restore the data is another: downloads in flight finish into nothing.
  void close() {
    _closed = true;
    _slowTimer?.cancel();
    for (final Timer t in _retries.values) {
      t.cancel();
    }
    _retries.clear();
    _queue.clear();
    for (final Completer<PlanDownload?> c in _waiting.values) {
      c.complete(null);
    }
    _waiting.clear();
  }
}

/// The network of the cemetery's map, for every screen of the app (ISSUE-027): the plans' downloads, and
/// the photo from above — whether it can be shown, and where its tiles come from. Above the navigator, so
/// a cemetery opened from the map, from a person's "Pochówek" or from a grave has the same; tests put their
/// own in its place, or none — then the screen shows what is stored and downloads nothing.
class MapNetwork extends InheritedWidget {
  const MapNetwork({
    super.key,
    required this.plans,
    this.photoReachable = orthophotoReachable,
    this.photoTiles = orthophotoTileProvider,
    required super.child,
  });

  final PlanDownloads? plans;

  /// Whether the photo from above can be shown now (element 13).
  final Future<bool> Function() photoReachable;

  /// The tiles of the photo from above.
  final TileProvider Function() photoTiles;

  static MapNetwork? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapNetwork>();

  @override
  bool updateShouldNotify(MapNetwork old) =>
      old.plans != plans ||
      old.photoReachable != photoReachable ||
      old.photoTiles != photoTiles;
}

/// The photo's server can be looked up — the phone has internet. Asked when "Zdjęcie" is chosen.
Future<bool> orthophotoReachable() async {
  try {
    final List<InternetAddress> found = await InternetAddress.lookup(
      Hosts.orthophotoHost,
    ).timeout(const Duration(seconds: 5));
    return found.isNotEmpty;
  } on Object {
    return false;
  }
}

/// GUGiK's tiles with flutter_map's tile cache off: by default flutter_map 8.3.2 keeps every tile in the
/// app's cache directory (`BuiltInMapCachingProvider`), and the photo from above must leave nothing on the
/// phone (ADR-003 pkt 2). Exceptions silenced: otherwise a tile that fails is printed with its address —
/// its tile numbers, the place the phone looked at — to the system log, in release too (`TileLayer`
/// `debugPrint`s the error; seen on the emulator at stop #2 of ISSUE-027; NFR-005: nothing of the family in
/// logs). A failed tile stays the surface colour; "bez internetu" comes from asking the host when "Zdjęcie"
/// is chosen (element 13). The headers are a map of its own, not a constant: `TileLayer` adds to it with
/// `putIfAbsent`.
TileProvider orthophotoTileProvider() => NetworkTileProvider(
  headers: {'User-Agent': Hosts.userAgent},
  cachingProvider: const DisabledMapCachingProvider(),
  silenceExceptions: true,
);
