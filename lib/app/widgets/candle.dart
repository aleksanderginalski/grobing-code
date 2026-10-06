import 'package:flutter/material.dart';

import '../theme.dart';

/// The candle (znicz) — the app's sign (style-b.md rule 8): one silhouette, drawn here and nowhere
/// else (05_DESIGN/cmentarze.md → Style B rules applied). A glass jar slightly narrower at the
/// bottom, a collar on top and a drop-shaped flame, in a 24 × 24 grid like the `outlined` icons.
Path _candlePath() {
  final Path flame = Path()
    ..moveTo(12, 2.6)
    ..cubicTo(13.6, 4.5, 14.4, 5.9, 14.4, 7.2)
    ..arcToPoint(const Offset(9.6, 7.2), radius: const Radius.circular(2.4))
    ..cubicTo(9.6, 5.9, 10.4, 4.5, 12, 2.6)
    ..close();
  final Path collar = Path()
    ..addRRect(
      RRect.fromLTRBR(7.4, 10.2, 16.6, 12.4, const Radius.circular(0.6)),
    );
  final Path glass = Path()
    ..moveTo(8.3, 12.4)
    ..lineTo(15.7, 12.4)
    ..lineTo(14.8, 21.5)
    ..lineTo(9.2, 21.5)
    ..close();
  return Path()
    ..addPath(flame, Offset.zero)
    ..addPath(collar, Offset.zero)
    ..addPath(glass, Offset.zero);
}

/// The candle as an icon: thin line (logo, button icons) or filled (inside a pin).
class CandleIcon extends StatelessWidget {
  const CandleIcon({
    super.key,
    this.size = 24,
    this.color = GrobingColors.amber,
    this.filled = false,
  });

  final double size;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _CandlePainter(color: color, filled: filled),
    ),
  );
}

class _CandlePainter extends CustomPainter {
  const _CandlePainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      _candlePath(),
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.color != color || old.filled != filled;
}

/// How a cemetery pin looks (05_DESIGN/cmentarze.md, element 4; style-b.md rule 13).
enum PinLook {
  /// A saved cemetery: amber pin, candle in the background colour.
  normal,

  /// The selected one: larger, with a soft amber glow (rule 2).
  selected,

  /// A place not saved yet: amber outline, the land colour inside.
  outlined,
}

/// A candle-shaped map pin, 32 × 40 dp (40 × 50 when selected), its tip at the bottom centre. [count]
/// above 1 adds the badge of a group of cemeteries that would cover each other (D8).
class CandlePin extends StatelessWidget {
  const CandlePin({super.key, this.look = PinLook.normal, this.count = 1});

  final PinLook look;
  final int count;

  static const Size normalSize = Size(32, 40);
  static const Size selectedSize = Size(40, 50);

  Size get size => look == PinLook.normal ? normalSize : selectedSize;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: CustomPaint(
      painter: _PinPainter(
        look: look,
        count: count,
        textScaler: MediaQuery.textScalerOf(context),
      ),
    ),
  );
}

class _PinPainter extends CustomPainter {
  const _PinPainter({
    required this.look,
    required this.count,
    required this.textScaler,
  });

  final PinLook look;
  final int count;

  /// The number grows with the system text size (style-b.md rule 13: a badge digit ≥ 11 sp).
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in a 32 × 40 grid, scaled to the widget.
    canvas.scale(size.width / 32, size.height / 40);
    final Path pin = Path()
      ..moveTo(16, 1)
      ..cubicTo(8.3, 1, 2, 7.1, 2, 14.6)
      ..cubicTo(2, 24.2, 13.6, 36.9, 15.1, 38.5)
      ..arcToPoint(
        const Offset(16.9, 38.5),
        radius: const Radius.circular(1.2),
        clockwise: false,
      )
      ..cubicTo(18.4, 36.9, 30, 24.2, 30, 14.6)
      ..cubicTo(30, 7.1, 23.7, 1, 16, 1)
      ..close();
    if (look == PinLook.selected) {
      canvas.drawPath(
        pin,
        Paint()
          ..color = GrobingColors.amber.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
      );
    }
    final bool outlined = look == PinLook.outlined;
    canvas.drawPath(
      pin,
      Paint()
        ..color = outlined ? GrobingColors.surface : GrobingColors.amber
        ..style = PaintingStyle.fill,
    );
    if (outlined) {
      canvas.drawPath(
        pin,
        Paint()
          ..color = GrobingColors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // The candle inside, 0.78 of the 24-grid, centred in the round part of the pin.
    canvas.save();
    canvas.translate(6.6, 4.2);
    canvas.scale(0.78);
    canvas.drawPath(
      _candlePath(),
      Paint()
        ..color = outlined ? GrobingColors.amber : GrobingColors.background
        ..style = outlined ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    if (count > 1) {
      const Offset c = Offset(26.5, 6.5);
      const double r = 8.5;
      canvas.drawCircle(c, r, Paint()..color = GrobingColors.surface);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = GrobingColors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: count > 9 ? '9+' : '$count',
          style: const TextStyle(
            color: GrobingColors.text,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.look != look || old.count != count || old.textScaler != textScaler;
}
