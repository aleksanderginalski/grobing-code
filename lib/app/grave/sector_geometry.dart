import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// The geometry of the author's sectors (05_DESIGN/cmentarz.md v6, elements 4 and 18; ISSUE-028) — on the
// map's own projection (Web Mercator, north up), so "left", "down" and "crossing" mean what the screen shows.
// No Flutter: the rules are tested on their own.

/// A point of the map in Mercator units: x grows east, y grows north.
({double x, double y}) _mercator(LatLng p) {
  final double phi = p.latitude * math.pi / 180;
  return (
    x: p.longitude * math.pi / 180,
    y: math.log(math.tan(math.pi / 4 + phi / 2)),
  );
}

/// The corner the sector's name stands at (element 4, D13): the most to the left and down — the largest
/// "y − x" on the screen — so the name stays in the zone's lower left and out from under the candles.
LatLng labelCorner(List<LatLng> ring) {
  LatLng best = ring.first;
  double bestScore = double.infinity;
  for (final LatLng p in ring) {
    final ({double x, double y}) m = _mercator(p);
    // Down on the screen is south: the smallest x + y is the most left and down.
    final double score = m.x + m.y;
    if (score < bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

/// Whether two sides of the closed [ring] cross (element 18 → walidacja: "Boki strefy się przecinają"):
/// sides that share a corner never count, a side touching another one does.
bool sidesCross(List<LatLng> ring) {
  final int n = ring.length;
  if (n < 4) return false;
  final List<({double x, double y})> m = [
    for (final LatLng p in ring) _mercator(p),
  ];
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      // Neighbours share a corner, the last side meets the first.
      if (j == i + 1 || (i == 0 && j == n - 1)) continue;
      if (_segmentsMeet(m[i], m[(i + 1) % n], m[j], m[(j + 1) % n])) {
        return true;
      }
    }
  }
  return false;
}

bool _segmentsMeet(
  ({double x, double y}) a,
  ({double x, double y}) b,
  ({double x, double y}) c,
  ({double x, double y}) d,
) {
  double cross(
    ({double x, double y}) o,
    ({double x, double y}) p,
    ({double x, double y}) q,
  ) => (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
  bool within(
    ({double x, double y}) o,
    ({double x, double y}) p,
    ({double x, double y}) q,
  ) =>
      math.min(o.x, p.x) <= q.x &&
      q.x <= math.max(o.x, p.x) &&
      math.min(o.y, p.y) <= q.y &&
      q.y <= math.max(o.y, p.y);
  final double d1 = cross(c, d, a), d2 = cross(c, d, b);
  final double d3 = cross(a, b, c), d4 = cross(a, b, d);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  return (d1 == 0 && within(c, d, a)) ||
      (d2 == 0 && within(c, d, b)) ||
      (d3 == 0 && within(a, b, c)) ||
      (d4 == 0 && within(a, b, d));
}

/// Whether [p] is inside the closed [ring] (a touch on a zone in mode E selects its sector — element 4).
bool ringContains(List<LatLng> ring, LatLng p) {
  bool inside = false;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final LatLng a = ring[i], b = ring[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) *
                    (p.latitude - a.latitude) /
                    (b.latitude - a.latitude) +
                a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

/// The area of the closed [ring] in Mercator units — the smallest zone wins when zones overlap.
double ringArea(List<LatLng> ring) {
  double sum = 0;
  final List<({double x, double y})> m = [
    for (final LatLng p in ring) _mercator(p),
  ];
  for (int i = 0, j = m.length - 1; i < m.length; j = i++) {
    sum += (m[j].x * m[i].y) - (m[i].x * m[j].y);
  }
  return sum.abs() / 2;
}
