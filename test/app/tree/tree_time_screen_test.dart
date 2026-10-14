import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/tree/tree_time_bar.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_family.dart';

import '../../support/a11y.dart';

// ISSUE-037 — the time row in the tree's card (05_DESIGN/drzewo.md v1.12, element 6; US-010), happy path per
// AC on the made-up family: the row and its reader (element 6, D5) with tap targets and contrast (retro 3, R2)
// · AC-1 a year: those not born yet off the tree, the middle before their birth an empty ring (C1), the card
// unchanged, the pill counts the year's people (D37) · AC-3 ▶ about 21 years a second to "dziś", ❚❚ stops,
// a drag stops, a touch of a person does not (D37); with the system's animations off a decade a second (R2,
// D36) · N3 the reader hears "nie wiadomo, czy już żyje" · D37 a new tree shows "dziś" · text at 200 % on
// 360 dp: the two years above ▶ and the slider. The windows, the pairs and the lines of a year —
// tree_time_test.dart. Made-up people only (family-data.md).

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

/// The people on the tree a touch can reach: a node says "w środek", the one in the middle "otwórz".
Finder _people() => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.hint == 'w środek' || w.properties.hint == 'otwórz'),
);

Future<void> _afterMove(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The slider's semantics — "Rok", its value, and the decade up and down (D5).
SemanticsProperties _slider(WidgetTester tester) => tester
    .widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Rok',
      ),
    )
    .properties;

/// A year as a finger on the slider gives it — the row's own callback, as the slider calls it.
Future<void> _year(WidgetTester tester, int? year) async {
  tester.widget<TreeTimeBar>(find.byType(TreeTimeBar)).onYear(year);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));

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
    await tester.runAsync(() => addFictionalFamily(db));
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
    await _pumpUntil(tester, () => _shown(find.byType(TreeTimeBar)));
    await _afterMove(tester);
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
    'element 6 — ▶, 1860, the slider and "dziś" in the card; the reader: "Rok", a decade a '
    'gesture (D5); tap targets and contrast (R2)',
    (tester) async {
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();

      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);
      expect(find.text('1860'), findsOneWidget);
      expect(_slider(tester).value, 'dziś');
      expect(_people(), findsNWidgets(20));
      SemanticsProperties s = _slider(tester);
      expect(s.slider, isTrue);
      expect(s.value, 'dziś');
      expect(s.decreasedValue, '2016');
      expect(s.increasedValue, 'dziś');

      s.onDecrease!();
      await tester.pump();
      expect(find.text('2016'), findsOneWidget);
      s = _slider(tester);
      expect(
        (s.value, s.decreasedValue, s.increasedValue),
        ('2016', '2006', 'dziś'),
      );
      s.onIncrease!();
      await tester.pump();
      expect(_slider(tester).value, 'dziś');

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-010 AC-1, C1, D37 — 1950: 5 of 20 on the tree, "Ja" an empty ring the reader calls '
    '"przed narodzinami", the card as before; the pill counts the year; a touch keeps the year',
    (tester) async {
      await pumpTree(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _year(tester, 1950);

      expect(find.text('1950'), findsOneWidget);
      expect(_people(), findsNWidgets(5));
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Mateusz Wymyślony, ur\. 1983, to ja — przed narodzinami$'),
        ),
        findsOneWidget,
      );
      expect(find.text('ur. 1983 · to ja'), findsOneWidget);

      await tester.tap(find.byTooltip('Oddal — dalsza rodzina'));
      await _afterMove(tester);
      expect(find.text('Poziom 3 · 25 osób'), findsOneWidget);
      await tester.tap(find.byTooltip('Przybliż — bliższa rodzina'));
      await _afterMove(tester);
      expect(find.text('Poziom 2 · 5 osób'), findsOneWidget);

      // A touch of a person keeps the year (D37): Henryk, born 1930, in the middle.
      await tester.tap(find.text('Henryk'));
      await _afterMove(tester);
      expect(find.text('Henryk Zmyślony'), findsOneWidget);
      expect(find.text('1950'), findsOneWidget);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'US-010 AC-3, D37 — ▶ from 1860 about 21 years a second; ❚❚ stops; on to "dziś" and ▶ again; '
    'a touch of a person goes on playing, a drag stops',
    (tester) async {
      await pumpTree(tester);

      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(seconds: 2));
      // 1860 + 2 s × 146 / 7 s a year.
      expect(find.text('1901'), findsOneWidget);
      expect(find.byTooltip('Zatrzymaj'), findsOneWidget);

      await tester.tap(find.byTooltip('Zatrzymaj'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1901'), findsOneWidget);
      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);

      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(milliseconds: 500));
      // Grandfather Henryk, born 1930, is on the tree by 1990: a touch puts him in the middle, ▶ goes on.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Henryk'));
      await _afterMove(tester);
      expect(find.byTooltip('Zatrzymaj'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(_slider(tester).value, 'dziś');
      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);

      // A drag — the slider's own change — stops ▶ at the year chosen.
      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(seconds: 1));
      await _year(tester, 1930);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1930'), findsOneWidget);
      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'element 6, D37 — ❚❚: the reader hears the year once; a person\'s view stops ▶ and back '
    'returns to that year (ui review of ISSUE-037)',
    (tester) async {
      final List<Object?> announced = [];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            announced.add(message);
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      await pumpTree(tester);
      List<String> heard() => [
        for (final Object? m in announced)
          if (m case {'type': 'announce', 'data': {'message': final String s}})
            s,
      ];

      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(seconds: 2));
      expect(heard(), isEmpty);
      await tester.tap(find.byTooltip('Zatrzymaj'));
      await tester.pump();
      expect(heard(), ['Rok 1901']);

      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Pokaż'));
      await tester.pump();
      final String year = _slider(tester).value!;
      expect(heard().last, 'Rok $year');
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      await tester.pump(const Duration(seconds: 2));
      await tester.pageBack();
      await _pumpUntil(tester, () => !_shown(find.byType(PersonScreen)));
      expect(_slider(tester).value, year);
      expect(find.byTooltip('Odtwórz historię'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'R2 (D36) — with the system\'s animations off ▶ goes by decades, about a second each',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpTree(tester);

      await tester.tap(find.byTooltip('Odtwórz historię'));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('1870'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('1880'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(_slider(tester).value, 'dziś');
      await cleanUp(tester);
    },
  );

  testWidgets(
    'N3 — Kazimierz, "przed 1900", in 1890: on the tree, the reader hears "nie wiadomo, czy już '
    'żyje"; in 1970 "…czy jeszcze żyje"; D37 — a new tree from the tab shows "dziś"',
    (tester) async {
      await tester.runAsync(() => addFictionalFamily(db));
      final int kz = await personNamed(tester, 'Kazimierz', 'Przykładek');
      await pumpTree(tester, focus: kz);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await _year(tester, 1890);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Kazimierz Przykładek, .*nie wiadomo, czy już żyje'),
        ),
        findsOneWidget,
      );
      await _year(tester, 1970);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Kazimierz Przykładek, .*nie wiadomo, czy jeszcze żyje'),
        ),
        findsOneWidget,
      );

      // "Pokaż" → his view → "Pokaż w drzewie": a new tree, from "dziś" (D37). The tab on its own screen
      // does nothing (style-b.md rule 12), so this is the way a new tree comes here.
      await tester.tap(find.text('Pokaż'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      await tester.scrollUntilVisible(
        find.text('Pokaż w drzewie'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Pokaż w drzewie'));
      await _pumpUntil(
        tester,
        () =>
            _shown(find.byType(TreeTimeBar)) &&
            !_shown(find.byType(PersonScreen)),
      );
      await _afterMove(tester);
      expect(find.text('Kazimierz Przykładek'), findsOneWidget);
      expect(_slider(tester).value, 'dziś');
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'text at 200 % on 360 dp — the two years in a row above ▶ and the slider, nothing cut',
    (tester) async {
      // The test font draws every letter as a square: the bottom bar (lib/app/tabs.dart, not this item's)
      // overflows in it at 200 % and not on a phone — as in tree_screen_test.dart, AC-7. Only that overflow
      // is let through; the row itself in Roboto is the emulator's (Dev report, m-200.png).
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
      await pumpTree(tester, text: 2);
      final SemanticsHandle semantics = tester.ensureSemantics();

      final Rect first = tester.getRect(find.text('1860'));
      final Rect now = tester.getRect(find.text('dziś').last);
      final Rect play = tester.getRect(find.byTooltip('Odtwórz historię'));
      final Rect slider = tester.getRect(find.byType(Slider));
      expect(now.left, greaterThan(first.right));
      expect((first.center.dy - now.center.dy).abs(), lessThan(2));
      expect(play.top, greaterThanOrEqualTo(first.bottom - 1));
      expect(slider.left, greaterThanOrEqualTo(play.right - 1));
      // The circle's button is 40 dp; its target, padded, 48 dp (the guideline below).
      expect(
        tester.getSemantics(find.byTooltip('Odtwórz historię')).rect.size,
        const Size(48, 48),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await cleanUp(tester);
    },
  );
}
