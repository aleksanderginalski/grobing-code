import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import '../widgets/candle.dart';
import 'pin_groups.dart';
import 'poland_map_data.dart';

/// A candle to draw on the map: a cemetery id and its point.
typedef MapPin = ({int id, LatLng point, String name});

/// How far in the map may zoom past the whole of Poland: 2⁶ = 64×, about a town. The outline is
/// Natural Earth 1:10m, so closer there would be nothing to see.
const double maxZoomIn = 6;

/// The map of Poland drawn from bundled data, no tile layer (ISSUE-014, ADR-007; style-b.md rule 13):
/// land in the surface colour, the border in the outline colour, rivers as decoration, nine cities,
/// and the family's cemeteries as candles — grouped when they would cover each other.
class PolandMap extends StatelessWidget {
  const PolandMap({
    super.key,
    required this.data,
    required this.controller,
    this.pins = const [],
    this.selected = const {},
    this.onPins,
    this.onMapTap,
    this.placed,
    this.placedLook = PinLook.selected,
    this.focus,
    this.fitPadding = const EdgeInsets.all(16),
  });

  final PolandMapData data;
  final MapController controller;
  final List<MapPin> pins;

  /// The ids of the selected candle (one cemetery, or a group).
  final Set<int> selected;

  /// Null: the candles are shown but not tappable (pick mode, 05_DESIGN/cmentarze.md element 16).
  final void Function(List<int> ids)? onPins;
  final void Function(LatLng point)? onMapTap;

  /// Pick mode: the candle set by a tap. The preview of a cemetery from the database: its candle.
  final LatLng? placed;

  /// How [placed] looks: selected in pick mode, outlined in the preview — a cemetery not added yet
  /// (style-b.md rule 13; 05_DESIGN/cmentarze.md D19).
  final PinLook placedLook;

  /// Start zoomed in on this point, [focusZoomIn] steps past the whole of Poland, instead of the whole
  /// of Poland (the preview, element 14).
  final LatLng? focus;

  /// 2^1.5 ≈ 2.8× the whole of Poland, about 240 km across: one of the nine cities is in the frame for
  /// 96% of the cemeteries in the database, so the map says where in Poland the cemetery is. At 2³
  /// (84 km) it was 29% — a lone candle on plain land (ui review, measured on the extract).
  static const double focusZoomIn = 1.5;

  /// Margins of the whole of Poland at the least zoom. The home screen keeps the sheet's height free
  /// at the bottom, so Poland stands under the search, above the sheet (ui review, 2026-10-06).
  final EdgeInsets fitPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final double minZoom = fitZoom(
        data.bounds,
        constraints.biggest,
        padding: fitPadding,
      );
      final Widget pinLayer = _PinLayer(
        pins: pins,
        selected: selected,
        onPins: onPins,
      );
      return FlutterMap(
        mapController: controller,
        options: MapOptions(
          backgroundColor: GrobingColors.background,
          // With a MapController, flutter_map checks the constraint against a camera built from these
          // before it applies the fit; its defaults (50.5° N, 30.5° E — Kyiv) are outside Poland and
          // fail that check (seen on the emulator, ISSUE-014).
          initialCenter: focus ?? data.bounds.center,
          initialZoom: focus == null ? minZoom : minZoom + focusZoomIn,
          initialCameraFit: focus != null
              ? null
              : CameraFit.bounds(bounds: data.bounds, padding: fitPadding),
          minZoom: minZoom,
          maxZoom: minZoom + maxZoomIn,
          // Not `contain`: on a portrait screen showing the whole width of Poland the view is taller
          // than Poland, so "every edge inside" cannot hold and nothing is drawn (measured, ISSUE-014
          // → Falsifier). The centre stays inside Poland instead.
          cameraConstraint: CameraConstraint.containCenter(bounds: data.bounds),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: onMapTap == null ? null : (_, point) => onMapTap!(point),
        ),
        children: [
          PolygonLayer(
            polygons: [
              Polygon(
                points: data.outline,
                color: GrobingColors.surface,
                borderColor: GrobingColors.outline,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
          // Decoration (SC 1.4.11 covers only graphics needed to understand the content).
          PolylineLayer(
            polylines: [
              for (final List<LatLng> river in data.rivers)
                Polyline(
                  points: river,
                  color: GrobingColors.outline.withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
            ],
          ),
          IgnorePointer(child: _CityLayer(cities: data.cities)),
          if (onPins == null) IgnorePointer(child: pinLayer) else pinLayer,
          if (placed != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: placed!,
                  width: CandlePin.selectedSize.width,
                  height: CandlePin.selectedSize.height,
                  alignment: Alignment.topCenter,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: CandlePin(look: placedLook),
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );
}

/// The zoom at which [bounds] fit [size] within [padding] — the same fit as the initial camera,
/// computed with flutter_map's own projection. The least zoom: the whole of Poland.
double fitZoom(
  LatLngBounds bounds,
  Size size, {
  EdgeInsets padding = const EdgeInsets.all(16),
}) {
  if (size.isEmpty || !size.isFinite) return 5;
  final MapCamera fitted = CameraFit.bounds(bounds: bounds, padding: padding)
      .fit(
        MapCamera(
          crs: const Epsg3857(),
          center: bounds.center,
          zoom: 5,
          rotation: 0,
          nonRotatedSize: size,
        ),
      );
  return fitted.zoom;
}

/// Which side of its dot a city's name goes (05_DESIGN/cmentarze.md, element 3): left at the eastern
/// border, below where a right-hand label would run into the border.
enum _LabelSide { right, left, below }

const Map<String, _LabelSide> _labelSides = {
  'Białystok': _LabelSide.left,
  'Lublin': _LabelSide.below,
};

/// Room for a label: wide enough for the longest name in a large system font. The dot (4 dp) sits at
/// the city's point, so the box is shifted by its half.
const double _labelWidth = 200;
const double _dotHalf = 2;

class _CityLayer extends StatelessWidget {
  const _CityLayer({required this.cities});

  final List<MapCity> cities;

  static const Widget _dot = SizedBox.square(
    dimension: 4,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: GrobingColors.textMuted,
        shape: BoxShape.circle,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const double x = 1 - _dotHalf / (_labelWidth / 2);
    return MarkerLayer(
      markers: [
        for (final MapCity city in cities)
          switch (_labelSides[city.name] ?? _LabelSide.right) {
            _LabelSide.right => Marker(
              point: city.point,
              width: _labelWidth,
              height: 24,
              alignment: const Alignment(x, 0),
              child: Row(
                children: [
                  _dot,
                  const SizedBox(width: 4),
                  Flexible(child: _HaloLabel(city.name)),
                ],
              ),
            ),
            _LabelSide.left => Marker(
              point: city.point,
              width: _labelWidth,
              height: 24,
              alignment: const Alignment(-x, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(child: _HaloLabel(city.name)),
                  const SizedBox(width: 4),
                  _dot,
                ],
              ),
            ),
            _LabelSide.below => Marker(
              point: city.point,
              width: _labelWidth,
              height: 28,
              alignment: const Alignment(0, 1 - _dotHalf / 14),
              child: Column(children: [_dot, _HaloLabel(city.name)]),
            ),
          },
      ],
    );
  }
}

/// A city name with a halo in the land colour, so the border, the coast and the rivers never cross
/// its letters (style-b.md rule 13, v1.4 — the cartographic standard).
class _HaloLabel extends StatelessWidget {
  const _HaloLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // The halo is drawing, not text: TalkBack reads the name once (seen in the stop #2 check).
      ExcludeSemantics(
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontSize: 13,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = GrobingColors.surface,
          ),
        ),
      ),
      Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
      ),
    ],
  );
}

/// The candles: positions on the screen at the current zoom → groups → one marker each.
class _PinLayer extends StatelessWidget {
  const _PinLayer({required this.pins, required this.selected, this.onPins});

  final List<MapPin> pins;
  final Set<int> selected;
  final void Function(List<int> ids)? onPins;

  @override
  Widget build(BuildContext context) {
    final MapCamera camera = MapCamera.of(context);
    final Map<int, MapPin> byId = {for (final MapPin p in pins) p.id: p};
    final List<PinGroup> groups = groupPins([
      for (final MapPin p in pins)
        (id: p.id, at: camera.latLngToScreenOffset(p.point)),
    ]);
    // The selected candle is drawn last, on top.
    groups.sort(
      (a, b) =>
          (a.ids.any(selected.contains) ? 1 : 0) -
          (b.ids.any(selected.contains) ? 1 : 0),
    );
    return MarkerLayer(
      markers: [
        for (final PinGroup g in groups)
          Marker(
            point: byId[g.ids.first]!.point,
            // ≥ 48 dp target (style-b.md); the pin's tip at the point.
            width: 48,
            height: CandlePin.selectedSize.height,
            alignment: Alignment.topCenter,
            child: Semantics(
              button: onPins != null,
              label: g.ids.length == 1
                  ? byId[g.ids.first]!.name
                  : 'Cmentarze w tym miejscu: ${g.ids.length}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPins == null ? null : () => onPins!(g.ids),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: CandlePin(
                    look: g.ids.any(selected.contains)
                        ? PinLook.selected
                        : PinLook.normal,
                    count: g.ids.length,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
