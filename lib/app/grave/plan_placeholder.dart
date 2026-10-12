import 'package:flutter/material.dart';

import '../theme.dart';

/// Why a cemetery has no plan to show (05_DESIGN/cmentarz.md, element 2a): each reason has its own way
/// forward, so one placeholder for all would say something untrue in three of them (D17).
enum PlanGap {
  /// (a) Being downloaded.
  downloading,

  /// (b) No internet.
  offline,

  /// (c) The servers did not answer.
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
    final (
      IconData? icon,
      String fact,
      String? way,
      String? action,
      VoidCallback? onAction,
    ) = switch (gap) {
      PlanGap.downloading => (
        null,
        'Pobieram plan cmentarza…',
        null,
        null,
        null,
      ),
      PlanGap.offline => (
        Icons.cloud_download_outlined,
        'Plan tego cmentarza pobierze się, gdy będzie internet.',
        hasGraves ? 'Groby są na liście — pasek na dole.' : null,
        'Pobierz teraz',
        onDownload,
      ),
      PlanGap.serverError => (
        Icons.cloud_off_outlined,
        'Nie udało się pobrać planu — serwer map nie odpowiada.',
        hasGraves
            ? 'Spróbuję znowu później. Groby są na liście.'
            : 'Spróbuję znowu później.',
        'Pobierz teraz',
        onDownload,
      ),
      PlanGap.notInOsm => (
        Icons.not_listed_location_outlined,
        'W OpenStreetMap nie ma planu tego cmentarza.',
        'Z internetem zobaczysz go na zdjęciu z góry.',
        onShowPhoto == null ? null : 'Pokaż zdjęcie z góry',
        onShowPhoto,
      ),
      PlanGap.noPoint => (
        Icons.location_off_outlined,
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
          liveRegion: gap == PlanGap.downloading,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == null)
                const SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                Icon(icon, size: 32, color: GrobingColors.textMuted),
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
