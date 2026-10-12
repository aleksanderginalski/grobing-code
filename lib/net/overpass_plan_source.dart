import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../data/cemeteries.dart';
import '../data/cemetery_plans.dart';
import 'hosts.dart';
import 'osm_plan.dart';

/// How one download of a cemetery's plan ended (05_DESIGN/cmentarz.md, element 2a).
sealed class PlanResult {
  const PlanResult();
}

/// The outline and the paths inside it, and the host that gave the outline.
final class PlanFound extends PlanResult {
  const PlanFound({
    required this.areas,
    required this.paths,
    required this.server,
  });

  final List<PlanArea> areas;
  final List<PlanPath> paths;
  final String server;
}

/// OpenStreetMap has no outline around the point — (d).
final class PlanNotInOsm extends PlanResult {
  const PlanNotInOsm({required this.server});

  final String server;
}

/// No server could even be looked up: the phone has no internet — (b).
final class PlanOffline extends PlanResult {
  const PlanOffline();
}

/// The servers were reached but none gave an answer — (c).
final class PlanServerError extends PlanResult {
  const PlanServerError();
}

/// Where a cemetery's plan comes from; tests put their own answers in its place.
abstract interface class PlanSource {
  Future<PlanResult> fetch(GeoPoint point);
}

/// The plan from the Overpass API (ADR-003 pkt 1; ISSUE-027 D4, D5): the outline around the point, then the
/// paths in its box — two requests, one after the other. Each request goes to the hosts of
/// [Hosts.overpass] in order, twice to a host that answers "busy" (429, 5xx, a timeout or a "runtime
/// error"), with a pause between; a host that cannot be looked up is passed over at once. Measured before
/// the plan: the outline in 3 s, the paths of a large cemetery refused twice with 504 by the first host —
/// so failing here is the normal case, and the screen says so (element 2a (c)).
class OverpassPlanSource implements PlanSource {
  OverpassPlanSource({
    List<Uri>? hosts,
    this.retryPause = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 30),
    this.deadline = const Duration(seconds: 60),
    this.maxBytes = 8 << 20,
    HttpClient Function()? client,
  }) : hosts = hosts ?? Hosts.overpass,
       _client = client ?? HttpClient.new;

  final List<Uri> hosts;
  final Duration retryPause;
  final Duration requestTimeout;

  /// No new try of a request after this long: the screen shows "Pobieram plan…" meanwhile, and the
  /// servers measured while building this either answered within seconds or not at all (104 s for
  /// nothing, with no deadline).
  final Duration deadline;

  /// The largest answer read; a larger one is a fault, not a plan (a large cemetery's paths: ~350 KB).
  final int maxBytes;
  final HttpClient Function() _client;

  @override
  Future<PlanResult> fetch(GeoPoint point) async {
    final _Body outline;
    switch (await _ask(outlineQuery(point))) {
      case _Failed(:final PlanResult result):
        return result;
      case final _Body body:
        outline = body;
    }
    // Parsed off the main thread: since Flutter 3.29 Dart runs on Android's main thread, and a large
    // answer parsed there would stall the screen (ISSUE-023's ANR).
    final String outlineBody = outline.body;
    final List<PlanArea>? areas = await Isolate.run(
      () => chooseOutline(outlineBody, point),
    );
    if (areas == null) return PlanNotInOsm(server: outline.host);
    // At most a request a second (Overpass's fair use).
    await Future<void>.delayed(const Duration(seconds: 1));
    // The paths of the host that gave the outline first: a busy host asked again would only cost pauses.
    switch (await _ask(pathsQuery(areas), first: outline.uri)) {
      case _Failed(:final PlanResult result):
        return result;
      case _Body(:final String body):
        return PlanFound(
          areas: areas,
          paths: await Isolate.run(() => pathsInside(body, areas)),
          server: outline.host,
        );
    }
  }

  Future<_Answer> _ask(String query, {Uri? first}) async {
    final Stopwatch elapsed = Stopwatch()..start();
    bool reached = false;
    final List<Uri> order = [
      ...hosts.where((h) => h == first),
      ...hosts.where((h) => h != first),
    ];
    for (final Uri host in order) {
      for (int attempt = 0; attempt < 2; attempt++) {
        if (elapsed.elapsed >= deadline) break;
        if (attempt > 0) await Future<void>.delayed(retryPause);
        try {
          final String body = await _post(host, query);
          if (isRuntimeError(body)) {
            reached = true;
            continue;
          }
          return _Body(body, host);
        } on SocketException catch (e) {
          // No name lookup: no internet, or no such host — the next one, at once. A refused or broken
          // connection reached the network.
          if (!_isLookupFailure(e)) reached = true;
          break;
        } on _Status catch (e) {
          reached = true;
          if (!e.busy) break;
        } on TimeoutException {
          reached = true;
        } on IOException {
          // TLS, a broken answer: the server was reached, and it may be better on the next try.
          reached = true;
        } on FormatException {
          reached = true;
          break;
        }
      }
    }
    return _Failed(reached ? const PlanServerError() : const PlanOffline());
  }

  Future<String> _post(Uri host, String query) async {
    final HttpClient client = _client()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = Hosts.userAgent;
    try {
      final HttpClientRequest request = await client
          .postUrl(host)
          .timeout(requestTimeout);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw _Status(response.statusCode);
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(requestTimeout)) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) throw const _Status(413);
      }
      return utf8.decode(bytes.takeBytes());
    } finally {
      client.close(force: true);
    }
  }
}

bool _isLookupFailure(SocketException e) =>
    e.message.contains('Failed host lookup') ||
    (e.osError?.message.contains('No address associated') ?? false);

sealed class _Answer {
  const _Answer();
}

final class _Body extends _Answer {
  const _Body(this.body, this.uri);

  final String body;
  final Uri uri;

  String get host => uri.host;
}

final class _Failed extends _Answer {
  const _Failed(this.result);

  final PlanResult result;
}

/// An answer other than 200. Busy — worth a second try at the same host: 429 and the 5xx of an overloaded
/// instance (`overpass-api.de` gave 504 twice while measuring).
class _Status implements Exception {
  const _Status(this.code);

  final int code;

  bool get busy => code == 429 || (code >= 500 && code != 501);
}
