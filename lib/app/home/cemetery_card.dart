import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../../data/database.dart' show PlanStatus;
import '../polish.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'cemetery_base.dart';

/// "Miejscowość · 3 groby · 6 osób", and "· bez punktu na mapie" when it has no candle — or, with a
/// point, "· bez planu" / "· bez planu w OSM" while no plan is stored, so the list before a trip shows what
/// is left (05_DESIGN/cmentarze.md, elements 9 and 11, D37; style-b.md rules 6 and 7). The sheet of a group
/// ([withState] false) names the cemeteries only.
String cemeteryLine(CemeterySummary c, {bool withState = true}) => [
  if (c.locality != null) c.locality!,
  gravesLabel(c.graveCount),
  peopleLabel(c.personCount),
  if (withState && c.point == null) 'bez punktu na mapie',
  if (withState && c.point != null && c.plan == null) 'bez planu',
  if (withState && c.point != null && c.plan == PlanStatus.notInOsm)
    'bez planu w OSM',
].join(' ·\u00A0');

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
                    cemeteryLine(cemetery, withState: !inSheet),
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const GrobingIcon(
              Glyphs.chevronRight,
              color: GrobingColors.textMuted,
            ),
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
/// the muted colour — then "Miejscowość (dzielnica) · przy: Okolica · woj. … · wyznanie". One you already
/// have shows "Dodany" instead of the chevron, so it is not added twice (D17).
class BaseCemeteryCard extends StatelessWidget {
  const BaseCemeteryCard({
    super.key,
    required this.cemetery,
    this.through,
    required this.added,
    required this.onTap,
  });

  final BaseCemetery cemetery;

  /// The nearby place the search found it through — "· przy: …" (D35, [foundThrough]); null: the card's
  /// own name and place hold every word.
  final String? through;
  final bool added;
  final VoidCallback onTap;

  static const TextStyle _placeStyle = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 14,
  );

  /// "przy: Nazwa": the hard space after "przy:" always, and between the words of the name when the whole
  /// "· przy: Nazwa" fits in the line — a name split over two lines reads as two places; one longer than the
  /// line keeps its plain spaces, so it breaks between words, never inside one (ui review, cmentarze.md D38).
  static String _throughPart(BuildContext context, String place, double width) {
    final String joined = 'przy:\u00A0${place.replaceAll(' ', '\u00A0')}';
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: '·\u00A0$joined',
        style: DefaultTextStyle.of(context).style.merge(_placeStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final bool fits = painter.width <= width;
    painter.dispose();
    return fits ? joined : 'przy:\u00A0$place';
  }

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
                      LayoutBuilder(
                        builder: (context, constraints) => Text(
                          joinPlaceLine([
                            cemetery.place,
                            if (through case final String place?)
                              _throughPart(
                                context,
                                place,
                                constraints.maxWidth,
                              ),
                            'woj.\u00A0${cemetery.voivodeship}',
                            ?cemetery.kind,
                          ]),
                          style: _placeStyle,
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
                  const GrobingIcon(
                    Glyphs.chevronRight,
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
