import 'package:flutter/widgets.dart';

/// One icon of the app's font (assets/fonts/grobing-symbols.ttf) — the constants are in glyphs.dart.
///
/// Not an [IconData] on purpose: Flutter's icon tree shaker cuts every font an [IconData] points at, and it drops
/// the glyphs some Material Symbols swap to along the FILL axis (group and settings came out blank in the
/// release build; ISSUE-046, probe 2026-10-18). Our font is already cut by tool/icons/build_symbols.py with the
/// layout closure, so the app draws it as text and the shaker never sees it.
///
/// A Material Symbol has one code point: its fill is the same glyph along the FILL axis. An icon traced from the
/// author's sheet (decision 1' of ISSUE-046) has two static glyphs: [codePoint] for its lines and [fill] for its
/// silhouette.
@immutable
class Glyph {
  const Glyph(this.codePoint, {this.fill});

  final int codePoint;
  final int? fill;
}

/// An icon of style B (style-b.md rule 3): Material Symbols Rounded at weight 300, in two tones — the glyph
/// filled at 25% under the same glyph's outline, both in the icon's colour. The outline carries the meaning and
/// the ≥ 3:1 contrast (WCAG 2.2 SC 1.4.11); the fill is decoration.
///
/// Size and colour come from the arguments or the ambient [IconTheme], like [Icon], so buttons, the app bar and
/// selected states keep working. Next to text the icon grows with the system text size ([applyTextScaling], the
/// default); a standalone icon control (an [IconButton], a tab, a round map button) or an icon inside a box of a
/// fixed size passes `applyTextScaling: false`.
class GrobingIcon extends StatelessWidget {
  const GrobingIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.applyTextScaling = true,
  });

  final Glyph? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final bool applyTextScaling;

  static const String fontFamily = 'GrobingSymbols';
  static const double weight = 300;
  static const double fillOpacity = 0.25;

  @override
  Widget build(BuildContext context) {
    final IconThemeData theme = IconTheme.of(context);
    final double base = size ?? theme.size ?? 24;
    final double px = applyTextScaling
        ? MediaQuery.textScalerOf(context).scale(base)
        : base;
    final Glyph? glyph = icon;
    if (glyph == null) {
      return Semantics(
        label: semanticLabel,
        child: SizedBox(width: px, height: px),
      );
    }
    Color ink = color ?? theme.color!;
    final double opacity = theme.opacity ?? 1;
    if (opacity != 1) {
      ink = ink.withValues(alpha: ink.a * opacity);
    }
    final String char = String.fromCharCode(glyph.codePoint);
    final String fillChar = String.fromCharCode(glyph.fill ?? glyph.codePoint);
    final TextDirection direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    // Optical size follows the drawn size (the opsz axis is 20–48), as Material Symbols intends.
    final double opticalSize = px.clamp(20, 48).toDouble();
    TextStyle style(double fill, Color c) => TextStyle(
      inherit: false,
      fontFamily: fontFamily,
      fontSize: px,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
      color: c,
      fontVariations: [
        FontVariation('FILL', fill),
        const FontVariation('wght', weight),
        const FontVariation('GRAD', 0),
        FontVariation('opsz', opticalSize),
      ],
    );
    Widget layer(double fill, Color c) => RichText(
      overflow: TextOverflow.visible,
      textDirection: direction,
      text: TextSpan(text: fill > 0 ? fillChar : char, style: style(fill, c)),
    );
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: px,
          height: px,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              layer(1, ink.withValues(alpha: ink.a * fillOpacity)),
              layer(0, ink),
            ],
          ),
        ),
      ),
    );
  }
}
