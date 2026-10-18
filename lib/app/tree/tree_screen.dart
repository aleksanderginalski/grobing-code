import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;

import '../../data/database.dart';
import '../../data/family_tree.dart';
import '../../data/kinship.dart';
import '../../data/residences.dart' show Residence, watchAllResidences;
import '../../data/wreaths.dart';
import '../dates.dart';
import '../external_link.dart' show openCastSettings, recommendedTimeout;
import '../family/union_wizard.dart' show shortPersonName;
import '../map/world_map_data.dart';
import '../people/me_picker_screen.dart';
import '../people/people_list.dart'
    show InitialsCircle, chooseMeLine, initialsOf;
import '../person/kinship_names.dart';
import '../person/person_screen.dart' show openPersonView;
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/candle.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import '../widgets/wreath.dart';
import 'connect_dialog.dart';
import 'migration_map.dart';
import 'migration_year.dart';
import 'presentation_mode.dart';
import 'tree_labels.dart';
import 'tree_layout.dart';
import 'tree_painter.dart';
import 'tree_path.dart';
import 'tree_presentation.dart';
import 'tree_time.dart';
import 'tree_time_bar.dart';

/// The scale the tree may take (drzewo.md D17, D18): at 0.4 a person's place is still 32 dp, at least the
/// 24 CSS px of WCAG 2.2 SC 2.5.8; at 2 a name is 26 sp.
const double treeMinScale = 0.4;
const double treeMaxScale = 2;

/// One press of + / − and a double tap: about one level (D18).
const double treeZoomStep = 1.45;

/// S2 (drzewo.md element 3, D18): zooming out adds a level, threshold by threshold — 1.3 · 0.85 · 0.55.
int treeLevelAtScale(double scale) => scale >= 1.3
    ? 1
    : scale >= 0.85
    ? 2
    : scale >= 0.55
    ? 3
    : 4;

const Duration _moveTime = Duration(milliseconds: 450);

/// Where the person in the middle stands: the middle across, 42 % down the tree's area.
const double _middleHeight = 0.42;

/// The Drzewo tab (05_DESIGN/drzewo.md v1.6; US-009, ISSUE-033): the family around one person, "Ja" at
/// first (AC-1). A touch puts a person in the middle (AC-2); zooming out adds the wider family level by
/// level (AC-3); a short dashed trace says where the family goes on (AC-4); the card says who the person
/// is to "ja" (AC-5). "Pokaż w drzewie" opens it with a given person in the middle ([focusPersonId], AC-6).
/// The TV icon turns it into presentation mode (element 11, AC-8; ISSUE-034): landscape, full screen, level 2
/// fitted to the screen, no buttons. "Połącz dwie osoby" lights the path between two people on the same tree
/// (elements 7–10; US-011, ISSUE-039). Since ISSUE-045 the tab has two parts, "Drzewo" and "Mapa" (drzewo.md v1.20,
/// W2): the migration map (05_DESIGN/mapa-migracji.md) shares the person in the middle, the card, the year, the
/// tempo, ▶ and presentation mode.
class TreeScreen extends StatefulWidget {
  const TreeScreen({
    super.key,
    required this.database,
    this.photos,
    this.focusPersonId,
    this.showMap = false,
  });

  final GrobingDatabase database;
  final Photos? photos;
  final int? focusPersonId;

  /// Open on the part "Mapa" — "Pokaż na mapie" in a person's view (osoba.md 9a, v2.7).
  final bool showMap;

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

/// The tab's two parts (drzewo.md element 1, v1.20).
enum _Part { tree, map }

class _TreeScreenState extends State<TreeScreen> with TickerProviderStateMixin {
  StreamSubscription<FamilyTreeData>? _subscription;
  Object? _error;
  FamilyTreeData? _family;
  TreeGraph? _graph;

  /// The part shown; the map's data comes when it is first shown (mapa-migracji.md).
  late _Part _part = widget.showMap ? _Part.map : _Part.tree;
  StreamSubscription<Map<int, List<Residence>>>? _residenceSubscription;
  Map<int, List<Residence>>? _residences;
  WorldMapData? _worldMap;
  Object? _worldError;
  MigrationYear? _migration;

  /// What everyone is to "ja", for the map's reader — the tree's [_kin] covers only the people laid out.
  Map<int, String?>? _kinAll;

  /// The person in the middle; null without "ja" and without a person given.
  int? _focus;
  int _level = 2;
  TreeLayout? _layout;

  /// The lines of [_layout] in [_year], their paths built once (SPIKE-002 M3).
  TreeLinesPainter? _lines;

  /// Time on the tree (element 6; US-010, ISSUE-037): the family's windows and the year shown — null is
  /// "dziś". The year is the view's, as the middle and the scale: kept by a touch, a level, back from a
  /// person, and into presentation and out of it (Z2 — D42); a new tree — the tab, "Pokaż w drzewie" — shows
  /// "dziś" (D37).
  TreeTime? _time;
  int? _year;

  /// ▶: a timer to the next year at the tempo chosen ([treeTempo]) — a decade, with the system's animations off
  /// (D36, D41).
  Timer? _play;

  /// People who appear and leave with the year: one layer for each group, faded together in 150 ms — an
  /// opacity on every person is a layer each, in every frame (measured on the emulator, ISSUE-037 Dev report).
  late final AnimationController _fade;
  Set<int> _fadingIn = const {};
  Set<int> _fadingOut = const {};

  /// Person → what they are to "ja", for the card and the screen reader; for the layout shown.
  Map<int, String?> _kin = const {};

  /// A move between two layouts: where each person starts (the old layout, shifted so that the person
  /// kept in place does not jump), who appears and who leaves.
  Map<int, Offset> _from = const {};
  Set<int> _entering = const {};
  Map<int, Offset> _leaving = const {};
  // Both made in initState, not lazily: a tree that never laid anyone out (an empty base, no "ja") would make
  // them first in dispose, with a ticker on an unmounted widget (found by qa's test of the states).
  late final AnimationController _move;
  Matrix4Tween? _viewMove;
  bool _linesShown = true;

  /// The view gliding back to the person in the middle when no one is left on the screen (_keepInView).
  late final AnimationController _glide;
  Matrix4Tween? _glideTo;
  Timer? _settle;

  final TransformationController _view = TransformationController();

  /// The tree's scale, read from the x axis: `getMaxScaleOnAxis()` takes the z axis too, and the level did
  /// not change in SPIKE-002's prototype (Dev report, error a).
  double _scale = 1;
  Size? _viewport;
  bool _centred = false;

  /// A finger has been on the tree since it was last put in the middle.
  bool _touched = false;

  TextScaler _scaler = TextScaler.noScaling;
  TreeMetrics _metrics = const TreeMetrics();
  bool _noMotion = false;
  final Map<String, double> _nameWidths = {};

  String _pill = '';
  bool _pillShown = false;
  Timer? _pillTimer;

  /// Presentation mode (element 11, D16): level 2 fitted to the screen, no bar, card or + / −. A tap on the
  /// empty space shows the controls — the bar at the bottom and "Zakończ prezentację" (B2 — D40) — for 5 s
  /// from the last touch of them, or as long as "Czas na działanie" asks; a second tap hides them. With a
  /// screen reader they stay: it cannot tap the empty space, which has no node (Dev report, deviation).
  bool _presenting = false;
  bool _controlsShown = false;
  Timer? _controlsTimer;
  Duration _controlsTime = _controlsDefault;
  static const Duration _controlsDefault = Duration(seconds: 5);

  /// A finger on the bar's slider: the controls stay while it drags.
  bool _sliding = false;

  /// An accessibility service reads the screen (TalkBack, Switch Access, Voice Access — Flutter sets it once
  /// one asks for the semantics tree).
  bool _readerOn = false;

  /// ▶ came to "dziś" in presentation: the year's corner says "dziś" for 3 s (L1 — D39).
  bool _todayShown = false;
  Timer? _todayTimer;

  /// "Przesyłaj na telewizor" (element 1, D30): the system's cast screen is open, or about to be — presentation
  /// comes when the app is back on top (ISSUE-036 D1); a second tap meanwhile opens nothing (D3).
  bool _casting = false;
  AppLifecycleListener? _castReturn;

  /// "Połącz dwie osoby" (elements 7–10; US-011, ISSUE-039): the path lit on the tree, or null; its line on the
  /// layout shown, run step by step ([_pathRun] 0 → 1, 0.7 s a step) once "Do" stands in the middle; how many
  /// of its people the line has reached ("Od" from the start); the banner (element 9, or 10 alone).
  TreePath? _path;
  List<List<Offset>> _pathRuns = const [];
  late final AnimationController _pathRun;
  int _reached = 0;
  bool _pathWaits = false;
  ({String? top, String text})? _banner;
  bool _bannerShown = false;
  Timer? _bannerTimer;
  Duration _bannerTime = pathBannerTime;

  /// A path or a banner on the tree: a touch, back and the rest of D49 end it first.
  bool get _lit => _path != null || _bannerShown;

  // A double tap on the tree's empty space zooms in (AC-3, SC 2.5.1). Read from raw pointer events, so a
  // tap on a person is not held back waiting for a second one.
  int _pointers = 0;
  int? _tapPointer;
  Offset? _tapDown;
  Duration? _tapDownTime;
  ({Offset at, Duration time})? _lastTap;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(vsync: this, duration: _moveTime, value: 1)
      ..addListener(_onMove)
      ..addStatusListener(_onMoveStatus);
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_onGlide);
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1,
    )..addStatusListener(_onFadeStatus);
    _pathRun = AnimationController(vsync: this)
      ..addListener(_onPathRun)
      ..addStatusListener(_onPathRunStatus);
    _view.addListener(_onView);
    _listen();
    if (_part == _Part.map) _openMap();
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = watchFamilyTree(widget.database).listen(
      _onData,
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  /// The map's data, once it is first shown: everyone's residences, kept fresh, and the world (mapa-migracji.md
  /// element 2) — read once while the app runs.
  void _openMap() {
    _residenceSubscription ??= watchAllResidences(widget.database).listen(
      (residences) {
        if (!mounted) return;
        setState(() {
          _residences = residences;
          _migration = _migrationOf(_family, _time);
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _worldError = e);
      },
    );
    if (_worldMap != null) return;
    WorldMapData.load().then(
      (world) {
        if (mounted) setState(() => _worldMap = world);
      },
      onError: (Object e) {
        if (mounted) setState(() => _worldError = e);
      },
    );
  }

  MigrationYear? _migrationOf(FamilyTreeData? family, TreeTime? time) {
    final Map<int, List<Residence>>? residences = _residences;
    if (family == null || time == null || residences == null) return null;
    return MigrationYear(
      time: time,
      residences: residences,
      people: family.people.keys,
    );
  }

  /// "Drzewo" · "Mapa" (element 1, v1.20): the person in the middle, the year, the tempo and ▶ stay; a lit path
  /// belongs to the tree and ends (D49).
  void _setPart(_Part part) {
    if (part == _part) return;
    _endPath();
    setState(() => _part = part);
    if (part == _Part.map) _openMap();
    _armControls();
  }

  /// A person touched on the map (mapa-migracji.md element 4): the one in the middle opens their view, as on the
  /// tree — not in presentation (D5) — another goes to the middle, the tree too.
  void _mapTap(int person) {
    if (person == _focus) {
      if (!_presenting) _open(person);
      return;
    }
    setState(() {
      _focus = person;
      // The tree follows, at once and centred, for the way back to it.
      _relayout(keep: person, centre: true);
    });
  }

  /// [_kinAll], worked out once a family.
  Map<int, String?> _kinOfAll(FamilyTreeData family) {
    final Map<int, String?>? known = _kinAll;
    if (known != null) return known;
    final int? me = family.meId;
    Sex? sexOf(int id) => family.people[id]?.sex;
    return _kinAll = {
      if (me != null)
        for (final int n in family.people.keys)
          n: n == me
              ? 'to ja'
              : switch (family.kin.path(me, n)) {
                  final List<KinStep> steps? => kinshipName(steps, sexOf),
                  null => 'nie wiadomo jeszcze, kim jest dla mnie',
                },
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _noMotion = MediaQuery.disableAnimationsOf(context);
    final bool reader = MediaQuery.accessibleNavigationOf(context);
    if (reader != _readerOn) {
      _readerOn = reader;
      // A reader switched on in the middle of a presentation gets the controls, and keeps them (D40). No
      // setState here: the build comes anyway.
      if (_presenting && reader) {
        _controlsShown = true;
        _controlsTimer?.cancel();
      } else if (_presenting) {
        _armControls();
      }
    }
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    if (scaler != _scaler) {
      _scaler = scaler;
      _nameWidths.clear();
      _metrics = _metricsFor(scaler, wreaths: _metrics.wreaths);
      _relayout(keep: _focus);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _residenceSubscription?.cancel();
    _pillTimer?.cancel();
    _controlsTimer?.cancel();
    _todayTimer?.cancel();
    _settle?.cancel();
    _play?.cancel();
    _bannerTimer?.cancel();
    _pathRun.dispose();
    _fade.dispose();
    _castReturn?.dispose();
    // Gone in the middle of a presentation: the phone gets its bars and orientation back all the same.
    if (_presenting) unawaited(leavePresentation());
    _move.dispose();
    _glide.dispose();
    _view
      ..removeListener(_onView)
      ..dispose();
    super.dispose();
  }

  /// A person's place grows with the system text, up to twice (80 → 160 dp, as the mini tree — osoba.md
  /// v2.2), and so does the row under the name (AC-7, D20). With wreaths it is at least 96 dp (drzewo.md
  /// v1.18) — for the whole family, not for the people shown: the place must not change when the middle
  /// moves.
  static TreeMetrics _metricsFor(TextScaler scaler, {bool wreaths = false}) {
    final double factor = (scaler.scale(13) / 13).clamp(1.0, 2.0);
    final double labelBottom =
        TreeMetrics.node + 4 + scaler.scale(13) * 1.3 + 4;
    return TreeMetrics(
      slot: wreaths ? math.max(96, 80 * factor) : 80 * factor,
      rowHeight: labelBottom + 36,
      labelBottom: labelBottom,
      wreaths: wreaths,
    );
  }

  void _onData(FamilyTreeData data) {
    if (!mounted) return;
    final bool wasLit = _path != null;
    setState(() {
      _error = null;
      _family = data;
      _graph = TreeGraph(data);
      final bool wreaths = data.people.keys.any(
        (id) => !data.wreaths.of(id).isEmpty,
      );
      if (wreaths != _metrics.wreaths) {
        _metrics = _metricsFor(_scaler, wreaths: wreaths);
      }
      final TreeTime time = TreeTime(data, now: DateTime.now().year);
      _time = time;
      _migration = _migrationOf(data, time);
      _kinAll = null;
      if (_year case final int y? when y < time.start) _year = time.start;
      // The family changed under a lit path: its people may be gone, so the light goes (element 8), as at its end
      // — the level from the scale, at least 0.4 (D46; ui review of ISSUE-039).
      if (_lit) _clearPath();
      if (wasLit) _level = treeLevelAtScale(math.max(_scale, treeMinScale));
      final int? wanted = _focus ?? widget.focusPersonId ?? data.meId;
      _focus = wanted != null && data.people.containsKey(wanted)
          ? wanted
          : data.meId;
      _relayout(keep: _focus);
    });
    final int? focus = _focus;
    if (wasLit && _scale < treeMinScale && focus != null) {
      final Matrix4? home = _centreOn(focus, treeMinScale);
      if (home != null) _view.value = home;
    }
  }

  /// Lays the tree out again for the middle and level now. [keep] stays where it is on the screen: the
  /// view's offset moves by as much as the person moved in the new layout, so nothing jumps (D18 — "zmiana
  /// poziomu zostawia osobę w środku w tym samym miejscu ekranu"). [centre] then slides the view so the
  /// new middle stands in the middle. [animate] moves the people from their old places (AC-2), unless the
  /// system asks for no animations (SC 2.3.3).
  void _relayout({int? keep, bool animate = false, bool centre = false}) {
    final TreeGraph? graph = _graph;
    final int? focus = _focus;
    final FamilyTreeData? family = _family;
    if (graph == null || focus == null || family == null) {
      _layout = null;
      return;
    }
    final TreeLayout? old = _layout;
    final Map<int, Offset> shownNow = old == null ? const {} : _positionsNow();
    final TreePath? path = _path;
    final TreeLayout next = layoutTree(
      graph,
      focus,
      _level,
      metrics: _metrics,
      also: path?.also ?? const {},
    );
    final Offset shift =
        keep != null &&
            old != null &&
            old.positions.containsKey(keep) &&
            next.positions.containsKey(keep)
        ? next.positions[keep]! - old.positions[keep]!
        : Offset.zero;
    _layout = next;
    _lines = TreeLinesPainter(next.linesAt(_time, _year));
    _pathRuns = path == null ? const [] : next.pathRoute(path.from, path.steps);
    _kin = _kinOf(family, next);
    if (old != null && shift != Offset.zero) {
      // The same picture in the new frame: the world moved by [shift] under the person kept.
      _view.value = _matrix(_scale, _offset - shift * _scale);
    }
    final bool moving = animate && !_noMotion && old != null;
    _from = {
      for (final int n in next.positions.keys)
        n: shownNow.containsKey(n) ? shownNow[n]! + shift : next.positions[n]!,
    };
    _entering = moving
        ? {
            for (final int n in next.positions.keys)
              if (!shownNow.containsKey(n)) n,
          }
        : const {};
    _leaving = moving
        ? {
            for (final MapEntry<int, Offset> e in shownNow.entries)
              if (!next.positions.containsKey(e.key)) e.key: e.value + shift,
          }
        : const {};
    final Matrix4? target = centre ? _home(focus) : null;
    if (moving) {
      _viewMove = target == null
          ? null
          : Matrix4Tween(begin: _view.value.clone(), end: target);
      _linesShown = false;
      _move.forward(from: 0);
    } else {
      _viewMove = null;
      _move.value = 1;
      _linesShown = true;
      if (target != null) _view.value = target;
    }
    if (old == null) {
      _centred = false;
      _touched = false;
    }
  }

  /// Where each person of the layout shown stands now — in the middle of a move, between its two ends.
  Map<int, Offset> _positionsNow() {
    final TreeLayout? layout = _layout;
    if (layout == null) return const {};
    final double t = Curves.easeInOut.transform(_move.value);
    return {
      for (final MapEntry<int, Offset> e in layout.positions.entries)
        e.key: Offset.lerp(_from[e.key] ?? e.value, e.value, t)!,
    };
  }

  Map<int, String?> _kinOf(FamilyTreeData family, TreeLayout layout) {
    final int? me = family.meId;
    if (me == null) return const {};
    Sex? sexOf(int id) => family.people[id]?.sex;
    return {
      for (final int n in layout.positions.keys)
        n: n == me
            ? 'to ja'
            : switch (family.kin.path(me, n)) {
                final List<KinStep> steps? => kinshipName(steps, sexOf),
                null => 'nie wiadomo jeszcze, kim jest dla mnie',
              },
    };
  }

  void _onMove() {
    final Matrix4Tween? move = _viewMove;
    if (move != null) {
      _view.value = move.transform(Curves.easeInOut.transform(_move.value));
    }
  }

  void _onMoveStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _viewMove = null;
        _entering = const {};
        _leaving = const {};
        _linesShown = true;
      });
      // "Do" stands in the middle: the path's line may run (element 8).
      if (_pathWaits) _runPath();
    }
  }

  Offset get _offset =>
      Offset(_view.value.entry(0, 3), _view.value.entry(1, 3));

  static Matrix4 _matrix(double scale, Offset offset) => Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    // All three axes, as InteractiveViewer scales: with z left at 1 its own reading of the scale breaks.
    ..scaleByDouble(scale, scale, scale, 1);

  /// The view with [person] in the middle, at the scale now — or at [scale].
  Matrix4? _centreOn(int person, [double? scale]) {
    final Size? v = _viewport;
    final Offset? p = _layout?.positions[person];
    if (v == null || p == null) return null;
    final double s = scale ?? _scale;
    return _matrix(
      s,
      Offset(
        v.width / 2 - p.dx * s,
        v.height * _middleHeight - (p.dy + 30) * s,
      ),
    );
  }

  /// Where the view rests: [person] in the middle — in presentation, the whole level fitted; with a path lit,
  /// the whole path.
  Matrix4? _home(int person) => _presenting
      ? _fitted()
      : _path != null
      ? _pathFramed()
      : _centreOn(person);

  /// F2 (drzewo.md D46): the whole path in the view — under the banner, 24 dp from the other edges, at the scale
  /// of its level (element 3), or smaller until it fits, never under [pathMinScale]. Measured on the mockup: at
  /// 100 % text 10 of 105 paths from "Ja" need less than 0.4, down to 0.34. Under 1 the names keep their size on
  /// the screen (I2), so the frame counts them, not only the people's places — at 200 % the name of "Do" went
  /// off the screen (ui review of ISSUE-039, MAJOR). A path that would reach under + / − is framed clear of them.
  Matrix4? _pathFramed() {
    final Size? v = _viewport;
    final TreeLayout? layout = _layout;
    final TreePath? path = _path;
    final FamilyTreeData? family = _family;
    if (v == null || layout == null || path == null || family == null) {
      return null;
    }
    final List<int> people = [
      for (final int n in path.people)
        if (layout.positions.containsKey(n)) n,
    ];
    if (people.isEmpty) return null;
    const double margin = 24;
    final ({String? top, String text})? banner = _banner;
    final double under = banner == null
        ? margin
        : 12 + PathBanner.heightFor(banner, v.width - 32, _scaler) + 12;
    final double top = math.min(under, v.height / 2);
    final Matrix4 framed = _pathFrame(
      layout,
      family,
      people,
      Rect.fromLTRB(margin, top, v.width - margin, v.height - margin),
    );
    if (!_underZoomButtons(framed, layout, family, people, v)) return framed;
    return _pathFrame(
      layout,
      family,
      people,
      Rect.fromLTRB(margin, top, v.width - _zoomColumn, v.height - margin),
    );
  }

  /// The column of + / − at the right of the tree: 12 dp from the edge, 48 dp wide, 12 dp more of room.
  static const double _zoomColumn = 12 + 48 + 12;

  /// [people] fitted into [area] at the scale of the level, or under it until they fit (F2).
  Matrix4 _pathFrame(
    TreeLayout layout,
    FamilyTreeData family,
    List<int> people,
    Rect area,
  ) {
    final Iterable<Offset> places = people.map((n) => layout.positions[n]!);
    final double x0 = places.map((p) => p.dx).reduce(math.min);
    final double x1 = places.map((p) => p.dx).reduce(math.max);
    final double y0 = places.map((p) => p.dy).reduce(math.min);
    final double y1 = places.map((p) => p.dy).reduce(math.max);
    final double half = _metrics.slot / 2;
    // A name on the screen under 1: as wide as written, at most its place (then "…"), as tall as its line.
    final double nameHalf = people
        .map((n) => _labelWidth(family, n) / 2)
        .reduce(math.max);
    final double nameHeight = _scaler.scale(13) * 1.3;
    const double toName = TreeMetrics.node + 4;
    double fit = math.min(
      area.width / (x1 - x0 + 2 * half),
      area.height / (y1 - y0 + _metrics.labelBottom),
    );
    if (fit < 1) {
      fit = math.min(
        fit,
        math.min(
          x1 > x0 ? (area.width - 2 * nameHalf) / (x1 - x0) : double.infinity,
          (area.height - nameHeight) / (y1 - y0 + toName),
        ),
      );
    }
    final ({double low, double high}) range = levelScales(_level);
    final double s = fit >= range.low
        ? math.min(fit, range.high)
        : math.max(pathMinScale, fit);
    // Centre what is drawn: across, the same on both sides; down, the places and, under 1, the names.
    final double bottom = math.max(
      _metrics.labelBottom * s,
      s < 1 ? toName * s + nameHeight : 0,
    );
    return _matrix(
      s,
      Offset(
        area.center.dx - (x0 + x1) / 2 * s,
        area.center.dy - (y0 * s + y1 * s + bottom) / 2,
      ),
    );
  }

  /// A name's width on the tree before the label's scale: as written with its halo, at most the place less 8.
  double _labelWidth(FamilyTreeData family, int n) =>
      math.min(_nameWidth(_label(family, n)) + 6, _metrics.slot - 8);

  /// Whether a person of the path, with their name, would stand under + / − in [view].
  bool _underZoomButtons(
    Matrix4 view,
    TreeLayout layout,
    FamilyTreeData family,
    List<int> people,
    Size v,
  ) {
    final Rect buttons = Rect.fromLTRB(
      v.width - 12 - 48,
      v.height - 12 - 104,
      v.width - 12,
      v.height - 12,
    );
    final double s = view.entry(0, 0);
    final Offset shift = Offset(view.entry(0, 3), view.entry(1, 3));
    final double nameHeight = _scaler.scale(13) * 1.3;
    for (final int n in people) {
      final Offset p = shift + layout.positions[n]! * s;
      final double width = math.max(
        _metrics.slot * s,
        s < 1 ? _labelWidth(family, n) : 0,
      );
      final double height = math.max(
        _metrics.labelBottom * s,
        s < 1 ? (TreeMetrics.node + 4) * s + nameHeight : 0,
      );
      if (Rect.fromLTWH(
        p.dx - width / 2,
        p.dy,
        width,
        height,
      ).overlaps(buttons)) {
        return true;
      }
    }
    return false;
  }

  /// Presentation (D4): the whole level in the view, 24 dp from its edges, at a scale within the tree's
  /// (D17, D18). An axis that does not fit even at the smallest scale — large text, a wide family — keeps
  /// the person in the middle in the middle; dragging shows the rest.
  Matrix4? _fitted() {
    final Size? v = _viewport;
    final TreeLayout? layout = _layout;
    if (v == null || layout == null || layout.positions.isEmpty) return null;
    final double half = _metrics.slot / 2;
    final Iterable<Offset> places = layout.positions.values;
    final Rect people = Rect.fromLTRB(
      places.map((p) => p.dx).reduce(math.min) - half,
      places.map((p) => p.dy).reduce(math.min),
      places.map((p) => p.dx).reduce(math.max) + half,
      places.map((p) => p.dy).reduce(math.max) + _metrics.labelBottom,
    );
    const double margin = 24;
    final double scale = math
        .min(
          (v.width - 2 * margin) / people.width,
          (v.height - 2 * margin) / people.height,
        )
        .clamp(treeMinScale, treeMaxScale);
    final Offset focus = layout.positions[layout.focus]!;
    // Half a dp of slack: on the axis the scale came from, size × scale is the room itself, and in floating point
    // it fell a hair over it — the level was then not fitted but put round the middle, cut at one side (seen at
    // 200 % with Michał in the middle; ui review of ISSUE-038, MAJOR).
    double along(double room, double size, double start, double focusAt) =>
        size * scale <= room - 2 * margin + 0.5
        ? (room - size * scale) / 2 - start * scale
        : room / 2 - focusAt * scale;
    return _matrix(
      scale,
      Offset(
        along(v.width, people.width, people.left, focus.dx),
        along(
          v.height,
          people.height,
          people.top,
          focus.dy + _metrics.labelBottom / 2,
        ),
      ),
    );
  }

  /// Every change of the view: the names follow the scale (D1 — I2), and a threshold crossed changes the
  /// level, the person in the middle kept in place (AC-3) — except in presentation, where level 2 stays at
  /// whatever scale fits it to the screen (D16).
  void _onView() {
    // Once the view has stood still for a moment — after a fling too — check that the tree is in it.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), _keepInView);
    final double s = _view.value.entry(0, 0);
    if ((s - _scale).abs() < 1e-4) return;
    final int level = treeLevelAtScale(s);
    setState(() {
      _scale = s;
      // A lit path keeps its level at the scale that frames it, under 0.4 too (D46); zooming ends it first.
      if (!_presenting && _path == null && level != _level && _layout != null) {
        _level = level;
        _relayout(keep: _focus, animate: true);
        _showPill();
      }
    });
  }

  /// No one on the screen — the tree panned or zoomed out of the view: it glides back to the person in the
  /// middle. Back does not move the middle (D15) and the tab on its own screen does nothing (style-b.md rule
  /// 12), so without this the tree could be lost (found on the emulator, ISSUE-033 — Dev report).
  void _keepInView() {
    final TreeLayout? layout = _layout;
    final Size? v = _viewport;
    final int? focus = _focus;
    if (!mounted || layout == null || v == null || focus == null) return;
    if (_move.isAnimating || _glide.isAnimating) return;
    final Rect seen = Rect.fromPoints(
      _view.toScene(Offset.zero),
      _view.toScene(Offset(v.width, v.height)),
    );
    final double half = _metrics.slot / 2;
    final bool anyone = layout.positions.values.any(
      (p) => seen.overlaps(
        Rect.fromLTWH(p.dx - half, p.dy, _metrics.slot, _metrics.labelBottom),
      ),
    );
    if (anyone) return;
    _glideHome(focus);
  }

  void _glideHome(int focus) {
    final Matrix4? target = _home(focus);
    if (target == null) return;
    if (_noMotion) {
      _view.value = target;
      return;
    }
    _glideTo = Matrix4Tween(begin: _view.value.clone(), end: target);
    _glide.forward(from: 0);
  }

  void _onGlide() {
    final Matrix4Tween? to = _glideTo;
    if (to != null) {
      _view.value = to.transform(Curves.easeInOut.transform(_glide.value));
    }
  }

  /// The level and its people on the tree in the year shown (D37).
  void _showPill() {
    final TreeLayout? layout = _layout;
    if (layout == null) return;
    _flash(
      'Poziom $_level · ${peopleLabel(layout.positions.keys.where(_isOn).length)}',
      const Duration(milliseconds: 1500),
    );
  }

  // ---- time (element 6; US-010, ISSUE-037) ----

  /// On the tree in the year shown: born, or maybe born (D32).
  bool _isOn(int person) => _time?.isOn(person, _year) ?? true;

  InYear _inYear(int person) => _time?.person(person, _year) ?? InYear.alive;

  /// Shows [year] — null, "dziś": who is on the tree, the lines and the trace of that year; nobody moves. Who
  /// appears or leaves fades in 150 ms (element 6) — at once with the system's animations off (SC 2.3.3).
  void _setYear(int? year) {
    final int? old = _year;
    _year = year;
    final TreeLayout? layout = _layout;
    final TreeTime? time = _time;
    if (layout == null) return;
    // Most years nobody is born and no pair joins: the same lines keep their paths and their layer.
    final List<TreeLines> lines = layout.linesAt(time, year);
    if (_lines == null || !TreeLinesPainter.same(_lines!.lines, lines)) {
      _lines = TreeLinesPainter(lines);
    }
    if (time == null || _noMotion || old == year) {
      _fadingIn = const {};
      _fadingOut = const {};
      return;
    }
    _fadingIn = {
      for (final int n in layout.positions.keys)
        if (n != layout.focus && !time.isOn(n, old) && time.isOn(n, year)) n,
    };
    _fadingOut = {
      for (final int n in layout.positions.keys)
        if (n != layout.focus && time.isOn(n, old) && !time.isOn(n, year)) n,
    };
    if (_fadingIn.isNotEmpty || _fadingOut.isNotEmpty) _fade.forward(from: 0);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _fadingIn = const {};
        _fadingOut = const {};
      });
    }
  }

  /// A year chosen by hand — dragging, the screen reader: ▶ stops (D37), a lit path ends (D49).
  void _chooseYear(int? year) {
    _endPath();
    setState(() {
      _stopPlaying();
      if (year != _year) _setYear(year);
    });
  }

  bool get _playing => _play != null;

  /// ▶ from the slider's start — or on from the year shown — to "dziś"; ❚❚ stops at the year shown (AC-3).
  void _togglePlay() {
    final TreeTime? time = _time;
    if (time == null) return;
    _endPath();
    if (_playing) {
      setState(_stopPlaying);
      _announceYear();
      return;
    }
    setState(() {
      if (_year == null) _setYear(time.start);
      _nextLater();
    });
  }

  void _stopPlaying() {
    _play?.cancel();
    _play = null;
  }

  /// While ▶ runs the reader hears no year — the row's year is out of its tree; once ▶ stops (❚❚, "dziś", a
  /// person's view) it hears the year once (element 6 → Czytnik; ui review of ISSUE-037).
  void _announceYear() {
    if (!mounted) return;
    final int? year = _year;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        year == null ? 'dziś' : 'Rok $year',
        TextDirection.ltr,
      ),
    );
  }

  /// At the tempo chosen, the same from any start: "Średnio" 10 years a second, 1880 → "dziś" in about 15 s
  /// (AC-3, D34, D41). A timer per year rather than a ticker: a frame only when the year changes, not in every
  /// vsync. With the system's animations off, a decade at once, every 2 · 1 · 0.5 s by the tempo, people at once
  /// (R2, D36). At "dziś" in presentation the corner says "dziś" for 3 s more (D39).
  void _nextLater() {
    final TreeTime? time = _time;
    if (time == null) return;
    final TreeTempo tempo = treeTempo;
    _play = Timer(_noMotion ? tempo.decadeStep : tempo.yearStep, () {
      final int? year = _year;
      if (!mounted || year == null) return;
      final int next = _noMotion ? (year ~/ 10) * 10 + 10 : year + 1;
      setState(() {
        if (next >= time.now) {
          _stopPlaying();
          _setYear(null);
          if (_presenting) _showToday();
        } else {
          _setYear(next);
          _nextLater();
        }
      });
      if (!_playing) _announceYear();
    });
  }

  /// The tempo button (D41): the next tempo for the card and presentation alike; ▶ goes on from the year shown.
  void _nextTempo() {
    setState(() {
      treeTempo = treeTempo.next;
      if (_playing) {
        _play?.cancel();
        _nextLater();
      }
    });
    _armControls();
  }

  void _showToday() {
    _todayShown = true;
    _todayTimer?.cancel();
    _todayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _todayShown = false);
    });
  }

  /// The pill at the top of the tree for [time]: the level after a change, the hint on entering presentation.
  void _flash(String text, Duration time) {
    _pill = text;
    _pillShown = true;
    _pillTimer?.cancel();
    _pillTimer = Timer(time, () {
      if (mounted) setState(() => _pillShown = false);
    });
  }

  // ---- "Połącz dwie osoby" (elements 7–10; US-011, ISSUE-039) ----

  /// Element 1 → 7: the window, then the path from "Od" to "Do".
  Future<void> _connect() async {
    final FamilyTreeData? family = _family;
    if (family == null || family.meId == null) return;
    _endPath();
    // "Czas na działanie" for the banner — text to read, as a Snackbar without an action (D43); asked as the
    // window opens, the answer is in before anyone picks a person.
    unawaited(
      recommendedTimeout(pathBannerTime, controls: false).then((time) {
        if (mounted) _bannerTime = time;
      }),
    );
    final ({int from, int to})? pair = await showConnectDialog(
      context,
      database: widget.database,
      family: family,
      photos: widget.photos,
    );
    if (pair == null || !mounted) return;
    _showPath(pair.from, pair.to);
  }

  /// Elements 8–10: "Do" moves to the middle (W2 — D45) at the lowest level that shows the whole path, the view
  /// frames the path (F2 — D46), the slider goes to "dziś" and ▶ stops (Y1 — D48), the rest fades; the line
  /// runs once "Do" stands in the middle. No path — the banner of element 10, and nothing else changes.
  void _showPath(int from, int to) {
    final FamilyTreeData? family = _family;
    final TreeGraph? graph = _graph;
    if (family == null || graph == null) return;
    final List<KinStep>? steps = family.kin.path(from, to);
    final ({String? top, String text}) banner = pathBannerText(
      family,
      from,
      to,
      steps,
    );
    if (steps == null) {
      _banner = banner;
      _showBanner();
      return;
    }
    final ({int level, Set<int> also}) at = pathLevel(graph, to, [
      from,
      for (final KinStep s in steps) s.personId,
    ]);
    final int? before = _focus;
    setState(() {
      _stopPlaying();
      if (_year != null) _setYear(null);
      _path = TreePath(from: from, to: to, steps: steps, also: at.also);
      _banner = banner;
      _reached = 1;
      _pathRun.value = 0;
      _focus = to;
      _level = at.level;
      // The banner stands where the level's pill would (D49).
      _pillTimer?.cancel();
      _pillShown = false;
      _relayout(keep: before, animate: true, centre: true);
      _pathWaits = true;
      // The path's frame is the tree's new rest: a new size before the next touch frames it again.
      _touched = false;
    });
    if (!_move.isAnimating) _runPath();
  }

  /// The line from "Od", a step every 0.7 s (D5) — with the system's animations off, all of it at once (SC
  /// 2.3.3).
  void _runPath() {
    _pathWaits = false;
    final TreePath? path = _path;
    if (path == null || !mounted) return;
    if (_noMotion || path.steps.isEmpty) {
      // At the end at once: the status "completed" brings the banner (_onPathRunStatus).
      _pathRun.value = 1;
      return;
    }
    _pathRun.duration = pathStepTime * path.steps.length;
    _pathRun.forward(from: 0);
  }

  /// Each person the line reaches gets the ring.
  void _onPathRun() {
    final TreePath? path = _path;
    if (path == null) return;
    final int reached = math.min(
      path.people.length,
      1 + (_pathRun.value * path.steps.length + 1e-6).floor(),
    );
    if (reached != _reached) setState(() => _reached = reached);
  }

  void _onPathRunStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _path != null) {
      _pathDone();
    }
  }

  /// The line has come to "Do": the banner with the name (element 9, D49).
  void _pathDone() {
    final TreePath? path = _path;
    if (path == null) return;
    setState(() => _reached = path.people.length);
    _showBanner();
  }

  /// The banner for 4 s — longer when "Czas na działanie" asks for it (D43).
  void _showBanner() {
    _bannerTimer?.cancel();
    setState(() => _bannerShown = true);
    _bannerTimer = Timer(_bannerTime, () {
      if (mounted) setState(() => _bannerShown = false);
    });
  }

  /// The end of the light (D49): a touch of the tree, back, zooming, ▶, the slider, a person's view, casting.
  /// "Do" stays in the middle at the level and scale it has; under the tree's smallest scale the view goes back
  /// to it (F2 — D46), and the people beyond the level go.
  void _endPath() {
    final TreePath? path = _path;
    if (!_lit) return;
    setState(() {
      _clearPath();
      if (path == null) return;
      final int level = treeLevelAtScale(math.max(_scale, treeMinScale));
      if (level != _level || path.also.isNotEmpty) {
        _level = level;
        _relayout(keep: _focus);
      }
    });
    if (path != null && _scale < treeMinScale) {
      final int? focus = _focus;
      final Matrix4? home = focus == null
          ? null
          : _centreOn(focus, treeMinScale);
      if (home != null) _view.value = home;
    }
  }

  /// The path's state gone, without a build — the caller builds.
  void _clearPath() {
    _bannerTimer?.cancel();
    _pathRun.stop();
    _pathWaits = false;
    _bannerShown = false;
    _path = null;
    _pathRuns = const [];
    _reached = 0;
  }

  // ---- presentation mode (element 11, D11, D16) ----

  /// "Przesyłaj na telewizor" (element 1, D30): the system's cast screen, then presentation once the app is
  /// back on top. The screen gives no result to wait for — `startActivityForResult` may answer "cancelled" at
  /// once for a protocol without one (Activity.java) — so the app's own life cycle tells: inactive when the
  /// screen opens, resumed when it closes (ISSUE-036 D1). Not "hidden": Android stops the app under the
  /// screen only seconds later, so a quick back never hides it (measured on the emulator). A phone without
  /// that screen goes straight to presentation with the hint (AC-2).
  Future<void> _cast() async {
    if (_casting) return;
    // Presentation has no "Połącz dwie osoby" (D49): the light ends here.
    _endPath();
    _casting = true;
    bool away = false;
    _castReturn = AppLifecycleListener(
      onInactive: () => away = true,
      onResume: () {
        if (!away) return;
        _stopWaiting();
        if (mounted && _treeShown && !_presenting) _present(hint: false);
      },
    );
    if (await openCastSettings() || !mounted) return;
    _stopWaiting();
    _present(hint: true);
  }

  void _stopWaiting() {
    _castReturn?.dispose();
    _castReturn = null;
    _casting = false;
  }

  /// Landscape, full screen, level 2 fitted once the screen has turned. The [hint] about casting from the
  /// quick settings only when the phone had no cast screen to open (D26, AC-2): after that screen the hint
  /// would only reach the TV.
  void _present({required bool hint}) {
    setState(() {
      _presenting = true;
      // With a reader the controls are there from the start: it cannot tap the empty space (D40).
      _controlsShown = _readerOn;
      _todayShown = false;
      // The year of the card goes along, as the person in the middle (Z2 — D42). ▶ stops: the system's
      // cast screen came in between, as a person's view stops it (D37).
      _stopPlaying();
      if (_level != 2) {
        _level = 2;
        _relayout(keep: _focus);
      }
      // Fitted when the landscape size comes (_treeArea), as a new size before any touch.
      _centred = false;
      _touched = false;
      _pillShown = false;
      if (hint) {
        _flash(
          // The function, not a tile's name: "Przesyłanie" on a Pixel, "Smart View" on a Samsung (drzewo.md D26);
          // a hard space after the one-letter word (style-b.md rule 6).
          'Obraz na telewizor: przesyłanie ekranu w\u00A0szybkich ustawieniach telefonu',
          const Duration(seconds: 4),
        );
      }
    });
    unawaited(enterPresentation());
    // "Czas na działanie" may ask for more than 5 s (D40); asked once a presentation, the answer is quick.
    unawaited(
      recommendedTimeout(_controlsDefault).then((time) {
        if (mounted) _controlsTime = time;
      }),
    );
  }

  /// "Zakończ prezentację" or back: portrait again, with the bars, the same person in the middle, level 2 at
  /// the tree's own scale.
  void _leave() {
    _controlsTimer?.cancel();
    _todayTimer?.cancel();
    setState(() {
      _presenting = false;
      _controlsShown = false;
      _sliding = false;
      _todayShown = false;
      _pillShown = false;
      _scale = 1;
      final int? focus = _focus;
      final Matrix4? home = focus == null ? null : _centreOn(focus);
      if (home != null) _view.value = home;
      // And again when the portrait size comes.
      _centred = false;
      _touched = false;
    });
    unawaited(leavePresentation());
  }

  /// A tap on the empty space in presentation: the controls, or away with them — as a video player's
  /// (Media3: hide on touch; D40). With a reader they only come.
  void _toggleControls() =>
      _controlsShown && !_readerOn ? _hideControls() : _showControls();

  /// The bar and "Zakończ prezentację"; the hint makes room for them (D25).
  void _showControls() {
    _pillTimer?.cancel();
    setState(() {
      _controlsShown = true;
      _pillShown = false;
    });
    _armControls();
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _controlsShown = false);
  }

  /// The controls go [_controlsTime] after the last touch of them — none while a finger drags the slider,
  /// none with a reader (D40). Each touch of the bar calls it again.
  void _armControls() {
    _controlsTimer?.cancel();
    if (!_presenting || !_controlsShown || _readerOn || _sliding) return;
    _controlsTimer = Timer(_controlsTime, _hideControls);
  }

  void _slide(bool on) {
    _sliding = on;
    _armControls();
  }

  /// + / − and the double tap: the point [at] of the tree's area stays where it is.
  void _zoom(double factor, Offset at) {
    _endPath();
    final double next = (_scale * factor).clamp(treeMinScale, treeMaxScale);
    if ((next - _scale).abs() < 1e-6) return;
    final Offset world = (at - _offset) / _scale;
    _view.value = _matrix(next, at - world * next);
  }

  void _zoomButton(double factor) {
    final Size? v = _viewport;
    if (v == null) return;
    _zoom(factor, Offset(v.width / 2, v.height * _middleHeight));
  }

  void _tap(int person) {
    // The first touch only ends the light, so a stray one does not move the middle (D49).
    if (_lit) {
      _endPath();
      return;
    }
    if (person == _focus) {
      // In presentation the person in the middle does not open their view — in portrait, it would end the
      // show (D5); the level is fitted anew, as after any touch of a person (element 11).
      _presenting ? _glideHome(person) : _open(person);
      return;
    }
    setState(() {
      _focus = person;
      _relayout(keep: person, animate: true, centre: true);
    });
  }

  /// A person's view stops ▶ at the year shown: back returns to it (D37; ui review of ISSUE-037 — the years
  /// ran on under the view).
  Future<void> _open(int person) {
    _endPath();
    if (_playing) {
      setState(_stopPlaying);
      _announceYear();
    }
    return _openView(person);
  }

  Future<void> _openView(int person) => openPersonView(
    context,
    widget.database,
    person,
    photos: widget.photos,
    tab: AppTab.tree,
  );

  Future<void> _chooseMe() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          MePickerScreen(database: widget.database, photos: widget.photos),
    ),
  );

  // ---- the double tap, from raw pointer events ----

  void _pointerDown(PointerDownEvent e) {
    // A finger on the tree takes over from a glide back.
    if (_glide.isAnimating) _glide.stop();
    _touched = true;
    _pointers++;
    if (_pointers == 1) {
      _tapPointer = e.pointer;
      _tapDown = e.localPosition;
      _tapDownTime = e.timeStamp;
    } else {
      _tapPointer = null;
    }
  }

  void _pointerUp(PointerUpEvent e) {
    _pointers = math.max(0, _pointers - 1);
    final Offset? down = _tapDown;
    final Duration? downTime = _tapDownTime;
    if (e.pointer != _tapPointer || down == null || downTime == null) return;
    _tapPointer = null;
    final bool tap =
        (e.localPosition - down).distance < 18 &&
        e.timeStamp - downTime < const Duration(milliseconds: 300);
    if (!tap || _onPerson(e.localPosition)) {
      _lastTap = null;
      return;
    }
    // A touch of the tree ends a lit path or a banner (D49), and does nothing more.
    if (_lit) {
      _lastTap = null;
      _endPath();
      return;
    }
    // In presentation the level stays (D16): a tap on the empty space shows the controls or hides them (D40).
    if (_presenting) {
      _toggleControls();
      return;
    }
    final ({Offset at, Duration time})? last = _lastTap;
    if (last != null &&
        e.timeStamp - last.time < const Duration(milliseconds: 300) &&
        (e.localPosition - last.at).distance < 40) {
      _lastTap = null;
      _zoom(treeZoomStep, e.localPosition);
    } else {
      _lastTap = (at: e.localPosition, time: e.timeStamp);
    }
  }

  void _pointerCancel(PointerCancelEvent e) {
    _pointers = math.max(0, _pointers - 1);
    _tapPointer = null;
  }

  bool _onPerson(Offset local) {
    final TreeLayout? layout = _layout;
    if (layout == null) return false;
    final Offset p = _view.toScene(local);
    final double half = _metrics.slot / 2;
    final double pad = _tapPad;
    // Someone not born in the year shown is no target, the empty ring of the middle neither (D33).
    return layout.positions.entries.any(
      (e) =>
          _isOn(e.key) &&
          p.dx >= e.value.dx - half &&
          p.dx <= e.value.dx + half &&
          p.dy >= e.value.dy - pad &&
          p.dy <= e.value.dy + _metrics.labelBottom + pad,
    );
  }

  // ---- building ----

  // In presentation the same widgets lose the bar, the card, + / − and the tab bar: the tree's area keeps its
  // place in the tree of widgets, so the view and the moves go on through the change.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_presenting && !_lit,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_presenting) {
        _leave();
      } else if (_lit) {
        _endPath();
      }
    },
    child: Scaffold(
      bottomNavigationBar: _presenting
          ? null
          : GrobingTabBar(
              active: AppTab.tree,
              database: widget.database,
              photos: widget.photos,
            ),
      body: SafeArea(
        bottom: _presenting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_presenting) _bar(),
            Expanded(child: _content()),
          ],
        ),
      ),
    ),
  );

  /// The tree is on the screen — not the states without it (drzewo.md → States).
  bool get _treeShown =>
      _error == null &&
      (_family?.people.isNotEmpty ?? false) &&
      _focus != null &&
      _layout != null;

  /// Element 1: "Drzewo" and, with a tree, "Połącz dwie osoby" (US-011; A1 — D44) and "Przesyłaj na telewizor"
  /// — the system's cast screen, then presentation mode (AC-8, D30). "Połącz dwie osoby" only once "ja" is
  /// chosen: the window starts from "Ja" and the banner speaks from "ja" (ISSUE-039 D3).
  Widget _bar() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 64),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          // Since v1.20 the switch "Drzewo" · "Mapa" stands where the title was (W2; R3's segmented toggle).
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _PartSwitch(
                part: _part,
                onChanged: _setPart,
                linkInTree: _treeShown && _family?.meId != null,
              ),
            ),
          ),
          // "Połącz dwie osoby" belongs to the tree: the map has no family lines to light (mapa-migracji.md D11).
          if (_treeShown && _family?.meId != null && _part == _Part.tree)
            IconButton(
              icon: const GrobingIcon(Glyphs.link, applyTextScaling: false),
              color: GrobingColors.amber,
              tooltip: 'Połącz dwie osoby',
              onPressed: _connect,
            ),
          if (_treeShown)
            // The reader hears where the tap leads, as with an external link (style-b.md rule 1); the
            // node keeps its own tap, or Switch Access and Voice Access could not press it (ISSUE-021).
            Semantics(
              button: true,
              label: 'Przesyłaj na telewizor — w ustawieniach telefonu',
              onTap: _cast,
              excludeSemantics: true,
              child: IconButton(
                icon: const GrobingIcon(Glyphs.cast, applyTextScaling: false),
                color: GrobingColors.amber,
                tooltip: 'Przesyłaj na telewizor',
                onPressed: _cast,
              ),
            ),
        ],
      ),
    ),
  );

  /// drzewo.md → States.
  Widget _content() {
    final FamilyTreeData? family = _family;
    if (_error != null) return _readError();
    if (family == null) return const Center(child: CircularProgressIndicator());
    if (family.people.isEmpty) {
      return _message(
        _part == _Part.map
            // mapa-migracji.md → States: "pusta mapa" — nobody, so no residence either.
            ? 'Tu pojawią się miejsca, w\u00A0których mieszkała rodzina. Dodasz je w\u00A0widoku osoby.'
            : 'Tu pojawi się drzewo — osoby z grobów i ich rodziny.',
      );
    }
    final int? focus = _focus;
    final TreeLayout? layout = _layout;
    if (focus == null) {
      return _message(
        'Aplikacja nie wie jeszcze, która osoba to Ty.',
        action: TextButton(
          style: TextButton.styleFrom(foregroundColor: GrobingColors.amber),
          onPressed: _chooseMe,
          child: const Text(chooseMeLine),
        ),
      );
    }
    if (layout == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _treeArea(family, layout)),
        if (!_presenting)
          // Its own layer: dragging the tree would repaint the card with it, the slider's thumb and its shadow,
          // in every frame (ISSUE-037 Dev report — on the emulator within the noise of its measure).
          RepaintBoundary(
            child: _TreeCard(
              person: family.people[focus]!,
              isMe: focus == family.meId,
              kin: family.meId == null ? null : _kin[focus],
              photos: widget.photos,
              // The map's part: where the person in the middle is in the year (mapa-migracji.md element 12).
              where: switch ((_part, _migration)) {
                (_Part.map, final MigrationYear m?) => mapWhereLine(
                  m.person(focus, _year),
                  _year,
                ),
                _ => null,
              },
              onShow: () => _open(focus),
              time: switch (_time) {
                final TreeTime time? => TreeTimeBar(
                  start: time.start,
                  now: time.now,
                  year: _year,
                  playing: _playing,
                  onPlay: _togglePlay,
                  onYear: _chooseYear,
                  tempo: treeTempo,
                  onTempo: _nextTempo,
                ),
                null => null,
              },
            ),
          ),
      ],
    );
  }

  Widget _message(String text, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 16,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    ),
  );

  Widget _readError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Nie udało się odczytać drzewa.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          style: secondaryButtonStyle,
          onPressed: () {
            setState(() => _error = null);
            _listen();
          },
          child: const Text('Spróbuj ponownie'),
        ),
      ],
    ),
  );

  Widget _treeArea(FamilyTreeData family, TreeLayout layout) => LayoutBuilder(
    builder: (context, constraints) {
      final Size size = constraints.biggest;
      final bool map = _part == _Part.map;
      // The first frame on Android can be nearly zero in size: the middle waits for the real one
      // (SPIKE-002, Dev report, error b). The map's part leaves the tree's view as it is, for the way back.
      if (!map && size.width > 1 && size.height > 1) {
        // A new size before anyone touched the tree — a keyboard closing after the choice of "ja", a turn
        // of the phone — puts the middle in the middle again.
        if (_viewport != null && _viewport != size && !_touched) {
          _centred = false;
        }
        _viewport = size;
        if (!_centred) {
          _centred = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final Matrix4? m = _focus == null ? null : _home(_focus!);
            if (!mounted || m == null) return;
            // In the middle of a move the view glides on to the new place, not the one measured for the old
            // size: a keyboard still closing after the list of people shrank the area when "Do" was chosen,
            // and the path was framed too high (found on the emulator, ISSUE-039).
            final Matrix4Tween? move = _viewMove;
            if (move != null && _move.isAnimating) {
              move.end = m;
            } else {
              _view.value = m;
            }
          });
        }
      }
      return Stack(
        children: [
          Positioned.fill(
            child: map ? _mapView(family) : _treeView(family, layout),
          ),
          if (!_presenting && !map)
            Positioned(right: 12, bottom: 12, child: _zoomButtons()),
          // In immersive sticky mode the system's swipe from the edge, which shows the bars for a moment,
          // reaches the app too: it dragged the tree away (found on the emulator) — from the top and the
          // bottom, and from the side where a three-button navigation bar stands in landscape. Along every
          // edge the tree takes no touch; the fitted level keeps 24 dp from them anyway (D4; drzewo.md D25).
          if (_presenting)
            for (final Alignment edge in const [
              Alignment.topCenter,
              Alignment.bottomCenter,
              Alignment.centerLeft,
              Alignment.centerRight,
            ])
              Align(
                alignment: edge,
                child: AbsorbPointer(
                  child: SizedBox(
                    width: edge.x == 0 ? double.infinity : 24,
                    height: edge.x == 0 ? 24 : double.infinity,
                  ),
                ),
              ),
          // L1 (D39): the year of the history in the corner, for the TV — when it is not "dziś", with the
          // controls, and for 3 s once ▶ has come to "dziś". Its own layer: it changes with every year of ▶.
          if (_presenting && (_year != null || _controlsShown || _todayShown))
            // It takes no touch, as the pill: a person under it and the empty space stay the tree's (qa's test, ui
            // review of ISSUE-038). The reader still hears it — IgnorePointer drops actions, not the label.
            Positioned(
              left: PresentationYear.left,
              top: PresentationYear.top,
              child: IgnorePointer(
                child: RepaintBoundary(child: PresentationYear(year: _year)),
              ),
            ),
          if (!map) ...[
            Positioned(top: 10, left: 16, right: 16, child: _levelPill()),
            // Elements 9 and 10: where the pill stands, which does not show with them (D49).
            Positioned(top: 12, left: 16, right: 16, child: _bannerView()),
          ],
          // B2 (D40): the bar at the bottom — the card's time row in one row — and the way out.
          if (_presenting && _controlsShown) ...[
            if (_time case final TreeTime time?)
              Positioned(
                left: PresentationBar.margin,
                right: PresentationBar.margin,
                bottom: PresentationBar.margin,
                child: RepaintBoundary(
                  child: PresentationBar(
                    child: TreeTimeBar(
                      start: time.start,
                      now: time.now,
                      year: _year,
                      playing: _playing,
                      onPlay: () {
                        _togglePlay();
                        _armControls();
                      },
                      onYear: (year) {
                        _chooseYear(year);
                        _armControls();
                      },
                      tempo: treeTempo,
                      onTempo: _nextTempo,
                      oneRow: true,
                      onSlide: _slide,
                    ),
                  ),
                ),
              ),
            // "Drzewo" · "Mapa" in the controls, at the top (drzewo.md element 11, v1.20; mapa-migracji.md element 13):
            // from the tree to the map in one touch, the same year, without casting again. In the middle of the room
            // between the year and "Zakończ prezentację", not of the screen: at 200 % on a phone held sideways the
            // three do not fit around the middle (qa, ISSUE-045 — 56 dp under the exit at 914 dp); where the words do
            // not fit, the icons alone.
            Positioned(
              top: 12,
              left: 0,
              right: 12,
              height: _ControlsTop.height,
              child: CustomMultiChildLayout(
                delegate: _ControlsTop(
                  left: PresentationYear.right(context) + 12,
                ),
                children: [
                  LayoutId(
                    id: _ControlsTop.exit,
                    child: PresentationExit(onPressed: _leave),
                  ),
                  LayoutId(
                    id: _ControlsTop.parts,
                    child: Material(
                      type: MaterialType.transparency,
                      child: _PartSwitch(
                        part: _part,
                        onChanged: _setPart,
                        filled: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );

  /// The map's part (mapa-migracji.md): the world, once it is read; until then the map's empty frame.
  Widget _mapView(FamilyTreeData family) {
    final WorldMapData? world = _worldMap;
    final MigrationYear? migration = _migration;
    if (_worldError != null) return _readError();
    if (world == null || migration == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return MigrationMap(
      world: world,
      family: family,
      migration: migration,
      year: _year,
      focus: _focus,
      kin: _kinOfAll(family),
      photos: widget.photos,
      presenting: _presenting,
      playing: _playing,
      onTap: _mapTap,
      onEmptyTap: _presenting ? _toggleControls : null,
    );
  }

  /// The tree's own area (element 4): the people of the slider's year, pinch and drag, the double tap.
  Widget _treeView(FamilyTreeData family, TreeLayout layout) {
    final Set<int> named = _visibleNames(family, layout);
    // The people of a lit path the line has reached: the ring, as the middle's (element 8).
    final Set<int> lit = {...?_path?.people.take(_reached)};
    // In the slider's year only those on the tree, the middle (its empty ring before birth) and those
    // fading out (element 6, AC-1).
    final Map<int, Widget> nodes = {
      for (final int n in layout.positions.keys)
        if (_isOn(n) || n == layout.focus || _fadingOut.contains(n))
          n: _node(family, layout, n, named.contains(n), lit.contains(n)),
    };
    return Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      child: InteractiveViewer(
        transformationController: _view,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: treeMinScale,
        maxScale: treeMaxScale,
        // In presentation dragging moves, but the level stays: no pinch (D16).
        scaleEnabled: !_presenting,
        // Two fingers end a lit path (D49); one drags it into view and keeps it.
        onInteractionUpdate: (details) {
          if (details.pointerCount > 1 && _path != null) _endPath();
        },
        child: _world(layout, nodes),
      ),
    );
  }

  /// The tree's own plane: the lines under the people. During a move the people slide and the lines wait,
  /// then fade in — no line is measured anew in each frame (SPIKE-002 M3).
  Widget _world(TreeLayout layout, Map<int, Widget> nodes) {
    final double half = _metrics.slot / 2;
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                // With a path lit, the lines off it at 30 %, as the people (element 8).
                opacity: _linesShown ? (_path != null ? pathDim : 1) : 0,
                duration: Duration(milliseconds: _noMotion ? 0 : 200),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _lines ?? TreeLinesPainter(layout.lines),
                  ),
                ),
              ),
            ),
          ),
          // The path's line over the family's lines, under the people; its own layer, as it grows every frame.
          if (_path != null && _pathRuns.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: PathLinePainter(
                      runs: _pathRuns,
                      progress: _pathRun,
                      scale: _scale,
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_move, _fade]),
                builder: (context, _) {
                  final double t = Curves.easeInOut.transform(_move.value);
                  final double pad = _tapPad;
                  Widget place(int person, Offset at, Widget child) =>
                      Positioned(
                        left: at.dx - half,
                        top: at.dy - pad,
                        width: _metrics.slot,
                        child: child,
                      );
                  final List<Widget> steady = [],
                      entering = [],
                      bornNow = [],
                      goneNow = [];
                  // With a path lit, the people off it in their own groups at 30 %, out of the reader's tree:
                  // a touch anywhere only ends the light (element 8; ISSUE-039 D6).
                  final List<Widget> steadyDim = [],
                      enteringDim = [],
                      bornNowDim = [];
                  final TreePath? path = _path;
                  for (final MapEntry<int, Offset> e
                      in layout.positions.entries) {
                    // Not on the tree in the slider's year: no node (AC-1) — the place stays empty.
                    final Widget? node = nodes[e.key];
                    if (node == null) continue;
                    final Offset at = Offset.lerp(
                      _from[e.key] ?? e.value,
                      e.value,
                      t,
                    )!;
                    final bool dim =
                        path != null && !path.members.contains(e.key);
                    (_fadingOut.contains(e.key)
                            ? goneNow
                            : _entering.contains(e.key)
                            ? (dim ? enteringDim : entering)
                            : _fadingIn.contains(e.key)
                            ? (dim ? bornNowDim : bornNow)
                            : (dim ? steadyDim : steady))
                        .add(place(e.key, at, node));
                  }
                  Widget dimmed(List<Widget> group, double opacity) =>
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: Opacity(
                            opacity: opacity * pathDim,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: group,
                            ),
                          ),
                        ),
                      );
                  // One layer for all who appear and one for all who leave: an Opacity on each person was a
                  // layer each, and the moves stuttered on the raster thread (measured on the emulator). The
                  // same for the slider's year (ISSUE-037): those born in it fade in, those not born yet out.
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (goneNow.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Opacity(
                                opacity: 1 - _fade.value,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: goneNow,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (bornNowDim.isNotEmpty)
                        dimmed(bornNowDim, _fade.value),
                      if (bornNow.isNotEmpty)
                        Positioned.fill(
                          child: Opacity(
                            opacity: _fade.value,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: bornNow,
                            ),
                          ),
                        ),
                      if (_leaving.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Opacity(
                                opacity: 1 - t,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    for (final MapEntry<int, Offset> e
                                        in _leaving.entries)
                                      place(e.key, e.value, _ghost(e.key)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (steadyDim.isNotEmpty) dimmed(steadyDim, 1),
                      ...steady,
                      if (enteringDim.isNotEmpty) dimmed(enteringDim, t),
                      if (entering.isNotEmpty)
                        Positioned.fill(
                          child: Opacity(
                            opacity: t,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: entering,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A person leaving the view in a move: just their circle and name, fading.
  Widget _ghost(int person) {
    final TreePerson? p = _family?.people[person];
    if (p == null) return const SizedBox.shrink();
    return _TreeNode(
      person: p,
      isFocus: false,
      isMe: person == _family?.meId,
      inYear: _inYear(person),
      photos: widget.photos,
      wreath: _family?.wreaths.of(person) ?? PersonWreath.empty,
      slot: _metrics.slot,
      labelHeight: _scaler.scale(13) * 1.3,
      tapPad: _tapPad,
      labelScale: _labelScale,
      showLabel: false,
      semanticsLabel: '',
      hint: null,
      onTap: null,
    );
  }

  double get _labelScale => _scale < 1 ? 1 / _scale : 1;

  /// The tap target is as tall as a person's place is wide — 80 dp, more with large text but at most the
  /// row less 16 dp — centred on the circle and the name; this is the room added above and below (ui
  /// review of ISSUE-033: 65 dp × the scale fell under 48 dp at level 3).
  double get _tapPad {
    final double content = TreeMetrics.node + 4 + _scaler.scale(13) * 1.3;
    final double target = math.min(_metrics.slot, _metrics.rowHeight - 16);
    return math.max(0, (target - content) / 2);
  }

  Widget _node(
    FamilyTreeData family,
    TreeLayout layout,
    int n,
    bool showLabel,
    bool lit,
  ) {
    final TreePerson p = family.people[n]!;
    final String who = personName(
      p.givenNames,
      p.surname,
      birthSurname: p.birthSurname,
    );
    final String? kin = _kin[n];
    final InYear inYear = _inYear(n);
    // The middle before their birth: the empty ring, for the reader too, and no target (C1, D33).
    final bool ring = inYear == InYear.notYet;
    return _TreeNode(
      key: ValueKey<int>(n),
      person: p,
      isFocus: n == layout.focus,
      lit: lit,
      isMe: n == family.meId,
      inYear: inYear,
      photos: widget.photos,
      // The middle before their birth is an empty ring: no wreath either (wieniec.md D4 in Elements D).
      wreath: ring ? PersonWreath.empty : family.wreaths.of(n),
      slot: _metrics.slot,
      labelHeight: _scaler.scale(13) * 1.3,
      tapPad: _tapPad,
      labelScale: _labelScale,
      showLabel: showLabel,
      semanticsLabel:
          [
            who,
            lifeYears(birth: p.birth, death: p.death),
            // The candle says it on the screen; without a date of death the years do not (ui review).
            if (inYear == InYear.dead && p.death == null) 'nie żyje',
            // The dashed outline says it on the screen (element 6, D32).
            if (inYear == InYear.maybeBorn) 'nie wiadomo, czy już żyje',
            if (inYear == InYear.maybeDead) 'nie wiadomo, czy jeszcze żyje',
            ?kin,
          ].join(', ') +
          (ring ? ' — przed narodzinami' : ''),
      // In presentation the person in the middle opens nothing (D5): no hint, the touch only fits the level anew.
      // With a path lit a touch only ends it (D49) — the reader hears that (ui review of ISSUE-039).
      hint: ring
          ? null
          : _path != null
          ? 'zakończ ścieżkę'
          : n != layout.focus
          ? 'w środek'
          : _presenting
          ? null
          : 'otwórz',
      onTap: ring ? null : () => _tap(n),
    );
  }

  /// I2 (D1): the names that stay readable without overlapping, the nearest to the middle first.
  Set<int> _visibleNames(FamilyTreeData family, TreeLayout layout) {
    final double k = _labelScale;
    final double fx = layout.positions[layout.focus]!.dx;
    final double maxWidth = _metrics.slot - 8;
    final double height = _scaler.scale(13) * 1.3;
    // Only the names of people on the tree in the year shown: one not born yet leaves its room to others.
    return visibleLabels([
      for (final MapEntry<int, Offset> e in layout.positions.entries)
        if (_isOn(e.key))
          LabelBox(
            id: e.key,
            centerX: e.value.dx,
            top: e.value.dy + TreeMetrics.node + 4,
            // The name and its halo's plate (3 dp on each side).
            width:
                math.min(_nameWidth(_label(family, e.key)) + 6, maxWidth) * k,
            height: height * k,
            // The path's names first (element 8), then the middle's.
            level: (_path?.members.contains(e.key) ?? false)
                ? -2
                : e.key == layout.focus
                ? -1
                : layout.levels[e.key] ?? 99,
            distance: (e.value.dx - fx).abs(),
          ),
    ], gap: 4 * k);
  }

  static String _label(FamilyTreeData family, int n) {
    if (n == family.meId) return 'Ja';
    final TreePerson p = family.people[n]!;
    return shortPersonName(p.givenNames, p.surname);
  }

  double _nameWidth(String name) => _nameWidths[name] ??= () {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: name, style: _TreeNode.nameStyle),
      textDirection: TextDirection.ltr,
      textScaler: _scaler,
      maxLines: 1,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }();

  Widget _zoomButtons() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ZoomButton(
        icon: Glyphs.add,
        tooltip: 'Przybliż — bliższa rodzina',
        onPressed: () => _zoomButton(treeZoomStep),
      ),
      const SizedBox(height: 8),
      _ZoomButton(
        icon: Glyphs.remove,
        tooltip: 'Oddal — dalsza rodzina',
        onPressed: () => _zoomButton(1 / treeZoomStep),
      ),
    ],
  );

  /// Elements 9 and 10 for a while at the top of the tree. A live region, as the pill: the reader says it once it
  /// comes, the focus staying where it is (SC 4.1.3; D43). No touch — the tree under it stays the tree's, and a
  /// touch there ends the light.
  Widget _bannerView() {
    final ({String? top, String text})? banner = _banner;
    if (banner == null) return const SizedBox.shrink();
    final Widget box = PathBanner(top: banner.top, text: banner.text);
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _bannerShown ? 1 : 0,
          duration: Duration(milliseconds: _noMotion ? 0 : 250),
          // Its own node: without one the flag went to a node above, not to the banner's text (qa's test).
          child: _bannerShown
              ? Semantics(container: true, liveRegion: true, child: box)
              : ExcludeSemantics(child: box),
        ),
      ),
    );
  }

  /// "Poziom 3 · 66 osób" for a moment after a change of level; a screen reader hears the same (element 3).
  /// In presentation, the hint about casting from the quick settings — only on a phone without the system's
  /// cast screen (element 11, D26, D30).
  Widget _levelPill() => IgnorePointer(
    child: Center(
      child: AnimatedOpacity(
        opacity: _pillShown ? 1 : 0,
        duration: Duration(milliseconds: _noMotion ? 0 : 250),
        child: Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: GrobingColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                _pill,
                textAlign: TextAlign.center,
                style: const TextStyle(color: GrobingColors.text, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One person on the tree (element 4): the circle — the profile photo in its crop, or the initials; "ja"
/// with the mark "Ja" (D14) — a candle on the dead (style-b.md rule 8), the ring in amber on the person in
/// the middle, and the first name under it. When the tree is zoomed out the name keeps its size on the
/// screen ([labelScale]) or hides ([showLabel] — I2).
class _TreeNode extends StatelessWidget {
  const _TreeNode({
    super.key,
    required this.person,
    required this.isFocus,
    this.lit = false,
    required this.isMe,
    this.inYear = InYear.alive,
    required this.photos,
    required this.slot,
    required this.labelHeight,
    required this.tapPad,
    required this.labelScale,
    required this.showLabel,
    required this.semanticsLabel,
    required this.hint,
    required this.onTap,
    this.wreath = PersonWreath.empty,
  });

  final TreePerson person;
  final bool isFocus;

  /// The wreath of the person's line, under the circle and the name (drzewo.md v1.18; wieniec.md D1) — in
  /// the node, so it fades and dims with the person's group, not on a layer of its own.
  final PersonWreath wreath;

  /// Reached by the line of a lit path (element 8): the ring and the glow of the middle (style-b.md rule 2).
  final bool lit;
  final bool isMe;

  /// The slider's year (element 6, D32): maybe alive — the outline dashed; surely dead — the candle; the
  /// person in the middle before their birth — the empty ring (D33).
  final InYear inYear;
  final Photos? photos;
  final double slot;
  final double labelHeight;

  /// Room above the circle and under the name that belongs to the tap target (_TreeScreenState._tapPad).
  final double tapPad;
  final double labelScale;
  final bool showLabel;
  final String semanticsLabel;

  /// What a touch does, for a screen reader: "w środek", "otwórz" — none in the middle of a presentation.
  final String? hint;
  final VoidCallback? onTap;

  static final double _wreathBox = WreathFrame.box(TreeMetrics.node);

  /// The name under a node: 13 sp, semi-bold (D10).
  static const TextStyle nameStyle = TextStyle(
    color: GrobingColors.text,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    if (isFocus && inYear == InYear.notYet) {
      return Semantics(
        container: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: SizedBox(
          width: slot,
          height: TreeMetrics.node + 4 + labelHeight + 2 * tapPad,
          child: Padding(
            padding: EdgeInsets.only(top: tapPad),
            child: const Align(
              alignment: Alignment.topCenter,
              child: SizedBox.square(
                dimension: TreeMetrics.node,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: GrobingColors.amber, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final bool unsure =
        inYear == InYear.maybeBorn || inYear == InYear.maybeDead;
    final Widget initials = InitialsCircle(
      text: isMe ? 'Ja' : initialsOf(person.givenNames, person.surname),
      size: TreeMetrics.node,
      accent: isMe,
      accentOutline: false,
      outline: !unsure,
    );
    Widget circle = switch ((isMe, photos, person.profile)) {
      (false, final Photos photos?, final p?) => ProfileCircle(
        file: photos.fileOf(p.relativePath),
        crop: p.crop,
        size: TreeMetrics.node,
        unreadable: initials,
      ),
      _ => initials,
    };
    final bool ring = isFocus || lit;
    if (unsure && !ring) {
      // Not known whether alive in this year: the outline dashed — the shape says it, not a fading (D32).
      circle = CustomPaint(
        foregroundPainter: const _DashedRing(GrobingColors.outline),
        child: circle,
      );
    }
    if (ring) {
      // The ring over the photo: under it, the opaque circle would hide it (osoba.md v2.2). The glow under
      // the circle: over it, it tinted the circle amber — "Ja" fell under 4.5:1 and a photo would be toned
      // (ui review of ISSUE-033, MAJOR; style-b.md rules 2 and 14).
      circle = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: GrobingColors.amber.withValues(alpha: 0.35),
              blurRadius: 14,
            ),
          ],
        ),
        child: unsure
            ? CustomPaint(
                foregroundPainter: const _DashedRing(GrobingColors.amber),
                child: circle,
              )
            : DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: GrobingColors.amber, width: 2),
                ),
                child: circle,
              ),
      );
    }
    if (inYear == InYear.dead) {
      circle = Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          const Positioned(right: -5, top: -5, child: _CandleBadge()),
        ],
      );
    }
    final String label = isMe
        ? 'Ja'
        : shortPersonName(person.givenNames, person.surname);
    // The halo in the background's colour, so the lines under the name do not cut its letters (style-b.md
    // rule 13): on the tree's even background a plate of that colour is the same halo, and a rectangle.
    // Blurred shadows and stroked letters were measured on the emulator first — a hundred of them a frame
    // made the moves and the panning stutter on the raster thread (ISSUE-033, Dev report).
    final Widget name = DecoratedBox(
      decoration: BoxDecoration(
        color: GrobingColors.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: nameStyle,
        ),
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticsLabel,
      hint: hint,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The circle is painted over the name: the glow of the person in the middle falls on the name's
        // plate, which would cut it off (seen at 200 % on the emulator). [tapPad] above and below makes the
        // target as tall as the place is wide (ui review of ISSUE-033: 65 dp fell under 48 dp at level 3).
        child: SizedBox(
          width: slot,
          height: TreeMetrics.node + 4 + labelHeight + 2 * tapPad,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Under the name's plate and the circle with its candle (wieniec.md D1); not touchable.
              if (!wreath.isEmpty)
                Positioned(
                  left: (slot - _wreathBox) / 2,
                  top:
                      tapPad +
                      TreeMetrics.node / 2 -
                      _wreathBox * WreathFrame.centreY,
                  width: _wreathBox,
                  height: _wreathBox,
                  // Sharper than the box: the tree zooms in to 1.3 and the presentation fills a television.
                  child: WreathView(
                    wreath: wreath,
                    side: _wreathBox,
                    oversample: 1.5,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: tapPad + TreeMetrics.node + 4,
                height: labelHeight,
                child: Visibility(
                  visible: showLabel,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Transform.scale(
                    scale: labelScale,
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(alignment: Alignment.topCenter, child: name),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: tapPad),
                child: Align(alignment: Alignment.topCenter, child: circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dashed outline of a person maybe alive in the slider's year (element 6, D32): 2 dp, dashes 4/3, inside
/// the circle's edge — the outline's colour, amber on the person in the middle.
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

/// The candle of the dead in the corner of a node (style-b.md rule 8, R3).
class _CandleBadge extends StatelessWidget {
  const _CandleBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: GrobingColors.background,
      shape: BoxShape.circle,
    ),
    child: const CandleIcon(size: 12, filled: true),
  );
}

/// + and − (element 3): one touch instead of two fingers (SC 2.5.1), 48 dp, the surface with an outline.
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

/// Element 5: the person in the middle — the circle with the ring, the name, and the years with who they
/// are to "ja" (D12, D13, D28 — in the author's voice: "Moja babcia", "to ja"), wrapped, never cut; "Pokaż ›" opens their view. With large system text
/// (≥ 150 %) "Pokaż" goes under the text, so the name and the kinship get the card's width (D20). Under it all,
/// the time row (element 6, US-010).
class _TreeCard extends StatelessWidget {
  const _TreeCard({
    required this.person,
    required this.isMe,
    required this.kin,
    required this.photos,
    required this.onShow,
    this.where,
    this.time,
  });

  final TreePerson person;
  final bool isMe;
  final String? kin;
  final Photos? photos;
  final VoidCallback onShow;

  /// Only in the map's part: "W 1930: Zmyślin, Polska · dziś Ukraina" (mapa-migracji.md element 12).
  final String? where;
  final Widget? time;

  @override
  Widget build(BuildContext context) {
    final bool large = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final Widget initials = InitialsCircle(
      text: isMe ? 'Ja' : initialsOf(person.givenNames, person.surname),
      accent: isMe,
    );
    final Widget avatar = ExcludeSemantics(
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: GrobingColors.amber, width: 2),
        ),
        child: switch ((isMe, photos, person.profile)) {
          (false, final Photos photos?, final p?) => ProfileCircle(
            file: photos.fileOf(p.relativePath),
            crop: p.crop,
            size: 40,
            unreadable: initials,
          ),
          _ => initials,
        },
      ),
    );
    final String years = lifeYears(birth: person.birth, death: person.death);
    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          personName(
            person.givenNames,
            person.surname,
            birthSurname: person.birthSurname,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: GrobingColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          kin == null ? years : '$years · $kin',
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        if (where case final String line) ...[
          const SizedBox(height: 2),
          Text(
            line,
            style: const TextStyle(color: GrobingColors.text, fontSize: 14),
          ),
        ],
      ],
    );
    final Widget show = TextButton(
      style: TextButton.styleFrom(foregroundColor: GrobingColors.amber),
      onPressed: onShow,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pokaż',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          GrobingIcon(Glyphs.chevronRight),
        ],
      ),
    );
    final Widget? time = this.time;
    return Material(
      color: GrobingColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 8, time == null ? 12 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (large) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                ],
              ),
              Align(alignment: Alignment.centerRight, child: show),
            ] else
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  show,
                ],
              ),
            ?time,
          ],
        ),
      ),
    );
  }
}

/// The top of presentation's controls (drzewo.md element 11; mapa-migracji.md element 13): "Zakończ prezentację" at the
/// right in its own width, and the "Drzewo" · "Mapa" switch in the middle of the room between the year and it — given
/// that room, so it shows its icons alone where its words do not fit (qa, ISSUE-045: at 200 % the switch in the middle
/// of the screen ran under the exit). Never less room than the icons: past that, as before, the two may overlap.
class _ControlsTop extends MultiChildLayoutDelegate {
  _ControlsTop({required this.left});

  static const Object exit = 'exit';
  static const Object parts = 'parts';

  /// Above the tallest exit at large text; the empty part takes no touch.
  static const double height = 96;
  static const double _gap = 12;

  /// Where the room starts: past the year in the corner.
  final double left;

  @override
  void performLayout(Size size) {
    final Size out = layoutChild(
      exit,
      BoxConstraints.loose(Size(double.infinity, size.height)),
    );
    final double outLeft = size.width - out.width;
    positionChild(exit, Offset(outLeft, 0));
    final double room = outLeft - _gap - left;
    final Size switcher = layoutChild(
      parts,
      BoxConstraints(
        maxWidth: math.max(room, _PartSwitch.iconsWidth),
        maxHeight: size.height,
      ),
    );
    positionChild(
      parts,
      Offset(
        left + (room - switcher.width) / 2,
        (out.height - switcher.height) / 2,
      ),
    );
  }

  @override
  bool shouldRelayout(_ControlsTop old) => old.left != left;
}

/// Element 1 since v1.20 (W2; mapa-migracji.md element 1): the tab's two parts as a segmented toggle, as in R3 — the
/// active one with a 2 dp outline and its icon in the accent. 40 dp high in a 48 dp target. When the words do not fit
/// the room left by the bar's icons (large system text), the icons alone, each with its tooltip.
class _PartSwitch extends StatelessWidget {
  const _PartSwitch({
    required this.part,
    required this.onChanged,
    this.linkInTree = false,
    this.filled = false,
  });

  final _Part part;
  final ValueChanged<_Part> onChanged;

  /// Presentation's controls: the capsule on the surface, in its own outline — one edge over the map, as "Zakończ
  /// prezentację" (second ui review of ISSUE-045: a 48 dp surface under the 40 dp outline drew two).
  final bool filled;

  /// The tree's part shows "Połącz dwie osoby" — the switch keeps the room it takes there in both parts.
  final bool linkInTree;

  static const TextStyle _style = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const List<(_Part, Glyph, String)> _parts = [
    (_Part.tree, Glyphs.nature, 'Drzewo'),
    (_Part.map, Glyphs.language, 'Mapa'),
  ];

  /// A segment with its words: 14 dp, the icon 20 dp, 6 dp, the words, 14 dp.
  static double _withWords(double words) => 14 + 20 + 6 + words + 14;

  /// A segment of the icon alone.
  static const double _iconOnly = 56;

  /// Both segments as icons alone: the least room the switch takes.
  static const double iconsWidth = 2 * _iconOnly;

  static const BoxDecoration _capsule = BoxDecoration(
    border: Border.fromBorderSide(BorderSide(color: GrobingColors.outline)),
    borderRadius: BorderRadius.all(Radius.circular(20)),
  );

  /// The bar's "Połącz dwie osoby", which only the tree's part has.
  static const double _linkIcon = 48;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final TextScaler scaler = MediaQuery.textScalerOf(context);
      double needed = 0;
      for (final (_, _, String label) in _parts) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: label, style: _style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        needed += _withWords(painter.width);
        painter.dispose();
      }
      // Measured against the tree's room — with "Połącz dwie osoby" beside it — in both parts: the switch must not
      // change its shape under the finger that has just changed the part (seen at 200% on 360 dp: words on the map,
      // icons on the tree).
      final double room =
          constraints.maxWidth -
          (part == _Part.map && linkInTree ? _linkIcon : 0);
      final bool words = needed <= room;
      return Stack(
        children: [
          // The capsule around both parts: 40 dp in the middle of the 48 dp row. Filled, it is Ink on the transparent
          // Material just above, so a touch's splash shows over the surface.
          Positioned.fill(
            top: 4,
            bottom: 4,
            child: filled
                ? Ink(
                    decoration: _capsule.copyWith(color: GrobingColors.surface),
                  )
                : const DecoratedBox(decoration: _capsule),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (_Part p, Glyph icon, String label) in _parts)
                _segment(p, icon, label, words),
            ],
          ),
        ],
      );
    },
  );

  Widget _segment(_Part p, Glyph icon, String label, bool words) {
    final bool on = p == part;
    return Semantics(
      button: true,
      selected: on,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(p),
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(p),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Container(
                height: 40,
                constraints: const BoxConstraints(minWidth: _iconOnly),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: on
                    ? BoxDecoration(
                        border: Border.all(
                          color: GrobingColors.amber,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      )
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GrobingIcon(
                      icon,
                      size: 20,
                      color: on ? GrobingColors.amber : GrobingColors.textMuted,
                      applyTextScaling: false,
                    ),
                    if (words) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        maxLines: 1,
                        style: _style.copyWith(color: GrobingColors.text),
                      ),
                    ],
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
