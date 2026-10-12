import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/net/osm_plan.dart';

// ISSUE-027 D5 (05_DESIGN/cmentarz.md, element 2) — a cemetery's plan out of Overpass answers: which outline,
// which paths. Invented geometry only: round coordinates in an empty field, no names, no tags but the ones
// the query asks for (family-data.md) — never an answer saved from a real server.

/// A closed square ring, [half] degrees around (lat, lon).
List<Map<String, double>> _square(double lat, double lon, double half) => [
  {'lat': lat - half, 'lon': lon - half},
  {'lat': lat - half, 'lon': lon + half},
  {'lat': lat + half, 'lon': lon + half},
  {'lat': lat + half, 'lon': lon - half},
  {'lat': lat - half, 'lon': lon - half},
];

Map<String, Object?> _way(
  int id,
  List<Map<String, double>> geometry, [
  Map<String, String> tags = const {'landuse': 'cemetery'},
]) => {'type': 'way', 'id': id, 'tags': tags, 'geometry': geometry};

String _answer(List<Map<String, Object?>> elements) =>
    jsonEncode({'version': 0.6, 'elements': elements});

void main() {
  const GeoPoint point = GeoPoint(51.5, 19.5);

  group('chooseOutline', () {
    test(
      'of the outlines containing the point, the largest — a graveyard drawn inside a cemetery is part of it',
      () {
        final String json = _answer([
          _way(1, _square(51.5, 19.5, 0.0005), {'amenity': 'grave_yard'}),
          _way(2, _square(51.5, 19.5, 0.002)),
          // A cemetery next door, nearer the point's edge but without it.
          _way(3, _square(51.5, 19.5035, 0.001)),
        ]);
        final List<PlanArea>? chosen = chooseOutline(json, point);
        expect(chosen, isNotNull);
        expect(chosen!.single.outer.first.lat, closeTo(51.498, 1e-9));
        expect(chosen.single.outer.first.lon, closeTo(19.498, 1e-9));
      },
    );

    test(
      'none contains the point: the nearest one within 100 m (a point set by hand at the gate)',
      () {
        // ~70 m east of the point: 0.001° of longitude at 51.5° N is ~69 m.
        final String json = _answer([
          _way(1, _square(51.5, 19.502, 0.001)),
          _way(2, _square(51.5, 19.51, 0.001)),
        ]);
        final GeoPoint corner = chooseOutline(json, point)!.single.outer.first;
        expect(corner.lat, closeTo(51.499, 1e-9));
        expect(corner.lon, closeTo(19.501, 1e-9));
      },
    );

    test(
      'none within 100 m, or no outline at all: null — "not in OpenStreetMap" (2a (d))',
      () {
        expect(
          chooseOutline(_answer([_way(1, _square(51.5, 19.51, 0.001))]), point),
          isNull,
        );
        expect(chooseOutline(_answer([]), point), isNull);
      },
    );

    test('an open way is not an outline', () {
      final List<Map<String, double>> open = _square(51.5, 19.5, 0.001)
        ..removeLast();
      expect(chooseOutline(_answer([_way(1, open)]), point), isNull);
    });

    test(
      'a relation: its outer ring joined from ways split anywhere, one of them reversed, with its hole',
      () {
        final List<Map<String, double>> ring = _square(51.5, 19.5, 0.002);
        final List<Map<String, double>> hole = _square(51.5, 19.5015, 0.0003);
        final String json = _answer([
          {
            'type': 'relation',
            'id': 9,
            'tags': {'type': 'multipolygon', 'landuse': 'cemetery'},
            'members': [
              {'type': 'way', 'role': 'outer', 'geometry': ring.sublist(0, 3)},
              {
                'type': 'way',
                'role': 'outer',
                'geometry': ring.sublist(2).reversed.toList(),
              },
              {'type': 'way', 'role': 'inner', 'geometry': hole},
              {'type': 'node', 'role': 'label'},
            ],
          },
        ]);
        final List<PlanArea> chosen = chooseOutline(json, point)!;
        expect(chosen.single.outer.length, 5);
        expect(chosen.single.outer.first, chosen.single.outer.last);
        expect(chosen.single.holes.single.length, 5);
        // A point in the hole is not in the cemetery.
        expect(insideAreas(const GeoPoint(51.5, 19.5015), chosen), isFalse);
        expect(insideAreas(point, chosen), isTrue);
      },
    );
  });

  test(
    'joinRings drops a ring that cannot be closed — half an outline is not a plan',
    () {
      final List<GeoPoint> a = [
        const GeoPoint(0, 0),
        const GeoPoint(0, 1),
        const GeoPoint(1, 1),
      ];
      expect(joinRings([a]), isEmpty);
      expect(joinRings([a, a.reversed.toList()]).single.length, 5);
    },
  );

  group('pathsInside', () {
    final List<PlanArea> areas = [
      const PlanArea([
        GeoPoint(51.498, 19.498),
        GeoPoint(51.498, 19.502),
        GeoPoint(51.502, 19.502),
        GeoPoint(51.502, 19.498),
        GeoPoint(51.498, 19.498),
      ]),
    ];

    test(
      'a path running out of the cemetery keeps only its segments inside; main and side by kind; other '
      'kinds and untagged ways left out',
      () {
        final String json = _answer([
          _way(
            1,
            [
              {'lat': 51.5, 'lon': 19.499},
              {'lat': 51.5, 'lon': 19.501},
              {'lat': 51.5, 'lon': 19.51},
              {'lat': 51.5, 'lon': 19.52},
            ],
            {'highway': 'service'},
          ),
          _way(
            2,
            [
              {'lat': 51.499, 'lon': 19.5},
              {'lat': 51.501, 'lon': 19.5},
            ],
            {'highway': 'footway'},
          ),
          _way(
            3,
            [
              {'lat': 51.499, 'lon': 19.4995},
              {'lat': 51.501, 'lon': 19.4995},
            ],
            {'highway': 'residential'},
          ),
          _way(4, [
            {'lat': 51.499, 'lon': 19.5005},
            {'lat': 51.501, 'lon': 19.5005},
          ], const {}),
        ]);
        final List<PlanPath> paths = pathsInside(json, areas);
        expect(paths.length, 2);
        final PlanPath main = paths.firstWhere((p) => p.main);
        expect(main.points, [
          const GeoPoint(51.5, 19.499),
          const GeoPoint(51.5, 19.501),
        ]);
        expect(paths.firstWhere((p) => !p.main).points.length, 2);
      },
    );

    test('a path entirely outside the cemetery gives nothing', () {
      final String json = _answer([
        _way(
          1,
          [
            {'lat': 51.6, 'lon': 19.6},
            {'lat': 51.61, 'lon': 19.6},
          ],
          {'highway': 'path'},
        ),
      ]);
      expect(pathsInside(json, areas), isEmpty);
    });
  });

  test(
    'the queries: is_in and around for the outline (each misses what the other finds), the box of the outline '
    'for the paths, JSON out with geometry',
    () {
      final String outline = outlineQuery(point);
      expect(outline, startsWith('[out:json]'));
      expect(outline, contains('is_in(51.5,19.5)'));
      expect(outline, contains('around:$outlineSearchRadius,51.5,19.5'));
      expect(outline, contains('"landuse"="cemetery"'));
      expect(outline, contains('"amenity"="grave_yard"'));
      expect(outline, endsWith('out geom qt;'));
      final String paths = pathsQuery([
        const PlanArea([
          GeoPoint(51.4, 19.4),
          GeoPoint(51.6, 19.6),
          GeoPoint(51.4, 19.6),
          GeoPoint(51.4, 19.4),
        ]),
      ]);
      expect(paths, contains('(51.4,19.4,51.6,19.6)'));
      for (final String kind in [...mainPathKinds, ...sidePathKinds]) {
        expect(paths, contains(kind));
      }
    },
  );

  test(
    'a 200 answer with a runtime error is not an answer (Overpass gave up, maybe half the data)',
    () {
      expect(
        isRuntimeError(
          '{"version":0.6,"elements":[],"remark":"runtime error: Query timed out"}',
        ),
        isTrue,
      );
      expect(isRuntimeError(_answer([])), isFalse);
    },
  );
}
