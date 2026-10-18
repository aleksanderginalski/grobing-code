import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'cemetery_plan_map.dart' show MapLayer;

// What sits on the cemetery's map in every mode (05_DESIGN/cmentarz.md, elements 3, 6, 7, 13, 16, 17): the
// badges and the switch Plan · Zdjęcie, the bottom panel with its handle, "no internet" for the photo. One
// place for the cemetery screen and the sectors' mode (ISSUE-028), so both look and behave the same.

/// A bottom panel on the surface: rounded top, over the map (elements 6, 7).
class MapPanel extends StatelessWidget {
  const MapPanel({
    super.key,
    required this.children,
    this.onDragUp,
    this.onDragDown,
    this.overSystemBar = false,
  });

  final List<Widget> children;
  final VoidCallback? onDragUp;
  final VoidCallback? onDragDown;

  /// At the screen's bottom edge without the tab bar (the sectors' mode): the panel reaches the edge and
  /// keeps its content above the system's gesture bar.
  final bool overSystemBar;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragEnd: (d) {
      final double v = d.primaryVelocity ?? 0;
      if (v < 0) onDragUp?.call();
      if (v > 0) onDragDown?.call();
    },
    child: Material(
      color: GrobingColors.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + (overSystemBar ? MediaQuery.viewPaddingOf(context).bottom : 0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// The handle's look: 32 × 4 dp in the outline colour.
class PanelHandle extends StatelessWidget {
  const PanelHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      decoration: BoxDecoration(
        color: GrobingColors.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// A handle that works with one tap — dragging has another way (D21; WCAG 2.2 SC 2.5.7): a 48 dp target
/// around the visible handle, a button for a screen reader.
class TapHandle extends StatelessWidget {
  const TapHandle({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(width: 96, height: 48, child: PanelHandle()),
        ),
      ),
    ),
  );
}

/// Elements 3 and its labels: "Plan offline" (or the photo's state) on the left, the switch Plan · Zdjęcie
/// on the right, the source under them. When both do not fit in a row — a large system text — "Plan
/// offline" moves under the switch, on the left (D22): badges are controls, so they grow in full.
class MapBadges extends StatelessWidget {
  const MapBadges({
    super.key,
    required this.planShown,
    required this.photo,
    required this.photoOnline,
    required this.withSwitch,
    required this.onLayer,
    this.hereStatus,
  });

  final bool planShown;
  final bool photo;
  final bool? photoOnline;
  final bool withSwitch;
  final void Function(MapLayer layer) onLayer;

  /// Element 10a: the location's state, on the right under the switch (ISSUE-029).
  final Widget? hereStatus;

  @override
  Widget build(BuildContext context) {
    final Widget? state = planShown
        ? const MapBadge(
            icon: Glyphs.offlinePin,
            iconColor: GrobingColors.stateOk,
            text: 'Plan offline',
          )
        : photo
        ? MapBadge(
            icon: photoOnline == false ? Glyphs.wifiOff : Glyphs.wifi,
            iconColor: GrobingColors.textMuted,
            text: photoOnline == false ? 'bez internetu' : 'tylko z internetem',
          )
        : null;
    final Widget? toggle = withSwitch
        ? LayerSwitch(photo: photo, onLayer: onLayer)
        : null;
    // The source of the map as a small badge on the surface, on the plan as on the photo: no path crosses
    // its letters (rule 13), nothing but badges on the photo (rule 14) — ui review, ISSUE-027.
    final Widget? source = planShown
        ? const MapBadge(text: '© OpenStreetMap', small: true)
        : photo && photoOnline != false
        ? const MapBadge(text: 'Ortofotomapa: GUGiK', small: true)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final TextScaler scaler = MediaQuery.textScalerOf(context);
        double width(String text, double size, double extra) {
          final TextPainter p = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(fontSize: size),
            ),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final double w = p.width + extra;
          p.dispose();
          return w;
        }

        final bool oneRow =
            state == null ||
            toggle == null ||
            width('tylko z internetem', 13, 8 + 18 + 6 + 12) +
                    8 +
                    width('Zdjęcie', 13, 2 * (10 + 18 + 4 + 10)) +
                    width('Plan', 13, 0) <=
                constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (oneRow)
              Row(children: [?state, const Spacer(), ?toggle])
            else ...[
              // Still too wide for the screen (a narrow phone, a wide font): smaller, never off the edge.
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: toggle,
                ),
              ),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: state),
            ],
            if (hereStatus != null) ...[
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: hereStatus),
            ],
            if (source != null) ...[
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: source),
            ],
          ],
        );
      },
    );
  }
}

class MapBadge extends StatelessWidget {
  const MapBadge({
    super.key,
    required this.text,
    this.icon,
    this.iconColor = GrobingColors.textMuted,
    this.small = false,
  });

  final Glyph? icon;
  final Color iconColor;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Material(
    color: GrobingColors.surface,
    elevation: 2,
    shape: const StadiumBorder(),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: small ? 22 : 32),
      child: Padding(
        padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              GrobingIcon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: small ? GrobingColors.textMuted : GrobingColors.text,
                  fontSize: small ? 11 : 13,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The switch Plan · Zdjęcie: a 32 dp pill, each half a 48 dp target; the active half in amber with the
/// text in the background colour, "wybrany" for a screen reader (SC 1.4.1).
class LayerSwitch extends StatelessWidget {
  const LayerSwitch({super.key, required this.photo, required this.onLayer});

  final bool photo;
  final void Function(MapLayer layer) onLayer;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _half(MapLayer.plan, Glyphs.map, 'Plan', !photo, left: true),
      _half(MapLayer.photo, Glyphs.satelliteAlt, 'Zdjęcie', photo, left: false),
    ],
  );

  Widget _half(
    MapLayer layer,
    Glyph icon,
    String text,
    bool active, {
    required bool left,
  }) {
    final Color fg = active ? GrobingColors.background : GrobingColors.text;
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: text,
      onTap: () => onLayer(layer),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onLayer(layer),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Material(
              color: active ? GrobingColors.amber : GrobingColors.surface,
              elevation: 2,
              borderRadius: BorderRadius.horizontal(
                left: left ? const Radius.circular(16) : Radius.zero,
                right: left ? Radius.zero : const Radius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GrobingIcon(icon, size: 18, color: fg),
                      const SizedBox(width: 4),
                      Text(
                        text,
                        style: TextStyle(
                          color: fg,
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill on the map (elements 11 and 15 — "Popraw pinezkę", "Kwatery"): 40 dp high on the surface, the icon
/// in amber; the whole 48 dp box takes the touch, not only the pill (ui review, ISSUE-028: 39 dp measured),
/// and a screen reader hears a button.
class MapPill extends StatelessWidget {
  const MapPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Glyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          child: Material(
            color: GrobingColors.surface,
            elevation: 2,
            shape: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GrobingIcon(icon, size: 18, color: GrobingColors.amber),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: GrobingColors.text,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// What "gdzie jestem" shows (element 10, D31).
enum HereButtonState {
  /// Location off — `my_location` in the text colour.
  off,

  /// On, the map at the dot — `my_location` in the dot's colour; a tap switches off.
  atDot,

  /// On, the map moved away — `location_searching` in the dot's colour; a tap returns to the dot.
  away,
}

/// Element 10: "Gdzie jestem" — a round 48 dp button on the surface, its state for a screen reader too.
/// [label] is the tooltip and what a screen reader says before the state ("Gdzie jestem"; in mode D "Pinezka
/// w Twojej pozycji").
class HereButton extends StatelessWidget {
  const HereButton({
    super.key,
    required this.state,
    required this.onTap,
    this.label = 'Gdzie jestem',
    this.accuracyM,
  });

  final HereButtonState state;
  final VoidCallback onTap;
  final String label;
  final double? accuracyM;

  @override
  Widget build(BuildContext context) {
    final bool on = state != HereButtonState.off;
    final String said = !on
        ? '$label, wyłączone'
        : accuracyM == null
        ? '$label, włączone'
        : '$label, włączone, ±${accuracyM!.round()} m';
    return Semantics(
      container: true,
      button: true,
      label: said,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: GrobingColors.surface,
          elevation: 2,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: GrobingIcon(
                state == HereButtonState.away
                    ? Glyphs.locationSearching
                    : Glyphs.myLocation,
                size: 24,
                color: on ? GrobingColors.here : GrobingColors.text,
                applyTextScaling: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Element 10a: the location's state when the dot cannot be shown or trusted — "poza cmentarzem · 2,5 km",
/// "Szukam pozycji…", "tylko przybliżona lokalizacja" — on the surface, 13 sp, the icon in the dot's colour.
class HereStatus extends StatelessWidget {
  const HereStatus({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: MapBadge(
      icon: Glyphs.myLocation,
      iconColor: GrobingColors.here,
      text: text,
    ),
  );
}

/// Element 13: the photo needs the internet; the plan works without it.
class NoInternetForPhoto extends StatelessWidget {
  const NoInternetForPhoto({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GrobingIcon(
            Glyphs.wifiOff,
            size: 32,
            color: GrobingColors.textMuted,
            applyTextScaling: false,
          ),
          const SizedBox(height: 12),
          const Text(
            'Zdjęcie z góry potrzebuje internetu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GrobingColors.text, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Plan działa bez niego.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GrobingColors.text, fontSize: 14),
          ),
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
            onPressed: onBack,
            child: const Text('Wróć do planu'),
          ),
        ],
      ),
    ),
  );
}
