import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/people/person_choice_screen.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/tree_layout.dart' show TreeMetrics;
import 'package:grobing/app/tree/tree_path.dart';
import 'package:grobing/app/tree/tree_screen.dart';
import 'package:grobing/app/tree/tree_time_bar.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_family.dart';

import '../../support/a11y.dart';

// ISSUE-039 — "Połącz dwie osoby" on the tree (05_DESIGN/drzewo.md v1.16, elements 1, 7–10; US-011), happy path
// per AC: AC-1 the icon, the window with "Od" ("Ja") and "Do", the list without the other tile's person, the
// search, "Od" changed; "Anuluj" and back · AC-2 "Do" in the middle (W2) at the lowest level with the whole path,
// only the path's people for the reader (D6), the line step by step, "dziś" (Y1), at once without animations
// (D5), a path wider than the screen under 0.4 and back to 0.4 after (F2) · AC-3 the banner once the line
// reaches "Do", gone after 4 s or the phone's longer time — text, not controls (D43); from someone else two
// lines (O2) · AC-4 no path: the banner, the tree as it was · the end of the light (D49) · no icon without "ja"
// (D3) or in presentation · text at 200 % on 360 dp · tap targets (retro 3, R2). The made-up family of the
// debug build, with Teofil, who has no family (D4; family-data.md).
// ISSUE-055 (drzewo.md v1.29): "Od" — the person in the middle, also without "ja" (D78) · a lit path stays until back
// — a touch, a double tap, one and two fingers keep it; "Anuluj" keeps it, a new "Do" takes its place (D79) · the tree
// alone while lit: no card, time row or + / −, the banner until the end (D80) · after back "Od" in the middle and the
// year from before the path (D81).

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

/// The people on the tree for the reader: a node says "w środek", the one in the middle "otwórz". Semantics on.
/// With a path lit its people have no hint and no action: a touch does nothing (D79; until v1.28 "zakończ ścieżkę").
SemanticsFinder _forReader() => find.semantics.byHint(
  RegExp(r'^(w środek|otwórz|zakończ ścieżkę|przybliż)$'),
);

/// The path's line on the tree.
Finder _pathLine() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is PathLinePainter,
);

double _progress(WidgetTester tester) =>
    (tester.widget<CustomPaint>(_pathLine()).painter! as PathLinePainter)
        .progress
        .value;

/// The banner's opacity: 0 before and after its time.
double _banner(WidgetTester tester) {
  final Finder box = find.byType(PathBanner);
  if (!_shown(box)) return 0;
  return tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: box, matching: find.byType(AnimatedOpacity)),
      )
      .opacity;
}

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .entry(0, 0);

/// A route's transition — the theme's page transition takes longer than 0.4 s.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
}

/// In the list of a tile only — the tree's card under it may show the same name.
Finder _inList(Finder f) =>
    find.descendant(of: find.byType(PersonChoiceScreen), matching: f);

/// In the window only.
Finder _inWindow(Finder f) =>
    find.descendant(of: find.byType(Dialog), matching: f);

/// A name under a node of the tree (13 sp, the line 1.3) — not the letters in a circle.
Finder _name(String name) => find.byWidgetPredicate(
  (w) => w is Text && w.data == name && w.style?.height == 1.3,
);

/// A point of the tree's area where no one stands.
Offset _empty(WidgetTester tester) {
  final Rect area = tester.getRect(find.byType(InteractiveViewer));
  return area.topLeft + const Offset(20, 20);
}

void main() {
  late GrobingDatabase db;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
    // A path raises the level chosen (D57), which lives while the app runs: each test starts as a new app does.
    treeLevel = 1;
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  }

  Future<void> pumpTree(
    WidgetTester tester, {
    int? focus,
    double text = 1,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3; // 360 × 800 dp
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
      treeFocus: focus,
    );
    await _pumpUntil(tester, () => _shown(find.byType(TreeScreen)));
    await _pumpUntil(tester, () => _shown(find.byTooltip('Połącz dwie osoby')));
    await _settle(tester);
  }

  /// The list of a tile: [query] typed, [name] — the card — tapped.
  Future<void> choose(WidgetTester tester, String query, String name) async {
    await _pumpUntil(tester, () => _shown(find.byType(PersonChoiceScreen)));
    await _settle(tester);
    await tester.enterText(_inList(find.byType(TextField)), query);
    await _pumpUntil(tester, () => _shown(_inList(find.text(name))));
    await tester.tap(_inList(find.text(name)));
    await _pumpUntil(tester, () => !_shown(find.byType(PersonChoiceScreen)));
    await _settle(tester);
  }

  /// Element 1 → 7: the window, "Od" changed when [from] is given, "Do" chosen.
  Future<void> connect(
    WidgetTester tester,
    String query,
    String name, {
    (String, String)? from,
  }) async {
    await tester.tap(find.byTooltip('Połącz dwie osoby'));
    await _settle(tester);
    if (from != null) {
      await tester.tap(_inWindow(find.text('Od')));
      await choose(tester, from.$1, from.$2);
    }
    await tester.tap(_inWindow(find.text('Wybierz osobę')));
    await choose(tester, query, name);
    await _pumpUntil(tester, () => !_shown(find.byType(Dialog)));
  }

  /// Until the line has come to "Do" and the banner is there.
  Future<void> untilBanner(WidgetTester tester) =>
      _pumpUntil(tester, () => _banner(tester) == 1);

  testWidgets(
    'AC-1 — the window: "Od" Ja, "Do" empty; "Anuluj" and back close it with nothing; the list without "Od", '
    'the search; the choice closes the window; tap targets (R2)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Połącz dwie osoby'), findsOneWidget);
      expect(find.bySemanticsLabel('Od: Mateusz Wymyślony'), findsOneWidget);
      expect(find.bySemanticsLabel('Do: wybierz osobę'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expectEveryButtonTappable(tester);

      await tester.tap(find.text('Anuluj'));
      await _settle(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('ur. 1983 · to ja'), findsOneWidget);

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(TreeScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      await tester.tap(_inWindow(find.text('Wybierz osobę')));
      await _pumpUntil(tester, () => _shown(find.text('Do kogo?')));
      await _settle(tester);
      // "Od" is not on the list of "Do": the same person has no path.
      await tester.enterText(_inList(find.byType(TextField)), 'mateusz');
      await _pumpUntil(
        tester,
        () => _shown(find.text('Nie ma osoby „mateusz”.')),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      await tester.enterText(_inList(find.byType(TextField)), 'wand');
      await _pumpUntil(
        tester,
        () => _shown(_inList(find.text('Wanda Przykładowa z d. Testowicz'))),
      );
      await tester.tap(_inList(find.text('Wanda Przykładowa z d. Testowicz')));
      await _pumpUntil(tester, () => !_shown(find.byType(Dialog)));
      await _settle(tester);
      expect(find.byType(PersonChoiceScreen), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-1 — "Od" changed to Piotr: back in the window with him; not on the list of "Do"',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      await tester.tap(_inWindow(find.text('Od')));
      await _pumpUntil(tester, () => _shown(find.text('Od kogo?')));
      await choose(tester, 'piotr', 'Piotr Przykładowy');
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.bySemanticsLabel('Od: Piotr Przykładowy'), findsOneWidget);

      await tester.tap(_inWindow(find.text('Wybierz osobę')));
      await _pumpUntil(tester, () => _shown(find.text('Do kogo?')));
      await _settle(tester);
      await tester.enterText(_inList(find.byType(TextField)), 'piotr');
      await _pumpUntil(
        tester,
        () => _shown(find.text('Nie ma osoby „piotr”.')),
      );
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-055 AC-4, D80, D81 — Ja → Wanda: "Od" stays in the middle; the tree alone — no card, time row or + / −; '
    'only the path\'s four for the reader, without an action (D79); the line step by step, the banner after it and '
    'still there 10 s later; back brings the card; tap targets and contrast (R2)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      // The people in view for the reader (the rest of level 2 is off the screen).
      expect(_forReader().evaluate().length, greaterThan(4));

      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      // D80: the tree alone — the card with its time row and the level's + / − go.
      expect(find.byType(TreeTimeBar), findsNothing);
      expect(find.text('ur. 1983 · to ja'), findsNothing);
      expect(find.byTooltip('Dalsza rodzina'), findsNothing);
      expect(find.byTooltip('Bliższa rodzina'), findsNothing);
      // Ja, Kasia, Piotr, Wanda — the rest at 30 % and out of the reader's tree (D6); a touch of them does nothing
      // (D79): no "w środek", "otwórz" or "zakończ ścieżkę" — at most "przybliż" where a place is under 24 dp (D52).
      await _pumpUntil(tester, () => _shown(_pathLine()));
      expect(
        find.semantics.byHint(RegExp(r'^(w środek|otwórz|zakończ ścieżkę)$')),
        findsNothing,
      );
      expect(_forReader().evaluate().length, lessThanOrEqualTo(4));
      for (final String who in [
        'Mateusz Wymyślony',
        'Kasia Wymyślona',
        'Piotr Przykładowy',
        'Wanda Przykładowa',
      ]) {
        expect(
          find.bySemanticsLabel(RegExp('^$who')),
          findsOneWidget,
          reason: who,
        );
      }
      // The line runs a step every 0.7 s (D5): part of the way, and no banner yet.
      await _pumpUntil(tester, () => _progress(tester) > 0);
      expect(_progress(tester), lessThan(1));
      expect(_banner(tester), 0);
      final double before = _progress(tester);
      await tester.pump(const Duration(milliseconds: 700));
      expect(_progress(tester) - before, closeTo(1 / 3, 0.05));
      await untilBanner(tester);
      expect(_progress(tester), 1);
      expect(find.text('Babcia mojej żony'), findsOneWidget);
      // Faded in — at opacity 0 a node has no semantics.
      await tester.pump(const Duration(milliseconds: 300));
      // A live region: the reader says it once it comes (SC 4.1.3; D43).
      final SemanticsNode node = tester.getSemantics(
        find.text('Babcia mojej żony'),
      );
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      // The frame keeps the path under the banner: its bottom over the top of Wanda's circle, the highest row.
      final double circleTop =
          tester.getRect(_name('Wanda')).top -
          (TreeMetrics.node + 4) * _scale(tester);
      expect(
        tester.getRect(find.byType(PathBanner)).bottom,
        lessThanOrEqualTo(circleTop + 0.5),
      );
      // From "Ja" the frame is zoomed out: a person's place under 48 dp, and a touch there only zooms in (D17, D52) —
      // the bar's targets at scale 1: tree_rotate_test. The labels stay.
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expectEveryButtonTappable(tester);

      // D80: the banner stays while the path does — no 4 s any more.
      await tester.pump(const Duration(seconds: 10));
      expect(_banner(tester), 1);
      expect(_pathLine(), findsOneWidget);

      // D81: back — "Od", Ja, in the middle, the card and + / − again.
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_pathLine(), findsNothing);
      expect(find.byType(TreeScreen), findsOneWidget);
      expect(find.text('ur. 1983 · to ja'), findsOneWidget);
      expect(find.byTooltip('Dalsza rodzina'), findsOneWidget);
      expect(_forReader().evaluate().length, greaterThan(4));
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D79 — a lit path stays: a touch of empty space, a touch of a person off the path, a double tap; back ends it '
    'and stays on the tree, "Od" in the middle (D81) — the reader has everyone again',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);
      await tester.tapAt(_empty(tester));
      await _settle(tester);
      expect(_pathLine(), findsOneWidget);
      expect(_banner(tester), 1);

      // A person off the path, in view: a touch does nothing. By the node — zoomed out, a hidden name's middle lies
      // past it (I2).
      // The touch of the empty space above zoomed in there — places under 24 dp (D52), the view only.
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      final Element off = find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.container &&
                (w.properties.label?.contains(', ') ?? false) &&
                !RegExp(
                  '^(Mateusz Wymyślony|Kasia Wymyślona|Piotr Przykładowy|Wanda Przykładowa)',
                ).hasMatch(w.properties.label!),
          )
          .evaluate()
          .firstWhere(
            (e) => area
                .deflate(12)
                .contains(
                  tester.getCenter(find.byElementPredicate((x) => x == e)),
                ),
          );
      await tester.tapAt(
        tester.getCenter(find.byElementPredicate((x) => x == off)),
      );
      await _settle(tester);
      expect(_pathLine(), findsOneWidget);
      expect(find.byType(TreeTimeBar), findsNothing);

      // A double tap changes the view only (D79; until v1.28 it ended the path). Which way the view goes depends on
      // who is left on the screen (the glide back home), so only the path is checked.
      final Offset empty = _empty(tester);
      await tester.tapAt(empty);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(empty);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_pathLine(), findsOneWidget);
      expect(_banner(tester), 1);

      // Back ends it, on the tree, with "Od" in the middle (D81).
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_pathLine(), findsNothing);
      expect(find.byType(TreeScreen), findsOneWidget);
      expect(find.text('ur. 1983 · to ja'), findsOneWidget);
      expect(_forReader().evaluate().length, greaterThan(4));
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-055 AC-1 (D78) — "Od" from the tree: a person put in the middle is the window\'s "Od"',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      final Finder michal = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.container &&
            (w.properties.label?.startsWith('Michał Wymyślony') ?? false),
      );
      await tester.tapAt(tester.getCenter(michal));
      await _settle(tester);
      expect(find.text('Michał Wymyślony'), findsOneWidget);

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Od: Michał Wymyślony'), findsOneWidget);
      expect(find.bySemanticsLabel('Do: wybierz osobę'), findsOneWidget);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D79 — the window over a lit path: "Anuluj" keeps the path; a new "Do" takes its place',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Anuluj'));
      await _settle(tester);
      expect(_pathLine(), findsOneWidget);
      expect(find.text('Babcia mojej żony'), findsOneWidget);

      await connect(tester, 'zofia', 'Zofia Wymyślona');
      await untilBanner(tester);
      expect(find.text('Moja córka'), findsOneWidget);
      expect(find.text('Babcia mojej żony'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D79 — two fingers zoom over a lit path and keep it; one finger drags it and keeps it (until v1.28 two '
    'fingers ended it)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);

      final Offset c = tester.getCenter(find.byType(InteractiveViewer));
      await tester.dragFrom(c, const Offset(60, 40));
      await _settle(tester);
      expect(_pathLine(), findsOneWidget);

      final double before = _scale(tester);
      final TestGesture a = await tester.startGesture(c - const Offset(40, 0));
      final TestGesture b = await tester.startGesture(c + const Offset(40, 0));
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await a.moveBy(const Offset(-12, 0));
        await b.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await _settle(tester);
      expect(_scale(tester), greaterThan(before));
      expect(_pathLine(), findsOneWidget);
      expect(_banner(tester), 1);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-4 — Teofil, with no family: the banner of element 10, the tree as it was',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      final int people = _forReader().evaluate().length;

      await connect(tester, 'teof', 'Teofil Przykładowski');
      await untilBanner(tester);
      expect(find.text(noPathText), findsOneWidget);
      expect(_pathLine(), findsNothing);
      expect(find.text('ur. 1983 · to ja'), findsOneWidget);
      expect(_forReader(), findsExactly(people));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_banner(tester), 0);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'O2 (D47) — from Piotr to Zofia, born 2012: "Piotr Przykładowy → Zofia Wymyślona" over "Wnuczka"',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await connect(
        tester,
        'zofia',
        'Zofia Wymyślona',
        from: ('piotr', 'Piotr Przykładowy'),
      );
      await untilBanner(tester);
      expect(find.text('Piotr Przykładowy → Zofia Wymyślona'), findsOneWidget);
      expect(find.text('Wnuczka'), findsOneWidget);
      // The reader hears the direction in words, not the arrow (ui review of ISSUE-039).
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.bySemanticsLabel(
          'Od: Piotr Przykładowy, do: Zofia Wymyślona — Wnuczka',
        ),
        findsOneWidget,
      );
      // D81: "Od", Piotr, in the middle — after back his card, which speaks from "ja", as always (G2).
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.text('Piotr Przykładowy'), findsOneWidget);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'F2 (D46) — a path wider than the screen: under 0.4 while lit, both ends in view; after back the scale stays '
    '(drzewo.md D57, D81 — the scale no longer belongs to a level)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);

      // From "Ja" in the middle (D81) — until v1.28 Ja → Zdzisław, framed from Zdzisław in the middle.
      await connect(tester, 'ryszard t', 'Ryszard Testowiak');
      await untilBanner(tester);
      expect(_scale(tester), lessThan(0.4));
      expect(_scale(tester), greaterThanOrEqualTo(treeMinScaleAtLeast));
      final double lit = _scale(tester);
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      for (final String name in ['Ja', 'Ryszard']) {
        final Rect r = tester.getRect(_name(name));
        expect(area.contains(r.center), isTrue, reason: '$name in view');
      }
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_pathLine(), findsNothing);
      expect(_scale(tester), closeTo(lit, 1e-6));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'F2 — the ends\' names of a wide path whole on the screen, 24 dp in (ui review of ISSUE-039, MAJOR): under 1 the '
    'names keep their size, so the frame counts them; no + / − while lit (D80)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);

      await connect(tester, 'ryszard t', 'Ryszard Testowiak');
      await untilBanner(tester);
      expect(_scale(tester), lessThan(0.4));
      expect(find.byTooltip('Dalsza rodzina'), findsNothing);
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      for (final String name in ['Ja', 'Ryszard']) {
        final Rect r = tester.getRect(_name(name));
        expect(
          area.deflate(24 - 0.5).contains(r.topLeft) &&
              area.deflate(24 - 0.5).contains(r.bottomRight),
          isTrue,
          reason: '$name whole on the screen: $r in $area',
        );
      }
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-049 AC-5 (D57) — a path past the level chosen raises it: Ja → Ryszard Przykładniak, from him at level 3, '
    'all of it in view; after the end the level and the scale stay; a path that needs less does not lower it',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      expect(treeLevel, 1);

      await connect(tester, 'przykładn', 'Ryszard Przykładniak');
      await untilBanner(tester);
      expect(treeLevel, 3);
      expect(find.text('Teść siostry partnerki mojego brata'), findsWidgets);
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      for (final String name in [
        'Ja',
        'Michał',
        'Natalia',
        'Patrycja',
        'Konrad',
      ]) {
        final Rect r = tester.getRect(_name(name));
        expect(area.contains(r.center), isTrue, reason: '$name in view');
      }
      final Finder ryszard = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.container &&
            (w.properties.label?.startsWith('Ryszard Przykładniak') ?? false),
      );
      expect(area.contains(tester.getCenter(ryszard)), isTrue);

      final double lit = _scale(tester);
      // The end of the path: back (D79).
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_pathLine(), findsNothing);
      expect(_scale(tester), closeTo(lit, 1e-6));
      expect(treeLevel, 3);

      // Ja → Wanda needs less (D50): the level stays where it is.
      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);
      expect(treeLevel, 3);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'Y1 (D48), D81 — the slider on 1950: the path at "dziś" (Ja, born 1983, on it); a new "Do" keeps the year from '
    'before the first path; back → 1950 again, ▶ standing',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      tester.widget<TreeTimeBar>(find.byType(TreeTimeBar)).onYear(1950);
      await _settle(tester);
      expect(find.text('1950'), findsOneWidget);

      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);
      expect(find.byType(TreeTimeBar), findsNothing);
      expect(_name('Ja'), findsOneWidget);

      await connect(tester, 'zofia', 'Zofia Wymyślona');
      await untilBanner(tester);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      final TreeTimeBar bar = tester.widget<TreeTimeBar>(
        find.byType(TreeTimeBar),
      );
      expect(bar.year, 1950);
      expect(bar.playing, isFalse);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D5 — the system\'s animations off: the whole path and the banner at once',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);

      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await tester.pump();
      expect(_progress(tester), 1);
      expect(_banner(tester), 1);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D43, D80 — "Czas na działanie": the banner of element 10 stays as long as the phone asks, for text, not '
    'controls; the banner of a path stays until the path ends',
    (tester) async {
      final List<Object?> asked = [];
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_external, (call) async {
        if (call.method != 'recommendedTimeout') return null;
        asked.add(call.arguments);
        return (call.arguments as Map)['controls'] == false ? 10000 : 5000;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_external, null));
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);

      await connect(tester, 'teof', 'Teofil Przykładowski');
      await untilBanner(tester);
      expect(asked, [
        {'ms': 4000, 'controls': false},
      ]);
      await tester.pump(const Duration(seconds: 5));
      expect(_banner(tester), 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_banner(tester), 0);

      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);
      await tester.pump(const Duration(seconds: 11));
      expect(_banner(tester), 1);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D78 — without "ja" "Połącz dwie osoby" is there: the window from the person in the middle, Wanda; the banner in '
    'two lines (D47); "Przesyłaj na telewizor" stays (until v1.28 no icon — D3)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      final int wanda = (await tester.runAsync(
        () => (db.select(
          db.persons,
        )..where((p) => p.givenNames.equals('Wanda'))).getSingle(),
      ))!.id;
      await tester.runAsync(
        () => db
            .update(db.settings)
            .write(const SettingsCompanion(mePersonId: Value(null))),
      );
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
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
        treeFocus: wanda,
      );
      await _pumpUntil(
        tester,
        () => _shown(find.byTooltip('Połącz dwie osoby')),
      );
      expect(find.byTooltip('Przesyłaj na telewizor'), findsOneWidget);
      await _settle(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Od: Wanda Przykładowa'), findsOneWidget);
      await tester.tap(_inWindow(find.text('Wybierz osobę')));
      await choose(tester, 'piotr', 'Piotr Przykładowy');
      await _pumpUntil(tester, () => !_shown(find.byType(Dialog)));
      await untilBanner(tester);
      expect(
        find.text('Wanda Przykładowa → Piotr Przykładowy'),
        findsOneWidget,
      );
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'text at 200 % on 360 dp: the tiles one under the other, the names whole; the banner over the path, not on it',
    (tester) async {
      // The test font draws every letter as a square: the bottom bar (lib/app/tabs.dart, not this item's)
      // overflows in it at 200 % and not on a phone — let through only that, as tree_screen_test AC-7.
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
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester, text: 2);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.tap(find.byTooltip('Połącz dwie osoby'));
      await _settle(tester);
      final Rect od = tester.getRect(_inWindow(find.text('Od')));
      final Rect to = tester.getRect(_inWindow(find.text('Do')));
      expect(to.top, greaterThan(od.bottom));
      expect(to.left, closeTo(od.left, 0.5));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Anuluj'));
      await _settle(tester);

      await connect(
        tester,
        'zofia',
        'Zofia Wymyślona',
        from: ('piotr', 'Piotr Przykładowy'),
      );
      await untilBanner(tester);
      expect(tester.takeException(), isNull);
      // The frame leaves room for the banner as tall as it is drawn (Dev report → Found b: measured 13 dp short
      // at 200 %). Whether the path is under it — at 100 %, in the test of AC-2: in the test font the banner here
      // is taller than half the tree's area, where the frame stops making room on purpose.
      expect(
        PathBanner.heightFor(
          (top: 'Piotr Przykładowy → Zofia Wymyślona', text: 'Wnuczka'),
          360 - 32,
          const TextScaler.linear(2),
        ),
        closeTo(tester.getSize(find.byType(PathBanner)).height, 0.5),
      );
      // The path framed at 0.34: a person's place under 48 dp, as on the zoomed-out tree (drzewo.md D17) — and a
      // touch there only ends the light. The labels stay.
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'presentation (D49): casting ends the light, and the mode has no "Połącz dwie osoby"',
    (tester) async {
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_external, (call) async {
        return call.method == 'openCastSettings' ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_external, null));
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await connect(tester, 'wand', 'Wanda Przykładowa z d. Testowicz');
      await untilBanner(tester);

      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      expect(_pathLine(), findsNothing);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(2400, 1080);
      await _settle(tester);
      expect(find.text('Drzewo'), findsNothing);
      expect(find.byTooltip('Połącz dwie osoby'), findsNothing);
      await cleanUp(tester);
    },
  );
}
