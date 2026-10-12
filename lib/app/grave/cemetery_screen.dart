import 'dart:async';
import 'dart:io';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/cemeteries.dart';
import '../../data/cemetery_plans.dart';
import '../../data/database.dart';
import '../../data/graves.dart';
import '../../data/sectors.dart';
import '../home/cemetery_edit.dart';
import '../home/poland_map_data.dart';
import '../map/plan_downloads.dart';
import '../photo/photo_viewer_screen.dart' show coverDecodeWidth;
import '../photo/photos.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/candle.dart';
import 'cemetery_plan_map.dart';
import 'grave_screen.dart';
import 'map_chrome.dart';
import 'person_form_screen.dart';
import 'plan_placeholder.dart';
import 'sectors_screen.dart';

/// The cemetery as a map (05_DESIGN/cmentarz.md v5; ISSUE-027): the schematic plan offline or the photo
/// from above online, the graves with a pin as candles, and three states — A the map with the bar of
/// graves, B one grave from its candle, C the list of all graves without the map. Without a plan, a
/// placeholder in its place says why and what next (element 2a); the list works in every case.
class CemeteryScreen extends StatefulWidget {
  const CemeteryScreen({
    super.key,
    required this.database,
    required this.cemeteryId,
    this.photos,
    this.tab = AppTab.map,
    this.highlightGraveId,
  });

  final GrobingDatabase database;
  final int cemeteryId;

  /// The tab of the stack — the map, or the tab of the person's view whose "Pochówek" opened this
  /// (style-b.md rule 12).
  final AppTab tab;

  /// The grave to mark — from a person's "Pochówek": with a pin it opens as one grave (B), without one on
  /// the list (C), scrolled to its card (cmentarz.md D23); back returns to the person.
  final int? highlightGraveId;

  /// Null only in tests of other features: then the cards have no thumbnails.
  final Photos? photos;

  @override
  State<CemeteryScreen> createState() => _CemeteryScreenState();
}

/// A, B, C (cmentarz.md → Navigation).
enum _View { map, grave, list }

/// No downloads — a screen without the app's network (tests of other features).
final ValueNotifier<Map<int, PlanDownload>> _noDownloads = ValueNotifier(
  const {},
);

class _CemeteryScreenState extends State<CemeteryScreen>
    with SingleTickerProviderStateMixin {
  late Stream<CemeteryGraves?> _graves = _watch();
  late final Stream<CemeteryPlan?> _plan = watchCemeteryPlan(
    widget.database,
    widget.cemeteryId,
  );
  late final Stream<List<Sector>> _sectors = watchSectors(
    widget.database,
    widget.cemeteryId,
  );
  final MapController _map = MapController();

  _View _view = _View.map;

  /// The state the list came from — back returns to it.
  _View _listFrom = _View.map;

  /// The grave of B; on the list its card is framed.
  int? _selected;
  late final bool _fromPerson = widget.highlightGraveId != null;
  bool _entered = false;

  MapLayer _layer = MapLayer.plan;

  /// Whether the photo can be shown — null until asked (element 13).
  bool? _photoOnline;
  bool _askingPhoto = false;
  bool _askedDownload = false;

  final GlobalKey _highlighted = GlobalKey();
  bool _scrolledToHighlight = false;

  /// The badges at the top and the panel at the bottom, measured: the room the whole cemetery fits in.
  final GlobalKey _badgesKey = GlobalKey();
  final GlobalKey _panelKey = GlobalKey();
  double _badgesHeight = 80;

  /// The bar of graves (A) — the least zoom fits the cemetery above it, in A and in B alike, so the zoom
  /// never jumps when the grave's sheet opens.
  double _barHeight = 170;
  bool _fitted = false;

  /// A finger moved the map: from then on the screen leaves the zoom and the place to it.
  bool _userMoved = false;

  /// The plan glides above the grave's sheet and back, about 300 ms (cmentarz.md element 2, as
  /// cmentarze.md D30).
  late final AnimationController _glide;
  LatLng? _glideFrom;
  LatLng? _glideTo;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_glideStep);
  }

  @override
  void dispose() {
    _glide.dispose();
    _map.dispose();
    super.dispose();
  }

  Stream<CemeteryGraves?> _watch() =>
      watchCemeteryGraves(widget.database, widget.cemeteryId);

  Future<void> _openGrave(int id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GraveScreen(
        database: widget.database,
        graveId: id,
        photos: widget.photos,
        tab: widget.tab,
      ),
    ),
  );

  /// "Dodaj grób" opens the form of the grave's first person at once: the grave is written with them
  /// (05_DESIGN/cmentarz.md → Navigation).
  Future<void> _addGrave(CemeteryGraves cemetery) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonFormScreen(
        database: widget.database,
        mode: NewGrave(cemeteryId: cemetery.id, cemeteryName: cemetery.name),
        photos: widget.photos,
        tab: widget.tab,
      ),
    ),
  );

  /// "Kwatery" (element 15) → the sectors' mode (16–19), on the layer the map has now (ISSUE-028).
  Future<void> _openSectors() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SectorsScreen(
        database: widget.database,
        cemeteryId: widget.cemeteryId,
        layer: _layer,
      ),
    ),
  );

  /// ✎ (element 1) and "Wskaż na mapie" (2a (e)): the same way as the ✎ on the map of Poland.
  Future<void> _editCemetery(CemeteryGraves c, {bool pointOnly = false}) async {
    final List<CemeterySummary> all = await watchCemeteries(
      widget.database,
    ).first;
    if (!mounted) return;
    await editCemetery(
      context,
      database: widget.database,
      mapData: PolandMapData.load(),
      others: [
        for (final CemeterySummary o in all)
          if (o.point != null && o.id != c.id)
            (id: o.id, point: LatLng(o.point!.lat, o.point!.lon), name: o.name),
      ],
      cemetery: (id: c.id, name: c.name, locality: c.locality, point: c.point),
      pointOnly: pointOnly,
    );
  }

  // --- states ---

  /// From a person's "Pochówek", once the graves are read (D23).
  void _enter(CemeteryGraves c) {
    if (_entered) return;
    _entered = true;
    final int? id = widget.highlightGraveId;
    if (id == null) return;
    final GraveSummary? grave = c.graves.where((g) => g.id == id).firstOrNull;
    if (grave == null) return;
    _selected = id;
    if (grave.hasPin) {
      _view = _View.grave;
      _afterLayout(_settle);
    } else {
      _view = _View.list;
    }
  }

  void _selectGrave(int id) {
    setState(() {
      _selected = id;
      _view = _View.grave;
    });
    _afterLayout(_settle);
  }

  void _toMap() {
    setState(() => _view = _View.map);
    _afterLayout(_settle);
  }

  void _openList() {
    setState(() {
      _listFrom = _view == _View.grave ? _View.grave : _View.map;
      _view = _View.list;
      _scrolledToHighlight = false;
    });
  }

  void _closeList() {
    setState(() => _view = _listFrom);
    _afterLayout(_settle);
  }

  void _back() {
    switch (_view) {
      case _View.list:
        _closeList();
      case _View.grave:
        _toMap();
      case _View.map:
        Navigator.of(context).pop();
    }
  }

  void _afterLayout(VoidCallback then) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) then();
      });

  // --- the camera ---

  /// The room the cemetery fits in at the least zoom: under the badges, above the bar of graves.
  EdgeInsets get _fitPadding =>
      EdgeInsets.fromLTRB(16, _badgesHeight + 8, 16, _barHeight + 16);

  /// Measures the badges and the panel; the first time, fits the whole cemetery into the measured room.
  void _measure(CemeteryPlan? plan) {
    final double? badges = _badgesKey.currentContext?.size?.height;
    final double? panel = _panelKey.currentContext?.size?.height;
    bool changed = false;
    if (badges != null && (badges + 12 - _badgesHeight).abs() > 1) {
      _badgesHeight = badges + 12;
      changed = true;
    }
    if (_view == _View.map && panel != null && (panel - _barHeight).abs() > 1) {
      _barHeight = panel;
      changed = true;
    }
    if (changed) setState(() {});
    // Again whenever the room changes — a larger system text makes the badges and the bar taller (seen at
    // 200% on the emulator: the plan ran under both) — until a finger takes the map over.
    if ((changed || !_fitted) &&
        _hasPlan(plan) &&
        _view == _View.map &&
        !_userMoved) {
      _fitted = true;
      _afterLayout(() {
        final MapCamera camera;
        try {
          camera = _map.camera;
        } on Object {
          return;
        }
        _map.fitCamera(
          CameraFit.bounds(
            bounds: planBounds(plan!.areas),
            padding: fitRoom(_fitPadding, camera.size),
          ),
        );
      });
    }
  }

  void _fingerDown() {
    _glide.stop();
    _userMoved = true;
  }

  bool _hasPlan(CemeteryPlan? plan) =>
      plan?.status == PlanStatus.ok && plan!.areas.isNotEmpty;

  CemeteryPlan? _currentPlan;

  /// After the state changed: at the least zoom the whole cemetery stands in the middle of the room above
  /// the panel — glides up over the grave's sheet and back (D30 of the map of Poland); closer in, the
  /// selected candle is kept above the sheet.
  void _settle() {
    final MapCamera camera;
    try {
      camera = _map.camera;
    } on Object {
      return; // no map on the screen (a placeholder, or the list)
    }
    final double panel = _panelKey.currentContext?.size?.height ?? _barHeight;
    final double top = _badgesHeight;
    final CemeteryPlan? plan = _currentPlan;
    final double least = camera.minZoom ?? camera.zoom;
    if (_hasPlan(plan) && camera.zoom <= least + 0.01) {
      final LatLngBounds b = planBounds(plan!.areas);
      _glideCentre(_centreFor(camera, b.center, top, panel));
      return;
    }
    final LatLng? pin = _selectedPin();
    if (_view != _View.grave || pin == null) return;
    final double y = camera.latLngToScreenOffset(pin).dy;
    if (y > camera.size.height - panel - 24 || y < top + 48) {
      _glideCentre(_centreFor(camera, pin, top, panel));
    }
  }

  LatLng? _selectedPin() {
    final GeoPoint? p = _pins[_selected];
    return p == null ? null : LatLng(p.lat, p.lon);
  }

  Map<int, GeoPoint> _pins = const {};

  /// The centre that puts [point] in the middle of the room between [top] and [bottom].
  LatLng _centreFor(MapCamera camera, LatLng point, double top, double bottom) {
    final MapCamera at = camera.withPosition(center: point);
    final double free = top + (at.size.height - top - bottom) / 2;
    return at.screenOffsetToLatLng(
      Offset(at.size.width / 2, at.size.height - free),
    );
  }

  void _glideCentre(LatLng target) {
    final MapCamera camera = _map.camera;
    if (MediaQuery.disableAnimationsOf(context)) {
      _glide.stop();
      _map.move(target, camera.zoom);
      return;
    }
    _glideFrom = camera.center;
    _glideTo = target;
    _glide.forward(from: 0);
  }

  void _glideStep() {
    final LatLng? from = _glideFrom, to = _glideTo;
    if (from == null || to == null) return;
    final double t = Curves.easeOutCubic.transform(_glide.value);
    _map.move(
      LatLng(
        lerpDouble(from.latitude, to.latitude, t)!,
        lerpDouble(from.longitude, to.longitude, t)!,
      ),
      _map.camera.zoom,
    );
  }

  // --- layers and downloads ---

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

  /// "Pobierz teraz" (2a (b), (c)): without a network the placeholder stays and a bar says so.
  Future<void> _downloadNow(PlanDownloads plans) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PlanDownload? result = await plans.download(widget.cemeteryId);
    if (result == PlanDownload.offline) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bez internetu. Plan pobierze się, gdy będzie zasięg.'),
        ),
      );
    }
  }

  /// A cemetery opened without its plan asks for it (ISSUE-027 D3), once.
  void _askDownload(PlanDownloads? plans, CemeteryGraves c, bool planRead) {
    if (_askedDownload || plans == null || !planRead || c.point == null) {
      return;
    }
    _askedDownload = true;
    _afterLayout(() => unawaited(plans.download(c.id)));
  }

  PlanGap? _gap(
    CemeteryGraves c,
    CemeteryPlan? plan,
    PlanDownload? download,
    PlanDownloads? plans,
  ) {
    if (c.point == null) return PlanGap.noPoint;
    if (_hasPlan(plan)) return null;
    if (plan != null) return PlanGap.notInOsm;
    return switch (download) {
      PlanDownload.downloading => PlanGap.downloading,
      PlanDownload.offline => PlanGap.offline,
      PlanDownload.serverError => PlanGap.serverError,
      null => plans == null ? PlanGap.offline : PlanGap.downloading,
    };
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    final MapNetwork? net = MapNetwork.maybeOf(context);
    final PlanDownloads? plans = net?.plans;
    return StreamBuilder<CemeteryGraves?>(
      stream: _graves,
      builder: (context, graves) => StreamBuilder<CemeteryPlan?>(
        stream: _plan,
        builder: (context, planSnapshot) => StreamBuilder<List<Sector>>(
          stream: _sectors,
          builder: (context, sectors) =>
              ValueListenableBuilder<Map<int, PlanDownload>>(
                valueListenable: plans?.states ?? _noDownloads,
                builder: (context, downloads, _) {
                  final CemeteryGraves? cemetery = graves.data;
                  final bool failed =
                      graves.hasError || (graves.hasData && cemetery == null);
                  final CemeteryPlan? plan = planSnapshot.data;
                  _currentPlan = plan;
                  if (cemetery != null) {
                    _enter(cemetery);
                    _pins = {
                      for (final GraveSummary g in cemetery.graves)
                        if (g.pin != null) g.id: g.pin!,
                    };
                    _askDownload(
                      plans,
                      cemetery,
                      planSnapshot.connectionState == ConnectionState.active,
                    );
                  }
                  _afterLayout(() => _measure(plan));
                  return PopScope(
                    canPop: _view == _View.map || _fromPerson,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _back();
                    },
                    child: Scaffold(
                      // From the map's cemetery sheet, or from a person's "Pochówek" in whatever tab.
                      bottomNavigationBar: GrobingTabBar(
                        active: widget.tab,
                        database: widget.database,
                        photos: widget.photos,
                      ),
                      body: SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _bar(cemetery),
                            Expanded(
                              child: _view == _View.list
                                  ? _listSheet(cemetery, failed)
                                  : _mapState(
                                      cemetery,
                                      failed,
                                      plan,
                                      cemetery == null
                                          ? null
                                          : downloads[cemetery.id],
                                      net,
                                      sectors.data ?? const [],
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
      ),
    );
  }

  /// Element 1: back, the cemetery's name (up to two lines), its locality, and the ✎.
  Widget _bar(CemeteryGraves? cemetery) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BackButton(color: GrobingColors.text),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cemetery?.name ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cemetery?.locality != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    cemetery!.locality!,
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          color: GrobingColors.amber,
          tooltip: 'Popraw cmentarz',
          onPressed: cemetery == null ? null : () => _editCemetery(cemetery),
        ),
      ],
    ),
  );

  /// States A and B: the map (or its placeholder) under the badges and the bottom panel.
  Widget _mapState(
    CemeteryGraves? cemetery,
    bool failed,
    CemeteryPlan? plan,
    PlanDownload? download,
    MapNetwork? net,
    List<Sector> sectors,
  ) {
    final PlanDownloads? plans = net?.plans;
    final PlanGap? gap = cemetery == null
        ? null
        : _gap(cemetery, plan, download, plans);
    if (gap == PlanGap.noPoint && _layer == MapLayer.photo) {
      _layer = MapLayer.plan;
    }
    if (gap == PlanGap.notInOsm && _photoOnline == null) {
      _afterLayout(_askPhoto);
    }
    final bool photo = _layer == MapLayer.photo && net != null;
    final bool showsMap =
        cemetery != null && (photo ? gap != PlanGap.noPoint : gap == null);
    final GraveSummary? grave = _view == _View.grave
        ? cemetery?.graves.where((g) => g.id == _selected).firstOrNull
        : null;
    return Stack(
      children: [
        if (cemetery == null && !failed)
          const Center(child: CircularProgressIndicator())
        else if (showsMap)
          Positioned.fill(
            child: Semantics(
              container: true,
              label: photo ? 'Zdjęcie cmentarza z góry' : 'Plan cmentarza',
              child: CemeteryPlanMap(
                // A plan coming or going rebuilds the map with its own fit.
                key: ValueKey<bool>(gap == null),
                controller: _map,
                layer: photo ? MapLayer.photo : MapLayer.plan,
                padding: _fitPadding,
                plan: plan,
                center: cemetery.point,
                candles: [
                  for (final GraveSummary g in cemetery.graves)
                    if (g.pin != null)
                      (
                        id: g.id,
                        point: LatLng(g.pin!.lat, g.pin!.lon),
                        label: 'Grób: ${_titleText(g)}',
                      ),
                ],
                selected: _view == _View.grave ? _selected : null,
                onCandle: _selectGrave,
                onMapTap: _view == _View.grave ? _toMap : null,
                onPointerDown: _fingerDown,
                photoTiles: net?.photoTiles,
                // Drawn, never touched here (D29): the sectors' mode manages them.
                sectors: [
                  for (final Sector s in sectors)
                    if (s.zone case final List<GeoPoint> zone?)
                      (
                        id: s.id,
                        name: s.name,
                        zone: [
                          for (final GeoPoint p in zone) LatLng(p.lat, p.lon),
                        ],
                      ),
                ],
              ),
            ),
          )
        else if (cemetery != null && gap != null)
          Positioned(
            left: 0,
            right: 0,
            top: _badgesHeight,
            bottom: _barHeight,
            child: PlanPlaceholder(
              gap: gap,
              hasGraves: cemetery.graves.isNotEmpty,
              onDownload: plans == null ? null : () => _downloadNow(plans),
              onShowPhoto: _photoOnline == true && net != null
                  ? () => _choose(MapLayer.photo)
                  : null,
              onPickPoint: () => _editCemetery(cemetery, pointOnly: true),
            ),
          ),
        if (photo && _photoOnline == false && cemetery != null)
          Positioned.fill(
            child: ColoredBox(
              color: GrobingColors.background,
              child: Padding(
                padding: EdgeInsets.only(
                  top: _badgesHeight,
                  bottom: _barHeight,
                ),
                child: NoInternetForPhoto(onBack: () => _choose(MapLayer.plan)),
              ),
            ),
          ),
        if (cemetery != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: KeyedSubtree(
              key: _badgesKey,
              child: MapBadges(
                planShown: gap == null && !photo,
                photo: photo,
                photoOnline: _photoOnline,
                withSwitch: gap != PlanGap.noPoint && net != null,
                onLayer: _choose,
              ),
            ),
          ),
        // Element 15: only in A, and only with something to mark on — the plan, or the photo online (D24).
        if (_view == _View.map && showsMap && !(photo && _photoOnline == false))
          Positioned(
            left: 12,
            bottom: _barHeight + 8,
            child: _SectorsPill(onTap: _openSectors),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: KeyedSubtree(
            key: _panelKey,
            child: grave != null
                ? _graveSheet(grave)
                : _graveBar(cemetery, failed),
          ),
        ),
      ],
    );
  }

  String _titleText(GraveSummary g) {
    if (g.name != null) return g.name!;
    final List<String> people = [
      for (final p in g.people) personName(p.givenNames, p.surname),
    ];
    return people.isEmpty ? 'Grób bez wpisanych osób' : people.join(', ');
  }

  /// Element 6 (A): the counts, how many graves have no pin, and "Dodaj grób" — the same as under the
  /// list. A tap or a drag up opens the list (D14, D21).
  Widget _graveBar(CemeteryGraves? cemetery, bool failed) {
    final int total = cemetery?.graves.length ?? 0;
    final int withoutPin = cemetery?.graves.where((g) => !g.hasPin).length ?? 0;
    final String? second = cemetery == null || total == 0
        ? null
        : withoutPin == 0
        ? 'wszystkie groby mają pinezki'
        : '${gravesLabel(withoutPin)} bez pinezki — na liście';
    return MapPanel(
      onDragUp: cemetery == null || total == 0 ? null : _openList,
      children: [
        if (failed)
          _readError()
        else
          Semantics(
            // Its own node: merged into the panel it took the panel's bounds, button included (seen in
            // uiautomator, qa ISSUE-027) — the fifth of its kind (CURRENT_STATE → Do retro).
            container: true,
            button: total > 0,
            label: total > 0 ? 'Pokaż listę grobów' : null,
            onTap: total > 0 ? _openList : null,
            child: InkWell(
              onTap: total > 0 ? _openList : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PanelHandle(),
                    if (cemetery == null)
                      const SizedBox(height: 20)
                    else if (total == 0)
                      const Text(
                        'Na tym cmentarzu nie ma jeszcze grobów.',
                        style: TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 14,
                        ),
                      )
                    else ...[
                      Text(
                        '${gravesLabel(total)} · '
                        '${peopleLabel(cemetery.personCount)}',
                        style: const TextStyle(
                          color: GrobingColors.text,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // W2: read at the cemetery, so in the text colour (NFR-004, stop #1 of ISSUE-027).
                      Text(
                        second!,
                        style: const TextStyle(
                          color: GrobingColors.text,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _addButton(failed ? null : cemetery),
      ],
    );
  }

  /// Element 7 (B): the grave from its candle — the gravestone, the title, the address, how many lie here,
  /// and "Pokaż grób". The handle (or a drag up) opens the list; a drag down closes it.
  Widget _graveSheet(GraveSummary g) {
    final File? photo = switch ((widget.photos, g.photoPath)) {
      (final Photos photos?, final String path?) => photos.fileOf(path),
      _ => null,
    };
    // W2: the address and the count are read at the grave (NFR-004).
    const TextStyle line = TextStyle(color: GrobingColors.text, fontSize: 14);
    return MapPanel(
      onDragUp: _openList,
      onDragDown: _toMap,
      children: [
        TapHandle(label: 'Pokaż listę grobów', onTap: _openList),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null) ...[
              _GravestoneThumb(file: photo),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (g.name != null)
                    Text(
                      g.name!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _GraveCard._title,
                    )
                  else
                    NamesText(
                      names: [
                        for (final p in g.people)
                          personName(p.givenNames, p.surname),
                      ],
                      style: _GraveCard._title,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    addressLine(
                      graveAddress(g.sector, g.row, g.plot),
                      hasPin: g.hasPin,
                    ),
                    style: line,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.group_outlined,
                        size: 18,
                        color: GrobingColors.text,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(peopleLabel(g.people.length), style: line),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // The candle leads to a place of memory (style-b.md rule 8).
        FilledButton.icon(
          style: primaryButtonStyle,
          onPressed: () => _openGrave(g.id),
          icon: const CandleIcon(size: 22, color: GrobingColors.background),
          label: const Text('Pokaż grób'),
        ),
      ],
    );
  }

  /// State C (elements 8, 9): all graves over the whole screen, without the map. The handle, a drag down
  /// or back return to where the list came from.
  Widget _listSheet(CemeteryGraves? cemetery, bool failed) => GestureDetector(
    onVerticalDragEnd: (d) {
      if ((d.primaryVelocity ?? 0) > 0) _closeList();
    },
    child: Material(
      color: GrobingColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TapHandle(label: 'Pokaż mapę', onTap: _closeList),
          Expanded(
            child: failed
                ? Center(child: _readError())
                : cemetery == null
                ? const Center(child: CircularProgressIndicator())
                : cemetery.graves.isEmpty
                ? _empty()
                : _list(cemetery),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _addButton(failed ? null : cemetery),
          ),
        ],
      ),
    ),
  );

  /// Element 8: the counts, then the graves in the order they were entered.
  Widget _list(CemeteryGraves cemetery) {
    _scrollToHighlight();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      // A marked grave far down the list needs its card built to scroll to it.
      cacheExtent: _selected == null ? null : 100000,
      children: [
        Text(
          '${gravesLabel(cemetery.graves.length)} · '
          '${peopleLabel(cemetery.personCount)}',
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 8),
        for (final GraveSummary g in cemetery.graves)
          _GraveCard(
            key: g.id == _selected ? _highlighted : null,
            grave: g,
            photo: switch ((widget.photos, g.photoPath)) {
              (final Photos photos?, final String path?) => photos.fileOf(path),
              _ => null,
            },
            // From a person's "Pochówek": 2 dp; the grave of B: 1.5 dp (element 8).
            selected: g.id == _selected,
            frameWidth: _fromPerson && g.id == widget.highlightGraveId
                ? 2
                : 1.5,
            onTap: () => _openGrave(g.id),
          ),
      ],
    );
  }

  /// Once each time the list opens: the marked card whole on the screen (cmentarz.md v4.3).
  void _scrollToHighlight() {
    if (_selected == null || _scrolledToHighlight) return;
    _scrolledToHighlight = true;
    _afterLayout(() {
      final BuildContext? card = _highlighted.currentContext;
      if (card != null && card.mounted) {
        Scrollable.ensureVisible(card, alignment: 0.3);
      }
    });
  }

  /// What will be here; the one action is the pinned "Dodaj grób" (style-b.md rule 9).
  Widget _empty() => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Na tym cmentarzu nie ma jeszcze grobów.',
        textAlign: TextAlign.center,
        style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
      ),
    ),
  );

  Widget _readError() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Nie udało się odczytać grobów.',
        style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
      const SizedBox(height: 14),
      OutlinedButton(
        style: secondaryButtonStyle,
        onPressed: () => setState(() => _graves = _watch()),
        child: const Text('Spróbuj ponownie'),
      ),
    ],
  );

  /// Elements 6 and 9: the main action; inactive while it is not known where it adds.
  Widget _addButton(CemeteryGraves? cemetery) => FilledButton.icon(
    style: primaryButtonStyle,
    onPressed: cemetery == null ? null : () => _addGrave(cemetery),
    icon: const Icon(Icons.add),
    label: const Text('Dodaj grób'),
  );
}

/// Element 15: "Kwatery" — a pill on the surface, 40 dp high in a 48 dp target, the icon in amber.
class _SectorsPill extends StatelessWidget {
  const _SectorsPill({required this.onTap});

  final VoidCallback onTap;

  // The whole 48 dp box takes the touch, not only the 40 dp pill (ui review, ISSUE-028: 39 dp measured).
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'Kwatery',
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
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pentagon_outlined,
                      size: 18,
                      color: GrobingColors.amber,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Kwatery',
                      style: TextStyle(color: GrobingColors.text, fontSize: 14),
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

/// Element 7: the gravestone, 72 dp, radius 12, cut from the middle; the sheet's text says what it is.
class _GravestoneThumb extends StatelessWidget {
  const _GravestoneThumb({required this.file});

  final File file;
  static const double _size = 72;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.file(
      file,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      cacheWidth: coverDecodeWidth(context, _size),
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    ),
  );
}

/// Element 8: a grave on the surface with a chevron (style-b.md rule 11). Its title is the grave's
/// name; without one, the people buried in it (D5).
class _GraveCard extends StatelessWidget {
  const _GraveCard({
    super.key,
    required this.grave,
    required this.onTap,
    this.photo,
    this.selected = false,
    this.frameWidth = 2,
  });

  final GraveSummary grave;
  final VoidCallback onTap;

  /// Marked from a person's "Pochówek" or as the grave of B: a frame in amber and "zaznaczone" — never
  /// colour alone (cmentarz.md D11, v4.3; SC 1.4.1).
  final bool selected;
  final double frameWidth;

  /// Element 8 (d): the gravestone photo, when the grave has one.
  final File? photo;

  static const TextStyle _title = TextStyle(
    color: GrobingColors.text,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _muted = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 14,
  );

  @override
  Widget build(BuildContext context) {
    final List<String> people = [
      for (final p in grave.people) personName(p.givenNames, p.surname),
    ];
    final Widget title = grave.name != null
        ? Text(
            grave.name!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _title,
          )
        : people.isEmpty
        ? const Text('Grób bez wpisanych osób', style: _muted)
        : NamesText(names: people, style: _title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        child: Material(
          color: GrobingColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: selected
                ? BorderSide(color: GrobingColors.amber, width: frameWidth)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    if (photo case final File file?) _Thumbnail(file: file),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          title,
                          if (grave.name != null && people.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            NamesText(names: people, style: _muted),
                          ],
                          const SizedBox(height: 3),
                          // W2: the address is read at the cemetery (NFR-004; element 8 (c)).
                          Text(
                            addressLine(
                              graveAddress(grave.sector, grave.row, grave.plot),
                              hasPin: grave.hasPin,
                            ),
                            style: const TextStyle(
                              color: GrobingColors.text,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
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
      ),
    );
  }
}

/// Element 8 (d): a 56 dp square, corners 8 dp, cut from the middle, 12 dp before the text (cmentarz.md
/// v3). The card's text tells a screen reader what it is, so the picture stays out of it. A photo that
/// cannot be read leaves no thumbnail and no gap (cmentarz.md → States).
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file});

  final File file;
  static const double _size = 56;

  @override
  Widget build(BuildContext context) => Image.file(
    file,
    width: _size,
    height: _size,
    fit: BoxFit.cover,
    cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
    excludeFromSemantics: true,
    frameBuilder: (_, child, _, _) => Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    ),
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

/// Names after commas in at most [maxLines] lines; those that do not fit become "i jeszcze 2"
/// (05_DESIGN/cmentarz.md, element 3a). Measured, so it holds at any text size.
class NamesText extends StatelessWidget {
  const NamesText({
    super.key,
    required this.names,
    required this.style,
    this.maxLines = 2,
  });

  final List<String> names;
  final TextStyle style;
  final int maxLines;

  static String _shown(List<String> names, int count) => count == names.length
      ? names.join(', ')
      : '${names.take(count).join(', ')} i jeszcze ${names.length - count}';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final TextScaler scaler = MediaQuery.textScalerOf(context);
      final TextDirection direction = Directionality.of(context);
      bool fits(String text) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        final bool result = !painter.didExceedMaxLines;
        painter.dispose();
        return result;
      }

      int count = names.length;
      while (count > 1 && !fits(_shown(names, count))) {
        count--;
      }
      return Text(
        _shown(names, count),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    },
  );
}
