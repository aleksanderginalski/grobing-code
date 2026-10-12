import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
import '../widgets/candle.dart';
import 'cemetery_plan_map.dart';
import 'here_location.dart';
import 'map_chrome.dart';

/// What [PinScreen] returns when the pin was saved: the cemetery shows that grave (state B, cmentarz.md D36).
class PinSaved {
  const PinSaved(this.graveId);

  final int graveId;
}

/// Mode D — "Pinezka grobu" (05_DESIGN/cmentarz.md v7, elements 12, 12a; ISSUE-029, P2 — the author's choice
/// at stop #1): the candle stands in the middle of the room and the plan moves under it. With the phone's
/// position the plan follows the blue dot, so the pin stands in it and is saved as GPS with its accuracy; a
/// finger's drag, or a touch that brings a place under the candle, makes it the author's — "postawiona na
/// planie" or "na zdjęciu z góry", without an accuracy (D33). "Gdzie jestem" returns it to the dot.
///
/// A mode like F (D36): ✕ in the bar, no tab bar, the layer the map had, the other candles dimmed and
/// untouchable. A new pin switches location on (D32) and starts in the dot, or — without one — in the middle of
/// the grave's sector; a correction starts where the pin is (D35).
class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.database,
    required this.cemeteryId,
    required this.graveId,
    this.layer = MapLayer.plan,
    this.clock,
  });

  final GrobingDatabase database;
  final int cemeteryId;
  final int graveId;
  final MapLayer layer;

  /// The pin's date (tests).
  final DateTime Function()? clock;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  late final Stream<CemeteryGraves?> _graves = watchCemeteryGraves(
    widget.database,
    widget.cemeteryId,
  );
  late final Stream<CemeteryPlan?> _plan = watchCemeteryPlan(
    widget.database,
    widget.cemeteryId,
  );
  late final Stream<List<Sector>> _sectors = watchSectors(
    widget.database,
    widget.cemeteryId,
  );
  final MapController _map = MapController();

  HereTracker? _here;

  /// The pin goes with the dot (and the plan with it) — until a finger moves the plan.
  bool _follow = false;

  /// A correction moved the pin (D35: "Zapisz pinezkę" waits for it).
  bool _changed = false;

  bool _started = false;

  /// The author pinched or double-tapped: the screen keeps their zoom.
  bool _zoomChosen = false;
  bool _saving = false;
  bool _saveFailed = false;

  late MapLayer _layer = widget.layer;
  bool? _photoOnline;
  bool _askingPhoto = false;

  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _panelKey = GlobalKey();
  double _top = 120;
  double _bottom = 220;

  /// Where the pin starts when the screen places it (D32, D35).
  LatLng? _point;

  /// The plan or the photo is on the screen — the candle stands on something seen (set by the build).
  bool _mapShown = false;

  /// The photo from above is what is shown (set by the build): a pin placed on it is "na zdjęciu z góry".
  bool _photoShown = false;

  /// Waits for a double tap's zoom to end before the pin goes back into the dot.
  Timer? _zoomSettle;

  CemeteryPlan? _currentPlan;
  CemeteryGraves? _currentCemetery;

  // Made in initState, not lazily: a screen without a map never moved and created it in dispose(), where
  // looking up the ticker's ancestors is no longer allowed (found by qa, ISSUE-029).
  late final AnimationController _move;
  LatLng? _fromCentre, _toCentre;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_moveStep);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final HereLocation? location = MapHereLocation.maybeOf(context);
    if (_here == null && location != null) {
      _here = HereTracker(location)..addListener(_onHere);
    }
  }

  @override
  void dispose() {
    _zoomSettle?.cancel();
    _here?.removeListener(_onHere);
    _here?.dispose();
    _move.dispose();
    _map.dispose();
    super.dispose();
  }

  void _afterLayout(VoidCallback then) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) then();
      });

  // --- where the pin is ---

  /// The crosshair's place — the candle's tip: in the middle of the room between the card and the panel.
  Offset _crosshair(Size map) =>
      Offset(map.width / 2, _top + (map.height - _top - _bottom) / 2);

  MapCamera? get _camera {
    try {
      return _map.camera;
    } on Object {
      return null; // no map on the screen
    }
  }

  /// The phone's position when it is worth standing the pin in: precise, and at the cemetery.
  HereFix? get _usableFix {
    final HereFix? f = _here?.fix;
    if (f == null) return null;
    return _atCemetery(f.point) ? f : null;
  }

  bool _atCemetery(LatLng p) {
    final CemeteryPlan? plan = _currentPlan;
    if (plan?.status == PlanStatus.ok && plan!.areas.isNotEmpty) {
      final LatLngBounds b = planBounds(plan.areas);
      return atCemetery(
        p,
        box: (southWest: b.southWest, northEast: b.northEast),
      );
    }
    final GeoPoint? c = _currentCemetery?.point;
    return atCemetery(p, point: c == null ? null : LatLng(c.lat, c.lon));
  }

  /// The pin is the phone's: it follows the dot, and the dot is at the cemetery.
  bool get _gps => _follow && _usableFix != null;

  /// Where the pin stands now; null when there is nothing to stand it on.
  LatLng? get _pinPoint {
    if (_gps) return _usableFix!.point;
    // Without a map to stand on, only the dot (ui review M3: a pin nobody saw was saved).
    final MapCamera? camera = _camera;
    if (camera == null || !_mapShown) return null;
    return camera.screenOffsetToLatLng(_crosshair(camera.size));
  }

  /// What the pin will be saved as (element 12a, D33).
  PositionSource get _source => _gps
      ? PositionSource.gps
      : _photoShown
      ? PositionSource.satellite
      : PositionSource.plan;

  // --- the camera ---

  /// [point] under the candle, at [zoom] (the present one when null).
  void _placeAt(LatLng point, {double? zoom, bool animate = false}) {
    final MapCamera? camera = _camera;
    if (camera == null) return;
    double z = zoom ?? camera.zoom;
    // The pin placed by the screen — the start, a position — stands closer in, z18 with the paths around
    // (element 12), until the author's fingers choose the zoom: the map opens at the whole cemetery and its
    // first fit came after the start's move (seen on the emulator).
    if (!_zoomChosen && z < 18) {
      z = 18;
      animate = false;
    }
    final MapCamera at = camera.withPosition(center: point, zoom: z);
    final Offset cross = _crosshair(at.size);
    final LatLng centre = at.screenOffsetToLatLng(
      Offset(at.size.width - cross.dx, at.size.height - cross.dy),
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _move.stop();
      _map.move(centre, z);
      return;
    }
    _fromCentre = camera.center;
    _toCentre = centre;
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
      _map.camera.zoom,
    );
    if (mounted) setState(() {});
  }

  /// The first frame with the graves and the plan: the pin where it starts (D32, D35), closer in — z18, the
  /// plan's paths still around it.
  void _start(CemeteryGraves cemetery, List<Sector> sectors) {
    if (_started) return;
    final GraveSummary? grave = cemetery.graves
        .where((g) => g.id == widget.graveId)
        .firstOrNull;
    if (grave == null) return;
    _started = true;
    final LatLng start;
    if (grave.pin case final GeoPoint p?) {
      start = LatLng(p.lat, p.lon);
    } else {
      final List<GeoPoint>? zone = sectors
          .where((s) => s.name == grave.sector)
          .firstOrNull
          ?.zone;
      start = zone != null && zone.isNotEmpty
          ? LatLng(
              zone.map((p) => p.lat).reduce((a, b) => a + b) / zone.length,
              zone.map((p) => p.lon).reduce((a, b) => a + b) / zone.length,
            )
          : _middle(cemetery) ?? const LatLng(52, 19);
    }
    _point = start;
    // Two frames on: the map fits the whole cemetery in its first layout.
    _afterLayout(
      () => _afterLayout(() {
        if (_gps) return; // the first position came first
        _placeAt(start);
        setState(() {});
      }),
    );
    // Mode D switches location on (D32). A new pin is "tu jestem": in the dot as soon as there is one; a
    // correction stays where it is, the dot only shown (D35).
    if (_here != null) {
      _follow = !grave.hasPin;
      unawaited(_turnOn());
    }
  }

  LatLng? _middle(CemeteryGraves cemetery) {
    final CemeteryPlan? plan = _currentPlan;
    if (plan?.status == PlanStatus.ok && plan!.areas.isNotEmpty) {
      return planBounds(plan.areas).center;
    }
    final GeoPoint? c = cemetery.point;
    return c == null ? null : LatLng(c.lat, c.lon);
  }

  Future<void> _turnOn() async {
    final HereTracker? here = _here;
    if (here == null) return;
    await here.turnOn();
  }

  /// A new position: the plan goes with the dot while the pin follows it.
  void _onHere() {
    if (!mounted) return;
    if (_gps) {
      // A correction changes when the pin really stands in the dot (ui review M2), not at the tap.
      if (_original != null) _changed = true;
      _placeAt(_usableFix!.point, animate: true);
    }
    setState(() {});
  }

  /// A finger's drag makes the pin the author's (P2); a pinch only zooms — the dot stays under it.
  void _onMapEvent(MapEvent e) {
    switch (e.source) {
      case MapEventSource.dragStart:
      case MapEventSource.onDrag:
        if (_follow || !_changed) {
          setState(() {
            _follow = false;
            _changed = true;
            _saveFailed = false;
          });
        } else {
          setState(() {});
        }
      case MapEventSource.multiFingerEnd:
        _zoomChosen = true;
        if (_gps) _placeAt(_usableFix!.point);
        setState(() {});
      case MapEventSource.doubleTapZoomAnimationController:
        _zoomChosen = true;
        _zoomSettle?.cancel();
        _zoomSettle = Timer(const Duration(milliseconds: 300), () {
          if (mounted && _gps) _placeAt(_usableFix!.point);
        });
        setState(() {});
      case MapEventSource.onMultiFinger:
      case MapEventSource.scrollWheel:
        _zoomChosen = true;
        setState(() {});
      case MapEventSource.flingAnimationController:
        setState(() {});
      default:
        break;
    }
  }

  /// A touch brings that place under the candle — the way without dragging (SC 2.5.7), as in mode F.
  void _toCandle(LatLng point) {
    setState(() {
      _follow = false;
      _changed = true;
      _saveFailed = false;
    });
    _placeAt(point, animate: true);
  }

  /// "Gdzie jestem" in mode D: the pin back in the dot, location on when it was not.
  Future<void> _toDot() async {
    final HereTracker? here = _here;
    if (here == null) return;
    setState(() {
      _follow = true;
      _saveFailed = false;
    });
    if (!here.on) await here.turnOn();
    if (!mounted) return;
    if (here.access == HereAccess.denied || here.access == HereAccess.blocked) {
      setState(() => _follow = false);
      _noConsent(here.access!);
      return;
    }
    final HereFix? f = _usableFix;
    if (f != null) {
      _changed = true;
      _placeAt(f.point, animate: true);
    }
    setState(() {});
  }

  void _noConsent(HereAccess access) {
    final HereTracker? here = _here;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Bez zgody na lokalizację pinezki postawisz tylko ręcznie.',
          ),
          action: access == HereAccess.blocked && here != null
              ? SnackBarAction(
                  label: 'Ustawienia',
                  onPressed: () => unawaited(here.location.openAppSettings()),
                )
              : null,
        ),
      );
  }

  // --- layers ---

  Future<void> _askPhoto() async {
    final MapNetwork? net = MapNetwork.maybeOf(context);
    if (net == null || _askingPhoto) return;
    _askingPhoto = true;
    final bool online = await net.photoReachable();
    _askingPhoto = false;
    if (!mounted) return;
    setState(() {
      _photoOnline = online;
      // Without the internet mode D stands on the plan: a pin on a photo nobody sees is no pin (ui review M3).
      if (!online) _layer = MapLayer.plan;
    });
  }

  // --- saving ---

  bool get _ready =>
      !_saving && _pinPoint != null && (_changed || _original == null);

  GravePin? _original;

  Future<void> _save() async {
    final LatLng? at = _pinPoint;
    if (!_ready || at == null) return;
    final PositionSource source = _source;
    final double? accuracy = source == PositionSource.gps
        ? _usableFix?.accuracyM
        : null;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await setGravePin(
        widget.database,
        widget.graveId,
        GeoPoint(at.latitude, at.longitude),
        source,
        accuracyM: accuracy,
        clock: widget.clock,
      );
      if (mounted) Navigator.of(context).pop(PinSaved(widget.graveId));
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  void _leave() => Navigator.of(context).pop();

  // --- build ---

  void _measure() {
    final double? top = _topKey.currentContext?.size?.height;
    final double? panel = _panelKey.currentContext?.size?.height;
    bool changed = false;
    if (top != null && (top + 12 + 12 - _top).abs() > 1) {
      _top = top + 12 + 12;
      changed = true;
    }
    if (panel != null && (panel - _bottom).abs() > 1) {
      _bottom = panel;
      changed = true;
    }
    if (changed) {
      setState(() {});
      // The room changed (a larger text, the weak signal's line): the pin's place with it.
      if (_gps) {
        _afterLayout(() => _placeAt(_usableFix!.point));
      } else if (_point != null && !_changed) {
        _afterLayout(() => _placeAt(_point!));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MapNetwork? net = MapNetwork.maybeOf(context);
    return StreamBuilder<CemeteryGraves?>(
      stream: _graves,
      builder: (context, graves) => StreamBuilder<CemeteryPlan?>(
        stream: _plan,
        builder: (context, planSnapshot) => StreamBuilder<List<Sector>>(
          stream: _sectors,
          builder: (context, sectorsSnapshot) {
            final CemeteryGraves? cemetery = graves.data;
            final CemeteryPlan? plan = planSnapshot.data;
            final List<Sector> sectors = sectorsSnapshot.data ?? const [];
            _currentPlan = plan;
            _currentCemetery = cemetery;
            final GraveSummary? grave = cemetery?.graves
                .where((g) => g.id == widget.graveId)
                .firstOrNull;
            if (grave != null && !_started) _original ??= grave.pinned;
            if (cemetery != null &&
                planSnapshot.connectionState == ConnectionState.active &&
                sectorsSnapshot.hasData) {
              _start(cemetery, sectors);
            }
            if (_layer == MapLayer.photo &&
                _photoOnline == null &&
                !_askingPhoto) {
              _afterLayout(_askPhoto);
            }
            _afterLayout(_measure);
            return Scaffold(
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bar(grave),
                    Expanded(child: _body(cemetery, plan, sectors, grave, net)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Element 12: ✕ ("Anuluj"), "Pinezka grobu" and the grave's title under it.
  Widget _bar(GraveSummary? grave) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          color: GrobingColors.text,
          tooltip: 'Anuluj',
          onPressed: _leave,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pinezka grobu',
                  style: TextStyle(
                    color: GrobingColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  grave == null ? '' : graveTitle(grave),
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

  Widget _body(
    CemeteryGraves? cemetery,
    CemeteryPlan? plan,
    List<Sector> sectors,
    GraveSummary? grave,
    MapNetwork? net,
  ) {
    final bool hasPlan =
        plan?.status == PlanStatus.ok && plan!.areas.isNotEmpty;
    final bool photo =
        _layer == MapLayer.photo && net != null && cemetery?.point != null;
    final bool showsMap = cemetery != null && (photo || hasPlan);
    final bool photoGone = photo && _photoOnline == false;
    _mapShown = showsMap && !photoGone;
    _photoShown = photo && !photoGone;
    final HereFix? fix = _here?.fix;
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
                  padding: EdgeInsets.fromLTRB(16, _top, 16, _bottom + 16),
                  plan: plan,
                  center: cemetery.point,
                  candles: [
                    for (final GraveSummary g in cemetery.graves)
                      if (g.pin != null && g.id != widget.graveId)
                        (
                          id: g.id,
                          point: LatLng(g.pin!.lat, g.pin!.lon),
                          label: 'Grób',
                        ),
                  ],
                  candlesDimmed: true,
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
                  here: fix == null
                      ? null
                      : (
                          point: fix.point,
                          accuracyM: fix.accuracyM,
                          label: false,
                        ),
                  onMapTapAt: _toCandle,
                  onPointerDown: _move.stop,
                  onMapEvent: _onMapEvent,
                  roomy: true,
                  photoTiles: net?.photoTiles,
                ),
              ),
            )
          else if (cemetery != null)
            Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, _top, 24, _bottom),
                child: const Text(
                  'Planu tego cmentarza nie ma w telefonie. Pinezkę postawisz tu '
                  'tylko z GPS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          if (photoGone)
            Positioned.fill(
              child: ColoredBox(
                color: GrobingColors.background,
                child: Padding(
                  padding: EdgeInsets.only(top: _top, bottom: _bottom),
                  child: NoInternetForPhoto(
                    onBack: () => setState(() => _layer = MapLayer.plan),
                  ),
                ),
              ),
            ),
          if (_mapShown)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final Offset tip = _crosshair(c.biggest);
                      return Stack(
                        children: [
                          // Not over the dot: the dot shows where the pin stands (ui review m1).
                          if (!_gps)
                            Positioned(
                              left: tip.dx - 5,
                              top: tip.dy - 2,
                              child: Container(
                                width: 10,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: GrobingColors.background.withValues(
                                    alpha: 0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          Positioned(
                            left: tip.dx - 14,
                            top: tip.dy - 35,
                            width: 28,
                            height: 35,
                            child: const CandlePin(look: PinLook.outlined),
                          ),
                        ],
                      );
                    },
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PinInstruction(
                    maxHeight: room.maxHeight * 0.22,
                    text: _instruction(),
                  ),
                  if (showsMap) ...[
                    const SizedBox(height: 4),
                    MapBadge(
                      text: photo ? 'Ortofotomapa: GUGiK' : '© OpenStreetMap',
                      small: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_here != null)
            Positioned(
              right: 12,
              bottom: _bottom + 12,
              child: HereButton(
                state: !(_here!.on)
                    ? HereButtonState.off
                    : _gps
                    ? HereButtonState.atDot
                    : HereButtonState.away,
                accuracyM: fix?.accuracyM,
                onTap: _toDot,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: KeyedSubtree(key: _panelKey, child: _panel(grave)),
          ),
        ],
      ),
    );
  }

  /// The card's text (cmentarz.md → States v7), in the P2 wording.
  InlineSpan _instruction() {
    final HereTracker? here = _here;
    final HereAccess? access = here?.access;
    const String byHand =
        'Przesuń plan tak, żeby znicz stał na grobie. Możesz też dotknąć '
        'miejsca na planie — przesunie się pod znicz.';
    // Without a map to stand on: only the dot (Dev report → Deviations 4).
    if (!_mapShown) {
      return const TextSpan(
        text:
            'Bez planu pinezkę postawisz tylko z GPS: stań przy grobie, a znicz '
            'stanie w niebieskiej kropce.',
      );
    }
    if (access == HereAccess.denied || access == HereAccess.blocked) {
      // After the colon a small letter (style-b.md rule 6; ui review m4).
      return const TextSpan(
        text:
            'Bez zgody na lokalizację pinezkę postawisz ręcznie: przesuń plan '
            'tak, żeby znicz stał na grobie. Możesz też dotknąć miejsca na '
            'planie — przesunie się pod znicz.',
      );
    }
    if (access == HereAccess.approximate && here!.on) {
      return const TextSpan(
        text:
            'Telefon podaje tylko przybliżoną lokalizację — postaw pinezkę '
            'ręcznie. Dokładną włączysz w ustawieniach telefonu.',
      );
    }
    // Only while the candle stands in the dot; searching or away from the cemetery the pin is by hand, and
    // the panel says why (cmentarz.md → States v7, D; ui review M1).
    if (_gps) {
      return const TextSpan(
        children: [
          TextSpan(
            text: 'Stań przy grobie. ',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text:
                'Plan idzie za niebieską kropką, a znicz stoi w niej. Jeśli nie '
                'trafia w grób, przesuń plan albo dotknij miejsca grobu.',
          ),
        ],
      );
    }
    if (here == null) return const TextSpan(text: byHand);
    return const TextSpan(
      children: [
        TextSpan(text: '$byHand '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            Icons.my_location,
            size: 16,
            color: GrobingColors.text,
            semanticLabel: 'Gdzie jestem',
          ),
        ),
        TextSpan(text: ' wraca do Twojej pozycji.'),
      ],
    );
  }

  /// Element 12a: the address, what the pin will be saved as, a weak signal or a missing position, and
  /// "Anuluj" · "Zapisz pinezkę".
  Widget _panel(GraveSummary? grave) {
    final HereTracker? here = _here;
    final HereFix? fix = _usableFix;
    final GravePin? original = _original;
    final String now = pinSourceText(
      _source,
      _source == PositionSource.gps ? fix?.accuracyM : null,
    );
    final String sourceLine = original != null && !_changed
        ? 'Teraz: ${pinLine(original.source, original.accuracyM, original.recordedAt)}'
        : original != null
        ? 'Po zapisie: $now'
        : 'Pinezka: $now';
    // What is missing for the dot, while the pin is to follow it (cmentarz.md → States v7, D).
    String? missing;
    bool switchedOff = false;
    if (_follow &&
        here != null &&
        here.on &&
        here.access == HereAccess.precise) {
      if (!here.enabled) {
        switchedOff = true;
      } else if (here.fix == null) {
        missing = 'Szukam pozycji…';
      } else if (fix == null) {
        final LatLng? middle = _currentCemetery == null
            ? null
            : _middle(_currentCemetery!);
        missing = middle == null
            ? 'Jesteś poza cmentarzem.'
            : 'Jesteś poza cmentarzem '
                  '(${distanceText(here.fix!.point, middle)}).';
      }
    }
    final bool weak = _gps && weakSignal(fix?.accuracyM);
    const TextStyle line = TextStyle(color: GrobingColors.text, fontSize: 14);
    return MapPanel(
      overSystemBar: true,
      children: [
        const SizedBox(height: 12),
        Text(
          grave == null
              ? ''
              : graveAddress(grave.sector, grave.row, grave.plot) ??
                    'Bez adresu kwatery',
          style: line,
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: GrobingColors.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(sourceLine, style: line)),
            ],
          ),
        ),
        if (missing != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              missing,
              // Read at the grave: the text colour, 7:1 (W2, NFR-004; ui review m2).
              style: const TextStyle(color: GrobingColors.text, fontSize: 14),
            ),
          ),
        ],
        if (switchedOff) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 26),
              const Expanded(
                child: Text(
                  'Lokalizacja w telefonie jest wyłączona.',
                  style: TextStyle(color: GrobingColors.text, fontSize: 14),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: GrobingColors.amber,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () async {
                  await here!.location.openLocationSettings();
                  await here.recheck();
                },
                child: const Text('Włącz'),
              ),
            ],
          ),
        ],
        if (weak) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.gps_not_fixed,
                  size: 18,
                  color: GrobingColors.text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Słaby sygnał: ±${fix!.accuracyM!.round()} m. Przesuń plan '
                  'tak, żeby znicz stał na grobie.',
                  style: line,
                ),
              ),
            ],
          ),
        ],
        if (_saveFailed) ...[
          const SizedBox(height: 8),
          const PhotoErrorLine(
            'Nie udało się zapisać pinezki. Spróbuj jeszcze raz.',
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: GrobingColors.text,
                minimumSize: const Size(48, 52),
              ),
              onPressed: _leave,
              child: const Text('Anuluj'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: primaryButtonStyle,
                onPressed: _ready ? _save : null,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Zapisz pinezkę'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The grave's title as the cemetery shows it: its name, or the people in it (cmentarz.md element 8 (a)).
String graveTitle(GraveSummary g) {
  if (g.name != null) return g.name!;
  final List<String> people = [
    for (final p in g.people) personName(p.givenNames, p.surname),
  ];
  return people.isEmpty ? 'Grób bez wpisanych osób' : people.join(', ');
}

/// Element 12, the card: what to do, in place of the badges — at most [maxHeight] and scrolled inside with a
/// visible bar, as mode F's card (ui review, ISSUE-028).
class _PinInstruction extends StatefulWidget {
  const _PinInstruction({required this.maxHeight, required this.text});

  final double maxHeight;
  final InlineSpan text;

  @override
  State<_PinInstruction> createState() => _PinInstructionState();
}

class _PinInstructionState extends State<_PinInstruction> {
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.edit_location_alt_outlined,
                size: 18,
                color: GrobingColors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  widget.text,
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
