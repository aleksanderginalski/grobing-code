import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/map/plan_downloads.dart';
import 'package:grobing/net/hosts.dart';

// ISSUE-027 — NFR-005 from the code, not the system: since the app has INTERNET, every address it talks to
// is in lib/net/hosts.dart, every one https (D4), and the photo from above leaves nothing on the phone
// (ADR-003 pkt 2).

/// Files allowed a web address outside hosts.dart, and why: the app hands it to another app and never
/// opens a connection to it.
const Map<String, String> _handedToOtherApps = {
  'lib/app/external_link.dart':
      'the satellite photo in Google Maps, opened by another app after a tap (ISSUE-015 D1, NFR-005)',
};

void main() {
  test(
    'no web address in a string of lib/ outside lib/net/hosts.dart (comments may cite sources)',
    () {
      final RegExp literal = RegExp(r'''(['"])(https?://[^'"]*)''');
      final List<String> found = [];
      for (final File f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final String path = f.path.replaceAll(r'\', '/');
        if (path == 'lib/net/hosts.dart' ||
            _handedToOtherApps.containsKey(path)) {
          continue;
        }
        for (final (int i, String line) in f.readAsLinesSync().indexed) {
          if (line.trimLeft().startsWith('//')) continue;
          if (literal.hasMatch(line)) found.add('$path:${i + 1}');
        }
      }
      expect(found, isEmpty);
    },
  );

  test('every address in hosts.dart is https', () {
    final String source = File('lib/net/hosts.dart').readAsStringSync();
    final Iterable<String> addresses = RegExp(
      r'''['"](\w+)://''',
    ).allMatches(source).map((m) => m.group(1)!);
    expect(addresses, isNotEmpty);
    expect(addresses, everyElement('https'));
    for (final Uri u in Hosts.overpass) {
      expect(u.scheme, 'https');
    }
    expect(Uri.parse(Hosts.orthophotoTiles).scheme, 'https');
  });

  test(
    'D4 — the plan from the two OpenStreetMap-community instances, in order, and no other; the photo from '
    'GUGiK; the User-Agent names the app, not a person',
    () {
      expect(Hosts.overpass.map((u) => u.host), [
        'overpass-api.de',
        'overpass.private.coffee',
      ]);
      expect(Uri.parse(Hosts.orthophotoTiles).host, Hosts.orthophotoHost);
      expect(Hosts.orthophotoHost, 'mapy.geoportal.gov.pl');
      expect(Hosts.userAgent, startsWith('Grobing'));
      expect(Hosts.userAgent, isNot(contains('@')));
    },
  );

  test('ADR-003 pkt 2 — the photo\'s tiles are never kept: the tile provider has flutter_map\'s cache off '
      '(by default 8.3.2 keeps every tile on disk) and says who asks', () {
    final TileProvider provider = orthophotoTileProvider();
    expect(provider, isA<NetworkTileProvider>());
    expect(
      (provider as NetworkTileProvider).cachingProvider,
      isA<DisabledMapCachingProvider>(),
    );
    expect(provider.headers['User-Agent'], Hosts.userAgent);
    // NFR-005: a failed tile is not printed with its address (the place) to the system log.
    expect(provider.silenceExceptions, isTrue);
    // TileLayer adds its own User-Agent with putIfAbsent: the headers must be a map it may touch.
    expect(
      () => provider.headers.putIfAbsent('X-Test', () => '1'),
      returnsNormally,
    );
  });
}
