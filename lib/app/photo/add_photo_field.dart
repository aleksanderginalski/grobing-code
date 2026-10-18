import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';

/// The place of a missing photo as one button — an outline, the icon in amber, the caption — never a
/// placeholder picture (style-b.md rules 11, 14). The gravestone's field (05_DESIGN/grob.md D12: the full
/// width, at least 120 dp) and the cemetery's in its sheet (05_DESIGN/cmentarze.md element 6a: 96 × 80 dp,
/// the caption 12 sp semi-bold) — ISSUE-023.
class AddPhotoField extends StatelessWidget {
  const AddPhotoField({
    super.key,
    required this.label,
    required this.onTap,
    this.width,
    this.height = 120,
    this.iconSize = 32,
    this.captionStyle = const TextStyle(
      color: GrobingColors.text,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    this.radius = 16,
    this.padding = const EdgeInsets.all(16),
  });

  /// The caption, and the button's name for a screen reader.
  final String label;
  final VoidCallback onTap;

  /// Null: the width it is given.
  final double? width;

  /// The least height: the field grows with a large system font rather than cut its caption.
  final double height;
  final double iconSize;
  final TextStyle captionStyle;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Semantics(
    // Its own node: in the cemetery's sheet nothing between it and the sheet starts one, so without this
    // its label and tap merge into the whole sheet (seen with uiautomator, ISSUE-023).
    container: true,
    button: true,
    label: label,
    // excludeSemantics drops the InkWell's tap too: without its own the button is only read, never pressed
    // by Switch Access or Voice Access (WCAG 2.2 SC 4.1.2; the pattern of ISSUE-017, ISSUE-021).
    onTap: onTap,
    excludeSemantics: true,
    child: SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: GrobingColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GrobingIcon(
                    Glyphs.addPhotoAlternate,
                    size: iconSize,
                    color: GrobingColors.amber,
                    applyTextScaling: false,
                  ),
                  SizedBox(height: iconSize / 4),
                  Text(label, textAlign: TextAlign.center, style: captionStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
