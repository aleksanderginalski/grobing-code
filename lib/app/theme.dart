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
