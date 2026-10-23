import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';

/// Why a cemetery has no plan to show (05_DESIGN/cmentarz.md, element 2a): each reason has its own way
/// forward, so one placeholder for all would say something untrue in three of them (D17).
enum PlanGap {
  /// (a) Being downloaded.
  downloading,

  /// (a) Being downloaded, and the server has been slow long enough to say so (v9, D39).
  downloadingSlowly,

  /// (b) No internet.
  offline,

  /// (c) The server is overloaded; the app tries again by itself, with the app closed too (v9, D40, B1).
  serverError,

  /// (d) OpenStreetMap has no outline around the point.
  notInOsm,

  /// (e) The cemetery has no point.
  noPoint,
}

/// Element 2a: in the place of the plan, in the middle of the free room — an icon, the fact and the way
/// forward, and a text button. Both lines in the text colour: they are read at the cemetery (W2, the author
/// at stop #1 of ISSUE-027; NFR-004). The list of graves works in every case — the bar below.
class PlanPlaceholder extends StatelessWidget {
  const PlanPlaceholder({
    super.key,
    required this.gap,
    this.onDownload,
    this.onShowPhoto,
    this.onPickPoint,
    this.hasGraves = true,
  });

  final PlanGap gap;

  /// Whether the cemetery has graves: without any, "Groby są na liście" would be untrue — the bar below says
  /// there are none (rule 7; ui review, ISSUE-027: a cemetery added without a network usually has none).
  final bool hasGraves;

  /// "Pobierz teraz" — (b) and (c).
  final VoidCallback? onDownload;

  /// "Pokaż zdjęcie z góry" — (d), only with a network; null hides it.
  final VoidCallback? onShowPhoto;

  /// "Wskaż na mapie" — (e).
  final VoidCallback? onPickPoint;

  @override
  Widget build(BuildContext context) {
    // (a) says where the plan will be: in the phone, for the cemetery without coverage (D41).
    const String kept =
        'Plan zostanie w\u00A0telefonie — na cmentarzu zasięg nie będzie potrzebny.';
    final (
      Glyph? icon,
      String fact,
      String? way,
      String? action,
      VoidCallback? onAction,
    ) = switch (gap) {
      PlanGap.downloading => (
        null,
        'Pobieram plan cmentarza…',
        kept,
        null,
        null,
      ),
      // One line in place of [kept], not a third one: at 200% on 360 dp the placeholder has room for about
      // two, and the rest went under the graves' bar (dev pass, ISSUE-052).
      PlanGap.downloadingSlowly => (
        null,
        'Pobieram plan cmentarza…',
        'Serwer map odpowiada dziś wolno. Plan zapisze się sam i\u00A0zostanie '
            'w\u00A0telefonie — możesz zamknąć aplikację.',
        null,
        null,
      ),
      PlanGap.offline => (
        Glyphs.cloudDownload,
        'Plan tego cmentarza pobierze się, gdy będzie internet.',
        hasGraves ? 'Groby są na liście — pasek na dole.' : null,
        'Pobierz teraz',
        onDownload,
      ),
      PlanGap.serverError => (
        Glyphs.cloudOff,
        'Serwer map jest teraz przeciążony.',
        hasGraves
            ? 'Spróbuję sam, także gdy zamkniesz aplikację. Groby są na liście.'
            : 'Spróbuję sam, także gdy zamkniesz aplikację.',
        'Pobierz teraz',
        onDownload,
      ),
      PlanGap.notInOsm => (
        Glyphs.notListedLocation,
        'W OpenStreetMap nie ma planu tego cmentarza.',
        'Z internetem zobaczysz go na zdjęciu z góry.',
        onShowPhoto == null ? null : 'Pokaż zdjęcie z góry',
        onShowPhoto,
      ),
      PlanGap.noPoint => (
        Glyphs.locationOff,
        'Plan pobierze się, gdy wskażesz cmentarz na mapie.',
        null,
        'Wskaż na mapie',
        onPickPoint,
      ),
    };
    const TextStyle line = TextStyle(color: GrobingColors.text, fontSize: 14);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Semantics(
          liveRegion:
              gap == PlanGap.downloading || gap == PlanGap.downloadingSlowly,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == null)
                const SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                GrobingIcon(
                  icon,
                  size: 32,
                  color: GrobingColors.textMuted,
                  applyTextScaling: false,
                ),
              const SizedBox(height: 12),
              Text(fact, textAlign: TextAlign.center, style: line),
              if (way != null) ...[
                const SizedBox(height: 4),
                Text(way, textAlign: TextAlign.center, style: line),
              ],
              if (action != null && onAction != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: GrobingColors.amber,
                    minimumSize: const Size(48, 48),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(action),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
