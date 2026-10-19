import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';

/// A square of a grid of photos with corners of 8 dp — the person's photos (05_DESIGN/zdjecia-osoby.md 4)
/// and "Zdjęcia w aplikacji" (zdjecia-w-aplikacji.md 6).
class PhotoCell extends StatelessWidget {
  const PhotoCell({
    super.key,
    required this.size,
    required this.child,
    this.color,
    this.selected = false,
  });

  final double size;
  final Widget child;
  final Color? color;

  /// The current background in "Zdjęcie w tle" (v1.4), the current profile photo in "Zdjęcie profilowe"
  /// (v1.5) and a ticked photo on "Zdjęcia w aplikacji": a 2 dp frame in amber around the cell, then the
  /// background, the photo smaller inside — as the crop's ring: amber against the background 8.81:1 on
  /// any photo, and the photo's changed outline says it without colour (ui review, MAJOR: drawn on the
  /// photo's edge, amber on a sepia photo was about 1:1).
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: selected
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GrobingColors.amber, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Material(
                color: color ?? Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          )
        : Material(
            color: color ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
  );
}

/// "Brak pliku": the cell without text, the icon in the muted colour.
class UnreadableCell extends StatelessWidget {
  const UnreadableCell({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: GrobingColors.surface,
    child: Center(
      child: GrobingIcon(
        Glyphs.brokenImage,
        color: GrobingColors.textMuted,
        applyTextScaling: false,
      ),
    ),
  );
}
