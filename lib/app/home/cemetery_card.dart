import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../polish.dart';
import '../theme.dart';
import 'cemetery_base.dart';

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

/// A cemetery from the database (05_DESIGN/cmentarze.md, element 12): name — or "Cmentarz bez nazwy" in
/// the muted colour — then "Miejscowość (dzielnica) · woj. … · wyznanie". One you already have shows
/// "Dodany" instead of the chevron, so it is not added twice (D17).
class BaseCemeteryCard extends StatelessWidget {
  const BaseCemeteryCard({
    super.key,
    required this.cemetery,
    required this.added,
    required this.onTap,
  });

  final BaseCemetery cemetery;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: GrobingColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shownName(cemetery),
                        style: TextStyle(
                          color: cemetery.name.isEmpty
                              ? GrobingColors.textMuted
                              : GrobingColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        joinPlaceLine([
                          cemetery.place,
                          'woj. ${cemetery.voivodeship}',
                          ?cemetery.kind,
                        ]),
                        style: const TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (added)
                  // The chevron's glyph has its own margin; the word lines up with it.
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Text(
                      'Dodany',
                      style: TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: GrobingColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
