import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/family_tree.dart';
import '../../data/kinship.dart';
import '../dates.dart';
import '../external_link.dart' show openCastSettings;
import '../family/union_wizard.dart' show shortPersonName;
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
import 'presentation_mode.dart';
import 'tree_labels.dart';
import 'tree_layout.dart';
import 'tree_painter.dart';

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
/// fitted to the screen, no buttons.
class TreeScreen extends StatefulWidget {
  const TreeScreen({
    super.key,
    required this.database,
    this.photos,
    this.focusPersonId,
  });

  final GrobingDatabase database;
  final Photos? photos;
  final int? focusPersonId;

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> with TickerProviderStateMixin {
  StreamSubscription<FamilyTreeData>? _subscription;
  Object? _error;
  FamilyTreeData? _family;
  TreeGraph? _graph;

  /// The person in the middle; null without "ja" and without a person given.
  int? _focus;
  int _level = 2;
  TreeLayout? _layout;

  /// The lines of [_layout], their paths built once (SPIKE-002 M3).
  TreeLinesPainter? _lines;

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

  /// Presentation mode (element 11, D16): level 2 fitted to the screen, no bar, card or + / −; a tap on the
  /// empty space shows "Zakończ prezentację" for 3 s.
  bool _presenting = false;
  bool _exitShown = false;
  Timer? _exitTimer;

  /// "Przesyłaj na telewizor" (element 1, D30): the system's cast screen is open, or about to be — presentation
  /// comes when the app is back on top (ISSUE-036 D1); a second tap meanwhile opens nothing (D3).
  bool _casting = false;
  AppLifecycleListener? _castReturn;

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
    _view.addListener(_onView);
    _listen();
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _noMotion = MediaQuery.disableAnimationsOf(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    if (scaler != _scaler) {
      _scaler = scaler;
      _nameWidths.clear();
      _metrics = _metricsFor(scaler);
      _relayout(keep: _focus);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pillTimer?.cancel();
    _exitTimer?.cancel();
    _settle?.cancel();
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
  /// v2.2), and so does the row under the name (AC-7, D20).
  static TreeMetrics _metricsFor(TextScaler scaler) {
    final double factor = (scaler.scale(13) / 13).clamp(1.0, 2.0);
    final double labelBottom =
        TreeMetrics.node + 4 + scaler.scale(13) * 1.3 + 4;
    return TreeMetrics(
      slot: 80 * factor,
      rowHeight: labelBottom + 36,
      labelBottom: labelBottom,
    );
  }

  void _onData(FamilyTreeData data) {
    if (!mounted) return;
    setState(() {
      _error = null;
      _family = data;
      _graph = TreeGraph(data);
      final int? wanted = _focus ?? widget.focusPersonId ?? data.meId;
      _focus = wanted != null && data.people.containsKey(wanted)
          ? wanted
          : data.meId;
      _relayout(keep: _focus);
    });
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
    final TreeLayout next = layoutTree(graph, focus, _level, metrics: _metrics);
    final Offset shift =
        keep != null &&
            old != null &&
            old.positions.containsKey(keep) &&
            next.positions.containsKey(keep)
        ? next.positions[keep]! - old.positions[keep]!
        : Offset.zero;
    _layout = next;
    _lines = TreeLinesPainter(next);
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
    }
  }

  Offset get _offset =>
      Offset(_view.value.entry(0, 3), _view.value.entry(1, 3));

  static Matrix4 _matrix(double scale, Offset offset) => Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    // All three axes, as InteractiveViewer scales: with z left at 1 its own reading of the scale breaks.
    ..scaleByDouble(scale, scale, scale, 1);

  /// The view with [person] in the middle, at the scale now.
  Matrix4? _centreOn(int person) {
    final Size? v = _viewport;
    final Offset? p = _layout?.positions[person];
    if (v == null || p == null) return null;
    return _matrix(
      _scale,
      Offset(
        v.width / 2 - p.dx * _scale,
        v.height * _middleHeight - (p.dy + 30) * _scale,
      ),
    );
  }

  /// Where the view rests: [person] in the middle — or, in presentation, the whole level fitted.
  Matrix4? _home(int person) => _presenting ? _fitted() : _centreOn(person);

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
    double along(double room, double size, double start, double focusAt) =>
        size * scale <= room - 2 * margin
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
      if (!_presenting && level != _level && _layout != null) {
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

  void _showPill() {
    final TreeLayout? layout = _layout;
    if (layout == null) return;
    _flash(
      'Poziom $_level · ${peopleLabel(layout.count)}',
      const Duration(milliseconds: 1500),
    );
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

  // ---- presentation mode (element 11, D11, D16) ----

  /// "Przesyłaj na telewizor" (element 1, D30): the system's cast screen, then presentation once the app is
  /// back on top. The screen gives no result to wait for — `startActivityForResult` may answer "cancelled" at
  /// once for a protocol without one (Activity.java) — so the app's own life cycle tells: inactive when the
  /// screen opens, resumed when it closes (ISSUE-036 D1). Not "hidden": Android stops the app under the
  /// screen only seconds later, so a quick back never hides it (measured on the emulator). A phone without
  /// that screen goes straight to presentation with the hint (AC-2).
  Future<void> _cast() async {
    if (_casting) return;
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
      _exitShown = false;
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
          'Obraz na telewizor: przesyłanie ekranu w szybkich ustawieniach telefonu',
          const Duration(seconds: 4),
        );
      }
    });
    unawaited(enterPresentation());
  }

  /// "Zakończ prezentację" or back: portrait again, with the bars, the same person in the middle, level 2 at
  /// the tree's own scale.
  void _leave() {
    _exitTimer?.cancel();
    setState(() {
      _presenting = false;
      _exitShown = false;
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

  /// A tap on the empty space in presentation: "Zakończ prezentację" for 3 s. The hint makes room for it.
  void _showExit() {
    _exitTimer?.cancel();
    _pillTimer?.cancel();
    setState(() {
      _exitShown = true;
      _pillShown = false;
    });
    _exitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _exitShown = false);
    });
  }

  /// + / − and the double tap: the point [at] of the tree's area stays where it is.
  void _zoom(double factor, Offset at) {
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

  Future<void> _open(int person) => openPersonView(
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
    // In presentation the level stays (D16): a tap on the empty space only offers the way out.
    if (_presenting) {
      _showExit();
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
    return layout.positions.values.any(
      (n) =>
          p.dx >= n.dx - half &&
          p.dx <= n.dx + half &&
          p.dy >= n.dy - pad &&
          p.dy <= n.dy + _metrics.labelBottom + pad,
    );
  }

  // ---- building ----

  // In presentation the same widgets lose the bar, the card, + / − and the tab bar: the tree's area keeps its
  // place in the tree of widgets, so the view and the moves go on through the change.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_presenting,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _presenting) _leave();
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

  /// Element 1: "Drzewo" and, with a tree, "Przesyłaj na telewizor" — the system's cast screen, then
  /// presentation mode (AC-8, D30). "Połącz dwie osoby" comes with US-011.
  Widget _bar() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 64),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: const Text(
                'Drzewo',
                style: TextStyle(
                  color: GrobingColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
                icon: const Icon(Icons.cast_outlined),
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
      return _message('Tu pojawi się drzewo — osoby z grobów i ich rodziny.');
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
          _TreeCard(
            person: family.people[focus]!,
            isMe: focus == family.meId,
            kin: family.meId == null ? null : _kin[focus],
            photos: widget.photos,
            onShow: () => _open(focus),
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
      // The first frame on Android can be nearly zero in size: the middle waits for the real one
      // (SPIKE-002, Dev report, error b).
      if (size.width > 1 && size.height > 1) {
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
            if (mounted && m != null) _view.value = m;
          });
        }
      }
      final Set<int> named = _visibleNames(family, layout);
      final Map<int, Widget> nodes = {
        for (final int n in layout.positions.keys)
          n: _node(family, layout, n, named.contains(n)),
      };
      return Stack(
        children: [
          Positioned.fill(
            child: Listener(
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
                child: _world(layout, nodes),
              ),
            ),
          ),
          if (!_presenting)
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
          Positioned(top: 10, left: 16, right: 16, child: _levelPill()),
          if (_presenting && _exitShown)
            Positioned(top: 12, right: 12, child: _exitButton()),
        ],
      );
    },
  );

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
                opacity: _linesShown ? 1 : 0,
                duration: Duration(milliseconds: _noMotion ? 0 : 200),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _lines ?? TreeLinesPainter(layout),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _move,
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
                  final List<Widget> steady = [], entering = [];
                  for (final MapEntry<int, Offset> e
                      in layout.positions.entries) {
                    final Offset at = Offset.lerp(
                      _from[e.key] ?? e.value,
                      e.value,
                      t,
                    )!;
                    (_entering.contains(e.key) ? entering : steady).add(
                      place(e.key, at, nodes[e.key]!),
                    );
                  }
                  // One layer for all who appear and one for all who leave: an Opacity on each person was a
                  // layer each, and the moves stuttered on the raster thread (measured on the emulator).
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
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
                      ...steady,
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
      photos: widget.photos,
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
  ) {
    final TreePerson p = family.people[n]!;
    final String who = personName(
      p.givenNames,
      p.surname,
      birthSurname: p.birthSurname,
    );
    final String? kin = _kin[n];
    return _TreeNode(
      key: ValueKey<int>(n),
      person: p,
      isFocus: n == layout.focus,
      isMe: n == family.meId,
      photos: widget.photos,
      slot: _metrics.slot,
      labelHeight: _scaler.scale(13) * 1.3,
      tapPad: _tapPad,
      labelScale: _labelScale,
      showLabel: showLabel,
      semanticsLabel: [
        who,
        lifeYears(birth: p.birth, death: p.death),
        // The candle says it on the screen; without a date of death the years do not (ui review).
        if (p.dead && p.death == null) 'nie żyje',
        ?kin,
      ].join(', '),
      // In presentation the person in the middle opens nothing (D5): no hint, the touch only fits the level anew.
      hint: n != layout.focus
          ? 'w środek'
          : _presenting
          ? null
          : 'otwórz',
      onTap: () => _tap(n),
    );
  }

  /// I2 (D1): the names that stay readable without overlapping, the nearest to the middle first.
  Set<int> _visibleNames(FamilyTreeData family, TreeLayout layout) {
    final double k = _labelScale;
    final double fx = layout.positions[layout.focus]!.dx;
    final double maxWidth = _metrics.slot - 8;
    final double height = _scaler.scale(13) * 1.3;
    return visibleLabels([
      for (final MapEntry<int, Offset> e in layout.positions.entries)
        LabelBox(
          id: e.key,
          centerX: e.value.dx,
          top: e.value.dy + TreeMetrics.node + 4,
          // The name and its halo's plate (3 dp on each side).
          width: math.min(_nameWidth(_label(family, e.key)) + 6, maxWidth) * k,
          height: height * k,
          level: e.key == layout.focus ? -1 : layout.levels[e.key] ?? 99,
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
        icon: Icons.add,
        tooltip: 'Przybliż — bliższa rodzina',
        onPressed: () => _zoomButton(treeZoomStep),
      ),
      const SizedBox(height: 8),
      _ZoomButton(
        icon: Icons.remove,
        tooltip: 'Oddal — dalsza rodzina',
        onPressed: () => _zoomButton(1 / treeZoomStep),
      ),
    ],
  );

  /// Element 11: "Zakończ prezentację" in the top right corner — close in amber, the words in the text colour,
  /// the surface with an outline, 48 dp.
  Widget _exitButton() => OutlinedButton.icon(
    style: secondaryButtonStyle.copyWith(
      backgroundColor: const WidgetStatePropertyAll(GrobingColors.surface),
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    ),
    onPressed: _leave,
    icon: const Icon(Icons.close),
    label: const Text('Zakończ prezentację'),
  );

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
    required this.isMe,
    required this.photos,
    required this.slot,
    required this.labelHeight,
    required this.tapPad,
    required this.labelScale,
    required this.showLabel,
    required this.semanticsLabel,
    required this.hint,
    required this.onTap,
  });

  final TreePerson person;
  final bool isFocus;
  final bool isMe;
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

  /// The name under a node: 13 sp, semi-bold (D10).
  static const TextStyle nameStyle = TextStyle(
    color: GrobingColors.text,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    final Widget initials = InitialsCircle(
      text: isMe ? 'Ja' : initialsOf(person.givenNames, person.surname),
      size: TreeMetrics.node,
      accent: isMe,
      accentOutline: false,
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
    if (isFocus) {
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
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: GrobingColors.amber, width: 2),
          ),
          child: circle,
        ),
      );
    }
    if (person.dead) {
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

  final IconData icon;
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
          child: Icon(icon, color: GrobingColors.text),
        ),
      ),
    ),
  );
}

/// Element 5: the person in the middle — the circle with the ring, the name, and the years with who they
/// are to "ja" (D12, D13, D28 — in the author's voice: "Moja babcia", "to ja"), wrapped, never cut; "Pokaż ›" opens their view. With large system text
/// (≥ 150 %) "Pokaż" goes under the text, so the name and the kinship get the card's width (D20).
class _TreeCard extends StatelessWidget {
  const _TreeCard({
    required this.person,
    required this.isMe,
    required this.kin,
    required this.photos,
    required this.onShow,
  });

  final TreePerson person;
  final bool isMe;
  final String? kin;
  final Photos? photos;
  final VoidCallback onShow;

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
          Icon(Icons.chevron_right),
        ],
      ),
    );
    return Material(
      color: GrobingColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(child: text),
                    ],
                  ),
                  Align(alignment: Alignment.centerRight, child: show),
                ],
              )
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  show,
                ],
              ),
      ),
    );
  }
}
