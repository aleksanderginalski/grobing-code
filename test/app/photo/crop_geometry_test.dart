import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/photo/crop_geometry.dart';
import 'package:grobing/data/photos.dart';

// ISSUE-018 — the geometry of the profile crop (05_DESIGN/kadr-profilowego.md), alone: no crop is the
// largest square from the middle (D3) · the circle always all on the photo (D4) · its side between the
// shorter side and 128 px (D5) · a drag and a pinch hold the point under the finger · a tap brings a point
// to the middle (D7') · a double tap grows ×2 at the point and goes back to the whole from 128 px (D7', v1.2)
// · the decode width of a circle (F6).

const Size _landscape = Size(2048, 1536);
const Size _portrait = Size(1536, 2048);
const Size _square = Size(800, 800);
const Size _small = Size(120, 90);

void main() {
  group('no crop: the largest square from the middle (D3)', () {
    test('landscape, portrait and square photos', () {
      expect(middleSquare(_landscape), const CropSquare(256, 0, 1536));
      expect(middleSquare(_portrait), const CropSquare(0, 256, 1536));
      expect(middleSquare(_square), const CropSquare(0, 0, 800));
      expect(squareOf(null, _landscape), middleSquare(_landscape));
    });

    test('the middle as the link keeps it: whole pixels, the same square', () {
      expect(
        middleSquare(_landscape).toCrop(_landscape),
        const PhotoCrop(left: 256, top: 0, width: 1536, height: 1536),
      );
    });
  });

  group('limits (D4, D5)', () {
    test('the side stays between 128 px and the shorter side', () {
      expect(smallestSide(_landscape), 128);
      expect(largestSide(_landscape), 1536);
      expect(clampSquare(const CropSquare(0, 0, 40), _landscape).side, 128);
      expect(clampSquare(const CropSquare(0, 0, 4000), _landscape).side, 1536);
    });

    test('the square stays on the photo: past an edge it stops at it', () {
      expect(
        clampSquare(const CropSquare(-50, -10, 300), _landscape),
        const CropSquare(0, 0, 300),
      );
      expect(
        clampSquare(const CropSquare(1900, 1400, 300), _landscape),
        const CropSquare(2048 - 300, 1536 - 300, 300),
      );
    });

    test('a photo smaller than 128 px: the shorter side is both limits', () {
      expect(smallestSide(_small), 90);
      expect(largestSide(_small), 90);
      final CropSquare s = middleSquare(_small);
      expect(canZoomIn(s, _small), isFalse);
      // A double tap cannot grow it: it stays the whole.
      expect(
        doubleTapped(
          square: s,
          tap: const Offset(156, 156),
          diameter: 312,
          image: _small,
        ),
        s,
      );
    });

    test(
      'a saved crop is read inside the photo; a rectangle gives its middle square',
      () {
        expect(
          squareOf(
            const PhotoCrop(left: 100, top: 200, width: 300, height: 300),
            _landscape,
          ),
          const CropSquare(100, 200, 300),
        );
        expect(
          squareOf(
            const PhotoCrop(left: 100, top: 200, width: 400, height: 200),
            _landscape,
          ),
          const CropSquare(200, 200, 200),
        );
        // Past the edge of this photo (e.g. a crop of another size): moved back on it.
        expect(
          squareOf(
            const PhotoCrop(left: 1900, top: 0, width: 300, height: 300),
            _landscape,
          ),
          const CropSquare(1748, 0, 300),
        );
      },
    );
  });

  group('gestures', () {
    const double d = 312;

    test('a drag moves the photo with the finger: the square the other way', () {
      const CropSquare start = CropSquare(500, 300, 624);
      final CropSquare moved = moveAndScale(
        start: start,
        startFocal: const Offset(100, 100),
        focal: const Offset(150, 100),
        scale: 1,
        diameter: d,
        image: _landscape,
      );
      // 50 dp to the right = 100 px of the photo at 2 px per dp: the square goes 100 px left.
      expect(moved, const CropSquare(400, 300, 624));
    });

    test('a pinch keeps the photo\'s point under the fingers', () {
      const CropSquare start = CropSquare(500, 300, 624);
      const Offset focal = Offset(78, 156);
      final CropSquare zoomedIn = moveAndScale(
        start: start,
        startFocal: focal,
        focal: focal,
        scale: 2,
        diameter: d,
        image: _landscape,
      );
      expect(zoomedIn.side, 312);
      final Offset before = Offset(
        start.left + focal.dx * start.side / d,
        start.top + focal.dy * start.side / d,
      );
      final Offset after = Offset(
        zoomedIn.left + focal.dx * zoomedIn.side / d,
        zoomedIn.top + focal.dy * zoomedIn.side / d,
      );
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
    });

    test('a tap brings the point to the middle of the circle (D7)', () {
      const CropSquare start = CropSquare(500, 300, 624);
      final CropSquare centred = centreOn(
        square: start,
        tap: const Offset(300, 156),
        diameter: d,
        image: _landscape,
      );
      // The point 300 dp into the circle is 500 + 600 = 1100 px; it becomes the middle.
      expect(centred.centre.dx, 1100);
      expect(centred.centre.dy, start.centre.dy);
      expect(centred.side, start.side);
    });

    test('a tap outside the circle works too, and stops at the edge (D4)', () {
      final CropSquare start = middleSquare(_landscape);
      final CropSquare centred = centreOn(
        square: start,
        tap: const Offset(-40, 156),
        diameter: d,
        image: _landscape,
      );
      expect(centred.left, 0);
    });

    test('a double tap: the point to the middle, the photo ×2 (D7\')', () {
      const CropSquare start = CropSquare(500, 300, 624);
      final CropSquare grown = doubleTapped(
        square: start,
        tap: const Offset(300, 156),
        diameter: d,
        image: _landscape,
      );
      // The point 300 dp into the circle is 500 + 600 = 1100 px; it becomes the middle of a 312 px square.
      expect(grown.side, 312);
      expect(grown.centre.dx, 1100);
      expect(grown.centre.dy, start.centre.dy);
    });

    test(
      'from the whole to 128 px in 4 double taps, and the fifth goes back to the whole',
      () {
        CropSquare s = middleSquare(_landscape);
        const Offset middle = Offset(156, 156);
        final List<double> sides = [];
        for (int i = 0; i < 5; i++) {
          s = doubleTapped(
            square: s,
            tap: middle,
            diameter: d,
            image: _landscape,
          );
          sides.add(s.side);
        }
        expect(sides, [768, 384, 192, 128, 1536]);
        expect(s, middleSquare(_landscape));
        expect(canZoomIn(const CropSquare(0, 0, 128), _landscape), isFalse);
      },
    );

    test('back to the whole around the point, stopped at the edge (D4)', () {
      const CropSquare smallest = CropSquare(1800, 600, 128);
      final CropSquare whole = doubleTapped(
        square: smallest,
        tap: const Offset(156, 156),
        diameter: d,
        image: _landscape,
      );
      expect(whole, const CropSquare(2048 - 1536, 0, 1536));
    });
  });

  test(
    'the decode width of a circle: twice its pixels over the crop, never past the file (F6)',
    () {
      // 96 dp at 3× = 288 px over a crop of 1536 px of 2048: 2 × 288 × 2048 / 1536 = 768.
      expect(
        cropDecodeWidth(imageWidth: 2048, cropSide: 1536, circlePixels: 288),
        768,
      );
      // The smallest crop in a 40 dp card at 2.625×: more than the file has — the whole file.
      expect(
        cropDecodeWidth(imageWidth: 2048, cropSide: 128, circlePixels: 105),
        2048,
      );
    },
  );
}
