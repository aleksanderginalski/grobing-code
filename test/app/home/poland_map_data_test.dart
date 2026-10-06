import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/home/poland_map_data.dart';
import 'package:latlong2/latlong.dart';

// ISSUE-014 AC-1: the map of Poland is bundled with the app (Natural Earth 1:10m), so it draws offline.
// The real asset, as tool/map/extract_poland.dart wrote it.
void main() {
  final PolandMapData map = PolandMapData.fromJson(
    File(PolandMapData.asset).readAsStringSync(),
  );

  test('outline of Poland: 1:10m, a closed ring inside Poland\'s extent', () {
    expect(map.outline.length, 1332);
    expect(map.outline.first, map.outline.last);
    expect(map.bounds.south, closeTo(49.0, 0.1));
    expect(map.bounds.north, closeTo(54.84, 0.1));
    expect(map.bounds.west, closeTo(14.12, 0.1));
    expect(map.bounds.east, closeTo(24.15, 0.1));
  });

  test(
    'the nine cities of the spec, with Polish names, inside the outline\'s extent',
    () {
      expect(map.cities.map((c) => c.name).toSet(), {
        'Szczecin',
        'Gdańsk',
        'Białystok',
        'Poznań',
        'Warszawa',
        'Łódź',
        'Wrocław',
        'Lublin',
        'Kraków',
      });
      for (final MapCity c in map.cities) {
        expect(map.bounds.contains(c.point), isTrue, reason: c.name);
      }
    },
  );

  test('rivers: cut to Poland, every point within its extent', () {
    expect(map.rivers, isNotEmpty);
    for (final List<LatLng> river in map.rivers) {
      expect(river.length, greaterThan(1));
      for (final LatLng p in river) {
        expect(map.bounds.contains(p), isTrue);
      }
    }
  });
}
