import 'package:flutter/material.dart';

import '../theme.dart';

// The two forms of action on style B screens (style-b.md rule 1). Local styles rather than the theme,
// so the technical screens ("Stan danych" and the backup ones) keep their look.

/// The main action — at most one filled button on a screen: amber, rounded rectangle, ≥ 52 dp.
final ButtonStyle primaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: GrobingColors.amber,
  foregroundColor: GrobingColors.background,
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
);

/// A secondary action: outlined, text in the text colour, the icon in amber.
final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: GrobingColors.text,
  iconColor: GrobingColors.amber,
  side: const BorderSide(color: GrobingColors.outline),
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
);
