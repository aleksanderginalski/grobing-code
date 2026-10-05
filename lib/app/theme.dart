import 'package:flutter/material.dart';

/// Style B (PROJECT_BRIEF §6a): near-black background, soft grey text, one accent colour — warm
/// amber like candlelight. Base tokens only; the visual guidelines are NT-006.
abstract final class GrobingColors {
  /// Near-black background. Mirrored in android/app/src/main/res/values/colors.xml
  /// (`grobing_background`) so the native launch screen matches the first Flutter frame.
  static const Color background = Color(0xFF121110);
  static const Color surface = Color(0xFF1C1B19);
  static const Color text = Color(0xFFC9C5BF);
  static const Color textMuted = Color(0xFF8E8A84);
  static const Color amber = Color(0xFFE3A646);
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
}
