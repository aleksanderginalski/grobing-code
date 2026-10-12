import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/sector_geometry.dart';
import 'package:latlong2/latlong.dart';

// ISSUE-028 — the geometry of a sector (05_DESIGN/cmentarz.md v6, elements 4 and 18): where its name
// stands, sides that cross, a touch inside a zone. Invented coordinates only.

void main() {
  // A square cemetery block, north up: south-west, south-east, north-east, north-west.
  const LatLng sw = LatLng(51.4990, 19.4990);
  const LatLng se = LatLng(51.4990, 19.5000);
  const LatLng ne = LatLng(51.5000, 19.5000);
  const LatLng nw = LatLng(51.5000, 19.4990);

  test(
    'D13 — the name stands at the corner most to the left and down, whatever the order',
    () {
      expect(labelCorner([ne, nw, sw, se]), sw);
      expect(labelCorner([se, ne, nw, sw]), sw);
      // A rhombus: the lowest-left of its corners.
      const LatLng south = LatLng(51.4990, 19.4995);
      const LatLng west = LatLng(51.4995, 19.4985);
      expect(
        labelCorner([
          south,
          const LatLng(51.4995, 19.5005),
          const LatLng(51.5000, 19.4995),
          west,
        ]),
        west,
      );
    },
  );

  test(
    'element 18 — a bow tie has sides that cross; a square, a triangle and a concave zone do not',
    () {
      expect(sidesCross([sw, ne, se, nw]), isTrue);
      expect(sidesCross([sw, se, ne, nw]), isFalse);
      expect(sidesCross([sw, se, ne]), isFalse);
      // An L-shaped zone.
      expect(
        sidesCross([
          sw,
          se,
          const LatLng(51.4995, 19.5000),
          const LatLng(51.4995, 19.4995),
          const LatLng(51.5000, 19.4995),
          nw,
        ]),
        isFalse,
      );
    },
  );

  test(
    'element 4 — a touch inside the zone hits it, one outside does not; a smaller zone is smaller',
    () {
      final List<LatLng> square = [sw, se, ne, nw];
      expect(ringContains(square, const LatLng(51.4995, 19.4995)), isTrue);
      expect(ringContains(square, const LatLng(51.5005, 19.4995)), isFalse);
      final List<LatLng> half = [
        sw,
        const LatLng(51.4990, 19.4995),
        const LatLng(51.5000, 19.4995),
        nw,
      ];
      expect(ringArea(half), lessThan(ringArea(square)));
      expect(
        ringArea(half) * 2,
        closeTo(ringArea(square), ringArea(square) * 0.01),
      );
    },
  );
}
