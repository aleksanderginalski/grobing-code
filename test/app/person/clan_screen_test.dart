import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/person/clan_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/glyphs.dart';
import 'package:grobing/app/widgets/wreath.dart';
import 'package:grobing/data/clans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';

import '../../support/a11y.dart';
import '../../support/glyphs.dart';

// ISSUE-044 — the wreath of a family line in a person's correction (lib/app/person/clan_screen.dart;
// 05_DESIGN/wieniec.md E1, E1a, E2, F; wpis-osoby.md 4b): the row in each state, the sheet of lines, the
// screen of a new line and of its correction; AC-1, AC-2, AC-6 on the screen; tap targets and labels
// (retro 3, R2); large text puts the buttons above the words (dev pass at 200 % on 360 dp). Made-up people
// only (family-data.md).

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

/// The sheet and the screen slide in: taps go where they end up.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

final String _nb = String.fromCharCode(0xA0);

void main() {
  late GrobingDatabase db;
  late int jozef;
  late int anna;
  late int jan;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
  });

  /// Józef ♂ (no father in the tree) married to Anna ♀ (no line, no father); their son Jan ♂.
  Future<void> withFamily(WidgetTester tester) async {
    await tester.runAsync(() async {
      Future<int> person(String given, String surname, Sex sex) => db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              givenNames: Value(given),
              surname: Value(surname),
              sex: Value(sex),
            ),
          );
      jozef = await person('Józef', 'Wymyślony', Sex.male);
      anna = await person('Anna', 'Wymyślona', Sex.female);
      jan = await person('Jan', 'Wymyślony', Sex.male);
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(jozef), ExistingMember(anna)],
          children: [ExistingMember(jan)],
          married: true,
        ),
      );
    });
  }

  Future<int> lineAt(WidgetTester tester, int person, String name) async =>
      (await tester.runAsync(
        () => createClan(
          db,
          name: name,
          motif: WreathMotif.dab,
          colour: ClanColour.stareZloto,
          forPerson: person,
        ),
      ))!;

  Future<void> pumpRow(
    WidgetTester tester,
    int personId, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio =
        3; // 360 dp, the narrowest phone of the specs
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [WreathFormRow(database: db, personId: personId)],
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => _shown(find.text('Brak')) || _shown(find.text('Zmień')),
    );
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  testWidgets(
    'E1 "Brak" — no father in the tree (O1) and a father without a line: what is missing in words, and '
    '"Wybierz ród" instead of "Zmień"; the targets and labels of the row (retro 3, R2)',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await withFamily(tester);
      await pumpRow(tester, jozef);

      expect(find.text('Brak'), findsOneWidget);
      expect(
        find.text(
          'Ojca nie ma w${_nb}drzewie, więc wieniec nie ma po kim przyjść.',
        ),
        findsOneWidget,
      );
      expect(find.text('Wybierz ród'), findsOneWidget);
      expect(find.text('Zmień'), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);

      await pumpRow(tester, jan);
      expect(
        find.text('Ojciec: Józef Wymyślony — bez wieńca.'),
        findsOneWidget,
      );
      expect(find.text('Wybierz ród'), findsOneWidget);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'F, AC-1 — "Wybierz ród" → "Nowy ród": the first free colour and motif, the name refused empty, F5 names '
    'who gets it; "Zapisz ród" writes the line chosen at Józef, closes the sheet, and his son has it after him',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await withFamily(tester);
      await tester.runAsync(
        () => createClan(
          db,
          name: 'Zmyśleńscy',
          motif: WreathMotif.laur,
          colour: ClanColour.stareZloto,
        ),
      );
      await pumpRow(tester, jozef);

      await tester.tap(find.text('Wybierz ród'));
      await _pumpUntil(tester, () => _shown(find.text('Wieniec rodu — Józef')));
      await _settle(tester);
      expect(find.text('Zmyśleńscy'), findsOneWidget);
      expect(
        find.text('Laur ·${_nb}Stare złoto ·${_nb}0${_nb}osób'),
        findsOneWidget,
      );
      // Nothing to come from a father: "Bez wieńca" would mean nothing.
      expect(find.text('Bez wieńca'), findsNothing);
      await tester.tap(find.text('Nowy ród'));
      await _pumpUntil(tester, () => _shown(find.text('Zapisz ród')));
      await _settle(tester);

      // F3, F4: Stare złoto and Laur are taken — the first free are Brąz and Dąb.
      expect(find.text('Kolor: Brąz'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Brąz')),
        isSemantics(isSelected: true),
      );
      // D20: a line is told by its motif and colour together. Zmyśleńscy have Laur in Stare złoto, so in
      // Brąz no tile says "też"; in Stare złoto, Laur does.
      expect(find.text('też:'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Stare złoto'));
      await tester.pump();
      expect(find.text('Kolor: Stare złoto'), findsOneWidget);
      expect(find.text('też:'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Laur'),
            matching: find.byType(InkWell),
          ),
          matching: find.text('też:'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Brąz'));
      await tester.pump();
      expect(find.text('też:'), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      // F5 is at the foot of the list, built when scrolled to.
      await tester.scrollUntilVisible(
        find.text(
          'Wieniec dostanie Józef Wymyślony, a${_nb}po nim, po linii ojca, 1 osoba: Jan.',
        ),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ClanScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Back to the name at the top.
      await tester.drag(
        find
            .descendant(
              of: find.byType(ClanScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 3000),
      );
      await _settle(tester);

      await tester.tap(find.text('Zapisz ród'));
      await _pumpUntil(tester, () => _shown(find.text('Wpisz nazwę rodu.')));
      await tester.enterText(find.byType(TextField), 'zmyslenscy');
      await tester.tap(find.text('Zapisz ród'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Taki ród już jest — wybierz go z${_nb}listy.')),
      );

      await tester.enterText(find.byType(TextField), 'Wymyślscy');
      await tester.tap(find.text('Zapisz ród'));
      await _pumpUntil(
        tester,
        () =>
            _shown(find.text('Wymyślscy')) && !_shown(find.text('Zapisz ród')),
      );
      expect(
        find.text('Wieniec rodu — Józef'),
        findsNothing,
      ); // the sheet closed (F6)
      expect(
        find.text('Wybrane tutaj. Po tej osobie wieniec mają: Jan.'),
        findsOneWidget,
      );
      final ClanRow row = (await tester.runAsync(
        () => (db.select(
          db.clans,
        )..where((c) => c.name.equals('Wymyślscy'))).getSingle(),
      ))!;
      expect((row.motif, row.colour), ('dab', 'braz'));

      await pumpRow(tester, jan);
      expect(find.text('Wymyślscy'), findsOneWidget);
      expect(find.text('Po ojcu: Józef Wymyślony.'), findsOneWidget);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'E2, AC-2, E1a — the sheet marks the line and "po ojcu"; another line at the son is an exception with "Wróć '
    'do wieńca po ojcu"; "Bez wieńca" too; back to the father\'s clears it',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await withFamily(tester);
      await lineAt(tester, jozef, 'Wymyślscy');
      await tester.runAsync(
        () => createClan(
          db,
          name: 'Przykładowscy',
          motif: WreathMotif.jarzebina,
          colour: ClanColour.lawenda,
        ),
      );
      await pumpRow(tester, jan);

      await tester.tap(find.text('Zmień'));
      await _pumpUntil(tester, () => _shown(find.text('Wieniec rodu — Jan')));
      await _settle(tester);
      // Józef, Jan and Anna — who wears his line whole, having none of her own (B5).
      expect(
        find.text(
          'Dąb ·${_nb}Stare złoto ·${_nb}3${_nb}osoby ·${_nb}po${_nb}ojcu',
        ),
        findsOneWidget,
      );
      expect(findGlyph(Glyphs.check), findsOneWidget);
      expect(find.text('Bez wieńca'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);

      await tester.tap(find.text('Przykładowscy'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Wybrane tutaj. Po ojcu byłoby: Wymyślscy.')),
      );
      expect(find.text('Wróć do wieńca po ojcu'), findsOneWidget);

      await tester.tap(find.text('Zmień'));
      await _pumpUntil(tester, () => _shown(find.text('Wieniec rodu — Jan')));
      await _settle(tester);
      await tester.tap(find.text('Bez wieńca'));
      await _pumpUntil(
        tester,
        () =>
            _shown(find.text('Bez wieńca')) &&
            !_shown(find.text('Wieniec rodu — Jan')),
      );
      expect(
        find.text('Wybrane tutaj. Po ojcu byłoby: Wymyślscy.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Wróć do wieńca po ojcu'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Po ojcu: Józef Wymyślony.')),
      );
      expect(find.text('Wróć do wieńca po ojcu'), findsNothing);
      final Person jansRow = (await tester.runAsync(
        () =>
            (db.select(db.persons)..where((p) => p.id.equals(jan))).getSingle(),
      ))!;
      expect((jansRow.clanId, jansRow.noWreath), (null, false));
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-4 in the row — a married woman without a line of her own: "Brak" and her husband\'s line for the '
    'whole wreath in words',
    (tester) async {
      await withFamily(tester);
      await lineAt(tester, jozef, 'Wymyślscy');
      await pumpRow(tester, anna);

      expect(find.text('Brak'), findsOneWidget);
      expect(
        find.text('Po ślubie wieniec męża: Wymyślscy (mąż: Józef Wymyślony).'),
        findsOneWidget,
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-6 — ✎ in the sheet opens "Ród": "Zmiana dotyczy 3 osób."; a new colour saved there is the line\'s for '
    'everyone',
    (tester) async {
      await withFamily(tester);
      final int w = await lineAt(tester, jozef, 'Wymyślscy');
      await pumpRow(tester, jan);

      await tester.tap(find.text('Zmień'));
      await _pumpUntil(tester, () => _shown(find.byTooltip('Popraw ród')));
      await _settle(tester);
      await tester.tap(find.byTooltip('Popraw ród'));
      await _pumpUntil(tester, () => _shown(find.text('Kolor: Stare złoto')));
      await _settle(tester);
      expect(find.text('Ród'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Miedź'));
      await tester.pump();
      expect(find.text('Kolor: Miedź'), findsOneWidget);
      // F5 is at the foot of the list, built when scrolled to.
      await tester.scrollUntilVisible(
        find.text('Zmiana dotyczy 3 osób.'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ClanScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Zmiana dotyczy 3 osób.'), findsOneWidget);
      await tester.tap(find.text('Zapisz'));
      await _pumpUntil(tester, () => !_shown(find.text('Kolor: Miedź')));

      final ClanRow row = (await tester.runAsync(
        () => (db.select(db.clans)..where((c) => c.id.equals(w))).getSingle(),
      ))!;
      expect(row.colour, 'miedz');
      await cleanUp(tester);
    },
  );

  testWidgets(
    'text 200 % on 360 dp — the buttons go above the words, which take the whole width (a line\'s name broke '
    'in the middle beside them, dev pass)',
    (tester) async {
      await withFamily(tester);
      await lineAt(tester, jozef, 'Przykładowiczowie');
      await pumpRow(tester, jan, textScale: 2);

      final Rect change = tester.getRect(find.text('Zmień'));
      final Rect name = tester.getRect(find.text('Przykładowiczowie'));
      final Rect sign = tester.getRect(find.byType(WreathSign));
      expect(change.bottom, lessThanOrEqualTo(name.top));
      // The words under the sign, from the frame's left edge — the whole width, not the strip beside it.
      expect(name.top, greaterThanOrEqualTo(sign.bottom));
      expect(name.left, lessThan(sign.right));
      await cleanUp(tester);
    },
  );
}
