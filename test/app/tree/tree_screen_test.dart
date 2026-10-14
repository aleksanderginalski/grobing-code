import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, PlatformException, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/people/me_picker_screen.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/tree_screen.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_family.dart';

import '../../support/a11y.dart';
import '../../support/style_checks.dart';

// ISSUE-033 — the Drzewo tab (05_DESIGN/drzewo.md v1.6; US-009), happy path per AC: AC-1 "Ja" in the middle
// at level 2 · AC-2 a touch puts a person in the middle and the card says who they are; the middle or "Pokaż"
// opens their view · AC-3 − / + and a double tap change the level with the pill · AC-5 a farther relation in
// the card · AC-6 "Pokaż w drzewie" from a person's view · AC-7 text at 200 % on 360 dp · the states (an
// empty base, no "ja", a person without a family) · tap targets (retro 3, R2). AC-4 (the trace) —
// tree_layout_test.dart; the kinship words — kinship_names_test.dart. The made-up family of the debug build
// (family-data.md).
//
// ISSUE-034 — presentation mode (drzewo.md element 11, D16; US-009 AC-8): the TV icon only with a tree;
// landscape, no bars, level 2 fitted, no buttons, the hint for 4 s; a touch puts a person in the middle, the
// middle opens nothing, the edges of the bars take no drag, the empty space shows "Zakończ prezentację" — from
// ISSUE-038 with the bar, for 5 s (D3); it and back return portrait with the same person, the card and the bar. The phone's turn is the test
// view's new size; what the tree asks of the system — the platform channel (presentation_mode_test.dart).
//
// ISSUE-036 — "Przesyłaj na telewizor" in place of the TV icon (drzewo.md element 1, D29, D30): AC-1 the
// system's cast screen opens (the `grobing/external` channel), the tree waits until the app is back on top —
// inactive, then resumed, as measured on the emulator — and presents without the hint; a second tap meanwhile
// opens nothing (D3); the reader hears "w ustawieniach telefonu" · AC-2 a phone without that screen, or a
// native error: presentation at once, with the hint for 4 s.

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

/// The people on the tree: a node says "w środek", the one in the middle "otwórz".
Finder _people() => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.hint == 'w środek' || w.properties.hint == 'otwórz'),
);

/// The move of the people and of the view, and the pill's moment.
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

/// The phone turned: the test view's new size (360 × 800 dp ↔ 800 × 360 dp), then the fit after it.
Future<void> _turn(WidgetTester tester, {required bool landscape}) async {
  tester.view.physicalSize = landscape
      ? const Size(2400, 1080)
      : const Size(1080, 2400);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await _afterMove(tester);
}

/// A point of the tree's area where no one stands, 40 dp in from its edges (the bars' 24 dp take no touch).
Offset _empty(WidgetTester tester) {
  final Rect area = tester.getRect(find.byType(InteractiveViewer));
  final List<Rect> people = [
    for (final Element e in _nodes().evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ];
  for (final Offset p in [
    area.bottomLeft + const Offset(40, -40),
    area.bottomRight + const Offset(-40, -40),
    area.topLeft + const Offset(40, 40),
  ]) {
    if (!people.any((r) => r.inflate(8).contains(p))) return p;
  }
  fail('no empty space on the tree');
}

double _opacityOf(WidgetTester tester, String text) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

// The function, not a tile's name (drzewo.md v1.8, D26); a hard space after "w" (style-b.md rule 6).
const String _hint =
    'Obraz na telewizor: przesyłanie ekranu w szybkich ustawieniach telefonu';

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // The pill's and the settle's timers, and drift's stream closing on the fake clock.
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  }

  /// The app's first route stands for the map; the tree opens over it as the tab does.
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
  }

  Future<int> personNamed(WidgetTester tester, String given, String surname) =>
      tester
          .runAsync(
            () =>
                (db.select(db.persons)..where(
                      (p) =>
                          p.givenNames.equals(given) &
                          p.surname.equals(surname),
                    ))
                    .getSingle()
                    .then((p) => p.id),
          )
          .then((id) => id!);

  testWidgets(
    'AC-1 — "Ja" in the middle at level 2: 20 people, the card "to ja"; tap targets (R2)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await _pumpUntil(tester, () => _shown(_people()));
      await _afterMove(tester);

      expect(_people(), findsNWidgets(20));
      expect(find.text('Mateusz Wymyślony'), findsOneWidget);
      expect(find.text('ur. 1983 · to ja'), findsOneWidget);
      final SemanticsHandle semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'^Mateusz Wymyślony, ur\. 1983, to ja$')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Kasia Wymyślona z d\. Przykładowa, ur\. 1985, Moja żona$'),
        ),
        findsOneWidget,
      );
      // A relation's name is in the author's voice (ISSUE-035, G2 — drzewo.md D28): nowhere "Twoja" / "Twój".
      expect(find.bySemanticsLabel(RegExp('Twoj|Twój')), findsNothing);
      expect(find.textContaining(RegExp('Twoj|Twój')), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      // The glow of the person in the middle lies under the circle (ui review, MAJOR).
      expectNoGlowOverContent(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-2 — a touch puts Kasia in the middle; "Pokaż" opens her view with Drzewo active',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await _pumpUntil(tester, () => _shown(find.text('Kasia')));
      await _afterMove(tester);

      await tester.tap(find.text('Kasia'));
      await _afterMove(tester);
      expect(find.text('Kasia Wymyślona z d. Przykładowa'), findsOneWidget);
      expect(find.text('ur. 1985 · Moja żona'), findsOneWidget);

      await tester.tap(find.text('Pokaż'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      expect(
        tester.widget<PersonScreen>(find.byType(PersonScreen)).tab,
        AppTab.tree,
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3 — − adds a level with the pill, + takes it back; a double tap on empty space zooms in',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await _pumpUntil(tester, () => _shown(_people()));
      await _afterMove(tester);

      await tester.tap(find.byTooltip('Oddal — dalsza rodzina'));
      await _afterMove(tester);
      expect(find.text('Poziom 3 · 66 osób'), findsOneWidget);
      expect(_people(), findsNWidgets(66));

      await tester.tap(find.byTooltip('Oddal — dalsza rodzina'));
      await _afterMove(tester);
      expect(find.text('Poziom 4 · 99 osób'), findsOneWidget);

      await tester.tap(find.byTooltip('Przybliż — bliższa rodzina'));
      await _afterMove(tester);
      await tester.tap(find.byTooltip('Przybliż — bliższa rodzina'));
      await _afterMove(tester);
      expect(find.text('Poziom 2 · 20 osób'), findsOneWidget);
      expect(_people(), findsNWidgets(20));

      // Empty space at the bottom left of the tree's area, under everyone.
      final Rect area = tester.getRect(find.byType(InteractiveViewer));
      final Offset empty = area.bottomLeft + const Offset(24, -24);
      await tester.tapAt(empty);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(empty);
      await _afterMove(tester);
      expect(find.text('Poziom 1 · 6 osób'), findsOneWidget);
      expect(_people(), findsNWidgets(6));
      await cleanUp(tester);
    },
  );

  testWidgets('AC-5 — a farther relation in the card: the wife\'s aunt', (
    tester,
  ) async {
    await tester.runAsync(() => addFictionalFamily(db));
    await pumpTree(tester);
    await _pumpUntil(tester, () => _shown(find.text('Kasia')));
    await _afterMove(tester);
    await tester.tap(find.text('Kasia'));
    await _afterMove(tester);
    await tester.tap(find.text('Jolanta'));
    await _afterMove(tester);
    expect(find.text('ur. 1961 · Ciotka mojej żony'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets(
    'AC-6 — "Pokaż w drzewie" in a person\'s view opens Drzewo with them in the middle; none without a family',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      final int jozef = await personNamed(tester, 'Józef', 'Wymyślony');
      final int alone = (await tester.runAsync(
        () => db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(
                givenNames: const Value('Teofil'),
                surname: const Value('Przykładowski'),
              ),
            ),
      ))!;
      // Tall enough for the whole person's view: its list builds only what is on the screen.
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: GrobingTheme.dark,
          home: const Scaffold(body: Text('mapa')),
        ),
      );

      openPersonView(
        tester.element(find.text('mapa')),
        db,
        alone,
        tab: AppTab.people,
      );
      await _pumpUntil(
        tester,
        () => _shown(find.textContaining('Rodziny jeszcze nie ma')),
      );
      expect(find.text('Pokaż w drzewie'), findsNothing);
      Navigator.of(tester.element(find.byType(PersonScreen))).pop();
      await tester.pump(const Duration(milliseconds: 500));

      openPersonView(
        tester.element(find.text('mapa')),
        db,
        jozef,
        tab: AppTab.people,
      );
      await _pumpUntil(tester, () => _shown(find.text('Pokaż w drzewie')));
      await tester.ensureVisible(find.text('Pokaż w drzewie'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pokaż w drzewie'));
      await _pumpUntil(tester, () => _shown(find.byType(TreeScreen)));
      await _pumpUntil(
        tester,
        () => _shown(find.text('1925–2004 · Mój dziadek')),
      );
      expect(find.text('Józef Wymyślony'), findsOneWidget);
      expect(find.byType(PersonScreen), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets('AC-7 — text at 200 % on 360 dp: a person\'s place 160 dp and the row taller, the initials in the circle, '
      '"Pokaż" under the text', (tester) async {
    // The test font draws every letter as a square, wider and taller than Roboto: the bottom bar
    // (lib/app/tabs.dart, not this item's) overflows in it at 200 % and not on a phone — the map's test of
    // 200 % leaves the bar out for the same reason. Only that overflow is let through here; whether the
    // names are whole in Roboto is the emulator's (Dev report, screenshot 10b, 360 dp, 200 %).
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final String error = details.toString();
      if (error.contains('overflowed') && error.contains('lib/app/tabs.dart')) {
        return;
      }
      previous?.call(details);
    };
    await tester.runAsync(() => addFictionalFamily(db));
    await pumpTree(tester, text: 2);
    await _pumpUntil(tester, () => _shown(find.text('Kasia')));
    await _afterMove(tester);

    // A person's place grows with the text up to twice — 80 → 160 dp, as the mini tree (osoba.md v2.2).
    final Finder kasia = find.ancestor(
      of: find.text('Kasia'),
      matching: _people(),
    );
    expect(tester.getSize(kasia).width, 160);
    // The name keeps its line: 26 sp, one line, the rest of the node above it.
    final Text name = tester.widget(find.text('Kasia'));
    expect(name.maxLines, 1);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Kasia'))).scale(13),
      26,
    );
    // The initials grow at most 1.3× and stay inside the 44 dp circle.
    expect(tester.getSize(find.text('KW')).width, lessThanOrEqualTo(44));
    // "Pokaż" stands under the card's text (D20).
    expect(
      tester.getTopLeft(find.text('Pokaż')).dy,
      greaterThan(tester.getBottomLeft(find.text('ur. 1983 · to ja')).dy),
    );
    await cleanUp(tester);
    FlutterError.onError = previous;
  });

  testWidgets(
    'States — an empty base; no "ja" with "Wybierz, która osoba to Ty"',
    (tester) async {
      await pumpTree(tester);
      await _pumpUntil(
        tester,
        () => _shown(
          find.text('Tu pojawi się drzewo — osoby z grobów i ich rodziny.'),
        ),
      );
      expect(find.byTooltip('Oddal — dalsza rodzina'), findsNothing);
      // No tree, no casting (element 1, ISSUE-034, ISSUE-036).
      expect(find.byTooltip('Przesyłaj na telewizor'), findsNothing);

      await tester.runAsync(
        () => db
            .into(db.persons)
            .insert(PersonsCompanion.insert(givenNames: const Value('Ula'))),
      );
      await _pumpUntil(
        tester,
        () =>
            _shown(find.text('Aplikacja nie wie jeszcze, która osoba to Ty.')),
      );
      expect(find.byTooltip('Przesyłaj na telewizor'), findsNothing);
      await tester.tap(find.text('Wybierz, która osoba to Ty'));
      await _pumpUntil(tester, () => _shown(find.byType(MePickerScreen)));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'States — a person without a family: only them, "nie wiadomo jeszcze, kim jest dla mnie"',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      final int alone = (await tester.runAsync(
        () => db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(
                givenNames: const Value('Teofil'),
                surname: const Value('Przykładowski'),
              ),
            ),
      ))!;
      await pumpTree(tester, focus: alone);
      await _pumpUntil(tester, () => _shown(_people()));
      await _afterMove(tester);
      expect(_people(), findsOneWidget);
      expect(
        find.text('bez dat · nie wiadomo jeszcze, kim jest dla mnie'),
        findsOneWidget,
      );
      await cleanUp(tester);
    },
  );

  // ---- ISSUE-034 — presentation mode ----

  /// What the tree asks of the system about its bars and orientation.
  List<String> recordChrome() {
    final List<String> chrome = [];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations' ||
          call.method == 'SystemChrome.setEnabledSystemUIMode') {
        chrome.add('${call.method.substring(13)} ${call.arguments}');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return chrome;
  }

  const List<String> leaving = [
    'setEnabledSystemUIMode SystemUiMode.edgeToEdge',
    'setPreferredOrientations [DeviceOrientation.portraitUp]',
    'setPreferredOrientations []',
  ];

  const List<String> entering = [
    'setPreferredOrientations '
        '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]',
    'setEnabledSystemUIMode SystemUiMode.immersiveSticky',
  ];

  /// The system's cast screen (`ExternalLinks.kt`): the calls the tree makes, answered with [opens] — false
  /// stands for a phone without that screen (ISSUE-036 AC-2).
  List<String> mockCastScreen({bool opens = true}) {
    final List<String> calls = [];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_external, (call) async {
      calls.add(call.method);
      return opens;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_external, null));
    return calls;
  }

  /// The app under the system's screen and back on top, as measured on the emulator (ISSUE-036, Dev report →
  /// Krok 0): inactive when it opens, resumed when it closes. A quick back never hides the app; [stayed] — the
  /// screen was there long enough for Android to stop the app under it.
  void backFromSystemScreen(WidgetTester tester, {bool stayed = false}) {
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    if (stayed) {
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  /// "Przesyłaj na telewizor", the system's screen and back, the phone turned.
  Future<void> castAndBack(WidgetTester tester, {bool stayed = false}) async {
    await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
    await tester.pump();
    backFromSystemScreen(tester, stayed: stayed);
    await tester.pump();
    await _turn(tester, landscape: true);
  }

  /// The tree from "Ja", the system's cast screen and back, the phone turned.
  Future<List<String>> present(WidgetTester tester) async {
    final List<String> chrome = recordChrome();
    mockCastScreen();
    await tester.runAsync(() => addFictionalFamily(db));
    await pumpTree(tester);
    await _pumpUntil(tester, () => _shown(_people()));
    await _afterMove(tester);
    await castAndBack(tester);
    return chrome;
  }

  Semantics node(WidgetTester tester, String label) => tester.widget(
    find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.container &&
          (w.properties.label?.startsWith(label) ?? false),
    ),
  );

  void expectAllOnScreen(WidgetTester tester, Size screen) {
    final Rect view = Offset.zero & screen;
    for (final Element e in _nodes().evaluate()) {
      final Rect r = tester.getRect(find.byWidget(e.widget));
      expect(
        view.contains(r.topLeft) &&
            view.contains(r.bottomRight - const Offset(0.1, 0.1)),
        isTrue,
        reason: '${(e.widget as Semantics).properties.label} at $r',
      );
    }
  }

  testWidgets(
    'ISSUE-036 AC-1 + AC-8 — "Przesyłaj na telewizor" opens the system\'s cast screen; the tree waits until the app is '
    'back on top, a second tap meanwhile opens nothing (D3); then landscape, no bars, level 2 fitted, no buttons and '
    'no hint; the reader hears where the tap leads; tap targets (R2)',
    (tester) async {
      final List<String> chrome = recordChrome();
      final List<String> calls = mockCastScreen();
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await _pumpUntil(tester, () => _shown(_people()));
      await _afterMove(tester);

      // Element 1 (D30): the cast icon in place of the TV icon, read with "w ustawieniach telefonu" and pressable.
      expect(find.byIcon(Icons.cast_outlined), findsOneWidget);
      expect(find.byIcon(Icons.tv_outlined), findsNothing);
      SemanticsHandle semantics = tester.ensureSemantics();
      final Finder cast = find.bySemanticsLabel(
        'Przesyłaj na telewizor — w ustawieniach telefonu',
      );
      expect(cast, findsOneWidget);
      expect(
        tester.getSemantics(cast),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();

      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      expect(calls, ['openCastSettings']);
      // The system's screen is open: nothing turns under it.
      expect(chrome, isEmpty);
      expect(find.byType(GrobingTabBar), findsOneWidget);

      backFromSystemScreen(tester);
      await tester.pump();
      await _turn(tester, landscape: true);
      // ISSUE-038 D4: entering asks once how long controls stay ("Czas na działanie").
      expect(calls, ['openCastSettings', 'recommendedTimeout']);
      expect(chrome, entering);
      // No bar, no tab bar, no card, no + / −.
      expect(find.text('Drzewo'), findsNothing);
      expect(find.byType(GrobingTabBar), findsNothing);
      expect(find.text('ur. 1983 · to ja'), findsNothing);
      expect(find.text('Pokaż'), findsNothing);
      expect(find.byTooltip('Oddal — dalsza rodzina'), findsNothing);
      expect(find.byTooltip('Przesyłaj na telewizor'), findsNothing);
      // Level 2 from "Ja" — 20 people, all of them on the 800 × 360 dp screen.
      expect(_nodes(), findsNWidgets(20));
      expectAllOnScreen(tester, const Size(800, 360));
      // Casting was just chosen: the hint about the quick settings would only reach the TV (D26, D30).
      expect(find.text(_hint), findsNothing);

      semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-8 — in presentation a touch puts Kasia in the middle, fitted anew; the middle opens nothing; a drag from '
    'the bars\' edge leaves the tree; the empty space shows "Zakończ prezentację" and the bar for 5 s (ISSUE-038 D3)',
    (tester) async {
      await present(tester);
      await tester.tap(find.text('Kasia'));
      await _afterMove(tester);
      // Level 2 from Kasia — 17 people, still no card; in the middle she has no hint (D5).
      expect(_nodes(), findsNWidgets(17));
      expect(find.text('ur. 1985 · Moja żona'), findsNothing);
      expect(node(tester, 'Kasia Wymyślona').properties.hint, isNull);
      expect(node(tester, 'Mateusz Wymyślony').properties.hint, 'w środek');
      expectAllOnScreen(tester, const Size(800, 360));

      // The middle opens nothing.
      await tester.tap(find.text('Kasia'));
      await _afterMove(tester);
      expect(find.byType(PersonScreen), findsNothing);

      // The system's swipe from the top edge, which shows the bars, leaves the tree; a drag inside moves it.
      final Offset fitted = tester.getCenter(find.text('Kasia'));
      await tester.dragFrom(const Offset(400, 2), const Offset(0, 200));
      await _afterMove(tester);
      expect(tester.getCenter(find.text('Kasia')), fitted);
      // And from the side, where a three-button navigation bar stands in landscape (ui review, MINOR-2).
      await tester.dragFrom(const Offset(798, 180), const Offset(-200, 0));
      await _afterMove(tester);
      expect(tester.getCenter(find.text('Kasia')), fitted);
      await tester.dragFrom(const Offset(400, 300), const Offset(120, 0));
      await _afterMove(tester);
      expect(
        tester.getCenter(find.text('Kasia')).dx,
        greaterThan(fitted.dx + 50),
      );

      // A touch of the person in the middle fits the level again (Dev report, deviation 1).
      await tester.tap(find.text('Kasia'));
      await _afterMove(tester);
      expect(
        tester.getCenter(find.text('Kasia')),
        offsetMoreOrLessEquals(fitted, epsilon: 1),
      );

      await tester.tapAt(_empty(tester));
      await tester.pump();
      expect(find.text('Zakończ prezentację'), findsOneWidget);
      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Zakończ prezentację'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Zakończ prezentację'), findsNothing);
      expect(find.byTooltip('Odtwórz historię'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-8 — "Zakończ prezentację" and back: portrait with the bars, the same person in the middle at level 2, '
    'the card and the bar',
    (tester) async {
      final List<String> chrome = await present(tester);
      await tester.tap(find.text('Kasia'));
      await _afterMove(tester);

      chrome.clear();
      await tester.tapAt(_empty(tester));
      await tester.pump();
      await tester.tap(find.text('Zakończ prezentację'));
      await tester.pump();
      await _turn(tester, landscape: false);
      expect(chrome, leaving);
      expect(find.text('ur. 1985 · Moja żona'), findsOneWidget);
      expect(_people(), findsNWidgets(17));
      expect(find.byTooltip('Przesyłaj na telewizor'), findsOneWidget);
      expect(find.byTooltip('Oddal — dalsza rodzina'), findsOneWidget);
      expect(find.byType(GrobingTabBar), findsOneWidget);
      // Kasia in the middle across the 360 dp screen, at the tree's own scale (level 2).
      expect(
        tester.getCenter(find.text('Kasia')).dx,
        moreOrLessEquals(180, epsilon: 1),
      );

      // Again — the cast screen long enough for Android to stop the app under it — and back ends it the same
      // way, and the tree stays.
      await castAndBack(tester, stayed: true);
      expect(find.text('Drzewo'), findsNothing);
      chrome.clear();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await _turn(tester, landscape: false);
      expect(chrome, leaving);
      expect(find.byType(TreeScreen), findsOneWidget);
      expect(find.text('ur. 1985 · Moja żona'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-036 AC-2 — a phone without the cast screen: presentation at once, with the hint for 4 s; a failure on '
    'the native side is the same, and nothing is thrown',
    (tester) async {
      final List<String> chrome = recordChrome();
      final List<String> calls = mockCastScreen(opens: false);
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await _pumpUntil(tester, () => _shown(_people()));
      await _afterMove(tester);

      // No back from anywhere: the answer "no such screen" is enough.
      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      await tester.pump();
      await _turn(tester, landscape: true);
      expect(calls, ['openCastSettings', 'recommendedTimeout']);
      expect(chrome, entering);
      expect(find.text('Drzewo'), findsNothing);
      expect(_nodes(), findsNWidgets(20));
      expect(_opacityOf(tester, _hint), 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, _hint), 0);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await _turn(tester, landscape: false);
      expect(find.byType(GrobingTabBar), findsOneWidget);

      // The native side failing otherwise (e.g. a SecurityException on some phone comes as a PlatformException):
      // the same, and nothing thrown.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _external,
            (call) async => throw PlatformException(code: 'error'),
          );
      await tester.tap(find.byTooltip('Przesyłaj na telewizor'));
      await tester.pump();
      await tester.pump();
      await _turn(tester, landscape: true);
      expect(find.text('Drzewo'), findsNothing);
      expect(_opacityOf(tester, _hint), 1);
      expect(tester.takeException(), isNull);
      await cleanUp(tester);
    },
  );
}
