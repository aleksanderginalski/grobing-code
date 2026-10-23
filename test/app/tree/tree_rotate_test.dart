import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/people/person_choice_screen.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/migration_map.dart';
import 'package:grobing/app/tree/tree_layout.dart' show TreeMetrics;
import 'package:grobing/app/tree/tree_orientation.dart';
import 'package:grobing/app/tree/tree_path.dart';
import 'package:grobing/app/tree/tree_screen.dart';
import 'package:grobing/app/tree/tree_time_bar.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_family.dart';

import '../../support/a11y.dart';

// ISSUE-055 — "Obróć" and the landscape layout of the tree and the migration map (05_DESIGN/drzewo.md v1.29–v1.30,
// element 12, D76, D77, D80, D82; mapa-migracji.md D31), happy path per AC-5: the button asks the system for landscape and
// for portrait; sideways no tab bar, the switch and the icons over the tree, the card in one row at the bottom, its
// surface down to the edge; a person's view goes by the phone's setting and back to the choice; leaving the tab gives
// the phone's setting back; a path sideways — the banner in the top row, the path under it, kept through a turn; the
// map's pill under the top row; tap targets (retro 3, R2). The made-up family of the debug build (family-data.md).

const Size _portrait = Size(1080, 2400); // 360 × 800 dp
const Size _landscape = Size(2400, 1080); // 800 × 360 dp
const String _sideways =
    '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]';
const String _upright = '[DeviceOrientation.portraitUp]';

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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
}

/// The path's line on the tree.
Finder _pathLine() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is PathLinePainter,
);

/// A name under a node of the tree (13 sp, the line 1.3) — not the letters in a circle.
Finder _name(String name) => find.byWidgetPredicate(
  (w) => w is Text && w.data == name && w.style?.height == 1.3,
);

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .entry(0, 0);

void main() {
  late GrobingDatabase db;
  late List<String> orientations;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
    treeLevel = 1;
    // The choice lives while the app runs: each test starts as a new app does.
    treeLandscape = null;
    orientations = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add('${call.arguments}');
          }
          return null;
        });
  });

  tearDown(() {
    treeLandscape = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  }

  Future<void> pumpTree(WidgetTester tester) async {
    tester.view.physicalSize = _portrait;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => addFictionalFamily(db));
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: const Scaffold(body: Text('mapa')),
      ),
    );
    openTab(tester.element(find.text('mapa')), AppTab.tree, database: db);
    await _pumpUntil(tester, () => _shown(find.byTooltip('Obróć poziomo')));
    await _settle(tester);
  }

  /// "Obróć" in portrait, and the system turning the screen.
  Future<void> turnSideways(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Obróć poziomo'));
    await tester.pump();
    tester.view.physicalSize = _landscape;
    await _settle(tester);
  }

  /// Element 1 → 7: the window, "Do" chosen by [query] and the card [name].
  Future<void> connect(WidgetTester tester, String query, String name) async {
    await tester.tap(find.byTooltip('Połącz dwie osoby'));
    await _settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Wybierz osobę'),
      ),
    );
    await _pumpUntil(tester, () => _shown(find.byType(PersonChoiceScreen)));
    await _settle(tester);
    final Finder list = find.byType(PersonChoiceScreen);
    await tester.enterText(
      find.descendant(of: list, matching: find.byType(TextField)),
      query,
    );
    await _pumpUntil(
      tester,
      () => _shown(find.descendant(of: list, matching: find.text(name))),
    );
    await tester.tap(find.descendant(of: list, matching: find.text(name)));
    await _pumpUntil(tester, () => !_shown(find.byType(Dialog)));
    // The list's route gone and the tree on the stage again, then frame by frame as on a phone: one jump of seconds
    // while the tree was still off the stage skipped the move to the path's frame (a test's artefact).
    await _pumpUntil(tester, () => _shown(find.byType(InteractiveViewer)));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets(
    'AC-5 (D82, D77) — "Obróć" asks for landscape; sideways no tab bar, the switch and the icons over the tree, the '
    'card in one row at the bottom, down to the edge; tap targets (R2)',
    (tester) async {
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      // Portrait: "Obróć" in the bar, left of "Połącz dwie osoby" (D82).
      expect(
        tester.getRect(find.byTooltip('Obróć poziomo')).right,
        lessThanOrEqualTo(
          tester.getRect(find.byTooltip('Połącz dwie osoby')).left + 0.5,
        ),
      );
      expect(find.byType(GrobingTabBar), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await turnSideways(tester);
      expect(orientations, [_sideways]);
      expect(treeLandscape, isTrue);
      expect(find.byType(GrobingTabBar), findsNothing);
      // The top row over the tree: the switch at the left, the icons at the right (element 12).
      final Rect rotate = tester.getRect(find.byTooltip('Obróć pionowo'));
      final Rect cast = tester.getRect(
        find.byTooltip('Przesyłaj na telewizor'),
      );
      final Rect parts = tester.getRect(find.byTooltip('Mapa'));
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      expect(rotate.top, lessThan(area.top + 20));
      // The pill 8 dp from the right edge; the tooltip's box is the icon's 40 dp in its 48 dp target.
      expect(cast.right, inInclusiveRange(800 - 8 - 4 - 1, 800 - 8));
      expect(parts.right, lessThan(400));
      // The card in one row: the name beside the time row, at the bottom, its surface down to the screen's edge.
      final Rect name = tester.getRect(find.text('Mateusz Wymyślony'));
      final Rect time = tester.getRect(find.byType(TreeTimeBar));
      expect(time.left, greaterThan(name.right));
      expect((name.center.dy - time.center.dy).abs(), lessThan(24));
      expect(time.top, greaterThan(360 - 72));
      expect(tester.getBottomRight(find.byType(TreeTimeBar)).dy, lessThan(360));
      expect(find.byTooltip('Dalsza rodzina'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D82 — sideways "Obróć" asks for portrait; a person\'s view goes by the phone\'s setting and back to the choice; '
    'leaving the tab gives the phone\'s setting back',
    (tester) async {
      await pumpTree(tester);
      await turnSideways(tester);
      orientations.clear();

      await tester.tap(find.byTooltip('Obróć pionowo'));
      await tester.pump();
      expect(orientations, [_upright]);
      expect(treeLandscape, isFalse);
      tester.view.physicalSize = _portrait;
      await _settle(tester);
      expect(find.byType(GrobingTabBar), findsOneWidget);
      expect(find.byTooltip('Obróć poziomo'), findsOneWidget);

      await turnSideways(tester);
      orientations.clear();
      // A person's view has no landscape layout (D76): the phone's setting while it is open.
      await tester.tap(find.text('Pokaż'));
      await _settle(tester);
      expect(orientations, [_upright, '[]']);
      orientations.clear();
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(orientations, [_sideways]);

      // The last tree tab gone: the phone's setting.
      orientations.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(orientations, [_upright, '[]']);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'D80, element 12 — a path sideways: the banner in the top row between the switch and the icons, the path under '
    'it, no card or + / −; "Obróć" keeps the path (D79)',
    (tester) async {
      await pumpTree(tester);
      await turnSideways(tester);

      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      expect(_pathLine(), findsOneWidget);
      final Rect banner = tester.getRect(find.byType(PathBanner));
      final Rect parts = tester.getRect(find.byTooltip('Mapa'));
      final Rect rotate = tester.getRect(find.byTooltip('Obróć pionowo'));
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      expect(banner.top, lessThan(area.top + 20));
      expect(banner.left, greaterThan(parts.right));
      expect(banner.right, lessThan(rotate.left));
      expect(find.byType(TreeTimeBar), findsNothing);
      expect(find.byTooltip('Dalsza rodzina'), findsNothing);
      // The path under the top row: the top of Wanda's circle, the highest row, under the banner.
      final double circleTop =
          tester.getRect(_name('Wanda')).top -
          (TreeMetrics.node + 4) * _scale(tester);
      expect(circleTop, greaterThanOrEqualTo(banner.bottom - 0.5));

      await tester.tap(find.byTooltip('Obróć pionowo'));
      await tester.pump();
      tester.view.physicalSize = _portrait;
      await _settle(tester);
      expect(_pathLine(), findsOneWidget);
      expect(find.byType(PathBanner), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D31 — the map sideways: the same layout, its pill under the top row; no "Połącz dwie osoby"; the part\'s switch '
    'keeps the turn',
    (tester) async {
      await pumpTree(tester);
      await turnSideways(tester);
      orientations.clear();

      await tester.tap(find.byTooltip('Mapa'));
      await _pumpUntil(tester, () => _shown(find.byType(MigrationMap)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.widget<MigrationMap>(find.byType(MigrationMap)).pillTop,
        68,
      );
      expect(find.byTooltip('Połącz dwie osoby'), findsNothing);
      expect(find.byTooltip('Obróć pionowo'), findsOneWidget);
      expect(find.byType(GrobingTabBar), findsNothing);
      expect(find.byType(TreeTimeBar), findsOneWidget);
      expect(orientations, isEmpty);
      await cleanUp(tester);
    },
  );
}
