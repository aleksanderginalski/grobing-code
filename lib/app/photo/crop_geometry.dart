import 'dart:math' as math;
import 'dart:ui';

import '../../data/photos.dart';

// The geometry of the profile crop (05_DESIGN/kadr-profilowego.md; ISSUE-018), apart from any screen so
// it can be tested alone. The crop is a square in the photo's pixels; on the crop screen the circle
// stands still and the photo moves under it (D1), so the square under the circle is the whole state.

/// The smallest square the circle may cover, in the photo's pixels (D5): a smaller one would be blurred
/// more than twice in the 96 dp header, and the access copy has no more detail anyway (ADR-008).
const double smallestCropSide = 128;

/// The square under the circle, in the photo's pixels: its top-left corner and its side.
class CropSquare {
  const CropSquare(this.left, this.top, this.side);

  final double left;
  final double top;
  final double side;

  /// The middle of the square, in the photo's pixels.
  Offset get centre => Offset(left + side / 2, top + side / 2);

  /// The whole pixels a link keeps (GEDCOM `CROP`), inside [image].
  PhotoCrop toCrop(Size image) {
    final int side = math.max(
      1,
      math.min(this.side.round(), shorterSide(image).floor()),
    );
    final int left = this.left.round().clamp(0, image.width.floor() - side);
    final int top = this.top.round().clamp(0, image.height.floor() - side);
    return PhotoCrop(left: left, top: top, width: side, height: side);
  }

  static CropSquare lerp(CropSquare a, CropSquare b, double t) => CropSquare(
    lerpDouble(a.left, b.left, t)!,
    lerpDouble(a.top, b.top, t)!,
    lerpDouble(a.side, b.side, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is CropSquare &&
      other.left == left &&
      other.top == top &&
      other.side == side;

  @override
  int get hashCode => Object.hash(left, top, side);

  @override
  String toString() => 'CropSquare($left, $top, $side)';
}

double shorterSide(Size image) => math.min(image.width, image.height);

/// The largest square the circle may cover: the shorter side, so the circle stays on the photo (D4).
double largestSide(Size image) => shorterSide(image);

/// The smallest square: [smallestCropSide], or the shorter side of a smaller photo (then the photo only
/// moves along its longer side).
double smallestSide(Size image) =>
    math.min(smallestCropSide, shorterSide(image));

/// No crop: the largest square from the middle — what every profile circle has shown so far (D3).
CropSquare middleSquare(Size image) {
  final double side = largestSide(image);
  return CropSquare((image.width - side) / 2, (image.height - side) / 2, side);
}

/// The square of a link's [crop] — a rectangle (none is written by the app, but GEDCOM allows it) gives
/// the square from its middle — kept inside [image]; no crop gives [middleSquare].
CropSquare squareOf(PhotoCrop? crop, Size image) {
  if (crop == null) return middleSquare(image);
  final double side = math
      .min(crop.width, crop.height)
      .toDouble()
      .clamp(smallestSide(image), largestSide(image));
  return clampSquare(
    CropSquare(
      crop.left + (crop.width - side) / 2,
      crop.top + (crop.height - side) / 2,
      side,
    ),
    image,
  );
}

/// [square] within its limits: its side between [smallestSide] and [largestSide], and the whole square on
/// the photo — the photo stops at its edge, with no bounce (D4). The side is clamped around the middle.
CropSquare clampSquare(CropSquare square, Size image) {
  final double side = square.side.clamp(
    smallestSide(image),
    largestSide(image),
  );
  final Offset centre = square.centre;
  return CropSquare(
    (centre.dx - side / 2).clamp(0, image.width - side),
    (centre.dy - side / 2).clamp(0, image.height - side),
    side,
  );
}

/// One frame of a drag or a pinch, measured from where it started: the photo's point that was under
/// [startFocal] is under [focal] now, and the photo is [scale] times as large as at the start. Points
/// are on the screen, relative to the circle's box (its top-left corner); [diameter] is the circle's.
CropSquare moveAndScale({
  required CropSquare start,
  required Offset startFocal,
  required Offset focal,
  required double scale,
  required double diameter,
  required Size image,
}) {
  final double side = (start.side / scale).clamp(
    smallestSide(image),
    largestSide(image),
  );
  final Offset held = Offset(
    start.left + startFocal.dx * start.side / diameter,
    start.top + startFocal.dy * start.side / diameter,
  );
  return clampSquare(
    CropSquare(
      held.dx - focal.dx * side / diameter,
      held.dy - focal.dy * side / diameter,
      side,
    ),
    image,
  );
}

/// A tap: the photo's point under [tap] goes to the middle of the circle (D7 — the one-tap way to move
/// the photo). [tap] is relative to the circle's box and may lie outside the circle.
CropSquare centreOn({
  required CropSquare square,
  required Offset tap,
  required double diameter,
  required Size image,
}) {
  final Offset point = Offset(
    square.left + tap.dx * square.side / diameter,
    square.top + tap.dy * square.side / diameter,
  );
  return clampSquare(
    CropSquare(
      point.dx - square.side / 2,
      point.dy - square.side / 2,
      square.side,
    ),
    image,
  );
}

/// A double tap (D7', v1.2 — the author's choice at stop #2, instead of "Pomniejsz"/"Powiększ"): the point
/// under it goes to the middle of the circle and the photo grows ×2; at the largest zoom it goes back to the
/// whole — the circle over the shorter side — around that point. The one-pointer way to zoom (SC 2.5.1).
CropSquare doubleTapped({
  required CropSquare square,
  required Offset tap,
  required double diameter,
  required Size image,
}) {
  final Offset point = Offset(
    square.left + tap.dx * square.side / diameter,
    square.top + tap.dy * square.side / diameter,
  );
  final double side = canZoomIn(square, image)
      ? square.side / 2
      : largestSide(image);
  return clampSquare(
    CropSquare(point.dx - side / 2, point.dy - side / 2, side),
    image,
  );
}

/// Whether the photo can grow any more; half a pixel of slack for rounding.
bool canZoomIn(CropSquare square, Size image) =>
    square.side > smallestSide(image) + 0.5;

/// The width to decode a photo at for a profile circle of [circlePixels] physical pixels showing
/// [cropSide] pixels of an image [imageWidth] wide: twice the circle's pixels over the crop, as the
/// circles decode now (`coverDecodeWidth`), but never more than the file has (plan F6).
int cropDecodeWidth({
  required double imageWidth,
  required double cropSide,
  required double circlePixels,
}) => math
    .min(imageWidth, (2 * circlePixels * imageWidth / cropSide).ceilToDouble())
    .round();
