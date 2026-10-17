// On a PC: rebuilds assets/map/world.json — the countries of the world for the migration map (ISSUE-045,
// 05_DESIGN/mapa-migracji.md element 2) — from Natural Earth 1:10m admin-0 (public domain,
// https://www.naturalearthdata.com/about/terms-of-use/). The app draws the world from this file alone, so
// the map works offline from the first start (AC-4; as the map of Poland, ADR-007).
//
// The source file is not in the repository. Download it from
// https://github.com/nvkelso/natural-earth-vector/tree/master/geojson into a directory:
//   ne_10m_admin_0_countries.geojson
// (the same file the map of Poland and the list of places are built from), then:
//   dart run tool/map/extract_world.dart <that directory>
//
// Each country keeps its code (`ISO_A2_EH` — `ISO_A2` is `-99` for France and Norway), its Polish name and
// the point Natural Earth puts its label at: the same point tool/places/build_places.dart gives a country,
// so a residence known only to its country stands where its name is (mapa-migracji.md, element 6 — O3).
// No holes: an enclave is a country of its own, drawn over the one around it in the same colour.

import 'dart:convert';
import 'dart:io';

/// Douglas–Peucker tolerance in degrees: about 6.7 km. The map shows a family's countries, not its towns'
/// streets: closer than a region it would look angular (mapa-migracji.md D1). Measured in the plan of
/// ISSUE-045 on the same source: 37.8 thousand points, about 615 KB.
const double _tolerance = 0.06;

/// Islands and specks smaller than this, in square degrees, are left out.
const double _minArea = 0.15;

/// Web Mercator ends before the poles; nobody of a family lived south of this.
const double _maxLatitude = 84;

/// Antarctica: its polygon runs to the pole, where Mercator has no end.
const Set<String> _left = {'AQ'};

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/map/extract_world.dart <directory with ne_10m_admin_0_countries.geojson>',
    );
    exitCode = 64;
    return;
  }
  final Map<String, Object?> source =
      jsonDecode(
            await File(
              '${args.single}/ne_10m_admin_0_countries.geojson',
            ).readAsString(),
          )
          as Map<String, Object?>;
  final List<Map<String, Object?>> countries = [];
  int points = 0;
  for (final Map<String, Object?> feature
      in (source['features']! as List<Object?>).cast<Map<String, Object?>>()) {
    final Map<String, Object?> p =
        feature['properties']! as Map<String, Object?>;
    final Map<String, Object?>? geometry =
        feature['geometry'] as Map<String, Object?>?;
    final String code = p['ISO_A2_EH']! as String;
    if (geometry == null || _left.contains(code)) continue;
    final List<List<double>> rings = [];
    for (final List<Object?> polygon in _polygons(geometry)) {
      final List<List<double>> outer = _points(polygon.first!);
      if (_area(outer) < _minArea) continue;
      final List<List<double>> simple = _simplifyRing(outer);
      if (simple.length < 4) continue;
      points += simple.length;
      rings.add([
        for (final List<double> q in simple) ...[
          _round(q[1].clamp(-_maxLatitude, _maxLatitude)),
          _round(q[0]),
        ],
      ]);
    }
    if (rings.isEmpty) continue;
    final String? name = p['NAME_PL'] as String?;
    countries.add({
      // Shapes without a code (Northern Cyprus, Somaliland) are land all the same.
      if (code != '-99') 'code': code,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      'label': [
        _round((p['LABEL_Y']! as num).toDouble()),
        _round((p['LABEL_X']! as num).toDouble()),
      ],
      'rings': rings,
    });
  }
  final File out = File('assets/map/world.json');
  await out.writeAsString(
    jsonEncode({
      'source':
          'Natural Earth 1:10m admin-0 countries (public domain) — tool/map/extract_world.dart',
      'countries': countries,
    }),
  );
  stdout.writeln(
    '${countries.length} countries, $points points, '
    '${(await out.length() / 1024).round()} KB → ${out.path}',
  );
}

/// GeoJSON positions are `[lon, lat]`.
List<List<double>> _points(Object line) => [
  for (final Object? p in line as List<Object?>)
    [
      ((p! as List<Object?>)[0]! as num).toDouble(),
      ((p as List<Object?>)[1]! as num).toDouble(),
    ],
];

/// The polygons of a Polygon or a MultiPolygon, each a list of rings: the outer one first, then holes.
List<List<Object?>> _polygons(Map<String, Object?> g) =>
    g['type'] == 'MultiPolygon'
    ? [
        for (final Object? p in g['coordinates']! as List<Object?>)
          p! as List<Object?>,
      ]
    : [g['coordinates']! as List<Object?>];

/// Douglas–Peucker on a closed ring: its first point stays, and so does the one farthest from it.
List<List<double>> _simplifyRing(List<List<double>> ring) {
  if (ring.length < 5) return ring;
  int far = 0;
  double best = -1;
  for (int i = 1; i < ring.length - 1; i++) {
    final double d = _distance2(ring[0], ring[i]);
    if (d > best) {
      best = d;
      far = i;
    }
  }
  return [
    ..._simplify(ring.sublist(0, far + 1)),
    ..._simplify(ring.sublist(far)).skip(1),
  ];
}

/// Douglas–Peucker on an open line, its ends kept.
List<List<double>> _simplify(List<List<double>> line) {
  if (line.length < 3) return line;
  final List<bool> keep = List<bool>.filled(line.length, false)
    ..[0] = true
    ..[line.length - 1] = true;
  final List<(int, int)> stack = [(0, line.length - 1)];
  const double t2 = _tolerance * _tolerance;
  while (stack.isNotEmpty) {
    final (int a, int b) = stack.removeLast();
    int index = -1;
    double best = 0;
    for (int i = a + 1; i < b; i++) {
      final double over = _segmentDistance2(line[i], line[a], line[b]) - t2;
      if (over > best) {
        best = over;
        index = i;
      }
    }
    if (index >= 0) {
      keep[index] = true;
      stack
        ..add((a, index))
        ..add((index, b));
    }
  }
  return [
    for (int i = 0; i < line.length; i++)
      if (keep[i]) line[i],
  ];
}

double _distance2(List<double> a, List<double> b) {
  final double dx = a[0] - b[0], dy = a[1] - b[1];
  return dx * dx + dy * dy;
}

double _segmentDistance2(List<double> p, List<double> a, List<double> b) {
  final double dx = b[0] - a[0], dy = b[1] - a[1];
  final double len2 = dx * dx + dy * dy;
  if (len2 == 0) return _distance2(p, a);
  final double t = (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2).clamp(
    0.0,
    1.0,
  );
  return _distance2(p, [a[0] + t * dx, a[1] + t * dy]);
}

/// The area of a ring in square degrees (shoelace) — only to sort out specks.
double _area(List<List<double>> ring) {
  double sum = 0;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    sum += ring[j][0] * ring[i][1] - ring[i][0] * ring[j][1];
  }
  return (sum / 2).abs();
}

/// Three decimal places: about 110 m, far below the tolerance.
double _round(double v) => (v * 1000).round() / 1000;
