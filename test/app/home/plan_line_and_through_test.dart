import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/home/cemetery_base.dart';
import 'package:grobing/app/home/cemetery_card.dart';
import 'package:grobing/app/home/home_screen.dart';
import 'package:grobing/app/home/poland_map_data.dart';
import 'package:grobing/app/map/plan_downloads.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/candle.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/net/overpass_plan_source.dart';

import '../../support/a11y.dart';
import '../../support/backup_fakes.dart';

// ISSUE-052 on the home screen (05_DESIGN/cmentarze.md v2.8): D35 "· przy: …" on a result found through a
// nearby place, one unit on its line · D37 the plan line in the sheet and "· bez planu" in "Twoje cmentarze"
// · touch targets of the changed screens (retro 3, R2). Made-up cemeteries and places only.

final PolandMapData _map = PolandMapData.fromJson(
  File(PolandMapData.asset).readAsStringSync(),
);

final CemeteryBase _base = CemeteryBase(const [
  BaseCemetery(
    name: 'Cmentarz parafialny',
    point: GeoPoint(51.2, 20.2),
    kind: 'rzymskokatolicki',
    locality: 'Zmyślonka',
    voivodeship: 'mazowieckie',
    nearby: ['Testowy Dwór', 'Przykładowa Wymyślanka'],
  ),
  BaseCemetery(
    name: 'Cmentarz Wymyślanka',
    point: GeoPoint(51.4, 20.4),
    locality: 'Testowo',
    voivodeship: 'łódzkie',
  ),
]);

const List<PlanArea> _areas = [
  PlanArea([
    GeoPoint(51.0, 20.0),
    GeoPoint(51.0, 20.001),
    GeoPoint(51.001, 20.001),
    GeoPoint(51.0, 20.0),
  ]),
];

class _Source implements PlanSource {
  _Source(this.answer);

  final PlanResult answer;
  Completer<void>? gate;

  @override
  Future<PlanResult> fetch(GeoPoint point) async {
    await gate?.future;
    return answer;
  }
}

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

void main() {
  late Directory tmp;
  late GrobingDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_issue052_test');
    db = GrobingDatabase(NativeDatabase.memory());
  });

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
  }

  Future<void> pumpHome(WidgetTester tester, {PlanDownloads? plans}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final Widget home = HomeScreen(
      database: db,
      location: DataLocation.inDirectory(Directory('${tmp.path}/data')),
      backup: backupServiceIn(
        tmp,
        db,
        FakeDocumentStore(Directory('${tmp.path}/drive')),
      ),
      mapData: _map,
      base: Future.value(_base),
      openUrl: (_) async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        builder: (context, child) =>
            plans == null ? child! : MapNetwork(plans: plans, child: child!),
        home: home,
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(FlutterMap).evaluate().isNotEmpty,
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await _pumpUntil(
      tester,
      () => find.byType(CandlePin).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(CandlePin));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ISSUE-052 AC-1 / D35: a result found through a nearby place says "· przy: …" after its locality, the '
    'place\'s name one unit (hard spaces); one found by its own name has none; the results\' targets are 48 dp',
    (tester) async {
      final String nbsp = String.fromCharCode(0xA0);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpHome(tester);
      await tester.tap(find.text('Szukaj cmentarza'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'przykladowa wymyslanka');
      await tester.pump();
      // The name after "przy:", then the voivodeship held to its word; whether the name's own words are joined
      // depends on the line's width — the next test.
      expect(
        find.textContaining(
          RegExp(
            '^Zmyślonka ·${nbsp}przy:${nbsp}Przykładowa[ $nbsp]Wymyślanka'
            ' ·${nbsp}woj.${nbsp}mazowieckie ·${nbsp}rzymskokatolicki\$',
          ),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'wymyslanka');
      await tester.pump();
      // Its own name holds the word: no "przy:"; and the whole word in a nearby place still finds the other.
      expect(find.text('Testowo ·${nbsp}woj.$nbspłódzkie'), findsOneWidget);
      expect(find.textContaining('przy:'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-052 D38 (ui review): the name after "przy:" is one unit when the whole "· przy: <name>" fits the '
    'line; a longer one keeps its plain spaces, so it breaks between words, never inside one',
    (tester) async {
      final String nbsp = String.fromCharCode(0xA0);
      // The test font draws every letter one font size wide: 14 dp a letter at 100%; the card leaves the
      // place line 400 − 16 − 12 − 8 − 24 = 340 dp.
      Future<String> placeLine(String through) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: BaseCemeteryCard(
                    cemetery: const BaseCemetery(
                      name: 'Cmentarz parafialny',
                      point: GeoPoint(51.2, 20.2),
                      locality: 'Zmyślonka',
                      voivodeship: 'mazowieckie',
                    ),
                    through: through,
                    added: false,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        return tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .firstWhere((s) => s.contains('przy:'));
      }

      // "· przy: Wola Testowa" — 20 letters, 280 dp: joined.
      expect(
        await placeLine('Wola Testowa'),
        contains('przy:${nbsp}Wola${nbsp}Testowa'),
      );
      // "· przy: " and 34 letters — 588 dp, wider than the line: plain spaces between the name's words.
      expect(
        await placeLine('Przykładowa Wymyślanka Zmyślona Dolna'),
        contains('przy:${nbsp}Przykładowa Wymyślanka Zmyślona Dolna'),
      );
    },
  );

  testWidgets(
    'ISSUE-052 D37: the sheet says "Plan offline" for a stored plan, its targets 48 dp and labelled',
    (tester) async {
      late int withPlan;
      await tester.runAsync(() async {
        withPlan = await addCemetery(
          db,
          name: 'Cmentarz Wymyślony',
          locality: 'Wymyślin',
          point: const GeoPoint(51.0, 20.0),
        );
        await savePlan(
          db,
          withPlan,
          forPoint: const GeoPoint(51.0, 20.0),
          areas: _areas,
          paths: const [],
          server: 'overpass.example',
        );
      });
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpHome(tester);
      await openSheet(tester);
      expect(find.text('Plan offline'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
    },
  );

  testWidgets('ISSUE-052 D37: a cemetery whose plan is not in OSM', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await addCemetery(
        db,
        name: 'Cmentarz Testowy',
        point: const GeoPoint(51.0, 20.0),
      );
      await saveNotInOsm(
        db,
        id,
        forPoint: const GeoPoint(51.0, 20.0),
        server: 'overpass.example',
      );
    });
    await pumpHome(tester);
    await openSheet(tester);
    expect(find.text('W\u00A0OpenStreetMap nie ma planu.'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets(
    'ISSUE-052 D37: while the plan downloads the sheet says "Pobieram plan…"; without one stored and no '
    'download, "Bez planu — pobierze się sam."; "Twoje cmentarze" says "· bez planu"',
    (tester) async {
      await tester.runAsync(
        () => addCemetery(
          db,
          name: 'Cmentarz Przykładowy',
          locality: 'Przykładowo',
          point: const GeoPoint(51.0, 20.0),
        ),
      );
      final _Source source = _Source(const PlanServerError())
        ..gate = Completer<void>();
      final PlanDownloads plans = PlanDownloads(database: db, source: source);
      addTearDown(plans.close);
      await pumpHome(tester, plans: plans);
      await tester.runAsync(() async {
        unawaited(plans.downloadAll());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await openSheet(tester);
      await _pumpUntil(
        tester,
        () => find.text('Pobieram plan…').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Szukaj cmentarza'));
      await tester.pumpAndSettle();
      expect(
        find.text('Przykładowo ·\u00A00 grobów ·\u00A00 osób ·\u00A0bez planu'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        source.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      plans.close();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await cleanUp(tester);

      // Without the plans' downloads (and so without their state): the fact and that it comes by itself.
      db = GrobingDatabase(NativeDatabase.memory());
      tmp = Directory.systemTemp.createTempSync('grobing_issue052_test');
      await tester.runAsync(
        () => addCemetery(
          db,
          name: 'Cmentarz Przykładowy',
          point: const GeoPoint(51.0, 20.0),
        ),
      );
      await pumpHome(tester);
      await openSheet(tester);
      expect(find.text('Bez planu — pobierze się sam.'), findsOneWidget);
      await cleanUp(tester);
    },
  );
}
