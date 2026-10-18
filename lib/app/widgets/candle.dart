import 'package:flutter/material.dart';

import '../theme.dart';
import 'glyphs.dart';
import 'grobing_icon.dart';

/// The candle (znicz) — the app's sign (style-b.md rule 8): one drawing, the author's candle from DALL-E traced into
/// the icon font (ISSUE-046; tool/icons/build_symbols.py) — in two tones ([Glyphs.candle]: the logo, the buttons)
/// or solid with its details cut out ([Glyphs.candleSolid]: inside a pin, the mark of the dead in the tree).
///
/// Next to a button's words it grows with the system text size like the other icons ([applyTextScaling],
/// style-b.md rule 3); the logo and the tree's mark stay.
class CandleIcon extends StatelessWidget {
  const CandleIcon({
    super.key,
    this.size = 24,
    this.color = GrobingColors.amber,
    this.filled = false,
    this.applyTextScaling = false,
  });

  final double size;
  final Color color;
  final bool filled;
  final bool applyTextScaling;

  @override
  Widget build(BuildContext context) => GrobingIcon(
    filled ? Glyphs.candleSolid : Glyphs.candle,
    size: size,
    color: color,
    applyTextScaling: applyTextScaling,
  );
}

/// Paints [glyph] of the icon font with its em square at [origin], [em] wide — for icons inside a painter (the pin).
/// A glyph with a fill paints it at 25% under its lines, as [GrobingIcon] does.
void _paintGlyph(
  Canvas canvas,
  Glyph glyph,
  Offset origin,
  double em,
  Color color,
) {
  void layer(int codePoint, Color c) {
    (TextPainter(
      text: TextSpan(
        text: String.fromCharCode(codePoint),
        style: TextStyle(
          fontFamily: GrobingIcon.fontFamily,
          fontSize: em,
          height: 1,
          color: c,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, origin);
  }

  if (glyph.fill case final int fill) {
    layer(fill, color.withValues(alpha: color.a * GrobingIcon.fillOpacity));
  }
  layer(glyph.codePoint, color);
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
    // The author's candle inside, an em of 18.7 (0.78 of a 24-grid icon) in the round part of the pin: solid in the
    // background's colour on the amber pin, in two tones of amber on a pin not saved yet (the drawing of P-pinezka).
    _paintGlyph(
      canvas,
      outlined ? Glyphs.candle : Glyphs.candleSolid,
      const Offset(6.64, 4.8),
      18.72,
      outlined ? GrobingColors.amber : GrobingColors.background,
    );
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
