import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/migration_map.dart';
import 'package:grobing/app/tree/tree_path.dart';
import 'package:grobing/app/tree/tree_presentation.dart';
import 'package:grobing/app/tree/tree_screen.dart';
import 'package:grobing/app/tree/tree_time.dart';
import 'package:grobing/app/tree/tree_time_bar.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_family.dart';
import 'package:grobing/dev/fictional_residences.dart';

import '../../support/a11y.dart';

// ISSUE-050 — "Następne" (05_DESIGN/drzewo.md v1.26, element 6a; mapa-migracji.md v1.5, element 15), happy path per AC on
// the made-up family and its made-up residences (lib/dev; family-data.md):
// · AC-1 — ⏭ right after ▶ in the card: from 1940 to 1944 with the year and the caption "W 1944 / Zmarł Leon Wymyślony
//   (ok. 1944)", then 1946; tap targets, labels, every button tappable (retro 3, R2); the caption a live region (D71);
// · D66 — a year of more than 4: 4 lines and "Jeszcze 1 w tym roku", the next ⏭ the rest of it, then the next year;
// · AC-4, D67 — after the last event "dziś" and "To wszystkie zdarzenia z datą.", then the first again; from "dziś" the
//   first event;
// · Z1 (D62) — ⏭ stops ▶; D69 — the caption stays through a touch of a person, goes with the slider, ▶ and a level;
// · V2 (D63) — the people of the caption on the screen after ⏭, under it, at the same scale;
// · U3 (D65) — the row at 200 % on 360 dp in two rows with the first year; D71 — no ⏭ without an event;
// · AC-3 (B — D72, drzewo.md v1.28) — presentation: ⏭ on the bar, the caption a small line on the bar, nothing under the
//   year; the line goes with the bar, the year and the glow stay; back on the phone the bubble;
// · D73–D75 (v1.28) — the people of the page glow: the ring and the glow under them, three pulses then steady, the motion
//   over before 5 s (SC 2.2.2); a wedding with the couple's line; zoomed out the glow keeps its size on the screen; with
//   the system's animations off steady at once; it goes with the caption;
// · AC-2 (M2 — D27–D29; D30) — the map: the caption in the pill's place, the frame kept, those who moved glow; the end.
// Events and their words — tree_events_test.dart; moves — migration_year_test.dart.

const MethodChannel _external = MethodChannel('grobing/external');

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, [
  String what = '',
]) async {
  for (int i = 0; i < 400; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('condition not met in time: $what');
}

bool _shown(Finder f) => f.evaluate().isNotEmpty;

/// A hard space, as the captions write it (style-b.md rule 6).
final String _nb = String.fromCharCode(0xA0);

/// A text on the screen — plain or rich — read with its hard spaces as spaces.
Finder _line(String plain) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().replaceAll(_nb, ' ') == plain,
);

/// A text that starts so.
Finder _lineStarting(String start) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text.toPlainText().replaceAll(_nb, ' ').startsWith(start),
);

Finder get _next => find.byTooltip('Następne zdarzenie');

/// The slider's value for the reader: "1944" or "dziś".
String? _year(WidgetTester tester) => tester
    .widget<Semantics>(
      find
          .byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Rok',
          )
          .first,
    )
    .properties
    .value;

/// The node of the person whose reader's label starts with [name].
Finder _nodeOf(String name) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.container &&
      (w.properties.label?.startsWith(name) ?? false),
);

/// The glow's layer under the caption's people (drzewo.md D73) — the screen's own painter, found by its name and read
/// through its public fields: level (the opacity now), glows, reach.
CustomPainter? _shine() {
  for (final Element e in find.byType(CustomPaint).evaluate()) {
    final CustomPainter? p = (e.widget as CustomPaint).painter;
    if (p != null && p.runtimeType.toString() == '_ShinePainter') return p;
  }
  return null;
}

double _shineLevel() =>
    ((_shine()! as dynamic).level as Animation<double>).value;

int _glows() => ((_shine()! as dynamic).glows as List).length;

/// The node of [name] has the amber ring of 2 dp — the middle's, a lit path's, the caption's (D73).
bool _ringed(String name) => find
    .descendant(
      of: _nodeOf(name).first,
      matching: find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final Decoration d = w.decoration;
        return d is BoxDecoration &&
            d.border?.top.color == GrobingColors.amber &&
            d.border?.top.width == 2;
      }),
    )
    .evaluate()
    .isNotEmpty;

/// The couples' lines of the caption (D73): a path's painter drawing every run at once.
List<List<Offset>> _pairs() => [
  for (final Element e in find.byType(CustomPaint).evaluate())
    if ((e.widget as CustomPaint).painter case final PathLinePainter p
        when p.together)
      ...p.runs,
];

/// A point of the tree's area where no one, and none of the controls, stands (as tree_presentation_test.dart).
Offset _empty(WidgetTester tester) {
  final Rect area = tester.getRect(find.byType(InteractiveViewer));
  final List<Rect> taken = [
    for (final Element e
        in find
            .byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.container &&
                  w.excludeSemantics &&
                  (w.properties.label?.isNotEmpty ?? false),
            )
            .evaluate())
      tester.getRect(find.byWidget(e.widget)).inflate(8),
    for (final Finder f in [
      find.byType(PresentationYear),
      find.byType(PresentationExit),
    ])
      if (_shown(f)) tester.getRect(f).inflate(8),
  ];
  for (final double fy in const [0.55, 0.45, 0.65, 0.35]) {
    for (double x = area.left + 40; x < area.right - 40; x += 20) {
      final Offset p = Offset(x, area.top + area.height * fy);
      if (!taken.any((r) => r.contains(p))) return p;
    }
  }
  fail('no empty space on the tree');
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 300));
}

/// ⏭, then the frame after it (the glide of V2 takes 0.45 s).
Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(_next);
  await _settle(tester);
}

/// A year as a finger on the slider gives it.
Future<void> _slideTo(WidgetTester tester, int? year) async {
  tester
      .widget<TreeTimeBar>(
        find.byWidgetPredicate((w) => w is TreeTimeBar && !w.oneRow),
      )
      .onYear(year);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  late GrobingDatabase db;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
    treeTempo = TreeTempo.medium;
    treeLevel = 1;
    migrationArea = null;
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await tester.runAsync(db.close);
  }

  void mockChannel() {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _external,
      (call) async => switch (call.method) {
        'openCastSettings' => true,
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_external, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  /// The phone 360 × 800 dp, the Drzewo tab — on its part "Mapa" with [map].
  Future<void> open(
    WidgetTester tester, {
    double text = 1,
    bool map = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() async {
      await addFictionalFamily(db);
      if (map) await addFictionalResidences(db);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: const Scaffold(body: Text('mapa')),
      ),
    );
    openTab(
      tester.element(find.text('mapa')),
      AppTab.tree,
      database: db,
      treeMap: map,
    );
    await _pumpUntil(tester, () => _shown(_next), 'the tree with ⏭');
    if (map) {
      await _pumpUntil(tester, () => _shown(find.byType(MigrationMap)), 'map');
    }
    await _settle(tester);
  }

  testWidgets(
    'AC-1 — ⏭ right after ▶: from 1940 to 1944, "W 1944 / Zmarł Leon Wymyślony (ok. 1944)", then 1946 "Ślub: Helena '
    'Wymyślona i Józef Wymyślony"; the caption a live region; tap targets, labels, every button tappable (R2)',
    (tester) async {
      await open(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      // Right after ▶: the next 48 dp cell — the tooltips are the buttons inside their padded targets.
      final double gap =
          tester.getTopLeft(_next).dx -
          tester.getTopRight(find.byTooltip('Odtwórz historię')).dx;
      expect(gap, inInclusiveRange(0, 8));
      expect(
        tester.getSize(
          find.ancestor(of: _next, matching: find.byType(IconButton)),
        ),
        const Size(48, 48),
      );
      // Tap targets with ⏭ in the card, before the view moves: after ⏭ a person may stand cut at the area's edge, a node
      // of the tree as before this item (style-b.md, the exception of the tree's node).
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await _slideTo(tester, 1940);
      await _tapNext(tester);
      expect(_year(tester), '1944');
      expect(_line('W 1944'), findsOneWidget);
      expect(_line('Zmarł Leon Wymyślony (ok. 1944)'), findsOneWidget);
      expect(
        find.ancestor(
          of: _line('W 1944'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false),
          ),
        ),
        findsWidgets,
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);

      await _tapNext(tester);
      expect(_year(tester), '1946');
      expect(_line('Ślub: Helena Wymyślona i Józef Wymyślony'), findsOneWidget);
      expect(_line('W 1944'), findsNothing);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D66 — 1955 has 5 events: 4 of them, "Jeszcze 1 w tym roku", "W 1955 · 1 z 2"; the next ⏭ the rest of 1955; then '
    '1956',
    (tester) async {
      await open(tester);
      await _slideTo(tester, 1954);
      await _tapNext(tester);
      expect(_year(tester), '1955');
      expect(_line('W 1955 · 1 z 2'), findsOneWidget);
      expect(
        _line('Ślub: Krystyna Zmyślona i Henryk Zmyślony'),
        findsOneWidget,
      );
      expect(_line('Urodził się Roman Zmyślony'), findsOneWidget);
      expect(_line('Jeszcze 1 w tym roku'), findsOneWidget);
      expect(_line('Urodził się Wojciech Testowski'), findsNothing);

      await _tapNext(tester);
      expect(_year(tester), '1955');
      expect(_line('W 1955 · 2 z 2'), findsOneWidget);
      expect(_line('Urodził się Wojciech Testowski'), findsOneWidget);
      expect(_line('Jeszcze 1 w tym roku'), findsNothing);

      await _tapNext(tester);
      expect(_year(tester), '1956');
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-4, D67 — from "dziś" the first event, 1868; after the last, 2019, "dziś" with "To wszystkie zdarzenia z datą."; '
    'then 1868 again, without an error',
    (tester) async {
      await open(tester);
      expect(_year(tester), 'dziś');
      await _tapNext(tester);
      expect(_year(tester), '1868');
      expect(_line('Urodził się Antoni Wymyślony'), findsOneWidget);

      await _slideTo(tester, 2019);
      await _tapNext(tester);
      expect(_year(tester), 'dziś');
      expect(_line('Dziś'), findsOneWidget);
      expect(_line('To wszystkie zdarzenia z datą.'), findsOneWidget);

      await _tapNext(tester);
      expect(_year(tester), '1868');
      expect(_line('To wszystkie zdarzenia z datą.'), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'Z1 (D62) — ⏭ while ▶ runs stops it at the next event after the year it had come to: ▶ from 1860, at 1870 ⏭ → 1893',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1050));
      expect(_year(tester), '1870');
      expect(find.byTooltip('Zatrzymaj'), findsOneWidget);

      await _tapNext(tester);
      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);
      expect(_year(tester), '1893');
      expect(_line('Urodził się Ignacy Zmyślicki'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(_year(tester), '1893');
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D69 — the caption goes with the slider, with ▶ and with a level; it stays through a touch of a person',
    (tester) async {
      await open(tester);
      await _tapNext(tester);
      expect(_line('W 1868'), findsOneWidget);
      await _slideTo(tester, 1900);
      expect(_line('W 1868'), findsNothing);
      expect(_lineStarting('W 19'), findsNothing);

      await _tapNext(tester);
      expect(_line('W 1902'), findsOneWidget);
      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump();
      expect(_line('W 1902'), findsNothing);
      await _tapNext(tester);
      expect(_lineStarting('W 19'), findsOneWidget);

      await tester.tap(find.byTooltip('Dalsza rodzina'));
      await _settle(tester);
      expect(_lineStarting('W 19'), findsNothing);
      await tester.tap(find.byTooltip('Bliższa rodzina'));
      await _settle(tester);

      await _slideTo(tester, 1867);
      await _tapNext(tester);
      expect(_line('W 1868'), findsOneWidget);
      await tester.tapAt(tester.getCenter(_nodeOf('Antoni Wymyślony').first));
      await _settle(tester);
      expect(_line('W 1868'), findsOneWidget);
      expect(_year(tester), '1868');
      await cleanUp(tester);
    },
  );

  testWidgets(
    'V2 (D63) — from "Ja" at the scale 1 the people of 1868 are off the screen; after ⏭ Antoni is on it, under the '
    'caption, and the scale is the same',
    (tester) async {
      await open(tester);
      double scale() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .entry(0, 0);
      final double before = scale();
      await _tapNext(tester);
      await tester.pump(const Duration(milliseconds: 600));
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      final Rect antoni = tester.getRect(_nodeOf('Antoni Wymyślony').first);
      final Rect caption = tester.getRect(_line('W 1868'));
      expect(area.contains(antoni.topLeft), isTrue);
      expect(area.contains(antoni.bottomRight), isTrue);
      expect(antoni.top, greaterThan(caption.bottom));
      expect(scale(), before);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'SC 2.3.3 (D36, D63) — with the system\'s animations off the view stands where it goes right after ⏭, no glide',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);
      Matrix4 view() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .clone();
      final Matrix4 before = view();
      await tester.tap(_next);
      await tester.pump();
      await tester.pump();
      final Matrix4 at = view();
      expect(at, isNot(before));
      await tester.pump(const Duration(seconds: 1));
      expect(view(), at);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'U3 (D65) — at 200 % on 360 dp two rows: the first year, the tempo and the year above ▶ ⏭ and the slider; the caption '
    'wraps, nothing overflows; tap targets',
    (tester) async {
      // The test font draws every letter as a square: the bottom bar (lib/app/tabs.dart, not this item's) overflows in it
      // at 200 % and not on a phone — as in tree_time_screen_test.dart. Only that overflow is let through; the emulator
      // saw the row and the caption at 200 % on 360 dp (Dev report, t200-v2c).
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final String error = details.toString();
        if (error.contains('overflowed') &&
            error.contains('lib/app/tabs.dart')) {
          return;
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      await open(tester, text: 2);
      expect(find.text('1860'), findsOneWidget);
      expect(
        tester.getTopLeft(_next).dy,
        greaterThan(tester.getBottomLeft(find.text('1860')).dy),
      );
      await _slideTo(tester, 1997);
      await _tapNext(tester);
      expect(
        _line('Ślub: Monika Wymyślona i Tomasz Wymyślony'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D71, U3 — the row without ⏭ (no event with a date) keeps the first year; with ⏭ the first year leaves the row',
    (tester) async {
      Widget row(VoidCallback? next) => MaterialApp(
        theme: GrobingTheme.dark,
        home: Scaffold(
          body: TreeTimeBar(
            start: 1860,
            now: 2026,
            year: null,
            playing: false,
            onPlay: () {},
            onYear: (_) {},
            tempo: TreeTempo.medium,
            onTempo: () {},
            onNext: next,
          ),
        ),
      );
      await tester.pumpWidget(row(null));
      expect(_next, findsNothing);
      expect(find.text('1860'), findsOneWidget);
      int taps = 0;
      await tester.pumpWidget(row(() => taps++));
      expect(_next, findsOneWidget);
      expect(find.text('1860'), findsNothing);
      await tester.tap(_next);
      expect(taps, 1);
    },
  );

  testWidgets(
    'D73 — after ⏭ the people of the page glow: the ring and the glow under them, the first pulse at 0.65, then steady '
    '0.30 and nothing moving after 4 s (SC 2.2.2); a wedding — both and the couple\'s line; the glow goes with the caption',
    (tester) async {
      await open(tester);
      expect(_shine(), isNull);
      await tester.tap(_next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_year(tester), '1868');
      expect(_ringed('Antoni Wymyślony'), isTrue);
      expect(_glows(), 1);
      expect(_shineLevel(), closeTo(0.65, 0.03));
      expect(_pairs(), isEmpty);
      await tester.pump(const Duration(milliseconds: 3400));
      expect(_shineLevel(), closeTo(0.30, 0.001));
      expect(tester.hasRunningAnimations, isFalse);
      expect(_ringed('Antoni Wymyślony'), isTrue);

      await _slideTo(tester, 1945);
      await _tapNext(tester);
      expect(_line('Ślub: Helena Wymyślona i Józef Wymyślony'), findsOneWidget);
      expect(_ringed('Helena Wymyślona'), isTrue);
      expect(_ringed('Józef Wymyślony'), isTrue);
      expect(_glows(), 2);
      expect(_pairs(), hasLength(1));
      expect(_pairs().single, hasLength(2));

      await _slideTo(tester, 1950);
      expect(_shine(), isNull);
      expect(_pairs(), isEmpty);
      expect(_ringed('Helena Wymyślona'), isFalse);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D73 — zoomed out the glow keeps its size on the screen, as the names do (I2): at the scale 0.5 it reaches twice as '
    'far on the tree',
    (tester) async {
      await open(tester);
      await _tapNext(tester);
      expect((_shine()! as dynamic).reach, 1.0);
      final TransformationController view = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      // The glide of V2 ends first: it would put its own frame back over the zoom.
      await tester.pump(const Duration(milliseconds: 500));
      view.value = view.value.clone()..scaleByDouble(0.5, 0.5, 0.5, 1);
      await tester.pump();
      expect((_shine()! as dynamic).reach, closeTo(2.0, 0.01));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D75, SC 2.3.3 — with the system\'s animations off the glow is steady at once: 0.30 right after ⏭ and after 0.6 s',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);
      await tester.tap(_next);
      await tester.pump();
      expect(_shineLevel(), closeTo(0.30, 0.001));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_shineLevel(), closeTo(0.30, 0.001));
      expect(_ringed('Antoni Wymyślony'), isTrue);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3 (B — D72) — presentation: ⏭ on the bar right after ▶; the year in the corner, nothing under it; on the bar a '
    'line "W 1868  Urodził się Antoni Wymyślony", 14 sp, read as "W 1868. Urodził się …"; it goes with the bar after 5 s, '
    'the year and the glow stay; an empty tap brings it back; back on the phone the bubble',
    (tester) async {
      mockChannel();
      await open(tester);
      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.view.physicalSize = const Size(2400, 1080);
      await _settle(tester);

      // The controls: a tap on the empty space (D40).
      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(_next, findsOneWidget);
      expect(
        tester.getTopLeft(_next).dx -
            tester.getTopRight(find.byTooltip('Odtwórz historię')).dx,
        inInclusiveRange(0, 8),
      );
      await tester.tap(_next);
      await _settle(tester);
      expect(
        tester.widget<PresentationYear>(find.byType(PresentationYear)).year,
        1868,
      );
      // The line on the bar: the head, then the event; the words 14 sp, the head 13 sp (D72).
      final Finder line = find.descendant(
        of: find.byType(PresentationBar),
        matching: _lineStarting('W 1868'),
      );
      expect(line, findsOneWidget);
      final String plain = tester
          .widget<RichText>(line)
          .text
          .toPlainText()
          .replaceAll(_nb, ' ');
      expect(plain, endsWith('Urodził się Antoni Wymyślony'));
      expect(tester.widget<RichText>(line).text.style?.fontSize, 14);
      // Over ▶ ⏭, inside the bar.
      expect(
        tester.getRect(line).bottom,
        lessThanOrEqualTo(tester.getTopLeft(_next).dy),
      );
      // Nothing under the year: no caption of 28 sp, no line outside the bar.
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.style?.fontSize == 28,
        ),
        findsNothing,
      );
      expect(_lineStarting('Urodził się Antoni'), findsNothing);
      // The reader hears the year with the line (D71).
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          RegExp(r'^W.1868\. Urodził.się Antoni.Wymyślony$'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
      expect(_ringed('Antoni Wymyślony'), isTrue);

      await tester.pump(const Duration(milliseconds: 5200));
      expect(_next, findsNothing);
      expect(line, findsNothing);
      expect(find.byType(PresentationYear), findsOneWidget);
      expect(_ringed('Antoni Wymyślony'), isTrue);
      expect(_shine(), isNotNull);

      // An empty tap: the bar again, with the same line (D69).
      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(line, findsOneWidget);

      await tester.binding.handlePopRoute();
      tester.view.physicalSize = const Size(1080, 2400);
      await _settle(tester);
      expect(_line('W 1868'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 (M2 — D27–D29) — the map: ⏭ to the first move, the caption "W …" with "→" in the pill\'s place; the frame kept; '
    'at the end "To wszystkie przeprowadzki z datą."',
    (tester) async {
      await open(tester, map: true);
      expect(find.textContaining('na mapie'), findsOneWidget);
      final Object? frame = migrationArea;

      await _tapNext(tester);
      // The caption's head "W 1914" — not the card's line "W 1914: …" (mapa-migracji.md element 12).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              RegExp(
                r'^W \d{4}$',
              ).hasMatch(w.text.toPlainText().replaceAll(_nb, ' ')),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('→'),
        ),
        findsWidgets,
      );
      expect(find.textContaining('na mapie'), findsNothing);
      expect(migrationArea, frame);
      // Those who moved glow (D30): the map's one layer of glow, in its pulse (over the steady 0.30), under a circle or
      // a "+N".
      final CustomPainter? mapShine = [
        for (final Element e
            in find
                .descendant(
                  of: find.byType(MigrationMap),
                  matching: find.byType(CustomPaint),
                )
                .evaluate())
          (e.widget as CustomPaint).painter,
      ].where((p) => p.runtimeType.toString() == '_ShineLayer').firstOrNull;
      expect(mapShine, isNotNull);
      expect(((mapShine! as dynamic).glows as List), isNotEmpty);
      expect(
        ((mapShine as dynamic).level as Animation<double>).value,
        greaterThan(0.45),
      );

      bool ended = false;
      for (int i = 0; i < 40 && !ended; i++) {
        await _tapNext(tester);
        ended = _shown(_line('To wszystkie przeprowadzki z datą.'));
      }
      expect(ended, isTrue);
      expect(_year(tester), 'dziś');
      await cleanUp(tester);
    },
  );
}
