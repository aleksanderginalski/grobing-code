import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/cemeteries.dart' show GeoPoint;
import '../../data/family_tree.dart';
import '../../data/residences.dart';
import '../../dev/frame_log.dart' show measureLog;
import '../family/union_wizard.dart' show shortPersonName;
import '../map/world_map_data.dart';
import '../people/people_list.dart' show initialsOf;
import '../person/residence_screen.dart' show residenceCardLine;
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart' show peopleLabel, personName;
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'migration_year.dart';

// The migration map (05_DESIGN/mapa-migracji.md v1.1; ISSUE-045): the part "Mapa" of the Drzewo tab (W2). The world
// from bundled Natural Earth data, and on it everyone alive in the slider's year where a residence says they lived
// (element 4); a move glides, with nothing behind it (8, D25). The frame is the author's own (R4, element 10): only the
// fingers and + / − change it — people who move out of it fly past its edge, and people who move in come from
// beyond it.

/// The frame chosen by hand (R4, element 10, D6): the area the map showed after the last gesture, kept while the
/// app runs — as the tempo (drzewo.md D41) — so a new map, presentation and back show the same. Null until a
/// gesture: then every place of the family.
LatLngBounds? migrationArea;

/// The farthest a finger may zoom in: a region (D1) — the world's outline is simplified to about 6.7 km.
const double _maxZoom = 7;
const double _minZoom = 1;

/// + / − (element 11): as the tree's, about a level a touch.
const double _zoomStep = 0.536; // log2(1.45)

/// Poland, for an empty map (mapa-migracji.md → States: "pusta mapa").
final LatLngBounds _poland = LatLngBounds(
  const LatLng(49.0, 14.1),
  const LatLng(54.9, 24.2),
);

/// A person's circle (element 4) and the room a finger needs around it.
const double _circle = 32;
const double _target = 48;

/// A stack: circles 22 dp apart, up to 3, then "+N" (element 4, D3).
const double _stackStep = 22;
const double _plusWidth = 24;

class MigrationMap extends StatefulWidget {
  const MigrationMap({
    super.key,
    required this.world,
    required this.family,
    required this.migration,
    required this.year,
    required this.focus,
    required this.kin,
    required this.onTap,
    this.photos,
    this.presenting = false,
    this.playing = false,
    this.onEmptyTap,
    this.showPill = true,
    this.pillTop = 12,
    this.ride = false,
    this.shine = const {},
    this.shineLevel,
  });

  final WorldMapData world;
  final FamilyTreeData family;
  final MigrationYear migration;

  /// The slider's year; null is "dziś".
  final int? year;

  /// The person in the middle: the ring, on top of their stack (element 4).
  final int? focus;

  /// What each person is to "ja", for the screen reader.
  final Map<int, String?> kin;

  /// A person touched — not a stack, which spreads first (element 9).
  final void Function(int person) onTap;
  final Photos? photos;

  /// Presentation mode (element 13): no pill, no + / −; an empty touch is [onEmptyTap].
  final bool presenting;

  /// ▶ runs: a move glides in 0.6 s (element 8); a year chosen by hand moves in 150 ms.
  final bool playing;
  final VoidCallback? onEmptyTap;

  /// The pill (element 3) — not while the caption of ⏭ stands in its place (element 15, ISSUE-050).
  final bool showPill;

  /// Where the pill stands from the top: sideways under the top row of the switch and the icons, which stand over
  /// the map (drzewo.md element 12, D31).
  final double pillTop;

  /// The year came with ⏭: its moves glide in 0.6 s, as with ▶ (element 15) — the move is the event told.
  final bool ride;

  /// Those of the caption's page who moved: the ring and the glow, at [shineLevel]'s opacity (D30) — on the way and in
  /// the new place, at the front of their stack; more than three of them in one — the "+N" glows too.
  final Set<int> shine;
  final Animation<double>? shineLevel;

  @override
  State<MigrationMap> createState() => _MigrationMapState();
}

/// Where one person stands on the map in the year shown: their place, their place in its stack, and whether their
/// birth or death is uncertain in that year (the dashed outline).
class _Mark {
  const _Mark({
    required this.place,
    required this.index,
    required this.count,
    required this.unsure,
    required this.residence,
  });

  final ResidencePlace place;
  final int index;
  final int count;
  final bool unsure;
  final Residence residence;

  LatLng get point => _latLng(place.point);
}

/// A move in progress (element 8): from where the person was — or where their last move had got to — to the new
/// place, over [travel] from [born] on the map's clock. Each move its own: the next year does not cut it short (ui
/// review of ISSUE-045 — at "Średnio" a year is 100 ms and a move 600 ms; the circle jumped after a sixth of its way).
class _Glide {
  const _Glide(this.from, this.to, {required this.born, required this.travel});

  final LatLng from;
  final LatLng to;
  final Duration born;
  final Duration travel;

  double progress(Duration now) => travel == Duration.zero
      ? 1
      : ((now - born).inMicroseconds / travel.inMicroseconds).clamp(0.0, 1.0);

  /// Where the move has got to.
  LatLng at(Duration now) {
    final double t = Curves.easeInOut.transform(progress(now));
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}

class _MigrationMapState extends State<MigrationMap>
    with TickerProviderStateMixin {
  final MapController _map = MapController();
  Size? _size;

  Map<int, _Mark> _marks = const {};

  /// Moving people (element 8), each on their own clock.
  final Map<int, _Glide> _glides = {};

  /// Where each circle was drawn in the last frame — in its stack, its cluster, a spread or on its way: the next move
  /// starts there (second ui review of ISSUE-045: from the place's point a circle jumped up to 34 dp at the start).
  final Map<int, LatLng> _drawn = {};

  /// Who appears and who leaves with the year: one layer for each group, faded together (retro 4, R3).
  Set<int> _entering = const {};
  Map<int, _Mark> _leaving = const {};

  late final AnimationController _fade;

  /// The map's clock while something moves (element 8): it runs while a glide does.
  late final AnimationController _clock;

  /// The time of the frame being drawn: a move is born and drawn on the frames' clock — in step with them, and with
  /// the test's clock (qa, ISSUE-045: a stopwatch ran on the wall's time, beside the frames).
  static Duration get _now =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  /// The place whose stack is spread (element 9).
  ResidencePlace? _spread;

  bool _noMotion = false;
  late List<Polygon> _land;

  @override
  void initState() {
    super.initState();
    _fade =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 150),
          value: 1,
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted) {
            setState(() {
              _entering = const {};
              _leaving = const {};
            });
          }
        });
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
    _land = _landOf(widget.world);
    _marks = _compute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _noMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(MigrationMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.world, widget.world)) _land = _landOf(widget.world);
    if (old.year != widget.year ||
        !identical(old.migration, widget.migration) ||
        old.focus != widget.focus) {
      // A new year folds a spread stack (element 9).
      if (old.year != widget.year) _spread = null;
      _changeTo(_compute(), animate: old.year != widget.year);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _clock.dispose();
    _map.dispose();
    super.dispose();
  }

  static List<Polygon> _landOf(WorldMapData world) => [
    for (final WorldCountry c in world.countries)
      for (final List<LatLng> ring in c.rings)
        Polygon(
          points: ring,
          color: GrobingColors.surface,
          // Borders and coasts are decoration (D14): land and sea are equally bright, the people carry the meaning.
          borderColor: GrobingColors.outline.withValues(alpha: 0.7),
          borderStrokeWidth: 0.7,
        ),
  ];

  Map<int, _Mark> _compute() {
    final Map<int, _Mark> marks = {};
    final Map<ResidencePlace, List<int>> groups = widget.migration.groups(
      widget.year,
      first: widget.focus,
    );
    for (final MapEntry<ResidencePlace, List<int>> g in groups.entries) {
      for (final (int i, int id) in g.value.indexed) {
        final MapPersonYear s = widget.migration.person(id, widget.year);
        marks[id] = _Mark(
          place: g.key,
          index: i,
          count: g.value.length,
          unsure: s.unsure,
          residence: s.residence!,
        );
      }
    }
    return marks;
  }

  /// The year changed: who moved glides from where they were — or from where their last move had got to — to the new
  /// place (element 8), 0.6 s with ▶ and 150 ms by hand; who came fades in, who went fades out. At once with the
  /// system's animations off (SC 2.3.3; drzewo.md D36).
  void _changeTo(Map<int, _Mark> next, {required bool animate}) {
    final Map<int, _Mark> old = _marks;
    _marks = next;
    if (!animate || _noMotion) {
      _glides.clear();
      _entering = const {};
      _leaving = const {};
      _fade.value = 1;
      return;
    }
    final bool playing = widget.playing || widget.ride;
    final Duration now = _now;
    final Duration travel = Duration(milliseconds: playing ? 600 : 150);
    for (final MapEntry<int, _Mark> e in next.entries) {
      final _Mark? was = old[e.key];
      if (was == null || was.place == e.value.place) continue;
      final _Glide? going = _glides[e.key];
      _glides[e.key] = _Glide(
        _drawn[e.key] ?? going?.at(now) ?? was.point,
        e.value.point,
        born: now,
        travel: travel,
      );
    }
    _entering = {
      for (final int id in next.keys)
        if (!old.containsKey(id)) id,
    };
    _leaving = {
      for (final MapEntry<int, _Mark> e in old.entries)
        if (!next.containsKey(e.key)) e.key: e.value,
    };
    if (_entering.isNotEmpty || _leaving.isNotEmpty) _fade.forward(from: 0);
    if (_glides.isNotEmpty && !_clock.isAnimating) {
      _clock.repeat();
    }
  }

  /// Moves that have arrived go; the clock stops with the last of them.
  void _tick() {
    final Duration now = _now;
    _glides.removeWhere((_, g) => now - g.born > g.travel);
    if (_glides.isEmpty) _clock.stop();
  }

  // ---- the frame (R4, element 10) ----

  /// Every place of the family, with the margins of element 10; Poland on an empty map.
  CameraFit _everything() {
    final List<GeoPoint> points = widget.migration.allPoints();
    if (points.isEmpty) return CameraFit.bounds(bounds: _poland);
    return CameraFit.coordinates(
      coordinates: [for (final GeoPoint p in points) _latLng(p)],
      padding: widget.presenting
          ? const EdgeInsets.fromLTRB(96, 100, 96, 56)
          : const EdgeInsets.fromLTRB(64, 88, 64, 52),
      maxZoom: 5,
    );
  }

  CameraFit get _frame => switch (migrationArea) {
    final LatLngBounds area? => CameraFit.bounds(bounds: area),
    null => _everything(),
  };

  /// A new size — the phone turned for presentation, or back: the same area again (element 13).
  void _onSize(Size size) {
    if (_size == size) return;
    final bool first = _size == null;
    _size = size;
    if (first) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.fitCamera(_frame);
    });
  }

  void _keepArea() => migrationArea = _map.camera.visibleBounds;

  void _zoomBy(double steps) {
    final MapCamera c = _map.camera;
    _map.move(c.center, (c.zoom + steps).clamp(_minZoom, _maxZoom));
    _keepArea();
  }

  // ---- touches ----

  /// A person alone, or spread (element 4, 9): to the middle.
  void _tapPerson(int id) {
    setState(() => _spread = null);
    widget.onTap(id);
  }

  /// A stack or a cluster (element 4, 9): a cluster zooms to its places — at the closest zoom, or a stack of one
  /// place, it spreads (Leaflet.markercluster: zoom to the bounds, spiderfy at the bottom zoom).
  void _tapSpot(_Spot s) {
    if (s.cluster && _map.camera.zoom < _maxZoom - 0.01) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [
            for (final ResidencePlace p in s.places) _latLng(p.point),
          ],
          padding: const EdgeInsets.all(72),
          maxZoom: _maxZoom,
        ),
      );
      _keepArea();
      return;
    }
    setState(() => _spread = s.lead);
  }

  MapOptions? _options;

  void _onMapTap(TapPosition _, LatLng _) => _tapEmpty();

  void _onPosition(MapCamera camera, bool hasGesture) {
    if (hasGesture) migrationArea = camera.visibleBounds;
  }

  void _tapEmpty() {
    if (_spread != null) {
      setState(() => _spread = null);
      return;
    }
    widget.onEmptyTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool empty = !widget.migration.hasPlaces;
    return LayoutBuilder(
      builder: (context, constraints) {
        _onSize(constraints.biggest);
        return Stack(
          children: [
            Positioned.fill(
              // The map's gestures (drag, two fingers, a touch) are a node of their own: it gets a name, or the reader
              // says only "przycisk" (labeledTapTargetGuideline — qa's test). The people are nodes inside it.
              child: Semantics(
                container: true,
                label: 'Mapa świata',
                child: FlutterMap(
                  mapController: _map,
                  // Made once: new options in every build of the tree's screen (each year of ▶) made the map build its
                  // layers again (measured: build p90 16.5 ms).
                  options: _options ??= MapOptions(
                    backgroundColor: GrobingColors.water,
                    // flutter_map checks the first camera against these before the fit; its defaults are Kyiv
                    // (ISSUE-014). The fit then puts the frame where it should be.
                    initialCenter: const LatLng(52, 19),
                    initialZoom: 4,
                    initialCameraFit: _frame,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onTap: _onMapTap,
                    onPositionChanged: _onPosition,
                  ),
                  children: [
                    _LandLayer(polygons: _land),
                    _PeopleLayer(state: this),
                  ],
                ),
              ),
            ),
            if (!widget.presenting && !empty && widget.showPill)
              Positioned(
                top: widget.pillTop,
                left: 16,
                right: 16,
                child: _Pill(
                  live: !widget.playing,
                  text: mapPill(
                    widget.migration.counts(widget.year),
                    widget.year,
                  ),
                ),
              ),
            if (empty)
              const IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Tu pojawią się miejsca, w\u00A0których mieszkała rodzina. Dodasz je w\u00A0widoku osoby.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            if (!widget.presenting)
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ZoomButton(
                      icon: Glyphs.add,
                      tooltip: 'Przybliż mapę',
                      onPressed: () => _zoomBy(_zoomStep),
                    ),
                    const SizedBox(height: 8),
                    _ZoomButton(
                      icon: Glyphs.remove,
                      tooltip: 'Oddal mapę',
                      onPressed: () => _zoomBy(-_zoomStep),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

LatLng _latLng(GeoPoint p) => LatLng(p.lat, p.lon);

/// The countries (element 2). Drawn from vectors while the camera moves; once it stands still, painted once into an
/// image, which every later frame shows. ▶ moves the people in every frame, and the new renderer keeps no raster
/// cache: the world's 35 thousand points were tessellated again in each one (measured on the emulator: raster p50
/// 13 ms, 22–26% slow frames) — the falsifier of the plan, "kraje rysowane raz do obrazu".
class _LandLayer extends StatefulWidget {
  const _LandLayer({required this.polygons});

  final List<Polygon> polygons;

  @override
  State<_LandLayer> createState() => _LandLayerState();
}

class _LandLayerState extends State<_LandLayer> {
  final GlobalKey _boundary = GlobalKey();
  ui.Image? _image;
  MapCamera? _imageCamera;
  Timer? _settle;

  /// The same picture on the screen: the same zoom and the same place of the world's pixels — within half a pixel,
  /// as the camera's own numbers come back with float noise between frames.
  static bool _same(MapCamera a, MapCamera b) =>
      (a.zoom - b.zoom).abs() < 1e-6 &&
      (a.pixelOrigin - b.pixelOrigin).distance < 0.5 &&
      a.nonRotatedSize == b.nonRotatedSize;

  @override
  void didUpdateWidget(_LandLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.polygons, widget.polygons)) _drop();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _image?.dispose();
    super.dispose();
  }

  void _drop() {
    _image?.dispose();
    _image = null;
    _imageCamera = null;
  }

  @override
  Widget build(BuildContext context) {
    final MapCamera camera = MapCamera.of(context);
    final ui.Image? image = _image;
    final MapCamera? at = _imageCamera;
    if (image != null && at != null && _same(at, camera)) {
      return IgnorePointer(
        child: SizedBox.expand(
          // Painted at the screen's own pixel ratio: one pixel for one, no filtering.
          child: RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
      );
    }
    // Moving: the vectors, and a picture once the camera has stood for a moment.
    _settle?.cancel();
    _tries = 0;
    _settle = Timer(const Duration(milliseconds: 300), _capture);
    return RepaintBoundary(
      key: _boundary,
      // Even-odd, not the default path combination: that redid a path operation per frame on the map of Poland
      // (2–3 s a frame, ISSUE-023 qa).
      child: PolygonLayer(
        polygons: widget.polygons,
        painterFillMethod: PolygonPainterFillMethod.evenOdd,
      ),
    );
  }

  /// Captures tried since the camera last moved: a capture can come before the layer is painted, and with the
  /// camera standing still (▶) nothing else would try again — the vectors would stay (seen in one of the
  /// emulator's runs: 10% slow frames against 3%).
  int _tries = 0;

  void _again() {
    if (++_tries > 5 || !mounted) return;
    _settle = Timer(const Duration(milliseconds: 300), _capture);
  }

  Future<void> _capture() async {
    if (!mounted) return;
    final RenderObject? box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return _again();
    final MapCamera camera = MapCamera.of(context);
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final ui.Image image;
    try {
      image = await box.toImage(pixelRatio: ratio);
    } on Object {
      // Not painted yet (a frame in between): again in a moment.
      return _again();
    }
    if (!mounted || !_same(MapCamera.of(context), camera)) {
      image.dispose();
      return;
    }
    // With FRAME_LOG only: the measurement of ▶ can tell the picture from the vectors.
    measureLog('map land image', Duration.zero);
    setState(() {
      _drop();
      _image = image;
      _imageCamera = camera;
    });
  }
}

// Places whose stacks would touch on the screen join one cluster (Leaflet.markercluster's clusters; the candles of the
// map of Poland join the same way — README → Mapa): far out, the towns of one country would lie on each other's people.
// A touch of a cluster zooms to its places (_PeopleLayer._around).

/// The room a spread person's name is centred in.
const double _labelBox = 280;

/// One spot of the screen: one place, or several close ones (a cluster), with their people in the order of a
/// stack — the person in the middle first, then each place's own order.
class _Spot {
  _Spot(this.anchor, this.lead);

  final Offset anchor;

  /// The first place — the person in the middle's, or the most people's: it names the spot and keys its spread.
  final ResidencePlace lead;
  final List<ResidencePlace> places = [];
  final List<int> people = [];

  bool get cluster => places.length > 1;
}

/// The people, in the screen's coordinates of the camera now: everything moves with the
/// map, and the moves and fades with their animations.
class _PeopleLayer extends StatelessWidget {
  const _PeopleLayer({required this.state});

  final _MigrationMapState state;

  MigrationMap get w => state.widget;

  @override
  Widget build(BuildContext context) {
    final MapCamera camera = MapCamera.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([state._fade, state._clock]),
      builder: (context, _) => _layer(context, camera),
    );
  }

  /// The spots of the year shown: places in the order of the person in the middle, then of the most people.
  List<_Spot> _spots(Offset Function(LatLng) screen) {
    final Map<ResidencePlace, List<int>> byPlace = {};
    for (final MapEntry<int, _Mark> e in state._marks.entries) {
      (byPlace[e.value.place] ??= List.filled(
        e.value.count,
        -1,
      ))[e.value.index] = e.key;
    }
    final ResidencePlace? focusPlace = state._marks[w.focus]?.place;
    final List<ResidencePlace> order = byPlace.keys.toList()
      ..sort((a, b) {
        if (a == focusPlace) return -1;
        if (b == focusPlace) return 1;
        final int c = byPlace[b]!.length.compareTo(byPlace[a]!.length);
        if (c != 0) return c;
        final int k = a.countryCode.compareTo(b.countryCode);
        return k != 0 ? k : (a.geonamesId ?? 0).compareTo(b.geonamesId ?? 0);
      });
    final List<_Spot> spots = [];
    for (final ResidencePlace place in order) {
      final Offset p = screen(_latLng(place.point));
      _Spot? near;
      final Rect mine = _around(p, byPlace[place]!.length);
      for (final _Spot s in spots) {
        if ((s.anchor - p).distance < _target ||
            _around(s.anchor, s.people.length).overlaps(mine)) {
          near = s;
          break;
        }
      }
      final _Spot spot = near ?? _Spot(p, place);
      if (near == null) spots.add(spot);
      spot.places.add(place);
      spot.people.addAll(byPlace[place]!);
    }
    // Those of the caption go to the front of their stack, so their own circles glow, not a "+N" (D30; found on the
    // emulator — at the frame of a family on two continents a move ended in a cluster of 14).
    final Set<int> shine = w.shine;
    if (shine.isNotEmpty) {
      for (final _Spot s in spots) {
        if (!s.people.skip(3).any(shine.contains)) continue;
        final List<int> order = [
          ...s.people.where(shine.contains),
          ...s.people.where((id) => !shine.contains(id)),
        ];
        s.people
          ..clear()
          ..addAll(order);
      }
    }
    return spots;
  }

  Widget _layer(BuildContext context, MapCamera camera) {
    final Map<int, _Mark> marks = state._marks;
    final Duration now = _MigrationMapState._now;
    Offset screen(LatLng p) => camera.latLngToScreenOffset(p);
    bool moving(int id) => (state._glides[id]?.progress(now) ?? 1) < 1;
    final List<_Spot> spots = _spots(screen);
    final Map<int, (_Spot, int)> placed = {
      for (final _Spot s in spots)
        for (final (int i, int id) in s.people.indexed) id: (s, i),
    };
    bool open(_Spot s) => state._spread == s.lead && s.people.length > 1;

    Offset stackOffset(int index, int count) {
      final int shown = math.min(count, 3);
      final double width =
          (shown - 1) * _stackStep + (count > 3 ? _plusWidth : 0);
      return Offset(-width / 2 + math.min(index, 2) * _stackStep, 0);
    }

    Offset slot(int id) {
      final (_Spot s, int i) = placed[id]!;
      final int n = s.people.length;
      if (open(s)) {
        final double r = math.max(
          34 + 5.0 * n,
          _target / 2 / math.sin(math.pi / n),
        );
        final double a = -math.pi / 2 + i * 2 * math.pi / n;
        return s.anchor + Offset(math.cos(a) * r, math.sin(a) * r);
      }
      return s.anchor + stackOffset(i, n);
    }

    // A move glides from where it started to the person's place in the new stack (element 8).
    Offset at(int id) {
      final Offset to = slot(id);
      final _Glide? g = state._glides[id];
      if (g == null) return to;
      final double p = g.progress(now);
      return p >= 1
          ? to
          : Offset.lerp(screen(g.from), to, Curves.easeInOut.transform(p))!;
    }

    bool visible(int id) {
      final (_Spot s, int i) = placed[id]!;
      return i < 3 || open(s);
    }

    state._drawn.clear();
    Offset drawn(int id) {
      final Offset p = at(id);
      state._drawn[id] = camera.screenOffsetToLatLng(p);
      return p;
    }

    // No names of places or countries on the map (the author, 2026-10-17: "wystarczą awatary i kontury krajów");
    // what stays over the people is "+N".
    final List<Widget> labels = [];
    final List<Widget> boxes = [];
    final List<Widget> legs = [];
    // Those of the caption glow on one layer under the people (D30; style-b.md rule 2 — not a shadow in each circle,
    // redrawn in every frame of the pulse: the ui review of round 2): where each is drawn, and a "+N" hiding more.
    final List<(Offset, double)> glows = [];
    for (final _Spot s in spots) {
      final int n = s.people.length;
      if (open(s)) {
        for (final int id in s.people) {
          legs.add(_Leg(from: s.anchor, to: slot(id)));
        }
        continue;
      }
      if (n > 3 && !s.people.any(moving)) {
        // Someone of the caption is hidden in it still — more than three of them came (D30).
        final bool shine = s.people.skip(3).any(w.shine.contains);
        final double left =
            s.anchor.dx - _stackWidth(n) / 2 + 2 * _stackStep + 16 + 3;
        labels.add(
          Positioned(
            left: left,
            top: s.anchor.dy - 10,
            child: _PlusBadge(n - 3, shine: shine),
          ),
        );
        if (shine) glows.add((Offset(left + 13, s.anchor.dy), 10));
      }
      if (n > 1 || s.cluster) {
        // The whole stack is one target and one node for the reader: "Zmyślin: 4 osoby — rozsuń", a cluster
        // "Testowo, Zmyślice i 1 więcej: 9 osób — przybliż" (element 4).
        final double width = _stackWidth(n) + _target;
        final List<String> names = [
          for (final ResidencePlace p in s.places.take(2))
            mapPlaceLabel(p).replaceAll('\u00A0', ' '),
        ];
        final int more = s.places.length - names.length;
        boxes.add(
          Positioned(
            left: s.anchor.dx - width / 2,
            top: s.anchor.dy - _target / 2,
            width: width,
            height: _target,
            child: Semantics(
              button: true,
              label:
                  '${names.join(', ')}${more > 0 ? ' i $more więcej' : ''}: ${peopleLabel(n)}',
              hint: s.cluster ? 'przybliż' : 'rozsuń',
              onTap: () => state._tapSpot(s),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => state._tapSpot(s),
              ),
            ),
          ),
        );
      }
    }
    // A stack is drawn from its last circle to its first: the first — the one in the middle, when they are there — on
    // top, and no circle loses both its edges (second ui review of ISSUE-045: "WP" read "WI" between "Ja" and the
    // third). Where each one is drawn is kept: a move starts from there (element 8), not from the place's point.
    int topLast(int a, int b) {
      if (a == w.focus) return 1;
      if (b == w.focus) return -1;
      return placed[b]!.$2.compareTo(placed[a]!.$2);
    }

    List<Widget> people(Iterable<int> ids) {
      final List<int> order = [
        for (final int id in ids)
          if (marks.containsKey(id) && visible(id)) id,
      ]..sort(topLast);
      return [
        for (final int id in order)
          if (marks[id] case final _Mark m)
            _positioned(context, id, m, drawn(id), placed[id]!.$1),
      ];
    }

    // Leaving people stand where they were, in their old stack (element 8: they fade there).
    List<Widget> leaving() => [
      for (final MapEntry<int, _Mark> e
          in state._leaving.entries.toList()
            ..sort((a, b) => b.value.index.compareTo(a.value.index)))
        if (e.value.index < 3)
          _positioned(
            context,
            e.key,
            e.value,
            screen(e.value.point) + stackOffset(e.value.index, e.value.count),
            null,
          ),
    ];

    final int? focus = w.focus;
    final List<int> steady = [
      for (final int id in marks.keys)
        if (!state._entering.contains(id) && id != focus) id,
      if (focus != null &&
          marks.containsKey(focus) &&
          !state._entering.contains(focus))
        focus,
    ];
    final double fade = state._fade.value;
    final _Spot? spread = [
      for (final _Spot s in spots)
        if (open(s)) s,
    ].firstOrNull;
    final Animation<double>? level = w.shineLevel;
    for (final int id in w.shine) {
      if (marks.containsKey(id) && placed.containsKey(id) && visible(id)) {
        glows.add((at(id), _circle / 2));
      }
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (level != null && glows.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _ShineLayer(glows, level)),
              ),
            ),
          ),
        ExcludeSemantics(
          child: IgnorePointer(child: Stack(children: labels)),
        ),
        ...boxes,
        IgnorePointer(child: Stack(children: legs)),
        ...people(steady),
        // One layer for each group, faded together (retro 4, R3; drzewo.md — the tree's _fade).
        if (state._entering.isNotEmpty)
          Opacity(
            opacity: fade,
            child: Stack(children: people(state._entering)),
          ),
        if (state._leaving.isNotEmpty)
          IgnorePointer(
            child: Opacity(
              opacity: 1 - fade,
              child: Stack(children: leaving()),
            ),
          ),
        if (spread != null)
          ExcludeSemantics(
            child: IgnorePointer(
              child: Stack(
                children: [
                  for (final int id in spread.people)
                    _name(slot(id) + const Offset(0, 22), _first(id)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Where a stack's circles and "+N" stand, with 8 dp around: two stacks closer than that join (ui review of
  /// ISSUE-045 — a fixed 44 dp let a person stand on another stack's "+N").
  static Rect _around(Offset at, int count) => Rect.fromCenter(
    center: at,
    width: _stackWidth(count) + _circle,
    height: _circle,
  ).inflate(8);

  /// A stack's width between its first circle's centre and its end: 22 dp a circle, "+N" after the third.
  static double _stackWidth(int count) =>
      (math.min(count, 3) - 1) * _stackStep + (count > 3 ? _plusWidth : 0);

  String _first(int id) {
    if (id == w.family.meId) return 'Ja';
    final TreePerson p = w.family.people[id]!;
    return shortPersonName(p.givenNames, p.surname);
  }

  /// A person's circle at [at]. In a stack or a cluster ([spot] with others, not spread) the stack's node speaks for
  /// the reader and a touch goes to the stack; alone or spread — the person's own node, a touch to the middle.
  Widget _positioned(
    BuildContext context,
    int id,
    _Mark m,
    Offset at,
    _Spot? spot,
  ) {
    final TreePerson? p = w.family.people[id];
    if (p == null) return const SizedBox.shrink();
    final bool isFocus = id == w.focus;
    final bool together =
        spot != null && spot.people.length > 1 && state._spread != spot.lead;
    final String? kin = w.kin[id];
    final String where =
        '${mapWhen(w.year).toLowerCase()} ${residenceCardLine(m.residence)}'
            .replaceAll('\u00A0', ' ')
            .replaceAll(' · ', ', ');
    final Widget mark = _PersonCircle(
      person: p,
      isFocus: isFocus,
      unsure: m.unsure,
      photos: w.photos,
      shine: w.shine.contains(id),
    );
    return Positioned(
      left: at.dx - _target / 2,
      top: at.dy - _target / 2,
      width: _target,
      height: _target,
      child: together
          ? ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => state._tapSpot(spot),
                child: Center(child: mark),
              ),
            )
          : Semantics(
              container: true,
              button: true,
              label: [
                personName(
                  p.givenNames,
                  p.surname,
                  birthSurname: p.birthSurname,
                ),
                ?kin,
                where,
              ].join(', '),
              hint: isFocus ? (w.presenting ? null : 'otwórz') : 'w środek',
              onTap: () => state._tapPerson(id),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => state._tapPerson(id),
                child: Center(child: mark),
              ),
            ),
    );
  }

  /// A spread person's first name under their circle (element 9), centred, with a halo in the background's colour so
  /// the map's lines never cross its letters (style-b.md rule 13).
  static Widget _name(Offset at, String text) => Positioned(
    left: at.dx - _labelBox / 2,
    top: at.dy,
    width: _labelBox,
    child: _SpreadName(text),
  );
}

class _SpreadName extends StatelessWidget {
  const _SpreadName(this.text);

  final String text;

  static const TextStyle _style = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    // Labels on the map grow with the system text up to 1.3× (style-b.md rule 13).
    maxScaleFactor: 1.3,
    child: ExcludeSemantics(
      // Centred on its point: the Stack's own start would put a short name to the left of its person.
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            textAlign: TextAlign.center,
            style: _style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..strokeJoin = StrokeJoin.round
                ..color = GrobingColors.background,
            ),
          ),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            textAlign: TextAlign.center,
            style: _style.copyWith(color: GrobingColors.text),
          ),
        ],
      ),
    ),
  );
}

/// A person's circle (element 4): the profile photo in its crop or the initials — "ja" too (D26); the ring and the glow
/// under it for the person in the middle (style-b.md rule 2); the outline dashed in an uncertain year (N3).
class _PersonCircle extends StatelessWidget {
  const _PersonCircle({
    required this.person,
    required this.isFocus,
    required this.unsure,
    required this.photos,
    this.shine = false,
  });

  final TreePerson person;
  final bool isFocus;
  final bool unsure;
  final Photos? photos;

  /// One of the caption's who moved (D30): the ring of the middle; the glow under it is the layer's (_ShineLayer).
  final bool shine;

  @override
  Widget build(BuildContext context) {
    // 12 sp for the 32 dp circle — the tree's 14 sp touched the outline at 1.3× ("MW"; ui review of ISSUE-045).
    final Widget initials = Container(
      width: _circle,
      height: _circle,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: GrobingColors.surface,
        shape: BoxShape.circle,
      ),
      child: Text(
        initialsOf(person.givenNames, person.surname),
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
        maxLines: 1,
        style: const TextStyle(
          color: GrobingColors.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    // The profile photo for everyone who has one, "ja" too; the initials without (mapa-migracji.md D26 — the author: "avatary
    // zamiast inicjałów"). Who is "ja" the card and the reader say.
    Widget circle = switch ((photos, person.profile)) {
      (final Photos photos?, final p?) => ProfileCircle(
        file: photos.fileOf(p.relativePath),
        crop: p.crop,
        size: _circle,
        unreadable: initials,
      ),
      _ => initials,
    };
    // The outline on every circle, a photo too: the circle is the land's colour, so only the outline draws its edge
    // (element 4: 1.5 dp, 3.10:1 on the land). Over the photo, not under it; dashed in an uncertain year (N3).
    final bool ring = isFocus || shine;
    final Color edge = ring ? GrobingColors.amber : GrobingColors.outline;
    circle = unsure
        ? CustomPaint(foregroundPainter: _DashedRing(edge), child: circle)
        : DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: edge, width: ring ? 2.5 : 1.5),
            ),
            child: circle,
          );
    if (isFocus) {
      // The glow under the circle (style-b.md rule 2).
      circle = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: GrobingColors.amber.withValues(alpha: 0.35),
              blurRadius: 12,
            ),
          ],
        ),
        child: circle,
      );
    }
    return SizedBox.square(dimension: _circle, child: circle);
  }
}

/// The dashed outline of a person maybe alive in the year (N3): as on the tree — 2 dp, dashes 4/3.
class _DashedRing extends CustomPainter {
  const _DashedRing(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const double width = 2, dash = 4, gap = 3;
    final double r = size.shortestSide / 2 - width / 2;
    final Offset c = size.center(Offset.zero);
    final int count = (2 * math.pi * r / (dash + gap)).floor();
    final double step = 2 * math.pi / count;
    final double sweep = step * dash / (dash + gap);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    for (int i = 0; i < count; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.color != color;
}

/// A spread stack's leg from the place to a person (element 9), in the outline's colour.
class _Leg extends StatelessWidget {
  const _Leg({required this.from, required this.to});

  final Offset from;
  final Offset to;

  @override
  Widget build(BuildContext context) =>
      Positioned.fill(child: CustomPaint(painter: _LegPainter(from, to)));
}

class _LegPainter extends CustomPainter {
  const _LegPainter(this.from, this.to);

  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = GrobingColors.outline
        ..strokeWidth = 1,
    );
    canvas.drawCircle(from, 3, Paint()..color = GrobingColors.text);
  }

  @override
  bool shouldRepaint(_LegPainter old) => old.from != from || old.to != to;
}

/// "+N" after the third circle of a stack (element 4): 11 sp, the surface with the outline.
class _PlusBadge extends StatelessWidget {
  const _PlusBadge(this.more, {this.shine = false});

  final int more;

  /// Someone of the caption is hidden in the stack (D30): the ring in amber; the glow under it is the layer's.
  final bool shine;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 26),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: GrobingColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: shine
          ? Border.all(color: GrobingColors.amber, width: 2)
          : Border.all(color: GrobingColors.outline),
    ),
    child: Text(
      '+$more',
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      style: const TextStyle(
        color: GrobingColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The glow under those of the caption who moved (D30): a soft amber disc under each circle and under a "+N" hiding more
/// of them, at [level]'s opacity — one layer, a radial gradient, as on the tree (drzewo.md D73; style-b.md rule 2).
class _ShineLayer extends CustomPainter {
  _ShineLayer(this.glows, this.level) : super(repaint: level);

  final List<(Offset, double)> glows;
  final Animation<double> level;

  @override
  void paint(Canvas canvas, Size size) {
    final double a = level.value;
    if (a <= 0) return;
    final Color full = GrobingColors.amber.withValues(alpha: a);
    final Color half = GrobingColors.amber.withValues(alpha: a * 0.45);
    final Color none = GrobingColors.amber.withValues(alpha: 0);
    for (final (Offset c, double r) in glows) {
      final double outer = r + 20;
      canvas.drawCircle(
        c,
        outer,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            outer,
            [full, full, half, none],
            [0, r / outer, (r + 6) / outer, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_ShineLayer old) =>
      old.glows != glows || old.level != level;
}

/// The pill at the top of the map (element 3): how many are on the map in the year, how many without a place. A live
/// region: the reader hears it when it changes — with ▶ running it changes every year, so it speaks once ▶ stops.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.live});

  final String text;

  /// Not while ▶ runs: the pill changes 5–20 times a second then (element 3, as the year on the tree).
  final bool live;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Semantics(
        liveRegion: live,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: GrobingColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GrobingColors.text, fontSize: 13),
            ),
          ),
        ),
      ),
    ),
  );
}

/// + and − (element 11): as the tree's — 48 dp, the surface with an outline (SC 2.5.1).
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Glyph icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: GrobingColors.surface,
      shape: const CircleBorder(side: BorderSide(color: GrobingColors.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: GrobingIcon(
            icon,
            color: GrobingColors.text,
            applyTextScaling: false,
          ),
        ),
      ),
    ),
  );
}
