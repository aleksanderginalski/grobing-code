import 'package:flutter/material.dart';

/// Style B (PROJECT_BRIEF §6a): near-black background, soft grey text, one accent colour — warm
/// amber like candlelight. The one home of the colour values; roles, rules and contrast measurements
/// live in grobing-vault/05_DESIGN/brand/style-b.md.
abstract final class GrobingColors {
  /// Near-black background. Mirrored in android/app/src/main/res/values/colors.xml
  /// (`grobing_background`) so the native launch screen matches the first Flutter frame.
  static const Color background = Color(0xFF121110);
  static const Color surface = Color(0xFF1C1B19);
  static const Color text = Color(0xFFC9C5BF);
  static const Color textMuted = Color(0xFF8E8A84);
  static const Color amber = Color(0xFFE3A646);

  /// Field frames, outlined buttons, dividers, the border of Poland on the map (rule 13): 3.40:1 on
  /// the background, 3.10:1 on the surface (WCAG 2.2 SC 1.4.11). Never text.
  static const Color outline = Color(0xFF6B6862);

  /// Error message under a field and its frame — always with an icon, never colour alone (SC 1.4.1):
  /// 6.45:1 on the background, 5.89:1 on the surface.
  static const Color error = Color(0xFFE07A6F);

  /// State green (style-b.md → State colours, the proposal of v1.14): something is safe and ready — the
  /// backup in the settings (05_DESIGN/ustawienia.md, element 2), later "Plan offline". Always with an
  /// icon and words, never colour alone (SC 1.4.1): 8.19:1 on the surface.
  static const Color stateOk = Color(0xFF8CC084);

  /// Relation lines in the family tree and the person's mini tree (style-b.md v1.16, roles; first used by
  /// 05_DESIGN/osoba.md element 6): parent–child 8.50:1 and partners 8.16:1 on the background (SC 1.4.11).
  /// The two differ only in hue (1.04:1), so the kind of line is carried by its shape too — a stepped line
  /// down for parent–child, a level one for partners, dashed for "razem" (SC 1.4.1). Never anything but
  /// relation lines.
  static const Color relParentChild = Color(0xFF8FB3C9);
  static const Color relPartners = Color(0xFFD39BB0);

  /// Water on the map of Poland like R1 (style-b.md v1.13, rule 13; 05_DESIGN/cmentarze.md element 3): the
  /// Baltic and the lakes. As bright as the land (1.00:1), so the coast is carried by Poland's border, not by
  /// colour (SC 1.4.1). Decoration — never anything off the map, never a carrier of meaning.
  static const Color water = Color(0xFF101C25);

  /// Rivers on the map, 1 dp (same role as [water]).
  static const Color waterLine = Color(0xFF3A5E74);

  /// "Tu jesteś" — the phone's position on the cemetery's map, the maps' blue dot (style-b.md → State
  /// colours, v1.16; 05_DESIGN/cmentarz.md element 10): 6.99:1 on the background, 6.38:1 on the surface
  /// (SC 1.4.11). The dot, its accuracy circle, the "gdzie jestem" button while it is on and the icon of the
  /// location's state (element 10a) — never the accent's roles, never a warning.
  static const Color here = Color(0xFF5EA2E6);
}

abstract final class GrobingTheme {
  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: GrobingColors.background,
    colorScheme: const ColorScheme.dark(
      primary: GrobingColors.amber,
      onPrimary: GrobingColors.background,
      secondary: GrobingColors.amber,
      onSecondary: GrobingColors.background,
      surface: GrobingColors.surface,
      onSurface: GrobingColors.text,
      onSurfaceVariant: GrobingColors.textMuted,
    ),
  );

  /// Field frames of style B screens (style-b.md → Token roles): the outline carries the edge, because
  /// background and surface differ by ~1.1:1. Applied per screen, not in [dark], so the technical
  /// screens ("Stan danych" and the backup ones) keep their fields.
  static final InputDecorationTheme fields = InputDecorationTheme(
    border: _frame(GrobingColors.outline),
    enabledBorder: _frame(GrobingColors.outline),
    focusedBorder: _frame(GrobingColors.amber, width: 2),
    errorBorder: _frame(GrobingColors.error),
    focusedErrorBorder: _frame(GrobingColors.error, width: 2),
    labelStyle: const TextStyle(color: GrobingColors.textMuted),
    // Amber marks focus only (style-b.md → Token roles): a raised label of a field without focus stays
    // muted, and of a field with an error takes the error colour (ui review, 2026-10-06).
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.error)
            ? GrobingColors.error
            : states.contains(WidgetState.focused)
            ? GrobingColors.amber
            : GrobingColors.textMuted,
      ),
    ),
    hintStyle: const TextStyle(color: GrobingColors.textMuted),
    errorStyle: const TextStyle(color: GrobingColors.error),
  );

  static OutlineInputBorder _frame(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
}
