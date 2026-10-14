import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/buttons.dart';

// What presentation mode shows over the tree (05_DESIGN/drzewo.md v1.14, element 11; ISSUE-038): the year in the
// corner (L1 — D39), the bar at the bottom and "Zakończ prezentację" (B2 — D40). The TV gets all of it: the
// system sends the phone's picture (D11, D29).

/// The year of the history, read from the couch (L1 — D39; style-b.md → Thresholds, text for a TV): 36 sp — the
/// TV type scale's display small, "for numerals" — in amber, as the slider's year, on a plate of the background's
/// colour so the lines under it do not cut it (rule 13, D23). It grows with the system text up to 1.3× only: it is
/// large already and stands on the tree. The reader hears the year when it gets there — not with every year of ▶.
class PresentationYear extends StatelessWidget {
  const PresentationYear({super.key, required this.year});

  /// Null: "dziś".
  final int? year;

  /// 48 dp from the left: 5 % of the width, which a TV may cut off (Android TV → Layouts; D38).
  static const double left = 48;
  static const double top = 24;
  static const double fontSize = 36;
  static const double maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) => Semantics(
    label: year == null ? 'dziś' : 'Rok $year',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: GrobingColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          year == null ? 'dziś' : '$year',
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: maxTextScale),
          style: const TextStyle(
            color: GrobingColors.amber,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}

/// The bar at the bottom (B2 — D40): the card's time row in one row, on the surface, rounded 16 dp.
class PresentationBar extends StatelessWidget {
  const PresentationBar({super.key, required this.child});

  /// The [TreeTimeBar] with `oneRow`.
  final Widget child;

  /// From the screen's edges: above the bands that take no touch (D25).
  static const double margin = 24;

  @override
  Widget build(BuildContext context) => Material(
    color: GrobingColors.surface,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: child,
    ),
  );
}

/// Element 11: "Zakończ prezentację" in the top right corner — close in amber, the words in the text colour,
/// the surface with an outline, 48 dp.
class PresentationExit extends StatelessWidget {
  const PresentationExit({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: secondaryButtonStyle.copyWith(
      backgroundColor: const WidgetStatePropertyAll(GrobingColors.surface),
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    ),
    onPressed: onPressed,
    icon: const Icon(Icons.close),
    label: const Text('Zakończ prezentację'),
  );
}
