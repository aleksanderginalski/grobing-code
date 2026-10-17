import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/tree_presentation.dart';
import 'package:grobing/app/tree/tree_screen.dart';
import 'package:grobing/app/tree/tree_time.dart';
import 'package:grobing/app/tree/tree_time_bar.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_family.dart';

import '../../support/a11y.dart';

// ISSUE-038 — history in presentation mode (05_DESIGN/drzewo.md v1.14, element 11, D39–D42), happy path per AC on
// the made-up family: AC-1 the empty space shows the bar and "Zakończ prezentację", 5 s from the last touch, a
// second tap hides them; ▶ in the bar runs the year in the corner, which stays with the bar hidden, 48 dp from the
// left and 24 dp from the top; at "dziś" it says "dziś" for 3 s; a finger on the slider keeps the controls (D40) ·
// AC-4 the card's year goes into presentation and back (Z2), ▶ stopped · AC-5 at 200 % the bar in one row, the
// year at most 1.3 × 36 sp; tap targets and contrast (retro 3, R2) · AC-6 with a reader the controls are there
// from the start and stay (Dev report, deviation 1); "Czas na działanie" 10 s keeps them 10 s. The system's cast
// screen and its channel are mocked as in tree_screen_test.dart (ISSUE-036). Made-up people only (family-data.md).

const MethodChannel _external = MethodChannel('grobing/external');

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (int i = 0; i < 400; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('condition not met in time');
}

bool _shown(Finder f) => f.evaluate().isNotEmpty;

Future<void> _afterMove(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Every person on the tree, also the one in the middle of a presentation, who has no hint.
Finder _nodes() => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.container &&
      w.excludeSemantics &&
      (w.properties.label?.isNotEmpty ?? false),
);

/// The bar of presentation: the time row in one row (B2).
Finder _bar() => find.byWidgetPredicate((w) => w is TreeTimeBar && w.oneRow);

/// The card's time row.
Finder _cardRow() =>
    find.byWidgetPredicate((w) => w is TreeTimeBar && !w.oneRow);

/// The year in the corner (L1), or null when it is not there.
int? _cornerYear(WidgetTester tester) =>
    tester.widget<PresentationYear>(find.byType(PresentationYear)).year;

/// A point of the tree's area in the middle band where no one, and none of the controls, stands.
Offset _empty(WidgetTester tester) {
  final Rect area = tester.getRect(find.byType(InteractiveViewer));
  final List<Rect> taken = [
    for (final Element e in _nodes().evaluate())
      tester.getRect(find.byWidget(e.widget)).inflate(8),
    for (final Finder f in [
      _bar(),
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

void main() {
  late GrobingDatabase db;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
    treeTempo = TreeTempo.medium;
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await tester.runAsync(db.close);
  }

  /// The system's cast screen (`ExternalLinks.kt`) opens; "Czas na działanie" answers [timeout] ms (null: the
  /// phone says nothing — 5 s).
  void mockChannel({int? timeout}) {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _external,
      (call) async => switch (call.method) {
        'openCastSettings' => true,
        'recommendedTimeout' => timeout,
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

  Future<void> pumpTree(WidgetTester tester, {double text = 1}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3; // 360 × 800 dp
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => addFictionalFamily(db));
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: const Scaffold(body: Text('mapa')),
      ),
    );
    openTab(tester.element(find.text('mapa')), AppTab.tree, database: db);
    await _pumpUntil(tester, () => _shown(_cardRow()));
    await _afterMove(tester);
  }

  /// "Przesyłaj na telewizor" → the system's screen → back (inactive, then resumed — ISSUE-036), the phone turned.
  Future<void> present(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
    await tester.pump();
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.physicalSize = const Size(2400, 1080);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _afterMove(tester);
    // The bar and the tab bar are gone. Not "Drzewo": since drzewo.md v1.20 it stands in the controls' switch
    // "Drzewo · Mapa" (ISSUE-045), which a reader has from the start.
    expect(find.byType(GrobingTabBar), findsNothing);
    expect(find.byTooltip('Połącz dwie osoby'), findsNothing);
  }

  testWidgets(
    'AC-1 — the empty space shows the bar and "Zakończ prezentację" for 5 s; a second tap hides them; ▶ runs the '
    'year in the corner, 48 dp from the left, which stays with the bar hidden; at "dziś" it says "dziś" for 3 s',
    (tester) async {
      mockChannel();
      await pumpTree(tester);
      await present(tester);
      // "dziś" and no controls: no year in the corner (D39).
      expect(find.byType(PresentationYear), findsNothing);
      expect(_bar(), findsNothing);

      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(_bar(), findsOneWidget);
      expect(find.byType(PresentationExit), findsOneWidget);
      // With the controls the corner says "dziś".
      expect(_cornerYear(tester), isNull);
      expect(
        find.descendant(
          of: find.byType(PresentationYear),
          matching: find.text('dziś'),
        ),
        findsOneWidget,
      );
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      expect(
        tester.getTopLeft(find.byType(PresentationYear)) - area.topLeft,
        const Offset(PresentationYear.left, PresentationYear.top),
      );
      await tester.pump(const Duration(milliseconds: 4900));
      expect(_bar(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_bar(), findsNothing);
      expect(find.byType(PresentationExit), findsNothing);

      // A second tap hides them at once (Media3: hide on touch).
      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(_bar(), findsOneWidget);
      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(_bar(), findsNothing);

      // ▶ in the bar: from 1860, "Średnio" — the year in the corner after 2 s is 1880, also with the bar hidden.
      await tester.tapAt(_empty(tester));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: _bar(),
          matching: find.byTooltip('Odtwórz historię'),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(_cornerYear(tester), 1880);
      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(_bar(), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(_cornerYear(tester), 1900);

      // On to "dziś": the corner says it for 3 s more, then goes.
      await tester.pump(const Duration(milliseconds: 12700));
      expect(_cornerYear(tester), isNull);
      expect(find.byType(PresentationYear), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2800));
      expect(find.byType(PresentationYear), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PresentationYear), findsNothing);

      // ❚❚ in the bar stops at the year shown.
      await tester.tapAt(_empty(tester));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: _bar(),
          matching: find.byTooltip('Odtwórz historię'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(
        find.descendant(of: _bar(), matching: find.byTooltip('Zatrzymaj')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_cornerYear(tester), 1870);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-1, D40 — a finger on the slider keeps the controls; the tempo in the bar is the card\'s; a touch of the bar '
    'starts the 5 s again',
    (tester) async {
      mockChannel();
      await pumpTree(tester);
      await present(tester);
      await tester.tapAt(_empty(tester));
      await tester.pump();

      // At 100 % the fitted tree is near scale 1: the whole screen with the controls meets the guidelines (R2).
      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();

      final TreeTimeBar bar = tester.widget<TreeTimeBar>(_bar());
      expect(bar.tempo, TreeTempo.medium);
      bar.onSlide!(true);
      await tester.pump(const Duration(seconds: 8));
      expect(_bar(), findsOneWidget);
      bar.onSlide!(false);
      await tester.pump(const Duration(milliseconds: 4900));
      expect(_bar(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_bar(), findsNothing);

      // The tempo button in the bar: the next tempo, the same for the card; and 5 s from that touch.
      await tester.tapAt(_empty(tester));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(
        find.descendant(
          of: _bar(),
          matching: find.byTooltip(TreeTimeBar.tempoLine(TreeTempo.medium)),
        ),
      );
      await tester.pump();
      expect(treeTempo, TreeTempo.fast);
      expect(tester.widget<TreeTimeBar>(_bar()).tempo, TreeTempo.fast);
      await tester.pump(const Duration(milliseconds: 4900));
      expect(_bar(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_bar(), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-4 (Z2, D42) — the card at 1950: presentation shows 1950 in the corner, ▶ stopped; "Zakończ prezentację" '
    'leaves the card at the year set in presentation',
    (tester) async {
      mockChannel();
      await pumpTree(tester);
      tester.widget<TreeTimeBar>(_cardRow()).onYear(1950);
      await tester.pump();
      await present(tester);

      expect(_cornerYear(tester), 1950);
      expect(_bar(), findsNothing);
      // 5 of 20 on the tree in 1950, as in the card (US-010 AC-1), and the empty ring of "Ja" (C1).
      expect(_nodes(), findsNWidgets(6));
      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(
        find.descendant(
          of: _bar(),
          matching: find.byTooltip('Odtwórz historię'),
        ),
        findsOneWidget,
      );

      tester.widget<TreeTimeBar>(_bar()).onYear(1930);
      await tester.pump();
      expect(_cornerYear(tester), 1930);
      await tester.tap(find.byType(PresentationExit));
      await tester.pump();
      tester.view.physicalSize = const Size(1080, 2400);
      await tester.pump();
      await _afterMove(tester);
      expect(tester.widget<TreeTimeBar>(_cardRow()).year, 1930);
      expect(find.byType(PresentationYear), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-5 — text at 200 %: the bar in one row, nothing cut; the year in the corner at most 1.3 × 36 sp; tap targets '
    'and contrast (R2)',
    (tester) async {
      // The test font's squares overflow the tab bar (lib/app/tabs.dart, not this item's) at 200 % before the turn,
      // as in tree_time_screen_test.dart; only that overflow is let through.
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
      mockChannel();
      await pumpTree(tester, text: 2);
      await present(tester);
      await tester.tapAt(_empty(tester));
      await tester.pump();

      final Rect play = tester.getRect(
        find.descendant(
          of: _bar(),
          matching: find.byTooltip('Odtwórz historię'),
        ),
      );
      final Rect slider = tester.getRect(
        find.descendant(of: _bar(), matching: find.byType(Slider)),
      );
      final Rect tempo = tester.getRect(
        find.descendant(
          of: _bar(),
          matching: find.byTooltip(TreeTimeBar.tempoLine(TreeTempo.medium)),
        ),
      );
      expect((play.center.dy - slider.center.dy).abs(), lessThan(2));
      expect((play.center.dy - tempo.center.dy).abs(), lessThan(2));
      expect(slider.left, greaterThanOrEqualTo(play.right - 1));
      expect(tempo.left, greaterThanOrEqualTo(slider.right - 1));
      final Rect bar = tester.getRect(_bar());
      expect(bar.contains(tempo.bottomRight - const Offset(0.1, 0.1)), isTrue);

      final Text year = tester.widget<Text>(
        find.descendant(
          of: find.byType(PresentationYear),
          matching: find.byType(Text),
        ),
      );
      expect(
        year.textScaler!.scale(PresentationYear.fontSize),
        moreOrLessEquals(36 * 1.3, epsilon: 0.01),
      );

      final SemanticsHandle semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('dziś'), findsWidgets);
      // The controls' targets ≥ 48 dp. The whole screen's guideline is not asked here: at 200 % the fitted tree's
      // scale takes a person's target under 48 dp — the exception for zoomed-out nodes (style-b.md → Thresholds,
      // drzewo.md D17), not the controls'.
      for (final Finder f in [
        find.descendant(
          of: _bar(),
          matching: find.byTooltip('Odtwórz historię'),
        ),
        find.descendant(
          of: _bar(),
          matching: find.byTooltip(TreeTimeBar.tempoLine(TreeTempo.medium)),
        ),
        find.byType(PresentationExit),
      ]) {
        final Size size = tester.getSemantics(f).rect.size;
        expect(size.width, greaterThanOrEqualTo(48), reason: '$f');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$f');
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-6 — with a reader the controls are there from the start and stay; a tap does not hide them (Dev report, '
    'deviation 1)',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      mockChannel();
      await pumpTree(tester);
      await present(tester);

      expect(_bar(), findsOneWidget);
      expect(find.byType(PresentationExit), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      expect(_bar(), findsOneWidget);
      await tester.tapAt(_empty(tester));
      await tester.pump(const Duration(seconds: 6));
      expect(_bar(), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-6 — "Czas na działanie" at 10 s: the controls stay 10 s, not 5 s',
    (tester) async {
      mockChannel(timeout: 10000);
      await pumpTree(tester);
      await present(tester);
      await tester.tapAt(_empty(tester));
      await tester.pump(const Duration(seconds: 6));
      expect(_bar(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3900));
      expect(_bar(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_bar(), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'element 11, D16 — at 200 % each person put in the middle gets level 2 fitted: everyone on the screen, 24 dp '
    'from its edges, unless the scale is at its least (ui review of ISSUE-038, MAJOR: Michał)',
    (tester) async {
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
      mockChannel();
      await pumpTree(tester, text: 2);
      await present(tester);

      // By the node, not the name: at 200 % names that would overlap hide (I2).
      final List<String> checked = [];
      for (final String name in const [
        'Michał Wymyślony',
        'Kasia Wymyślona',
        'Joanna Testowicz',
        'Mateusz Wymyślony',
      ]) {
        final Finder person = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.container &&
              (w.properties.label?.startsWith(name) ?? false),
        );
        if (!_shown(person)) continue;
        await tester.tapAt(tester.getCenter(person.first));
        await _afterMove(tester);
        final double scale = tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .entry(0, 0);
        if (scale <= treeMinScale + 1e-6) continue;
        checked.add('$name ${scale.toStringAsFixed(3)}');
        final Rect area = tester.getRect(find.byType(InteractiveViewer));
        for (final Element e in _nodes().evaluate()) {
          final Rect r = tester.getRect(find.byWidget(e.widget));
          final String label = (e.widget as Semantics).properties.label!;
          expect(
            r.left,
            greaterThanOrEqualTo(area.left + 24 - 1),
            reason: '$name in the middle: $label at $r, scale $scale',
          );
          expect(
            r.right,
            lessThanOrEqualTo(area.right - 24 + 1),
            reason: '$name in the middle: $label at $r, scale $scale',
          );
        }
      }
      // Not empty: at least one middle was fitted above the least scale, so the check above ran.
      // In the test font: Michał and Joanna at 0.553, "Ja" at 0.435.
      expect(checked, isNotEmpty);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'L1 — the year in the corner takes no touch: a tap on it reaches the tree below (the empty space shows the '
    'controls)',
    (tester) async {
      mockChannel();
      await pumpTree(tester);
      tester.widget<TreeTimeBar>(_cardRow()).onYear(1890);
      await tester.pump();
      await present(tester);
      expect(_cornerYear(tester), 1890);
      expect(_bar(), findsNothing);

      await tester.tapAt(tester.getCenter(find.byType(PresentationYear)));
      await tester.pump();
      expect(_bar(), findsOneWidget);
      expect(find.byType(TreeScreen), findsOneWidget);
      await cleanUp(tester);
    },
  );
}
