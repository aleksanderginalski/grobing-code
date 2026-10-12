import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/cemeteries.dart';
import '../../data/cemetery_plans.dart';
import '../../data/database.dart' show PlanStatus;
import '../../net/hosts.dart';
import '../home/poland_map.dart' show fitZoom;
import '../theme.dart';
import '../widgets/candle.dart';
import 'sector_geometry.dart';

/// What the map shows under the candles (05_DESIGN/cmentarz.md, element 3).
enum MapLayer { plan, photo }

/// A grave's candle on the cemetery's map: its id, point and what a screen reader says.
typedef GraveCandle = ({int id, LatLng point, String label});

/// One of the author's sectors with a zone (05_DESIGN/cmentarz.md v6, element 4): its id, name — without
/// "Kwatera" in front — and ring.
typedef MapSector = ({int id, String name, List<LatLng> zone});

/// A zone being marked (element 18): its corners in order, and the name its label says from three corners on.
typedef MapDrawing = ({List<LatLng> corners, String name});

/// The phone's position on the map (05_DESIGN/cmentarz.md v7, element 10): the point, the accuracy in metres
/// at the 68th percentile when the phone gave one, and whether the "tu jesteś · ±5 m" label is drawn — not in
/// mode D, whose panel says the accuracy (element 12).
typedef MapHere = ({LatLng point, double? accuracyM, bool label});

/// The deepest zoom of the cemetery's map: the photo's last level (ADR-003 pkt 2), and the plan follows it,
/// so switching layers never jumps.
const double cemeteryMaxZoom = 19;

/// The zoom of the photo from above around a cemetery's point when there is no plan to fit
/// (05_DESIGN/cmentarz.md, element 2a (d) → "Pokaż zdjęcie z góry").
const double photoWithoutPlanZoom = 17;

/// The room for the whole cemetery: [padding] as the screen measured it, but the plan keeps at least 35% of
/// the map's height — on a short screen with a large system text the name, the badges and the bar of graves
/// leave almost nothing (360 × 640 dp at 200%, seen on the emulator). The bar then covers the plan's south,
/// as cmentarz.md D14 → Obali foresaw.
EdgeInsets fitRoom(EdgeInsets padding, Size size) {
  if (!size.isFinite || size.isEmpty) return padding;
  final double least = math.max(120, size.height * 0.35);
  if (size.height - padding.vertical >= least) return padding;
  final double top = math.min(padding.top, size.height - least);
  final double bottom = math.max(16, size.height - least - top);
  return EdgeInsets.fromLTRB(
    padding.left,
    math.max(16, top),
    padding.right,
    bottom,
  );
}

/// The box of a plan's outline.
LatLngBounds planBounds(List<PlanArea> areas) => LatLngBounds.fromPoints([
  for (final PlanArea a in areas)
    for (final GeoPoint p in a.outer) LatLng(p.lat, p.lon),
]);

/// The cemetery as a map (05_DESIGN/cmentarz.md v5, elements 2, 3, 5): the schematic plan from
/// OpenStreetMap in the tokens of style B — the cemetery's land in the surface colour with its outline,
/// main paths 4 dp and side paths 2 dp in the outline colour, the rest in the background colour — or the
/// photo from above; the graves' candles on either. North up, no rotation. [bounds] null: no plan, the
/// photo around [center].
class CemeteryPlanMap extends StatelessWidget {
  const CemeteryPlanMap({
    super.key,
    required this.controller,
    required this.layer,
    required this.padding,
    this.plan,
    this.center,
    this.candles = const [],
    this.selected,
    this.onCandle,
    this.onMapTap,
    this.onMapTapAt,
    this.onPointerDown,
    this.photoTiles,
    this.sectors = const [],
    this.selectedSector,
    this.drawing,
    this.ghost,
    this.candlesDimmed = false,
    this.roomy = false,
    this.here,
    this.onMapEvent,
  });

  /// Every move of the map, with where it came from — mode D tells a finger's drag from a pinch.
  final MapEventCallback? onMapEvent;

  /// The blue dot with its accuracy circle (element 10); null — location off, or no position yet.
  final MapHere? here;

  /// Mode F: the centre may go half the cemetery's size past its box. The crosshair stands in the middle of
  /// the room above the panel, not of the map, so a corner on the cemetery's edge needs the centre outside.
  final bool roomy;

  final MapController controller;
  final MapLayer layer;

  /// The free room for the whole cemetery: below the badges, above the bottom panel (element 2).
  final EdgeInsets padding;
  final CemeteryPlan? plan;

  /// The cemetery's point — the middle of the photo when there is no plan.
  final GeoPoint? center;
  final List<GraveCandle> candles;
  final int? selected;

  /// Null: the candles are drawn but take no touch (modes E and F — cmentarz.md element 16).
  final void Function(int graveId)? onCandle;
  final VoidCallback? onMapTap;

  /// A touch on the map where it landed — mode E selects a zone with it, mode F moves the crosshair.
  final void Function(LatLng point)? onMapTapAt;
  final VoidCallback? onPointerDown;

  /// The author's sectors with a zone (element 4); [selectedSector] in amber (mode E).
  final List<MapSector> sectors;
  final int? selectedSector;

  /// The zone being marked (element 18) and, when one is drawn again, the old one in grey under it.
  final MapDrawing? drawing;
  final List<LatLng>? ghost;

  /// Mode F: the candles at 55%, so the corners stand out.
  final bool candlesDimmed;

  /// The photo's tiles (MapNetwork); null — no photo layer is drawn.
  final TileProvider Function()? photoTiles;

  bool get _hasPlan => plan?.status == PlanStatus.ok && plan!.areas.isNotEmpty;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final LatLngBounds? bounds = _hasPlan ? planBounds(plan!.areas) : null;
      final LatLng middle = bounds?.center ?? LatLng(center!.lat, center!.lon);
      final EdgeInsets room = fitRoom(padding, constraints.biggest);
      final double least = bounds == null
          ? photoWithoutPlanZoom - 2
          : fitZoom(bounds, constraints.biggest, padding: room);
      return FlutterMap(
        mapController: controller,
        options: MapOptions(
          // Missing tiles of the photo are the surface colour (element 3); the plan's outside is the background.
          backgroundColor: layer == MapLayer.photo
              ? GrobingColors.surface
              : GrobingColors.background,
          initialCenter: middle,
          initialZoom: bounds == null ? photoWithoutPlanZoom : least,
          initialCameraFit: bounds == null
              ? null
              : CameraFit.bounds(bounds: bounds, padding: room),
          minZoom: least,
          maxZoom: math.max(cemeteryMaxZoom, least),
          // Not `contain`: at the least zoom the whole cemetery is smaller than the screen, so "every edge
          // inside" cannot hold and nothing is drawn (ADR-003 → Follow-ups, M7; the same as the map of
          // Poland). The centre stays inside the cemetery's box instead.
          cameraConstraint: CameraConstraint.containCenter(
            bounds: switch ((bounds, roomy)) {
              (final LatLngBounds b, true) => _grown(b),
              (final LatLngBounds b, false) => b,
              (null, _) => _around(middle),
            },
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: onMapTap == null && onMapTapAt == null
              ? null
              : (_, point) {
                  onMapTapAt?.call(point);
                  onMapTap?.call();
                },
          onPointerDown: onPointerDown == null
              ? null
              : (_, _) => onPointerDown!(),
          onMapEvent: onMapEvent,
        ),
        children: [
          if (layer == MapLayer.photo && photoTiles != null)
            TileLayer(
              urlTemplate: Hosts.orthophotoTiles,
              tileProvider: photoTiles!(),
              maxNativeZoom: Hosts.orthophotoMaxZoom,
              userAgentPackageName: 'com.grobing.app',
            )
          else if (_hasPlan) ...[
            // The plan for a screen reader is one node — "Plan cmentarza" — not its paths.
            ExcludeSemantics(
              child: PolygonLayer(
                polygons: [
                  for (final PlanArea a in plan!.areas)
                    Polygon(
                      points: [for (final GeoPoint p in a.outer) _at(p)],
                      holePointsList: a.holes.isEmpty
                          ? null
                          : [
                              for (final List<GeoPoint> h in a.holes)
                                [for (final GeoPoint p in h) _at(p)],
                            ],
                      color: GrobingColors.surface,
                      borderColor: GrobingColors.outline,
                      borderStrokeWidth: 1.5,
                    ),
                ],
                // The holes never cross: even-odd draws the same without a path operation every frame
                // (ISSUE-023's ANR).
                painterFillMethod: PolygonPainterFillMethod.evenOdd,
              ),
            ),
            ExcludeSemantics(
              child: PolylineLayer(
                polylines: [
                  for (final PlanPath path in plan!.paths)
                    Polyline(
                      points: [for (final GeoPoint p in path.points) _at(p)],
                      color: GrobingColors.outline,
                      strokeWidth: path.main ? 4 : 2,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                ],
              ),
            ),
          ],
          if (ghost != null) _ghostLayer(ghost!),
          if (sectors.isNotEmpty) _sectorLayer(),
          if (drawing != null) ..._drawingLines(drawing!),
          Opacity(
            opacity: candlesDimmed ? 0.55 : 1,
            child: _CandleLayer(
              candles: candles,
              selected: selected,
              onCandle: onCandle,
            ),
          ),
          if (sectors.isNotEmpty)
            _LabelLayer(
              labels: [
                for (final MapSector s in sectors)
                  (
                    at: labelCorner(s.zone),
                    ring: s.zone,
                    text: 'Kwatera ${s.name}',
                    selected: s.id == selectedSector,
                  ),
              ],
            ),
          if (drawing != null) ...[
            if (drawing!.corners.length >= 3)
              _LabelLayer(
                labels: [
                  (
                    at: labelCorner(drawing!.corners),
                    ring: drawing!.corners,
                    text: 'Kwatera ${drawing!.name}',
                    selected: true,
                  ),
                ],
              ),
            _CornerLayer(corners: drawing!.corners),
          ],
          if (here != null) ..._hereLayers(here!),
        ],
      );
    },
  );

  /// Element 10: the accuracy circle — its radius the phone's accuracy in metres, in the dot's colour at 18% —
  /// the dot, 16 dp with a 2 dp ring in the background colour, and beside it "tu jesteś · ±5 m" on the surface,
  /// 12 sp, growing with the system text up to 1.3× like every label pinned to the map (style-b.md rule 13).
  /// A drawing, not a control: the "gdzie jestem" button says the state to a screen reader.
  List<Widget> _hereLayers(MapHere h) => [
    if (h.accuracyM case final double r? when r > 0)
      ExcludeSemantics(
        child: CircleLayer(
          circles: [
            CircleMarker(
              point: h.point,
              radius: r,
              useRadiusInMeter: true,
              color: GrobingColors.here.withValues(alpha: 0.18),
            ),
          ],
        ),
      ),
    IgnorePointer(
      child: ExcludeSemantics(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: MarkerLayer(
            markers: [
              Marker(
                point: h.point,
                width: 20,
                height: 20,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: GrobingColors.here,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: GrobingColors.background, width: 2),
                    ),
                  ),
                ),
              ),
              if (h.label)
                Marker(
                  point: h.point,
                  width: 200,
                  height: 30,
                  // The label's left edge 14 dp right of the dot's middle.
                  alignment: const Alignment(1.14, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: GrobingColors.surface,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          h.accuracyM == null
                              ? 'tu jesteś'
                              : 'tu jesteś · ±${h.accuracyM!.round()} m',
                          style: const TextStyle(
                            color: GrobingColors.text,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ];

  /// The author's line of a zone (element 4, D13): dashed 5/4, never filled (D28) — the text colour at 75%,
  /// 1.5 dp; the selected sector's in amber, 2.5 dp (mode E). For a screen reader the zones are part of
  /// "Plan cmentarza": mode E lists them.
  ///
  /// On the photo from above each line lies on a line in the background colour, 3.5 dp (5 dp under the
  /// selected one), as the zone being marked does: a light roof or path would leave the dashes unseen (ui
  /// review, ISSUE-028).
  Widget _sectorLayer() => ExcludeSemantics(
    child: PolygonLayer(
      polygons: [
        if (layer == MapLayer.photo)
          for (final MapSector s in sectors)
            Polygon(
              points: s.zone,
              borderColor: GrobingColors.background,
              borderStrokeWidth: s.id == selectedSector ? 5 : 3.5,
            ),
        for (final MapSector s in sectors)
          Polygon(
            points: s.zone,
            borderColor: s.id == selectedSector
                ? GrobingColors.amber
                : GrobingColors.text.withValues(alpha: 0.75),
            borderStrokeWidth: s.id == selectedSector ? 2.5 : 1.5,
            pattern: StrokePattern.dashed(segments: const [5, 4]),
          ),
      ],
    ),
  );

  /// The box the centre may move in when there is no plan: a little more than a large cemetery.
  LatLngBounds _around(LatLng p) => LatLngBounds(
    LatLng(p.latitude - 0.01, p.longitude - 0.015),
    LatLng(p.latitude + 0.01, p.longitude + 0.015),
  );

  /// The old zone while it is drawn again (element 18, D26): dashed, 2 dp, in the muted text colour — 5.01:1
  /// on the surface and apart from the paths (1.62:1). The outline colour was the paths' own and the old zone
  /// vanished along them (ui review, ISSUE-028).
  Widget _ghostLayer(List<LatLng> ring) => ExcludeSemantics(
    child: PolygonLayer(
      polygons: [
        Polygon(
          points: ring,
          borderColor: GrobingColors.textMuted,
          borderStrokeWidth: 2,
          pattern: StrokePattern.dashed(segments: const [5, 4]),
        ),
      ],
    ),
  );

  /// The sides of the zone being marked (element 18; style-b.md rule 13 v1.22): amber 2.5 dp on a 5 dp line
  /// in the background colour, seen on the plan and on the photo alike; the closing side dashed.
  List<Widget> _drawingLines(MapDrawing d) {
    final List<LatLng> c = d.corners;
    if (c.length < 2) return const [];
    final List<LatLng> closing = c.length >= 3 ? [c.last, c.first] : const [];
    return [
      ExcludeSemantics(
        child: PolylineLayer(
          polylines: [
            for (final List<LatLng> line in [
              c,
              if (closing.isNotEmpty) closing,
            ])
              Polyline(
                points: line,
                color: GrobingColors.background,
                strokeWidth: 5,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            Polyline(
              points: c,
              color: GrobingColors.amber,
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
            if (closing.isNotEmpty)
              Polyline(
                points: closing,
                color: GrobingColors.amber,
                strokeWidth: 2.5,
                pattern: StrokePattern.dashed(segments: const [6, 5]),
              ),
          ],
        ),
      ),
    ];
  }
}

LatLng _at(GeoPoint p) => LatLng(p.lat, p.lon);

/// [b] with half its size more on every side.
LatLngBounds _grown(LatLngBounds b) {
  final double dLat = (b.north - b.south) / 2, dLon = (b.east - b.west) / 2;
  return LatLngBounds(
    LatLng(b.south - dLat, b.west - dLon),
    LatLng(b.north + dLat, b.east + dLon),
  );
}

/// Element 5: a grave's candle — 28 × 35 dp, selected 38 × 47 dp with a glow (style-b.md rule 13), the
/// target 48 dp wide; its tip at the grave. The selected one is drawn last, on top.
class _CandleLayer extends StatelessWidget {
  const _CandleLayer({required this.candles, this.selected, this.onCandle});

  final List<GraveCandle> candles;
  final int? selected;
  final void Function(int graveId)? onCandle;

  static const Size _normal = Size(28, 35);
  static const Size _selected = Size(38, 47);

  @override
  Widget build(BuildContext context) {
    final List<GraveCandle> ordered = [
      ...candles.where((c) => c.id != selected),
      ...candles.where((c) => c.id == selected),
    ];
    return MarkerLayer(
      markers: [
        for (final GraveCandle c in ordered)
          Marker(
            point: c.point,
            width: 48,
            height: 48,
            alignment: Alignment.topCenter,
            child: Semantics(
              button: onCandle != null,
              selected: c.id == selected,
              label: c.label,
              onTap: onCandle == null ? null : () => onCandle!(c.id),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCandle == null ? null : () => onCandle!(c.id),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox.fromSize(
                    size: c.id == selected ? _selected : _normal,
                    child: CandlePin(
                      look: c.id == selected
                          ? PinLook.selected
                          : PinLook.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The name of a sector at its corner (element 4, D13): 12 sp, semi-bold, in the text colour — amber when
/// selected or being marked — with a 3 dp halo in the plan's surface colour, so the paths never cross its
/// letters. Above the corner, 6 dp towards the inside of the zone: to the right, or to the left when the
/// right side is outside it (a corner at the zone's right end — ui review, ISSUE-028); grows with the system
/// text up to 1.3×, as every label pinned to the map (style-b.md rule 13). Drawing, not a control: no touch,
/// no screen reader.
class _LabelLayer extends StatelessWidget {
  const _LabelLayer({required this.labels});

  final List<({LatLng at, List<LatLng> ring, String text, bool selected})>
  labels;

  static const double _maxScale = 1.3;
  static const double _width = 240;

  /// Whether the label's start, just above and right of [l]'s corner, is inside its zone.
  static bool _rightInside(
    MapCamera camera,
    ({LatLng at, List<LatLng> ring, String text, bool selected}) l,
  ) => ringContains(
    l.ring,
    camera.screenOffsetToLatLng(
      camera.latLngToScreenOffset(l.at) + const Offset(12, -8),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final MapCamera camera = MapCamera.of(context);
    final double line = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _maxScale).scale(12 * 1.5);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxScale,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: MarkerLayer(
            markers: [
              for (final l in labels)
                if (_rightInside(camera, l))
                  Marker(
                    point: l.at,
                    width: _width,
                    height: line + 6,
                    // The marker's lower left at the corner.
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 6),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _HaloText(
                          l.text,
                          color: l.selected
                              ? GrobingColors.amber
                              : GrobingColors.text,
                        ),
                      ),
                    ),
                  )
                else
                  Marker(
                    point: l.at,
                    width: _width,
                    height: line + 6,
                    // The marker's lower right at the corner.
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 6),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: _HaloText(
                          l.text,
                          color: l.selected
                              ? GrobingColors.amber
                              : GrobingColors.text,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HaloText extends StatelessWidget {
  const _HaloText(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round
            ..color = GrobingColors.surface,
        ),
      ),
      Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// The corners of the zone being marked (element 18): 14 dp circles in amber with a 2 dp ring in the
/// background colour, on the plan and on the photo alike.
class _CornerLayer extends StatelessWidget {
  const _CornerLayer({required this.corners});

  final List<LatLng> corners;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: MarkerLayer(
        markers: [
          for (final LatLng c in corners)
            Marker(
              point: c,
              width: 18,
              height: 18,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: GrobingColors.amber,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: GrobingColors.background, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
