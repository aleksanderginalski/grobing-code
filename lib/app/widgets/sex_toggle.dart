import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../theme.dart';

/// Element 4a of the person form (05_DESIGN/wpis-osoby.md v5.6), also in the family wizard's new person
/// (rodzina.md C1'): ♀ and ♂ beside "Imiona". One or none — a touch on the chosen one takes it away (sex
/// not known). The chosen one has the surface, a 2 dp frame and the icon in amber, so the choice is never
/// the colour alone (SC 1.4.1); the screen reader hears "Kobieta" or "Mężczyzna" and the checked state.
/// Outside the `next` order, as the date's qualifier: a suggestion that is right costs nothing.
class SexToggle extends StatelessWidget {
  const SexToggle({super.key, required this.value, required this.onChanged});

  final Sex? value;
  final ValueChanged<Sex?> onChanged;

  static const Map<Sex, String> labels = {
    Sex.female: 'Kobieta',
    Sex.male: 'Mężczyzna',
  };

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    descendantsAreTraversable: false,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Sex.female, Icons.female_outlined),
        const SizedBox(width: 6),
        _button(Sex.male, Icons.male_outlined),
      ],
    ),
  );

  Widget _button(Sex sex, IconData icon) {
    final bool chosen = value == sex;
    void toggle() => onChanged(chosen ? null : sex);
    return Semantics(
      button: true,
      checked: chosen,
      inMutuallyExclusiveGroup: true,
      label: labels[sex],
      // The action stays with the merged node, so Switch Access and Voice Access can press it (ISSUE-021).
      onTap: toggle,
      excludeSemantics: true,
      child: Tooltip(
        message: labels[sex]!,
        child: Material(
          color: chosen ? GrobingColors.surface : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: chosen ? GrobingColors.amber : GrobingColors.outline,
              width: chosen ? 2 : 1,
            ),
          ),
          child: InkWell(
            canRequestFocus: false,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: toggle,
            child: SizedBox(
              width: 48,
              height: 56,
              child: Icon(
                icon,
                color: chosen ? GrobingColors.amber : GrobingColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
