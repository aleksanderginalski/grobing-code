// On a PC: rebuilds assets/map/poland.json — the outline of Poland, its rivers and eleven cities, and
// around it the sea, the lakes and the borders of the neighbours — from Natural Earth 1:10m (public
// domain, https://www.naturalearthdata.com/about/terms-of-use/). The app draws the map from this file
// alone, so the map of Poland works offline from the first start (ISSUE-014, ADR-007; the map like R1 —
// ISSUE-023, 05_DESIGN/cmentarze.md D29).
//
// The seven source files are not in the repository. Download them from
// https://github.com/nvkelso/natural-earth-vector/tree/master/geojson into one directory:
//   ne_10m_admin_0_countries.geojson
//   ne_10m_rivers_lake_centerlines.geojson
//   ne_10m_populated_places_simple.geojson
//   ne_10m_ocean.geojson
//   ne_10m_lakes.geojson
//   ne_10m_lakes_europe.geojson
//   ne_10m_admin_0_boundary_lines_land.geojson
// then:
//   dart run tool/map/extract_poland.dart <that directory>
//
// No names leave the source files but the cities' below: the countries, the sea, the lakes and the
// rivers are shapes only.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// The cities on the map (05_DESIGN/cmentarze.md, element 3): Natural Earth's ASCII name → the Polish
/// one shown in the app. Spread over the whole country — orientation, not an atlas.
const Map<String, String> _cities = {
  'Szczecin': 'Szczecin',
  'Gdansk': 'Gdańsk',
  'Bydgoszcz': 'Bydgoszcz',
  'Bialystok': 'Białystok',
  'Poznan': 'Poznań',
  'Warsaw': 'Warszawa',
  'Lodz': 'Łódź',
  'Wroclaw': 'Wrocław',
  'Katowice': 'Katowice',
  'Lublin': 'Lublin',
  'Krakow': 'Kraków',
};

/// Rivers up to this Natural Earth rank: the Vistula, the Oder and their main tributaries.
const int _maxRiverRank = 7;

/// What is kept around Poland, `[west, south, east, north]` in degrees: more than the camera can show.
/// Its centre stays inside Poland (`CameraConstraint.containCenter`), so at the least zoom the view reaches
/// half a screen past Poland's box on every side: on a 411 × 914 dp phone about 5.5° east and west and to
/// 42.5° and 59.7° north; on a short 360 × 640 dp one, where the room for the sheet makes Poland small, to
/// 4.5° and 33.7° east and 41.3° and 60.4° north (computed; `qa` checks it, ISSUE-023). An edge of the data
/// on the screen would be a sea that ends in a straight line.
const List<double> _box = [3, 40, 35, 62];

/// Lakes smaller than this are left out: at the least zoom 1 dp is about 2 km, so smaller ones would be
/// specks. Abroad only the large ones, and far away the largest — there the map is background.
const double _minLakeKm2 = 8;
const double _minLakeKm2Abroad = 40;
const double _minLakeKm2FarAway = 150;

/// Douglas–Peucker tolerance in degrees, by place. Near Poland about 50 m — about 1 dp at the closest
/// zoom, so the sea's coast meets Poland's own outline, which is not simplified. Around it about 600 m.
/// Far away about 2 km: only the least zoom reaches there, where 1 dp is about 0.026°.
double _tolerance(List<double> p) => _nearPoland(p)
    ? 0.0005
    : _aroundPoland(p)
    ? 0.006
    : 0.02;

/// Poland's box, `[west, south, east, north]`, and half a degree around it.
const List<double> _poland = [13.6, 48.5, 24.7, 55.4];

bool _nearPoland(List<double> p) => _within(p, _poland, 0);

/// Four degrees around Poland's box: what a closer zoom can reach near the border.
bool _aroundPoland(List<double> p) => _within(p, _poland, 3.5);

bool _within(List<double> p, List<double> box, double margin) =>
    p[0] >= box[0] - margin &&
    p[0] <= box[2] + margin &&
    p[1] >= box[1] - margin &&
    p[1] <= box[3] + margin;

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/map/extract_poland.dart <directory with the Natural Earth files>',
    );
    exit(64);
  }
  final String dir = args.single;
  Map<String, Object?> read(String name) =>
      jsonDecode(File('$dir/$name.geojson').readAsStringSync())
          as Map<String, Object?>;
  List<Map<String, Object?>> features(Map<String, Object?> collection) =>
      (collection['features']! as List<Object?>).cast<Map<String, Object?>>();
  Map<String, Object?> props(Map<String, Object?> f) =>
      f['properties']! as Map<String, Object?>;

  // Outline: the single polygon of Poland (Natural Earth has no islands for it at 1:10m).
  final Map<String, Object?> poland = features(
    read('ne_10m_admin_0_countries'),
  ).singleWhere((f) => props(f)['ADM0_A3'] == 'POL');
  final Map<String, Object?> geometry =
      poland['geometry']! as Map<String, Object?>;
  final List<Object?> polygon = geometry['type'] == 'MultiPolygon'
      ? ((geometry['coordinates']! as List<Object?>).single! as List<Object?>)
      : geometry['coordinates']! as List<Object?>;
  final List<List<double>> ring = _points(polygon.first!);

  // Rivers: kept only inside the outline, cut where they leave it.
  final List<List<List<double>>> rivers = [];
  for (final Map<String, Object?> f in features(
    read('ne_10m_rivers_lake_centerlines'),
  )) {
    final Object? rank = props(f)['scalerank'];
    final Map<String, Object?>? g = f['geometry'] as Map<String, Object?>?;
    if (g == null || rank is! num || rank > _maxRiverRank) continue;
    for (final Object? line in _lines(g)) {
      rivers.addAll(_cut(_points(line!), (p) => _inside(p, ring)));
    }
  }

  // The sea: the ocean's polygons cut to the box, islands as holes.
  final List<List<List<List<double>>>> water = [];
  for (final Map<String, Object?> f in features(read('ne_10m_ocean'))) {
    for (final List<Object?> p in _polygons(
      f['geometry']! as Map<String, Object?>,
    )) {
      final List<List<List<double>>>? kept = _clipPolygon(p);
      if (kept != null) water.add(kept);
    }
  }

  // Lakes from both files; the European one adds the smaller lakes the world one leaves out.
  final List<List<List<List<double>>>> lakes = [];
  for (final String name in ['ne_10m_lakes', 'ne_10m_lakes_europe']) {
    for (final Map<String, Object?> f in features(read(name))) {
      final Map<String, Object?>? g = f['geometry'] as Map<String, Object?>?;
      if (g == null) continue;
      for (final List<Object?> p in _polygons(g)) {
        final List<List<double>> outer = _points(p.first!);
        if (!_touchesBox(outer)) continue;
        final double min = outer.any(_nearPoland)
            ? _minLakeKm2
            : outer.any(_aroundPoland)
            ? _minLakeKm2Abroad
            : _minLakeKm2FarAway;
        if (_areaKm2(outer) < min) continue;
        final List<List<List<double>>>? kept = _clipPolygon(p);
        if (kept != null) lakes.add(kept);
      }
    }
  }

  // The neighbours' borders, without Poland's own: the outline draws those.
  final List<List<List<double>>> borders = [];
  for (final Map<String, Object?> f in features(
    read('ne_10m_admin_0_boundary_lines_land'),
  )) {
    final Map<String, Object?> p = props(f);
    if (p['ADM0_A3_L'] == 'POL' || p['ADM0_A3_R'] == 'POL') continue;
    final Map<String, Object?>? g = f['geometry'] as Map<String, Object?>?;
    if (g == null) continue;
    for (final Object? line in _lines(g)) {
      for (final List<List<double>> piece in _cut(_points(line!), _inBox)) {
        final List<List<double>> simple = _simplify(piece);
        if (simple.length > 1) borders.add(simple);
      }
    }
  }

  final List<Map<String, Object>> cities = [];
  for (final Map<String, Object?> f in features(
    read('ne_10m_populated_places_simple'),
  )) {
    final Map<String, Object?> p = props(f);
    final String? polish = _cities[p['nameascii']];
    if (polish == null || p['adm0_a3'] != 'POL') continue;
    cities.add({
      'name': polish,
      'lat': _round((p['latitude']! as num).toDouble()),
      'lon': _round((p['longitude']! as num).toDouble()),
    });
  }
  if (cities.length != _cities.length) {
    stderr.writeln(
      'Expected ${_cities.length} cities, found ${cities.length}.',
    );
    exit(1);
  }

  List<List<double>> latLon(List<List<double>> line) => [
    for (final List<double> p in line) [_round(p[1]), _round(p[0])],
  ];
  List<List<List<double>>> rings(List<List<List<double>>> polygon) => [
    for (final List<List<double>> r in polygon) latLon(r),
  ];
  final Map<String, Object> out = {
    'source':
        'Natural Earth 1:10m (public domain) — tool/map/extract_poland.dart',
    'outline': latLon(ring),
    'rivers': [for (final List<List<double>> r in rivers) latLon(r)],
    'water': [for (final List<List<List<double>>> p in water) rings(p)],
    'lakes': [for (final List<List<List<double>>> p in lakes) rings(p)],
    'borders': [for (final List<List<double>> b in borders) latLon(b)],
    'cities': cities,
  };
  final File file = File('assets/map/poland.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(out));
  int count(Iterable<List<List<double>>> lines) =>
      lines.fold(0, (n, l) => n + l.length);
  stdout.writeln(
    'outline ${ring.length} points · rivers ${rivers.length} lines · '
    'water ${water.length} polygons, ${count(water.expand((p) => p))} points · '
    'lakes ${lakes.length}, ${count(lakes.expand((p) => p))} points · '
    'borders ${borders.length} lines, ${count(borders)} points · '
    'cities ${cities.length} · ${file.lengthSync()} bytes → ${file.path}',
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

/// The lines of a LineString or a MultiLineString.
List<Object?> _lines(Map<String, Object?> g) => g['type'] == 'MultiLineString'
    ? g['coordinates']! as List<Object?>
    : [g['coordinates']];

/// The polygons of a Polygon or a MultiPolygon, each a list of rings: the outer one first, then holes.
List<List<Object?>> _polygons(Map<String, Object?> g) =>
    g['type'] == 'MultiPolygon'
    ? (g['coordinates']! as List<Object?>).cast<List<Object?>>()
    : [g['coordinates']! as List<Object?>];

/// The pieces of [line] whose points pass [keep], cut where it leaves.
List<List<List<double>>> _cut(
  List<List<double>> line,
  bool Function(List<double> p) keep,
) {
  final List<List<List<double>>> pieces = [];
  List<List<double>> current = [];
  for (final List<double> p in line) {
    if (keep(p)) {
      current.add(p);
    } else {
      if (current.length > 1) pieces.add(current);
      current = [];
    }
  }
  if (current.length > 1) pieces.add(current);
  return pieces;
}

bool _inBox(List<double> p) =>
    p[0] >= _box[0] && p[0] <= _box[2] && p[1] >= _box[1] && p[1] <= _box[3];

bool _touchesBox(List<List<double>> ring) {
  double w = 180, s = 90, e = -180, n = -90;
  for (final List<double> p in ring) {
    w = math.min(w, p[0]);
    e = math.max(e, p[0]);
    s = math.min(s, p[1]);
    n = math.max(n, p[1]);
  }
  return w <= _box[2] && e >= _box[0] && s <= _box[3] && n >= _box[1];
}

/// [polygon]'s rings cut to the box and simplified; null when its outer ring is gone. A hole outside the
/// box is dropped. Clipping a concave ring can leave edges along the box — outside what the camera shows.
List<List<List<double>>>? _clipPolygon(List<Object?> polygon) {
  final List<List<List<double>>> kept = [];
  for (final (int i, Object? r) in polygon.indexed) {
    final List<List<double>> ring = _points(r!);
    if (!_touchesBox(ring)) {
      if (i == 0) return null;
      continue;
    }
    final List<List<double>> clipped = _simplifyRing(_clipRing(ring));
    if (clipped.length < 4) {
      if (i == 0) return null;
      continue;
    }
    kept.add(clipped);
  }
  return kept;
}

/// Sutherland–Hodgman against the four edges of the box; the result is closed again.
List<List<double>> _clipRing(List<List<double>> ring) {
  List<List<double>> points =
      ring.first[0] == ring.last[0] && ring.first[1] == ring.last[1]
      ? ring.sublist(0, ring.length - 1)
      : ring;
  for (int edge = 0; edge < 4; edge++) {
    if (points.isEmpty) break;
    final int axis = edge % 2 == 0 ? 0 : 1;
    final double limit = _box[edge];
    final bool keepAbove = edge < 2; // west and south keep ≥, east and north ≤
    bool inside(List<double> p) =>
        keepAbove ? p[axis] >= limit : p[axis] <= limit;
    List<double> cross(List<double> a, List<double> b) {
      final double t = (limit - a[axis]) / (b[axis] - a[axis]);
      return axis == 0
          ? [limit, a[1] + t * (b[1] - a[1])]
          : [a[0] + t * (b[0] - a[0]), limit];
    }

    final List<List<double>> next = [];
    for (int i = 0; i < points.length; i++) {
      final List<double> current = points[i];
      final List<double> previous =
          points[(i + points.length - 1) % points.length];
      if (inside(current)) {
        if (!inside(previous)) next.add(cross(previous, current));
        next.add(current);
      } else if (inside(previous)) {
        next.add(cross(previous, current));
      }
    }
    points = next;
  }
  if (points.isEmpty) return points;
  return [...points, points.first];
}

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

/// Douglas–Peucker on an open line, its ends kept; each point measured against [_tolerance] at its place.
List<List<double>> _simplify(List<List<double>> line) {
  if (line.length < 3) return line;
  final List<bool> keep = List<bool>.filled(line.length, false)
    ..[0] = true
    ..[line.length - 1] = true;
  final List<(int, int)> stack = [(0, line.length - 1)];
  while (stack.isNotEmpty) {
    final (int a, int b) = stack.removeLast();
    int index = -1;
    double best = 0;
    for (int i = a + 1; i < b; i++) {
      final double t = _tolerance(line[i]);
      final double over = _segmentDistance2(line[i], line[a], line[b]) - t * t;
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

/// The area of a ring in km², near enough to sort out specks: degrees scaled by the cosine of the
/// latitude, then the shoelace formula.
double _areaKm2(List<List<double>> ring) {
  const double kmPerDegree = 111.32;
  double sum = 0;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final double xi = ring[i][0] * math.cos(ring[i][1] * math.pi / 180);
    final double xj = ring[j][0] * math.cos(ring[j][1] * math.pi / 180);
    sum += xj * ring[i][1] - xi * ring[j][1];
  }
  return (sum / 2).abs() * kmPerDegree * kmPerDegree;
}

/// Ray casting, `[lon, lat]` against `[lon, lat]` ring.
bool _inside(List<double> p, List<List<double>> ring) {
  bool inside = false;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final double xi = ring[i][0], yi = ring[i][1];
    final double xj = ring[j][0], yj = ring[j][1];
    if ((yi > p[1]) != (yj > p[1]) &&
        p[0] < (xj - xi) * (p[1] - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// Four decimal places: about 10 m, far below what the map of Poland can show.
double _round(double v) => (v * 10000).round() / 10000;
