import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/net/hosts.dart';
import 'package:grobing/net/overpass_plan_source.dart';

// ISSUE-027 D4, D5 — the download of a plan against a local server standing in for Overpass: never the real
// one (its fair use, and an answer from it would be real data). Invented geometry only.

/// A local "Overpass": answers each request with the next of [answers] (status and body), records what it
/// was asked.
class _FakeOverpass {
  _FakeOverpass(this.answers);

  final List<(int, String)> answers;
  final List<String> queries = [];
  final List<String?> agents = [];
  late final HttpServer _server;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/api/interpreter');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final String body = await utf8.decodeStream(request);
      queries.add(Uri.splitQueryString(body)['data'] ?? '');
      agents.add(request.headers.value(HttpHeaders.userAgentHeader));
      final (int status, String answer) = answers.isEmpty
          ? (500, '')
          : answers.removeAt(0);
      request.response
        ..statusCode = status
        ..write(answer);
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

String _answer(List<Map<String, Object?>> elements) =>
    jsonEncode({'version': 0.6, 'elements': elements});

final String _outline = _answer([
  {
    'type': 'way',
    'id': 1,
    'tags': {'landuse': 'cemetery'},
    'geometry': [
      {'lat': 51.498, 'lon': 19.498},
      {'lat': 51.498, 'lon': 19.502},
      {'lat': 51.502, 'lon': 19.502},
      {'lat': 51.502, 'lon': 19.498},
      {'lat': 51.498, 'lon': 19.498},
    ],
  },
]);

final String _paths = _answer([
  {
    'type': 'way',
    'id': 2,
    'tags': {'highway': 'footway'},
    'geometry': [
      {'lat': 51.499, 'lon': 19.5},
      {'lat': 51.501, 'lon': 19.5},
    ],
  },
]);

const GeoPoint _point = GeoPoint(51.5, 19.5);

void main() {
  OverpassPlanSource source(List<Uri> hosts) => OverpassPlanSource(
    hosts: hosts,
    retryPause: Duration.zero,
    requestTimeout: const Duration(seconds: 5),
    deadline: const Duration(seconds: 20),
  );

  test(
    'the outline, then the paths in its box: the plan, with the host that gave it; the app says who '
    'asks (User-Agent)',
    () async {
      final _FakeOverpass server = _FakeOverpass([
        (200, _outline),
        (200, _paths),
      ]);
      await server.start();
      addTearDown(server.stop);
      final PlanResult result = await source([server.uri]).fetch(_point);
      expect(result, isA<PlanFound>());
      final PlanFound found = result as PlanFound;
      expect(found.areas.single.outer.length, 5);
      expect(found.paths.single.main, isFalse);
      expect(found.server, '127.0.0.1');
      expect(server.queries.first, contains('is_in(51.5,19.5)'));
      expect(server.queries.last, contains('"highway"'));
      expect(server.agents, everyElement(Hosts.userAgent));
    },
  );

  test(
    'busy (504, then a runtime error in a 200): asked again, then the next host — and the plan from it; '
    'the paths asked of the host that gave the outline, not of the busy one again',
    () async {
      final _FakeOverpass busy = _FakeOverpass([
        (504, 'busy'),
        (200, '{"elements":[],"remark":"runtime error: Query timed out"}'),
      ]);
      final _FakeOverpass next = _FakeOverpass([
        (200, _outline),
        (200, _paths),
      ]);
      await busy.start();
      await next.start();
      addTearDown(busy.stop);
      addTearDown(next.stop);
      final PlanResult result = await source([
        busy.uri,
        next.uri,
      ]).fetch(_point);
      expect(result, isA<PlanFound>());
      expect(busy.queries.length, 2);
      expect(next.queries.length, 2);
    },
  );

  test(
    'no outline at or near the point: not in OpenStreetMap — no paths asked for',
    () async {
      final _FakeOverpass server = _FakeOverpass([(200, _answer([]))]);
      await server.start();
      addTearDown(server.stop);
      final PlanResult result = await source([server.uri]).fetch(_point);
      expect(result, isA<PlanNotInOsm>());
      expect(server.queries.length, 1);
    },
  );

  test(
    'every host busy, or the paths refused: the servers did not answer (2a (c)), nothing half-kept',
    () async {
      final _FakeOverpass a = _FakeOverpass([(504, ''), (429, '')]);
      final _FakeOverpass b = _FakeOverpass([
        (200, _outline),
        (503, ''),
        (503, ''),
      ]);
      await a.start();
      await b.start();
      addTearDown(a.stop);
      addTearDown(b.stop);
      expect(
        await source([a.uri, b.uri]).fetch(_point),
        isA<PlanServerError>(),
      );
    },
  );

  test('no host can even be looked up: no internet (2a (b))', () async {
    expect(
      await source([
        Uri.parse('https://no-such-host.invalid/api/interpreter'),
      ]).fetch(_point),
      isA<PlanOffline>(),
    );
  });
}
