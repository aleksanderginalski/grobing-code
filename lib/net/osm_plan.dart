import 'dart:convert';
import 'dart:math' as math;

import '../data/cemeteries.dart';
import '../data/cemetery_plans.dart';

// A cemetery's plan out of Overpass answers (ISSUE-027 D5; 05_DESIGN/cmentarz.md, element 2). Pure
// functions over the JSON of `out geom`, so they run in an isolate and in tests without a network. Nothing
// of OpenStreetMap's tags or names leaves this file: only coordinates and "main or side" for a path.

/// How far from the cemetery's point an outline is looked for, in metres: the query's radius.
const int outlineSearchRadius = 300;

/// An outline not containing the point is taken when its edge is this close, in metres — a point set by
/// hand at the gate (05_DESIGN/cmentarz.md D19 keeps anything further for the photo from above).
const double nearOutline = 100;

/// Paths drawn 4 dp wide (style-b.md rule 13: "główne"); every other kind asked for is a side path, 2 dp
/// (SPIKE-001 M11).
const Set<String> mainPathKinds = {'pedestrian', 'service', 'track'};
const Set<String> sidePathKinds = {'footway', 'path', 'steps'};

/// The query for the outlines at and around [point]: ways and relations tagged as a cemetery or a
/// graveyard. Two ways in one query, because each misses what the other finds (measured on a public test
/// cemetery in ISSUE-027): `around` measures to an outline's edge, so the middle of a large cemetery can
/// be further from it than the radius; `is_in` finds only outlines that contain the point, so not one next
/// to a point set by hand at the gate.
String outlineQuery(GeoPoint point) {
  final String p = '${point.lat},${point.lon}';
  final String at = 'around:$outlineSearchRadius,$p';
  return '[out:json][timeout:25];'
      'is_in($p)->.a;('
      'way(pivot.a)["landuse"="cemetery"];'
      'relation(pivot.a)["landuse"="cemetery"];'
      'way(pivot.a)["amenity"="grave_yard"];'
      'relation(pivot.a)["amenity"="grave_yard"];'
      'way["landuse"="cemetery"]($at);'
      'relation["landuse"="cemetery"]($at);'
      'way["amenity"="grave_yard"]($at);'
      'relation["amenity"="grave_yard"]($at);'
      ');out geom qt;';
}

/// The query for the paths in the box of [areas].
String pathsQuery(List<PlanArea> areas) {
  final ({double south, double west, double north, double east}) box = boxOf(
    areas,
  );
  final String kinds = [...mainPathKinds, ...sidePathKinds].join('|');
  return '[out:json][timeout:25];'
      'way["highway"~"^($kinds)\$"]'
      '(${box.south},${box.west},${box.north},${box.east});'
      'out geom qt;';
}

/// The box around the outer rings of [areas].
({double south, double west, double north, double east}) boxOf(
  List<PlanArea> areas,
) {
  double south = 90, west = 180, north = -90, east = -180;
  for (final PlanArea a in areas) {
    for (final GeoPoint p in a.outer) {
      south = math.min(south, p.lat);
      north = math.max(north, p.lat);
      west = math.min(west, p.lon);
      east = math.max(east, p.lon);
    }
  }
  return (south: south, west: west, north: north, east: east);
}

/// The cemetery's outline in an answer to [outlineQuery]: of the outlines containing [point], the largest
/// — a graveyard drawn inside a cemetery's land is part of it; otherwise the nearest one within
/// [nearOutline]; otherwise null (element 2a (d)). Seen before the plan: the one outline 300 m around a
/// point need not contain it — it was the cemetery next door.
List<PlanArea>? chooseOutline(String json, GeoPoint point) {
  final List<List<PlanArea>> outlines = parseOutlines(json);
  List<PlanArea>? largest;
  double largestArea = 0;
  for (final List<PlanArea> o in outlines) {
    if (!_inside(point, o)) continue;
    final double area = _areaOf(o);
    if (largest == null || area > largestArea) {
      largest = o;
      largestArea = area;
    }
  }
  if (largest != null) return largest;
  List<PlanArea>? nearest;
  double nearestDistance = nearOutline;
  for (final List<PlanArea> o in outlines) {
    final double d = _distanceTo(point, o);
    if (d <= nearestDistance) {
      nearest = o;
      nearestDistance = d;
    }
  }
  return nearest;
}

/// Every outline in an answer to [outlineQuery]: a closed way is one polygon; a relation is its outer rings,
/// each with the inner rings inside it, rings joined from their member ways.
List<List<PlanArea>> parseOutlines(String json) {
  final List<List<PlanArea>> outlines = [];
  for (final Map<String, Object?> e in _elements(json)) {
    switch (e['type']) {
      case 'way':
        final List<GeoPoint> ring = _geometry(e['geometry']);
        if (ring.length >= 4 && ring.first == ring.last) {
          outlines.add([PlanArea(ring)]);
        }
      case 'relation':
        final List<List<GeoPoint>> outer = [], inner = [];
        for (final Object? m in (e['members'] as List<Object?>?) ?? const []) {
          if (m is! Map<String, Object?> || m['type'] != 'way') continue;
          final List<GeoPoint> line = _geometry(m['geometry']);
          if (line.length < 2) continue;
          (m['role'] == 'inner' ? inner : outer).add(line);
        }
        final List<List<GeoPoint>> outerRings = joinRings(outer);
        final List<List<GeoPoint>> innerRings = joinRings(inner);
        final List<PlanArea> areas = [
          for (final List<GeoPoint> ring in outerRings)
            PlanArea(ring, [
              for (final List<GeoPoint> hole in innerRings)
                if (_inRing(hole.first, ring)) hole,
            ]),
        ];
        if (areas.isNotEmpty) outlines.add(areas);
    }
  }
  return outlines;
}

/// Closed rings out of a relation's member ways, which OpenStreetMap splits anywhere: joined end to end,
/// turned where needed. A ring that cannot be closed is dropped — half an outline is not a plan.
List<List<GeoPoint>> joinRings(List<List<GeoPoint>> ways) {
  final List<List<GeoPoint>> open = [for (final List<GeoPoint> w in ways) w];
  final List<List<GeoPoint>> rings = [];
  while (open.isNotEmpty) {
    final List<GeoPoint> ring = [...open.removeAt(0)];
    while (ring.first != ring.last) {
      final int next = open.indexWhere(
        (w) => w.first == ring.last || w.last == ring.last,
      );
      if (next < 0) break;
      final List<GeoPoint> w = open.removeAt(next);
      ring.addAll((w.first == ring.last ? w : w.reversed).skip(1));
    }
    if (ring.length >= 4 && ring.first == ring.last) rings.add(ring);
  }
  return rings;
}

/// The paths of an answer to [pathsQuery] inside [areas]: a segment stays when its middle is inside, and
/// the segments left in a row make one path (SPIKE-001 M11 counted paths the same way).
List<PlanPath> pathsInside(String json, List<PlanArea> areas) {
  final List<PlanPath> paths = [];
  for (final Map<String, Object?> e in _elements(json)) {
    if (e['type'] != 'way') continue;
    final Object? kind = (e['tags'] as Map<String, Object?>?)?['highway'];
    if (kind is! String) continue;
    final bool main = mainPathKinds.contains(kind);
    if (!main && !sidePathKinds.contains(kind)) continue;
    final List<GeoPoint> line = _geometry(e['geometry']);
    List<GeoPoint> run = [];
    for (int i = 0; i + 1 < line.length; i++) {
      final GeoPoint a = line[i], b = line[i + 1];
      final GeoPoint middle = GeoPoint(
        (a.lat + b.lat) / 2,
        (a.lon + b.lon) / 2,
      );
      if (_inside(middle, areas)) {
        if (run.isEmpty) run.add(a);
        run.add(b);
      } else if (run.isNotEmpty) {
        paths.add(PlanPath(run, main: main));
        run = [];
      }
    }
    if (run.isNotEmpty) paths.add(PlanPath(run, main: main));
  }
  return paths;
}

/// Whether an answer says the server gave up (Overpass answers 200 with a "remark" then, and possibly part
/// of the data) — such an answer is not used.
bool isRuntimeError(String json) =>
    json.contains('"remark"') && json.contains('runtime error');

Iterable<Map<String, Object?>> _elements(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) return const [];
  return [
    for (final Object? e in (decoded['elements'] as List<Object?>?) ?? const [])
      if (e is Map<String, Object?>) e,
  ];
}

List<GeoPoint> _geometry(Object? geometry) => [
  for (final Object? p in (geometry as List<Object?>?) ?? const [])
    if (p is Map<String, Object?> && p['lat'] is num && p['lon'] is num)
      GeoPoint((p['lat']! as num).toDouble(), (p['lon']! as num).toDouble()),
];

/// Whether [p] is inside [areas]: in an outer ring and in none of its holes.
bool insideAreas(GeoPoint p, List<PlanArea> areas) => _inside(p, areas);

bool _inside(GeoPoint p, List<PlanArea> areas) =>
    areas.any((a) => _inRing(p, a.outer) && !a.holes.any((h) => _inRing(p, h)));

/// Ray casting on degrees: within a cemetery the earth is flat enough.
bool _inRing(GeoPoint p, List<GeoPoint> ring) {
  bool inside = false;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final GeoPoint a = ring[i], b = ring[j];
    if ((a.lat > p.lat) != (b.lat > p.lat) &&
        p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon) {
      inside = !inside;
    }
  }
  return inside;
}

// Metres on a local flat projection around a point: enough for distances of a few hundred metres.
const double _metresPerDegreeLat = 110574;
double _metresPerDegreeLon(double lat) =>
    111320 * math.cos(lat * math.pi / 180);

double _areaOf(List<PlanArea> areas) {
  double total = 0;
  for (final PlanArea a in areas) {
    final double kx = _metresPerDegreeLon(a.outer.first.lat);
    double sum = 0;
    for (int i = 0, j = a.outer.length - 1; i < a.outer.length; j = i++) {
      sum +=
          (a.outer[j].lon * kx) * (a.outer[i].lat * _metresPerDegreeLat) -
          (a.outer[i].lon * kx) * (a.outer[j].lat * _metresPerDegreeLat);
    }
    total += sum.abs() / 2;
  }
  return total;
}

double _distanceTo(GeoPoint p, List<PlanArea> areas) {
  final double kx = _metresPerDegreeLon(p.lat);
  ({double x, double y}) at(GeoPoint q) =>
      (x: (q.lon - p.lon) * kx, y: (q.lat - p.lat) * _metresPerDegreeLat);
  double best = double.infinity;
  for (final PlanArea a in areas) {
    for (int i = 0; i + 1 < a.outer.length; i++) {
      final ({double x, double y}) s = at(a.outer[i]), e = at(a.outer[i + 1]);
      final double dx = e.x - s.x, dy = e.y - s.y;
      final double length = dx * dx + dy * dy;
      final double t = length == 0
          ? 0
          : ((-s.x * dx - s.y * dy) / length).clamp(0, 1).toDouble();
      final double x = s.x + t * dx, y = s.y + t * dy;
      best = math.min(best, math.sqrt(x * x + y * y));
    }
  }
  return best;
}
