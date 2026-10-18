import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/address_text.dart';
import '../../data/cemeteries.dart';
import '../../data/cemetery_plans.dart';
import '../../data/database.dart';
import '../../data/graves.dart';
import '../../data/sectors.dart';
import '../map/plan_downloads.dart';
import '../photo/photo_viewer_screen.dart' show PhotoErrorLine;
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'cemetery_plan_map.dart';
import 'map_chrome.dart';
import 'sector_geometry.dart';

/// The author's sectors of one cemetery (05_DESIGN/cmentarz.md v6, elements 16–19; ISSUE-028): mode E —
/// the list of sectors, one sector with its name, its zone and its actions — and mode F, marking a zone
/// with the crosshair and "Dodaj róg" (K1, the author's choice at stop #1). A mode, so no tab bar
/// (style-b.md rule 12); the candles are drawn but take no touch.
class SectorsScreen extends StatefulWidget {
  const SectorsScreen({
    super.key,
    required this.database,
    required this.cemeteryId,
    this.layer = MapLayer.plan,
  });

  final GrobingDatabase database;
  final int cemeteryId;

  /// The layer the cemetery's map had: a sector is marked on the plan or on the photo from above.
  final MapLayer layer;

  @override
  State<SectorsScreen> createState() => _SectorsScreenState();
}

/// E's list (17a), E's one sector (17b), F (18).
enum _Mode { list, sector, drawing }

class _SectorsScreenState extends State<SectorsScreen>
    with SingleTickerProviderStateMixin {
  late final Stream<CemeteryGraves?> _graves = watchCemeteryGraves(
    widget.database,
    widget.cemeteryId,
  );
  late final Stream<CemeteryPlan?> _plan = watchCemeteryPlan(
    widget.database,
    widget.cemeteryId,
  );
  late Stream<List<Sector>> _sectors = _watchSectors();
  final MapController _map = MapController();

  _Mode _mode = _Mode.list;
  int? _selected;

  // Mode F: the corners so far, the name the zone is for, the sector drawn again (null — a new one) and
  // the mode it came from.
  List<LatLng> _corners = [];
  String _drawName = '';
  int? _redraw;
  _Mode _drawFrom = _Mode.list;
  bool _saving = false;
  bool _saveFailed = false;

  late MapLayer _layer = widget.layer;
  bool? _photoOnline;
  bool _askingPhoto = false;

  /// What covers the map at the top (badges or the card) and at the bottom (the panel), measured: the room
  /// a zone fits in, and the crosshair's place.
  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _panelKey = GlobalKey();
  double _top = 80;
  double _bottom = 200;
  bool _fitted = false;

  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(_moveStep);
  LatLng? _fromCentre, _toCentre;
  double? _fromZoom, _toZoom;

  @override
  void dispose() {
    _move.dispose();
    _map.dispose();
    super.dispose();
  }

  Stream<List<Sector>> _watchSectors() =>
      watchSectors(widget.database, widget.cemeteryId);

  void _afterLayout(VoidCallback then) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) then();
      });

  // --- the camera ---

  void _measure(List<Sector> sectors) {
    final double? top = _topKey.currentContext?.size?.height;
    final double? panel = _panelKey.currentContext?.size?.height;
    bool changed = false;
    if (top != null && (top + 12 - _top).abs() > 1) {
      _top = top + 12;
      changed = true;
    }
    if (panel != null && (panel - _bottom).abs() > 1) {
      _bottom = panel;
      changed = true;
    }
    if (changed) setState(() {});
    // Once: every zone in the room above the list (element 16); without zones the plan's own fit stays.
    if (!_fitted && _mode == _Mode.list) {
      final List<LatLng> all = [
        for (final Sector s in sectors)
          for (final GeoPoint p in s.zone ?? const <GeoPoint>[])
            LatLng(p.lat, p.lon),
      ];
      if (all.isNotEmpty) {
        _fitted = true;
        _afterLayout(() => _fitTo(all, animate: false, onlyIfNeeded: true));
      }
    }
  }

  /// [points] in the room between the top and the panel, with 48 dp to spare above the panel (element 16).
  ///
  /// [onlyIfNeeded] (the list's first frame, element 16): the camera stays where it is when every point is
  /// already in that room — the list does not move a plan that shows its zones (ui review, ISSUE-028).
  void _fitTo(
    List<LatLng> points, {
    bool animate = true,
    bool onlyIfNeeded = false,
  }) {
    final MapCamera camera;
    try {
      camera = _map.camera;
    } on Object {
      return; // no map on the screen
    }
    if (points.isEmpty) return;
    if (onlyIfNeeded) {
      final Rect room = Rect.fromLTRB(
        24,
        _top + 16,
        camera.size.width - 24,
        camera.size.height - _bottom - 48,
      );
      if (points.every((p) => room.contains(camera.latLngToScreenOffset(p)))) {
        return;
      }
    }
    final MapCamera fitted = CameraFit.coordinates(
      coordinates: points,
      padding: EdgeInsets.fromLTRB(24, _top + 16, 24, _bottom + 48),
      maxZoom: cemeteryMaxZoom,
    ).fit(camera);
    LatLng centre = fitted.center;
    double zoom = fitted.zoom;
    // Already in the room at this zoom: no closer — only into the middle of the room (seen on the emulator:
    // a fitted zone filled the screen and the paths around it were gone).
    if (fitted.zoom >= camera.zoom) {
      zoom = camera.zoom;
      final MapCamera at = camera.withPosition(
        center: LatLngBounds.fromPoints(points).center,
      );
      final double free =
          _top + 16 + (at.size.height - _top - 16 - _bottom - 48) / 2;
      centre = at.screenOffsetToLatLng(
        Offset(at.size.width / 2, at.size.height - free),
      );
    }
    if (animate) {
      _animateCamera(centre, zoom);
    } else {
      _map.move(centre, zoom);
    }
  }

  void _animateCamera(
    LatLng centre,
    double zoom, {
    Duration duration = const Duration(milliseconds: 300),
  }) {
    final MapCamera camera = _map.camera;
    if (MediaQuery.disableAnimationsOf(context)) {
      _move.stop();
      _map.move(centre, zoom);
      return;
    }
    _fromCentre = camera.center;
    _fromZoom = camera.zoom;
    _toCentre = centre;
    _toZoom = zoom;
    _move.duration = duration;
    _move.forward(from: 0);
  }

  void _moveStep() {
    final LatLng? from = _fromCentre, to = _toCentre;
    if (from == null || to == null) return;
    final double t = Curves.easeOutCubic.transform(_move.value);
    _map.move(
      LatLng(
        lerpDouble(from.latitude, to.latitude, t)!,
        lerpDouble(from.longitude, to.longitude, t)!,
      ),
      lerpDouble(_fromZoom, _toZoom, t)!,
    );
  }

  /// The crosshair (K1): in the middle of the room between the card and the panel.
  Offset _crosshair(Size map) =>
      Offset(map.width / 2, _top + (map.height - _top - _bottom) / 2);

  // --- layers ---

  Future<void> _choose(MapLayer layer) async {
    if (layer == _layer) return;
    setState(() => _layer = layer);
    if (layer == MapLayer.photo) await _askPhoto();
  }

  Future<void> _askPhoto() async {
    final MapNetwork? net = MapNetwork.maybeOf(context);
    if (net == null || _askingPhoto) return;
    _askingPhoto = true;
    final bool online = await net.photoReachable();
    _askingPhoto = false;
    if (mounted) setState(() => _photoOnline = online);
  }

  // --- mode E ---

  void _select(Sector s) {
    setState(() {
      _mode = _Mode.sector;
      _selected = s.id;
    });
    final List<GeoPoint>? zone = s.zone;
    if (zone != null) {
      _afterLayout(
        () => _fitTo([for (final GeoPoint p in zone) LatLng(p.lat, p.lon)]),
      );
    }
  }

  /// A touch on the map in mode E: the zone under it — the smallest when zones overlap (element 4).
  void _tapInE(LatLng point, List<Sector> sectors) {
    Sector? hit;
    double area = double.infinity;
    for (final Sector s in sectors) {
      final List<GeoPoint>? zone = s.zone;
      if (zone == null) continue;
      final List<LatLng> ring = [
        for (final GeoPoint p in zone) LatLng(p.lat, p.lon),
      ];
      if (!ringContains(ring, point)) continue;
      final double a = ringArea(ring);
      if (a < area) {
        area = a;
        hit = s;
      }
    }
    if (hit != null) _select(hit);
  }

  Future<void> _newSector(List<Sector> sectors) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (_) => SectorNameDialog(
        title: 'Nowa kwatera',
        confirm: 'Dalej',
        others: sectors,
      ),
    );
    if (name != null && mounted) _startDrawing(name: name);
  }

  Future<void> _rename(Sector s, List<Sector> sectors) => showDialog<String>(
    context: context,
    builder: (_) => SectorNameDialog(
      title: 'Nazwa kwatery',
      confirm: 'Zapisz',
      initial: s.name,
      others: [
        for (final Sector o in sectors)
          if (o.id != s.id) o,
      ],
      graveCount: s.graveCount,
      save: (name) => renameSector(widget.database, s.id, name),
    ),
  );

  Future<void> _removeZone(Sector s) async {
    final bool? removed = await showDialog<bool>(
      context: context,
      builder: (_) => RemoveZoneDialog(
        name: s.name,
        remove: () => removeSectorZone(widget.database, s.id),
      ),
    );
    if (removed == true && mounted) {
      setState(() {
        _mode = _Mode.list;
        _selected = null;
      });
    }
  }

  // --- mode F ---

  void _startDrawing({required String name, int? redraw}) {
    setState(() {
      _drawFrom = _mode;
      _mode = _Mode.drawing;
      _drawName = name;
      _redraw = redraw;
      _corners = [];
      _saveFailed = false;
    });
  }

  /// "Dodaj róg": a corner under the crosshair.
  void _addCorner() {
    final MapCamera camera = _map.camera;
    setState(() {
      _corners = [
        ..._corners,
        camera.screenOffsetToLatLng(_crosshair(camera.size)),
      ];
      _saveFailed = false;
    });
  }

  void _undo() {
    if (_corners.isEmpty) return;
    setState(() {
      _corners = _corners.sublist(0, _corners.length - 1);
      _saveFailed = false;
    });
  }

  /// A touch on the plan in mode F brings that place under the crosshair — the way without dragging
  /// (WCAG 2.2 SC 2.5.7; element 18, K1).
  void _toCrosshair(LatLng point) {
    final MapCamera camera = _map.camera;
    final Offset cross = _crosshair(camera.size);
    final MapCamera at = camera.withPosition(center: point);
    _animateCamera(
      at.screenOffsetToLatLng(
        Offset(at.size.width - cross.dx, at.size.height - cross.dy),
      ),
      camera.zoom,
      duration: const Duration(milliseconds: 220),
    );
  }

  bool get _crossing => sidesCross(_corners);

  bool get _ready => _corners.length >= 3 && !_crossing && !_saving;

  Future<void> _finish() async {
    if (!_ready) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final List<GeoPoint> zone = [
      for (final LatLng c in _corners) GeoPoint(c.latitude, c.longitude),
    ];
    try {
      final int id = switch (_redraw) {
        final int sector => await setSectorZone(
          widget.database,
          sector,
          zone,
        ).then((_) => sector),
        null => await addSector(
          widget.database,
          widget.cemeteryId,
          name: _drawName,
          zone: zone,
        ),
      };
      if (!mounted) return;
      final List<LatLng> drawn = _corners;
      setState(() {
        _saving = false;
        _mode = _Mode.sector;
        _selected = id;
        _corners = [];
        _redraw = null;
      });
      _afterLayout(() => _fitTo(drawn));
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  /// ✕ or back in mode F: without corners straight back, with corners after "Porzucić zaznaczanie?" (19d).
  Future<void> _leaveDrawing() async {
    if (_corners.isNotEmpty) {
      final bool? leave = await showDialog<bool>(
        context: context,
        builder: (_) => const _AbandonDialog(),
      );
      if (leave != true || !mounted) return;
    }
    setState(() {
      _mode = _drawFrom;
      _corners = [];
      _redraw = null;
      _saveFailed = false;
    });
  }

  void _back() {
    switch (_mode) {
      case _Mode.drawing:
        _leaveDrawing();
      case _Mode.sector:
        setState(() {
          _mode = _Mode.list;
          _selected = null;
        });
      case _Mode.list:
        Navigator.of(context).pop();
    }
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    final MapNetwork? net = MapNetwork.maybeOf(context);
    return StreamBuilder<CemeteryGraves?>(
      stream: _graves,
      builder: (context, graves) => StreamBuilder<CemeteryPlan?>(
        stream: _plan,
        builder: (context, plan) => StreamBuilder<List<Sector>>(
          stream: _sectors,
          builder: (context, sectorsSnapshot) {
            final List<Sector> sectors = sectorsSnapshot.data ?? const [];
            final bool failed = sectorsSnapshot.hasError;
            final Sector? selected = sectors
                .where((s) => s.id == _selected)
                .firstOrNull;
            if (_mode == _Mode.sector &&
                sectorsSnapshot.hasData &&
                selected == null) {
              // The sector went (its zone removed, no graves): back to the list.
              _mode = _Mode.list;
              _selected = null;
            }
            _afterLayout(() => _measure(sectors));
            return PopScope(
              canPop: _mode == _Mode.list,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _back();
              },
              child: Scaffold(
                body: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _bar(graves.data?.name),
                      Expanded(
                        child: _body(
                          graves.data,
                          plan.data,
                          sectors,
                          selected,
                          failed,
                          sectorsSnapshot.hasData,
                          net,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Element 16 (and 18): ✕, the title, the cemetery's name — or, in mode F, what is being marked.
  Widget _bar(String? cemeteryName) {
    final bool drawing = _mode == _Mode.drawing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const GrobingIcon(Glyphs.close, applyTextScaling: false),
            color: GrobingColors.text,
            tooltip: drawing ? 'Zamknij zaznaczanie' : 'Zamknij kwatery',
            onPressed: drawing
                ? _leaveDrawing
                : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drawing ? 'Kwatera $_drawName — strefa' : 'Kwatery',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    drawing
                        ? (_redraw != null
                              ? 'Stara strefa jest szara'
                              : 'Zaznacz rogi według planu zarządcy')
                        : cemeteryName ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    CemeteryGraves? cemetery,
    CemeteryPlan? plan,
    List<Sector> sectors,
    Sector? selected,
    bool failed,
    bool read,
    MapNetwork? net,
  ) {
    final bool drawing = _mode == _Mode.drawing;
    final bool hasPlan =
        plan?.status == PlanStatus.ok && plan!.areas.isNotEmpty;
    final bool photo =
        _layer == MapLayer.photo && net != null && cemetery?.point != null;
    final bool showsMap = cemetery != null && (photo || hasPlan);
    return LayoutBuilder(
      builder: (context, room) => Stack(
        children: [
          if (showsMap)
            Positioned.fill(
              child: Semantics(
                container: true,
                label: photo ? 'Zdjęcie cmentarza z góry' : 'Plan cmentarza',
                child: CemeteryPlanMap(
                  key: ValueKey<bool>(hasPlan),
                  controller: _map,
                  layer: photo ? MapLayer.photo : MapLayer.plan,
                  padding: EdgeInsets.fromLTRB(16, _top + 8, 16, _bottom + 16),
                  plan: plan,
                  center: cemetery.point,
                  candles: [
                    for (final GraveSummary g in cemetery.graves)
                      if (g.pin != null)
                        (
                          id: g.id,
                          point: LatLng(g.pin!.lat, g.pin!.lon),
                          label: 'Grób',
                        ),
                  ],
                  candlesDimmed: drawing,
                  sectors: [
                    for (final Sector s in sectors)
                      if (s.zone case final List<GeoPoint> zone?)
                        if (!(drawing && s.id == _redraw))
                          (
                            id: s.id,
                            name: s.name,
                            zone: [
                              for (final GeoPoint p in zone)
                                LatLng(p.lat, p.lon),
                            ],
                          ),
                  ],
                  selectedSector: drawing ? null : _selected,
                  ghost: drawing
                      ? switch (sectors
                            .where((s) => s.id == _redraw)
                            .firstOrNull
                            ?.zone) {
                          final List<GeoPoint> zone => [
                            for (final GeoPoint p in zone) LatLng(p.lat, p.lon),
                          ],
                          null => null,
                        }
                      : null,
                  drawing: drawing
                      ? (corners: _corners, name: _drawName)
                      : null,
                  onMapTapAt: drawing
                      ? _toCrosshair
                      : (point) => _tapInE(point, sectors),
                  onPointerDown: _move.stop,
                  roomy: drawing,
                  photoTiles: net?.photoTiles,
                ),
              ),
            )
          else if (cemetery != null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Planu tego cmentarza nie ma w telefonie.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          if (photo && _photoOnline == false)
            Positioned.fill(
              child: ColoredBox(
                color: GrobingColors.background,
                child: Padding(
                  padding: EdgeInsets.only(top: _top, bottom: _bottom),
                  child: NoInternetForPhoto(
                    onBack: () => _choose(MapLayer.plan),
                  ),
                ),
              ),
            ),
          if (drawing && showsMap && !(photo && _photoOnline == false))
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: LayoutBuilder(
                    builder: (context, c) =>
                        CustomPaint(painter: _Crosshair(_crosshair(c.biggest))),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: KeyedSubtree(
              key: _topKey,
              child: drawing
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Instruction(maxHeight: room.maxHeight * 0.22),
                        // The licence's line stays while the card hides the badges (style-b.md v1.21).
                        if (showsMap) ...[
                          const SizedBox(height: 4),
                          MapBadge(
                            text: photo
                                ? 'Ortofotomapa: GUGiK'
                                : '© OpenStreetMap',
                            small: true,
                          ),
                        ],
                      ],
                    )
                  : cemetery == null
                  ? const SizedBox.shrink()
                  : MapBadges(
                      planShown: hasPlan && !photo,
                      photo: photo,
                      photoOnline: _photoOnline,
                      withSwitch: net != null && cemetery.point != null,
                      onLayer: _choose,
                    ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: KeyedSubtree(
              key: _panelKey,
              child: switch (_mode) {
                _Mode.drawing => _drawingPanel(),
                _Mode.sector when selected != null => _sectorSheet(
                  selected,
                  sectors,
                ),
                _ => _listSheet(sectors, failed, read),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Element 17 (a): the cemetery's sectors as cards on the sheet, then "Zaznacz kwaterę".
  Widget _listSheet(List<Sector> sectors, bool failed, bool read) {
    final List<Sector> ordered = [...sectors]
      ..sort((a, b) => sectorOrder(a.name, b.name));
    return MapPanel(
      overSystemBar: true,
      children: [
        const PanelHandle(),
        if (failed)
          _readError()
        else if (!read)
          const SizedBox(height: 24)
        else if (ordered.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Na tym cmentarzu nie ma jeszcze kwater. Zaznacz te, w których '
              'leży rodzina — według planu zarządcy.',
              style: TextStyle(color: GrobingColors.text, fontSize: 14),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height / 2,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final Sector s in ordered)
                  _SectorCard(sector: s, onTap: () => _select(s)),
              ],
            ),
          ),
        const SizedBox(height: 4),
        FilledButton.icon(
          style: primaryButtonStyle,
          onPressed: failed || !read ? null : () => _newSector(sectors),
          icon: const GrobingIcon(Glyphs.add),
          label: const Text('Zaznacz kwaterę'),
        ),
      ],
    );
  }

  Widget _readError() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nie udało się odczytać kwater.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: _rowButton,
          onPressed: () => setState(() => _sectors = _watchSectors()),
          child: const Text('Spróbuj ponownie'),
        ),
      ],
    ),
  );

  /// Element 17 (b): one sector — its name with ✎, how many graves and whether it is on the plan, and what
  /// can be done with it.
  Widget _sectorSheet(Sector s, List<Sector> sectors) => MapPanel(
    overSystemBar: true,
    children: [
      const PanelHandle(),
      Row(
        children: [
          IconButton(
            icon: const GrobingIcon(
              Glyphs.chevronLeft,
              applyTextScaling: false,
            ),
            color: GrobingColors.text,
            tooltip: 'Wszystkie kwatery',
            onPressed: () => setState(() {
              _mode = _Mode.list;
              _selected = null;
            }),
          ),
          Expanded(
            child: Text(
              'Kwatera ${s.name}',
              style: const TextStyle(
                color: GrobingColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const GrobingIcon(Glyphs.inkPen, applyTextScaling: false),
            color: GrobingColors.amber,
            tooltip: 'Zmień nazwę kwatery',
            onPressed: () => _rename(s, sectors),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 48, bottom: 12),
        child: Text(
          sectorLine(s),
          style: const TextStyle(color: GrobingColors.text, fontSize: 14),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            style: _rowButton,
            onPressed: () => _startDrawing(name: s.name, redraw: s.id),
            icon: const GrobingIcon(Glyphs.pentagon),
            label: Text(
              s.zone == null ? 'Narysuj strefę' : 'Narysuj strefę od nowa',
            ),
          ),
          if (s.zone != null)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: GrobingColors.text,
                minimumSize: const Size(48, 48),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => _removeZone(s),
              icon: const GrobingIcon(Glyphs.delete),
              label: const Text('Usuń z planu'),
            ),
        ],
      ),
    ],
  );

  /// Element 18, the panel: how many corners, "Cofnij", "Dodaj róg" and "Gotowe".
  Widget _drawingPanel() {
    final int n = _corners.length;
    final bool crossing = _crossing;
    final Widget undo = OutlinedButton.icon(
      style: _rowButton,
      onPressed: n == 0 ? null : _undo,
      icon: const GrobingIcon(Glyphs.undo),
      label: const Text('Cofnij'),
    );
    final Widget add = OutlinedButton.icon(
      style: _rowButton,
      onPressed: _addCorner,
      icon: const GrobingIcon(Glyphs.addCircle),
      label: const Text('Dodaj róg'),
    );
    // At a large system text "Cofnij" is its icon alone, beside "Dodaj róg": two rows of buttons left no room
    // for the plan on a 360 × 640 dp phone at 200% (seen on the emulator).
    final bool compact = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return MapPanel(
      overSystemBar: true,
      children: [
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            n < 3
                ? '${cornersLabel(n)} — potrzebne co najmniej 3'
                : cornersLabel(n),
            style: const TextStyle(color: GrobingColors.text, fontSize: 13),
          ),
        ),
        if (crossing) ...[
          const SizedBox(height: 6),
          const PhotoErrorLine(
            'Boki strefy się przecinają — cofnij ostatni róg.',
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            if (compact)
              Tooltip(
                message: 'Cofnij',
                child: OutlinedButton(
                  style: _rowButton.copyWith(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    minimumSize: const WidgetStatePropertyAll(Size(52, 52)),
                  ),
                  onPressed: n == 0 ? null : _undo,
                  child: const GrobingIcon(
                    Glyphs.undo,
                    applyTextScaling: false,
                  ),
                ),
              )
            else
              undo,
            const SizedBox(width: 8),
            Expanded(child: add),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: primaryButtonStyle,
          onPressed: _ready ? _finish : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Gotowe'),
        ),
        if (_saveFailed) ...[
          const SizedBox(height: 8),
          const PhotoErrorLine(
            'Nie udało się zapisać kwatery. Spróbuj jeszcze raz.',
          ),
        ],
      ],
    );
  }

  static final ButtonStyle _rowButton = secondaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  );
}

/// The second line of a sector (elements 17 (a), (b)): its graves and whether it has a zone — W2, read at
/// the cemetery, so in the text colour.
String sectorLine(Sector s) => [
  if (s.graveCount == 0) 'bez grobów' else gravesLabel(s.graveCount),
  if (s.zone != null) 'na planie' else 'bez strefy — tylko w adresach',
].join(' · ');

/// Element 17 (a): a sector on the sheet — a card in the background colour on the surface, with a chevron
/// (style-b.md rule 11).
class _SectorCard extends StatelessWidget {
  const _SectorCard({required this.sector, required this.onTap});

  final Sector sector;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: GrobingColors.background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Kwatera ${sector.name}',
                        style: const TextStyle(
                          color: GrobingColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sectorLine(sector),
                        style: const TextStyle(
                          color: GrobingColors.text,
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
        ),
      ),
    ),
  );
}

/// Element 18, the card: what to do with the crosshair (K1), in place of the badges.
///
/// At most [maxHeight] — about a fifth of the map — and scrolled inside: at 200% on a small phone the whole
/// text took the plan's room and the crosshair with it (seen on the emulator).
class _Instruction extends StatefulWidget {
  const _Instruction({required this.maxHeight});

  final double maxHeight;

  @override
  State<_Instruction> createState() => _InstructionState();
}

class _InstructionState extends State<_Instruction> {
  // Its own controller: the bar is always visible, so it needs one with a client (ui review, ISSUE-028 — the
  // bar shows there is more to read at a large system text).
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: GrobingColors.surface,
    elevation: 2,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(12),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GrobingIcon(
                Glyphs.pentagon,
                size: 18,
                color: GrobingColors.amber,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Przesuń plan tak, żeby celownik stał na rogu kwatery, i dotknij '
                  '„Dodaj róg”. Możesz też dotknąć miejsca na planie — przesunie się '
                  'pod celownik.',
                  style: TextStyle(color: GrobingColors.text, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The crosshair (element 18, K1; style-b.md rule 13 v1.22): a 28 dp cross and an 18 dp circle, 1.6 dp in
/// the text colour on a halo in the background colour — seen on the plan and on the photo alike.
class _Crosshair extends CustomPainter {
  const _Crosshair(this.at);

  final Offset at;

  @override
  void paint(Canvas canvas, Size size) {
    void draw(Color color, double width) {
      final Paint p = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;
      canvas
        ..drawLine(at - const Offset(14, 0), at + const Offset(14, 0), p)
        ..drawLine(at - const Offset(0, 14), at + const Offset(0, 14), p)
        ..drawCircle(at, 9, p);
    }

    draw(GrobingColors.background, 4.5);
    draw(GrobingColors.text, 1.6);
  }

  @override
  bool shouldRepaint(_Crosshair old) => old.at != at;
}

/// Windows 19 (a) "Nowa kwatera" and (b) "Nazwa kwatery": the name with "Kwatera " in front of the field.
/// Without [save] the window checks the name and returns it (a — the drawing comes next); with [save] it
/// saves and closes, and a failed save keeps it open with the message (b). A name another sector of the
/// cemetery has — "b" is "B" — is refused with that sector's name.
class SectorNameDialog extends StatefulWidget {
  const SectorNameDialog({
    super.key,
    required this.title,
    required this.confirm,
    required this.others,
    this.initial = '',
    this.graveCount = 0,
    this.save,
  });

  final String title;
  final String confirm;

  /// The cemetery's other sectors: their names are taken.
  final List<Sector> others;
  final String initial;

  /// (b): how many addresses the new name goes to — the line under the field says so (ADR-016).
  final int graveCount;
  final Future<void> Function(String name)? save;

  @override
  State<SectorNameDialog> createState() => _SectorNameDialogState();
}

class _SectorNameDialogState extends State<SectorNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  )..selection = TextSelection.collapsed(offset: widget.initial.length);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final String? name = addressPart(_name.text, sectorWord);
    if (name == null) {
      setState(() => _error = 'Podaj nazwę kwatery.');
      return;
    }
    final Sector? taken = widget.others
        .where((o) => sectorKey(o.name) == sectorKey(name))
        .firstOrNull;
    if (taken != null) {
      setState(() => _error = _taken(taken.name));
      return;
    }
    final Future<void> Function(String name)? save = widget.save;
    if (save == null) {
      Navigator.of(context).pop(name);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await save(name);
      if (mounted) Navigator.of(context).pop(name);
    } on SectorNameTaken catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _taken(e.name);
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Nie udało się zapisać kwatery. Spróbuj jeszcze raz.';
        });
      }
    }
  }

  /// (a) a new sector goes to the one already there; (b) a rename cannot merge two sectors, so it asks for
  /// another name (ui review, ISSUE-028).
  String _taken(String name) => widget.save == null
      ? 'Kwatera $name już jest na liście — wybierz ją tam.'
      : 'Kwatera $name już jest na tym cmentarzu — wpisz inną nazwę.';

  /// Under the field: (a) what to type; (b) what happens to the addresses, as it is typed.
  String? get _helper {
    if (widget.save == null) {
      return 'Sama nazwa, jak na planie zarządcy, np. B albo 12.';
    }
    if (widget.graveCount == 0) return null;
    final String name = addressPart(_name.text, sectorWord) ?? '…';
    return 'Adresy ${gravesGenitive(widget.graveCount)} zmienią się na '
        '„Kwatera $name”.';
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(inputDecorationTheme: GrobingTheme.fields),
    child: AlertDialog(
      backgroundColor: GrobingColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.title,
        style: const TextStyle(
          color: GrobingColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _confirm(),
            style: const TextStyle(color: GrobingColors.text, fontSize: 16),
            decoration: InputDecoration(
              prefixText: 'Kwatera ',
              prefixStyle: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 16,
              ),
              helperText: _error == null ? _helper : null,
              helperStyle: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 13,
              ),
              helperMaxLines: 3,
              // Never colour alone (SC 1.4.1): the message comes with an icon.
              error: _error == null
                  ? null
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const GrobingIcon(
                          Glyphs.error,
                          size: 16,
                          color: GrobingColors.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: GrobingColors.error),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: _saving ? null : _confirm,
          child: Text(widget.confirm),
        ),
      ],
    ),
  );
}

/// Window 19 (c) "Usunąć kwaterę B z planu?": only the zone goes, the addresses stay (cmentarz.md D27). The
/// safe action in amber, removing in the text colour (style-b.md rule 14). Pops true once removed.
class RemoveZoneDialog extends StatefulWidget {
  const RemoveZoneDialog({super.key, required this.name, required this.remove});

  final String name;
  final Future<void> Function() remove;

  @override
  State<RemoveZoneDialog> createState() => _RemoveZoneDialogState();
}

class _RemoveZoneDialogState extends State<RemoveZoneDialog> {
  bool _removing = false;
  bool _failed = false;

  Future<void> _remove() async {
    if (_removing) return;
    setState(() {
      _removing = true;
      _failed = false;
    });
    try {
      await widget.remove();
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _removing = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: GrobingColors.surface,
    surfaceTintColor: Colors.transparent,
    title: Text(
      'Usunąć kwaterę ${widget.name} z planu?',
      style: const TextStyle(
        color: GrobingColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Strefa zniknie z planu. Adresy grobów zostaną.',
          style: TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        if (_failed) ...[
          const SizedBox(height: 12),
          const PhotoErrorLine(
            'Nie udało się zapisać kwatery. Spróbuj jeszcze raz.',
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
        onPressed: _removing ? null : _remove,
        child: const Text('Usuń'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Zostaw'),
      ),
    ],
  );
}

/// Window 19 (d): the corners would be lost (style-b.md rule 10). Pops true to leave.
class _AbandonDialog extends StatelessWidget {
  const _AbandonDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: GrobingColors.surface,
    surfaceTintColor: Colors.transparent,
    title: const Text(
      'Porzucić zaznaczanie?',
      style: TextStyle(
        color: GrobingColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    content: const Text(
      'Zaznaczone rogi przepadną.',
      style: TextStyle(color: GrobingColors.text, fontSize: 16),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Porzuć'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Rysuj dalej'),
      ),
    ],
  );
}
