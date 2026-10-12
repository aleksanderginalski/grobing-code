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

/// What the map shows under the candles (05_DESIGN/cmentarz.md, element 3).
enum MapLayer { plan, photo }

/// A grave's candle on the cemetery's map: its id, point and what a screen reader says.
typedef GraveCandle = ({int id, LatLng point, String label});

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
    this.onPointerDown,
    this.photoTiles,
  });

  final MapController controller;
  final MapLayer layer;

  /// The free room for the whole cemetery: below the badges, above the bottom panel (element 2).
  final EdgeInsets padding;
  final CemeteryPlan? plan;

  /// The cemetery's point — the middle of the photo when there is no plan.
  final GeoPoint? center;
  final List<GraveCandle> candles;
  final int? selected;
  final void Function(int graveId)? onCandle;
  final VoidCallback? onMapTap;
  final VoidCallback? onPointerDown;

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
            bounds: bounds ?? _around(middle),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: onMapTap == null ? null : (_, _) => onMapTap!(),
          onPointerDown: onPointerDown == null
              ? null
              : (_, _) => onPointerDown!(),
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
          _CandleLayer(
            candles: candles,
            selected: selected,
            onCandle: onCandle,
          ),
        ],
      );
    },
  );
}

LatLng _at(GeoPoint p) => LatLng(p.lat, p.lon);

/// The box the centre may move in when there is no plan: a little more than a large cemetery.
LatLngBounds _around(LatLng p) => LatLngBounds(
  LatLng(p.latitude - 0.01, p.longitude - 0.015),
  LatLng(p.latitude + 0.01, p.longitude + 0.015),
);

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
