import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../polish.dart';
import '../theme.dart';

/// "Miejscowość · 3 groby · 6 osób", and "· bez punktu na mapie" when it has no candle
/// (05_DESIGN/cmentarze.md, elements 9 and 11; style-b.md rules 6 and 7).
String cemeteryLine(CemeterySummary c, {bool withPoint = true}) => [
  if (c.locality != null) c.locality!,
  gravesLabel(c.graveCount),
  peopleLabel(c.personCount),
  if (withPoint && c.point == null) 'bez punktu na mapie',
].join(' · ');

/// A cemetery that leads further: a card on the surface with a chevron (style-b.md rule 11), or — in a
/// sheet, which already is the surface — a row without its own background.
class CemeteryCard extends StatelessWidget {
  const CemeteryCard({
    super.key,
    required this.cemetery,
    required this.onTap,
    this.inSheet = false,
  });

  final CemeterySummary cemetery;
  final VoidCallback onTap;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: EdgeInsets.fromLTRB(inSheet ? 0 : 16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cemetery.name,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cemeteryLine(cemetery, withPoint: !inSheet),
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: GrobingColors.textMuted),
          ],
        ),
      ),
    );
    if (inSheet) return InkWell(onTap: onTap, child: content);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: GrobingColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
