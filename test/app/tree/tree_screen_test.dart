import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
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
    'AC-1 — "Ja" in the middle at level 2: 20 people, the card "to Ty"; tap targets (R2)',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      await pumpTree(tester);
      await _pumpUntil(tester, () => _shown(_people()));
      await _afterMove(tester);

      expect(_people(), findsNWidgets(20));
      expect(find.text('Mateusz Wymyślony'), findsOneWidget);
      expect(find.text('ur. 1983 · to Ty'), findsOneWidget);
      final SemanticsHandle semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'^Mateusz Wymyślony, ur\. 1983, to Ty$')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Kasia Wymyślona z d\. Przykładowa, ur\. 1985, Twoja żona$'),
        ),
        findsOneWidget,
      );
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
      expect(find.text('ur. 1985 · Twoja żona'), findsOneWidget);

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
    expect(find.text('ur. 1961 · Ciotka Twojej żony'), findsOneWidget);
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
        () => _shown(find.text('1925–2004 · Twój dziadek')),
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
      greaterThan(tester.getBottomLeft(find.text('ur. 1983 · to Ty')).dy),
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
      await tester.tap(find.text('Wybierz, która osoba to Ty'));
      await _pumpUntil(tester, () => _shown(find.byType(MePickerScreen)));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'States — a person without a family: only them, "nie wiadomo jeszcze, kim jest dla Ciebie"',
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
        find.text('bez dat · nie wiadomo jeszcze, kim jest dla Ciebie'),
        findsOneWidget,
      );
      await cleanUp(tester);
    },
  );
}
