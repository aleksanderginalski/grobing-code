import 'dart:math' as math;

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

/// The map of Poland drawn from bundled data, no tile layer (ISSUE-014, ADR-007; style-b.md rule 13), like
/// R1 since ISSUE-023 (05_DESIGN/cmentarze.md element 3, D29): the neighbours in the background colour with
/// their borders as decoration, the sea and the lakes in the water colour, Poland's land in the surface
/// colour with its border in the muted text colour, rivers in the water line colour, "Polska", eleven cities,
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
    this.onPointerDown,
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

  /// 2^1.5 ≈ 2.8× the whole of Poland, about 240 km across: one of the nine cities (measured before
  /// ISSUE-023 added Bydgoszcz and Katowice) is in the frame for
  /// 96% of the cemeteries in the database, so the map says where in Poland the cemetery is. At 2³
  /// (84 km) it was 29% — a lone candle on plain land (ui review, measured on the extract).
  static const double focusZoomIn = 1.5;

  /// Margins of the whole of Poland at the least zoom. The home screen splits a sheet's height between
  /// the top and the bottom: the zoom leaves room for the sheet, and Poland stands in the middle until one
  /// opens (05_DESIGN/cmentarze.md D30).
  final EdgeInsets fitPadding;

  /// A finger on the map — the home screen stops its own movement of the map then.
  final VoidCallback? onPointerDown;

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
          onPointerDown: onPointerDown == null
              ? null
              : (_, _) => onPointerDown!(),
        ),
        children: [
          // Beyond the data the background shows: the neighbours' colour, so a gap between their simplified
          // shapes and Poland's full outline never shows.
          // Islands are holes cut with the even-odd rule: flutter_map's default `Path.combine` redid a path
          // operation on the whole sea every frame — 2–3 s a frame (measured, ISSUE-023 qa). The islands never
          // cross each other, so even-odd draws the same.
          PolygonLayer(
            polygons: _areas(data.water),
            painterFillMethod: PolygonPainterFillMethod.evenOdd,
          ),
          PolygonLayer(
            polygons: [
              Polygon(points: data.outline, color: GrobingColors.surface),
            ],
          ),
          PolygonLayer(
            polygons: _areas(data.lakes),
            painterFillMethod: PolygonPainterFillMethod.evenOdd,
          ),
          // Decoration (SC 1.4.11 covers only graphics needed to understand the content).
          PolylineLayer(
            polylines: [
              for (final List<LatLng> river in data.rivers)
                Polyline(
                  points: river,
                  color: GrobingColors.waterLine,
                  strokeWidth: 1,
                ),
              for (final List<LatLng> border in data.borders)
                Polyline(
                  points: border,
                  color: GrobingColors.outline.withValues(alpha: 0.45),
                  strokeWidth: 0.7,
                ),
            ],
          ),
          // Poland's border carries where the candles are (SC 1.4.11): in the muted text colour, because the
          // outline colour has only 3.11:1 on the water (style-b.md rule 13). On top, so a lake at the border
          // does not cut it.
          PolylineLayer(
            polylines: [
              Polyline(
                points: [...data.outline, data.outline.first],
                color: GrobingColors.textMuted,
                strokeWidth: 1.4,
              ),
            ],
          ),
          const IgnorePointer(child: _CountryLabel()),
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

/// The sea or the lakes as polygons in the water colour, islands as holes.
List<Polygon> _areas(List<MapArea> areas) => [
  for (final MapArea a in areas)
    Polygon(
      points: a.outer,
      holePointsList: a.holes.isEmpty ? null : a.holes,
      color: GrobingColors.water,
    ),
];

/// Where "Polska" stands: free land in the north, in Masuria, between the labels of Gdańsk, Bydgoszcz,
/// Warszawa and Białystok (05_DESIGN/cmentarze.md, element 3).
const LatLng _countryLabelAt = LatLng(53.85, 21.0);

/// Past this many zoom steps beyond the whole of Poland the country's name is gone: it names the whole,
/// and closer in it would only lie over a region (the cartographic standard — the country's label belongs
/// to the least zooms).
const double _countryLabelUntil = 2;

/// "Polska": 22 sp, semi-bold, letter spacing 2, the muted text colour at 85% (style-b.md rule 13). It grows
/// with the system text size only up to [_labelMaxScale], as the cities: larger it would cover them, and it
/// names what the outline already shows.
class _CountryLabel extends StatelessWidget {
  const _CountryLabel();

  @override
  Widget build(BuildContext context) {
    final MapCamera camera = MapCamera.of(context);
    final double least = camera.minZoom ?? camera.zoom;
    if (camera.zoom > least + _countryLabelUntil) {
      return const SizedBox.shrink();
    }
    return MarkerLayer(
      markers: [
        Marker(
          point: _countryLabelAt,
          width: 240,
          height: 48,
          child: Center(
            child: Text(
              'Polska',
              maxLines: 1,
              softWrap: false,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: _labelMaxScale),
              style: TextStyle(
                color: GrobingColors.textMuted.withValues(alpha: 0.85),
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which side of its dot a city's name goes (05_DESIGN/cmentarze.md, element 3, D32): left at Katowice,
/// whose right-hand label would run into Kraków's dot; below at the eastern border — Lublin, and Białystok,
/// whose left-hand label stood a space from Bydgoszcz's in one line and read as one name (360 dp, text
/// 200%; ui review, ISSUE-023).
enum _LabelSide { right, left, below }

const Map<String, _LabelSide> _labelSides = {
  'Białystok': _LabelSide.below,
  'Katowice': _LabelSide.left,
  'Lublin': _LabelSide.below,
};

/// Room for a label: wide enough for the longest name in a large system font. The dot (4 dp) sits at
/// the city's point, so the box is shifted by its half.
const double _labelWidth = 200;
const double _dotHalf = 2;

/// Map labels — the cities and "Polska" — grow with the system text size up to 1.3×. Larger they would
/// run into each other (Bydgoszcz into Białystok at 200%, ISSUE-023) and cover the map they name; at 1.3×
/// a city label is 17 sp.
const double _labelMaxScale = 1.3;

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
    // The box is as tall as the label in the clamped size, so a large system font never cuts its letters.
    final double line = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _labelMaxScale).scale(13 * 1.5);
    final double side = math.max(24, line);
    final double below = 2 * _dotHalf + line;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _labelMaxScale,
      child: MarkerLayer(
        markers: [
          for (final MapCity city in cities)
            switch (_labelSides[city.name] ?? _LabelSide.right) {
              _LabelSide.right => Marker(
                point: city.point,
                width: _labelWidth,
                height: side,
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
                height: side,
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
                height: below,
                alignment: Alignment(0, 1 - _dotHalf / (below / 2)),
                child: Column(children: [_dot, _HaloLabel(city.name)]),
              ),
            },
        ],
      ),
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
