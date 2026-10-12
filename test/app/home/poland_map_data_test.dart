import 'dart:convert';
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/home/poland_map_data.dart';
import 'package:latlong2/latlong.dart';

// ISSUE-014 AC-1: the map of Poland is bundled with the app (Natural Earth 1:10m), so it draws offline.
// ISSUE-023 AC-1 (05_DESIGN/cmentarze.md D29): like R1 — the sea, the lakes, the neighbours' borders and
// eleven cities, still from the bundled file alone. The real asset, as tool/map/extract_poland.dart wrote it.
void main() {
  final String source = File(PolandMapData.asset).readAsStringSync();
  final PolandMapData map = PolandMapData.fromJson(source);

  /// Ray casting, as the extraction tool does.
  bool inside(LatLng p, List<LatLng> ring) {
    bool result = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final LatLng a = ring[i], b = ring[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        result = !result;
      }
    }
    return result;
  }

  bool inArea(LatLng p, MapArea a) =>
      inside(p, a.outer) && !a.holes.any((h) => inside(p, h));

  test('outline of Poland: 1:10m, a closed ring inside Poland\'s extent', () {
    expect(map.outline.length, 1332);
    expect(map.outline.first, map.outline.last);
    expect(map.bounds.south, closeTo(49.0, 0.1));
    expect(map.bounds.north, closeTo(54.84, 0.1));
    expect(map.bounds.west, closeTo(14.12, 0.1));
    expect(map.bounds.east, closeTo(24.15, 0.1));
  });

  test(
    'ISSUE-023 AC-1 — the eleven cities of the spec (D29), with Polish names, inside the outline\'s extent',
    () {
      expect(map.cities.map((c) => c.name).toSet(), {
        'Szczecin',
        'Gdańsk',
        'Bydgoszcz',
        'Białystok',
        'Poznań',
        'Warszawa',
        'Łódź',
        'Wrocław',
        'Katowice',
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

  test(
    'ISSUE-023 AC-1 — the sea: the Baltic off Gdańsk and off Kołobrzeg is water, Warsaw and Berlin are not; '
    'Bornholm is an island in it',
    () {
      bool water(LatLng p) => map.water.any((a) => inArea(p, a));
      expect(water(const LatLng(54.7, 18.9)), isTrue, reason: 'Gulf of Gdańsk');
      expect(water(const LatLng(54.6, 15.6)), isTrue, reason: 'off Kołobrzeg');
      expect(water(const LatLng(52.23, 21.0)), isFalse, reason: 'Warsaw');
      expect(water(const LatLng(52.52, 13.4)), isFalse, reason: 'Berlin');
      expect(water(const LatLng(55.12, 14.92)), isFalse, reason: 'Bornholm');
    },
  );

  test(
    'ISSUE-023 AC-1 — lakes: closed rings, some of them in Poland (Masuria), none of them specks of a '
    'single point',
    () {
      expect(map.lakes, isNotEmpty);
      for (final MapArea lake in map.lakes) {
        expect(lake.outer.length, greaterThanOrEqualTo(4));
        expect(lake.outer.first, lake.outer.last);
      }
      expect(
        map.lakes.where((l) => l.outer.any((p) => inside(p, map.outline))),
        isNotEmpty,
      );
    },
  );

  test(
    'ISSUE-023 AC-1 — the neighbours\' borders are there, but not Poland\'s own (the outline draws it)',
    () {
      expect(map.borders, isNotEmpty);
      final Set<String> outline = {
        for (final LatLng p in map.outline) '${p.latitude},${p.longitude}',
      };
      for (final List<LatLng> border in map.borders) {
        expect(border.length, greaterThan(1));
        expect(
          border.every((p) => outline.contains('${p.latitude},${p.longitude}')),
          isFalse,
        );
      }
    },
  );

  test(
    'ISSUE-023 AC-1 — no names in the file but the eleven cities and the source line (family-data.md: '
    'the file is public data, and the content guard reads it at every git add)',
    () {
      final Set<String> strings = {};
      void walk(Object? node) {
        switch (node) {
          case final String s:
            strings.add(s);
          case final List<Object?> l:
            l.forEach(walk);
          case final Map<String, Object?> m:
            m.values.forEach(walk);
        }
      }

      walk(jsonDecode(source));
      expect(strings, {
        'Natural Earth 1:10m (public domain) — tool/map/extract_poland.dart',
        ...map.cities.map((c) => c.name),
      });
    },
  );

  test(
    'ISSUE-023 — the file stays small enough to read at start (budget 300 KB, plan → Scope)',
    () {
      expect(File(PolandMapData.asset).lengthSync(), lessThan(300 * 1024));
    },
  );

  test('the water\'s box is larger than Poland\'s on every side', () {
    final LatLngBounds sea = LatLngBounds.fromPoints([
      for (final MapArea a in map.water) ...a.outer,
    ]);
    expect(sea.west, lessThan(map.bounds.west));
    expect(sea.east, greaterThan(map.bounds.east));
    expect(sea.south, lessThan(map.bounds.south));
    expect(sea.north, greaterThan(map.bounds.north));
  });
}
