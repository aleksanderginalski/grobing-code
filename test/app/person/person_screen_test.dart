import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/photo/person_photo_viewer_screen.dart';
import 'package:grobing/app/photo/person_photos_screen.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

import '../../support/photo_fakes.dart';
import '../../support/style_checks.dart';

// ISSUE-024 — the person's view (05_DESIGN/osoba.md v2.1), happy path per AC: AC-2 the mini tree with role
// names and a node to the relative's view · AC-3 the chain from "ja" by first names and one-step relations;
// without "ja", without a path, none for "ja" · AC-4 "Pochówek" → the cemetery with the grave marked · AC-5
// the background over the portrait · D20 the place to add photos → the correction with the photo sheet ·
// D15 one correction of a person at a time · W2 the photos only to look at. AC-1 (the grave's card) —
// grave_screens_test.dart. Made-up people and drawn pictures only (family-data.md).

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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

bool _shown(Finder f) => f.evaluate().isNotEmpty;

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late FakePhotoPicker picker;
  late Photos photos;
  late int maria;
  late int jan;
  late int anna;
  late int ewa;
  late int zofia;
  late int mariaGrave;
  late int otherGrave;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_person_screen');
    db = GrobingDatabase(NativeDatabase.memory());
    picker = FakePhotoPicker();
    photos = fakePhotos(tmp, picker: picker);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still open on Windows; the system cleans the temp directory.
    }
  });

  NewPhoto drawn(int n) => NewPhoto(
    File('${tmp.path}/photo-work/narysowane-$n.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(fictionalPeoplePng(n, heads: 1 + n % 2)),
  );

  /// Maria (in "Grób rodzinny Wymyślonych", the second grave of the cemetery) with her husband Jan, her
  /// parents Józef and Zofia, her children Anna and Stanisław; Ewa — "ja" — is Anna's daughter. Maria has
  /// two photos, the second her background, unless [mariaPhotos] is false.
  Future<void> withFamily(
    WidgetTester tester, {
    bool mariaPhotos = true,
    bool me = true,
  }) async {
    await tester.runAsync(() async {
      final int cemetery = await addCemetery(
        db,
        name: 'Cmentarz parafialny w Wymyślonowie',
      );
      otherGrave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Józef', surname: 'Zmyślony'),
      );
      mariaGrave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(
          givenNames: 'Maria',
          surname: 'Wymyślona',
          birthSurname: 'Testowa',
          sex: Sex.female,
          bio: 'Nauczycielka w szkole w Wymyślonowie.',
          birth: QualifiedDate(DateQualifier.exact, PartialDate(1925, 3, 12)),
          death: QualifiedDate(DateQualifier.exact, PartialDate(2004, 11, 4)),
        ),
      );
      await setGraveName(db, mariaGrave, 'Grób rodzinny Wymyślonych');
      maria = (await loadGrave(db, mariaGrave))!.people.single.id;
      jan = await addPersonToGrave(
        db,
        graveId: mariaGrave,
        entry: const PersonEntry(
          givenNames: 'Jan',
          surname: 'Wymyślony',
          sex: Sex.male,
        ),
      );
      await saveFamily(
        db,
        FamilyDraft(
          partners: const [
            NewMember(givenNames: 'Józef', surname: 'Testowy', sex: Sex.male),
            NewMember(givenNames: 'Zofia', surname: 'Testowa', sex: Sex.female),
          ],
          children: [ExistingMember(maria)],
          married: true,
        ),
      );
      zofia = (await (db.select(
        db.persons,
      )..where((p) => p.givenNames.equals('Zofia'))).getSingle()).id;
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(maria), ExistingMember(jan)],
          children: const [
            NewMember(
              givenNames: 'Anna',
              surname: 'Wymyślona',
              sex: Sex.female,
            ),
            NewMember(
              givenNames: 'Stanisław',
              surname: 'Wymyślony',
              sex: Sex.male,
            ),
          ],
          married: true,
        ),
      );
      anna = (await (db.select(
        db.persons,
      )..where((p) => p.givenNames.equals('Anna'))).getSingle()).id;
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(anna)],
          children: const [
            NewMember(
              givenNames: 'Ewa',
              surname: 'Przykładowa',
              sex: Sex.female,
            ),
          ],
        ),
      );
      ewa = (await (db.select(
        db.persons,
      )..where((p) => p.givenNames.equals('Ewa'))).getSingle()).id;
      if (me) await setMe(db, ewa);
      if (mariaPhotos) {
        final PersonEntry mariaEntry = (await loadPersonForCorrection(
          db,
          maria,
        ))!.person.entry;
        final NewPhoto portrait = drawn(1);
        final NewPhoto house = drawn(2);
        await photos.writeWithPersonPhotos<void>(
          db,
          PersonPhotoEdits(
            photos: [portrait, house],
            backgroundChanged: true,
            background: house,
          ),
          (also) => updatePersonEntry(db, maria, mariaEntry, alsoWrite: also),
        );
      }
    });
  }

  Future<void> pumpView(
    WidgetTester tester,
    int personId, {
    AppTab tab = AppTab.people,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: PersonScreen(
          database: db,
          personId: personId,
          photos: photos,
          tab: tab,
        ),
      ),
    );
    await _pumpUntil(tester, () => _shown(find.text('Rodzina')));
    await _settle(tester);
  }

  /// Takes the screens down before the database closes (README → Testy).
  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    PaintingBinding.instance.imageCache.clear();
    await tester.runAsync(db.close);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await _settle(tester);
  }

  testWidgets(
    'AC-2 — the mini tree: "Ojciec", "Matka", "Mąż", "Córka", "Syn" over first names; a node opens the '
    'relative\'s view on the same stack, and back returns',
    (tester) async {
      await withFamily(tester);
      await pumpView(tester, maria);

      expect(find.text('Maria Wymyślona z d. Testowa'), findsOneWidget);
      expect(find.text('12.03.1925 – 04.11.2004'), findsOneWidget);
      expect(
        find.text('Nauczycielka w szkole w Wymyślonowie.'),
        findsOneWidget,
      );
      for (final String role in ['Ojciec', 'Matka', 'Mąż', 'Córka', 'Syn']) {
        expect(find.text(role), findsOneWidget, reason: role);
      }
      expect(find.text('Stanisław'), findsOneWidget);
      // Each relative's node is a button for a screen reader; the person in the middle is not.
      expect(
        find.bySemanticsLabel(RegExp(r'^Matka: Zofia Testowa')),
        findsOneWidget,
      );
      // "Pokaż w drzewie" came back with the tree (osoba.md v2.4, D11) — tree_screen_test.dart, AC-6.
      // The glow of the person in the middle and of the portrait lies under the circle, not over it (ui
      // review of ISSUE-033; the author's "ok" at its stop #2).
      expectNoGlowOverContent(tester);

      await tester.tap(find.text('Zofia'));
      await _pumpUntil(tester, () => _shown(find.text('Zofia Testowa')));
      await _settle(tester);
      expect(find.text('Córka'), findsOneWidget); // Maria, in Zofia's tree
      await tester.pageBack();
      await _pumpUntil(
        tester,
        () => _shown(find.text('Maria Wymyślona z d. Testowa')),
      );
      expect(zofia, isPositive);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-3 — the chain from "Ja" by first names and one-step relations: "Ja", "Mama Anna", "Jej mama '
    'Maria"; the rows of relatives open their views',
    (tester) async {
      await withFamily(tester);
      await pumpView(tester, maria);
      await scrollTo(tester, find.text('Jej mama Maria'));
      expect(find.text('Jak łączy się ze mną'), findsOneWidget);
      expect(
        find.text('Ja'),
        findsNWidgets(2),
      ); // the mark in the circle and the label
      expect(find.text('Mama Anna'), findsOneWidget);
      expect(find.text('Jej mama Maria'), findsOneWidget);
      // No compound names here — they belong to the tree (D13').
      expect(find.textContaining('babcia'), findsNothing);
      expect(find.textContaining('Twoja'), findsNothing);
      expect(
        find.textContaining('Moja'),
        findsNothing,
      ); // G2 (ISSUE-035): the tree's words, not here

      await tester.tap(find.text('Mama Anna'));
      await _pumpUntil(tester, () => _shown(find.text('Anna Wymyślona')));
      await _settle(tester);
      await scrollTo(tester, find.text('Mama Anna'));
      expect(
        find.text('Jej mama Maria'),
        findsNothing,
      ); // Anna's own chain ends with her
      await cleanUp(tester);
    },
  );

  testWidgets('AC-3 — for "ja" there is no chain section', (tester) async {
    await withFamily(tester);
    await pumpView(tester, ewa);
    expect(find.text('Jak łączy się ze mną'), findsNothing);
    await cleanUp(tester);
  });

  testWidgets(
    'AC-3 — without "ja": the fact and "Wybierz, która osoba to Ty"; without a path: the fact',
    (tester) async {
      await withFamily(tester, me: false);
      await pumpView(tester, maria);
      await scrollTo(tester, find.text('Wybierz, która osoba to Ty'));
      expect(
        find.text('Aplikacja nie wie jeszcze, która osoba to Ty.'),
        findsOneWidget,
      );
      await cleanUp(tester);

      db = GrobingDatabase(NativeDatabase.memory());
      await withFamily(tester);
      late int stranger;
      await tester.runAsync(() async {
        stranger = await addPersonToGrave(
          db,
          graveId: otherGrave,
          entry: const PersonEntry(givenNames: 'Obcy', surname: 'Zmyślony'),
        );
      });
      await pumpView(tester, stranger);
      await scrollTo(
        tester,
        find.textContaining('Nie wiadomo jeszcze, jak łączy się z Tobą'),
      );
      expect(
        find.text('Rodziny jeszcze nie ma. Dodasz ją pod ✎.'),
        findsOneWidget,
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'AC-4 — "Pochówek" → the cemetery with this grave marked: its card selected for a screen reader, the '
    'tab of the stack still active; back returns to the view',
    (tester) async {
      await withFamily(tester);
      await pumpView(tester, maria);
      await scrollTo(tester, find.text('Pochówek'));
      expect(find.text('Grób rodzinny Wymyślonych'), findsOneWidget);
      expect(find.text('Cmentarz parafialny w Wymyślonowie'), findsOneWidget);

      await tester.tap(find.text('Pochówek'));
      await _pumpUntil(tester, () => _shown(find.byType(CemeteryScreen)));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Grób rodzinny Wymyślonych')),
      );
      await _settle(tester);
      final CemeteryScreen screen = tester.widget(find.byType(CemeteryScreen));
      expect(screen.highlightGraveId, mariaGrave);
      expect(screen.tab, AppTab.people);
      expect(
        tester.getSemantics(
          find
              .ancestor(
                of: find.text('Grób rodzinny Wymyślonych'),
                matching: find.byType(Semantics),
              )
              .first,
        ),
        isSemantics(isSelected: true),
      );

      await tester.pageBack();
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      await cleanUp(tester);
    },
  );

  /// Takes the screen down before the test reads the database itself (README → Testy).
  Future<void> leaveScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    PaintingBinding.instance.imageCache.clear();
  }

  /// Who is the background on Maria's links, in the order of her photos.
  Future<List<bool>> backgroundsOfMaria(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => [
          for (final PersonPhoto p in await personPhotos(db, maria))
            p.isBackground,
        ],
      ))!;

  testWidgets(
    'AC-5, D21 — the background over the portrait; the band opens "Zdjęcie w tle": the current one framed '
    'and selected, a tap on another sets it at once and the view returns; "Bez zdjęcia w tle" takes it off',
    (tester) async {
      await withFamily(tester);
      await pumpView(tester, maria);
      expect(find.bySemanticsLabel('Zdjęcie w tle'), findsOneWidget);
      expect(find.bySemanticsLabel('Zdjęcie profilowe'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Zdjęcie w tle'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);
      expect(find.text('Dotknij zdjęcia, które ma być w tle.'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Zdjęcie 2 z 2, tło — wybierz'),
        ),
        isSemantics(isSelected: true),
      );
      expect(find.text('Bez zdjęcia w tle'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Zdjęcie 1 z 2 — ustaw jako tło'));
      await _pumpUntil(tester, () => !_shown(find.byType(PersonPhotosScreen)));
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      await _settle(tester);
      // Written at once: "Zdjęcie w tle" opened again has the first one as the background.
      await tester.tap(find.bySemanticsLabel('Zdjęcie w tle'));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Zdjęcie 1 z 2, tło — wybierz')),
      );
      await _settle(tester);
      await tester.tap(find.text('Bez zdjęcia w tle'));
      await _pumpUntil(tester, () => !_shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);
      // The band stays — a plain one.
      expect(find.bySemanticsLabel('Zdjęcie w tle: brak'), findsOneWidget);
      await leaveScreen(tester);
      expect(await backgroundsOfMaria(tester), [false, false]);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'W2 — "Zdjęcia" opens the photos only to look at: no "Dodaj zdjęcie" tile, the background said for a '
    'screen reader; a photo opens without actions and without "Zmień"',
    (tester) async {
      await withFamily(tester);
      await pumpView(tester, maria);
      await scrollTo(tester, find.text('Zdjęcia · 2'));
      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby, 2'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);
      expect(find.text('Dodaj zdjęcie'), findsNothing);
      expect(
        find.bySemanticsLabel('Zdjęcie 2 z 2, tło — otwórz'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Zdjęcie 2 z 2, tło — otwórz'));
      await _pumpUntil(
        tester,
        () => _shown(find.byType(PersonPhotoViewerScreen)),
      );
      await _settle(tester);
      expect(find.text('Zdjęcie w tle'), findsOneWidget); // the bar
      expect(find.text('Ustaw jako tło'), findsNothing);
      expect(find.text('Usuń z tej osoby'), findsNothing);
      expect(find.text('Zmień'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D21 — without photos: the plain band → "Zdjęcie w tle" → "Dodaj zdjęcie" → the sheet "Zdjęcie w tle" → '
    'one photo from the gallery → it is the background at once (and, the first photo, the profile)',
    (tester) async {
      await withFamily(tester, mariaPhotos: false);
      picker.answers.add(
        File('${tmp.path}/galeria/wymyslony-dom.jpg')
          ..createSync(recursive: true)
          ..writeAsBytesSync(fictionalPeoplePng(4, heads: 1)),
      );
      await pumpView(tester, maria);
      expect(find.bySemanticsLabel('Zdjęcie profilowe'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Zdjęcie w tle: brak'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);
      expect(find.text('Bez zdjęcia w tle'), findsNothing);
      await tester.tap(find.text('Dodaj zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('Wybierz z galerii')));
      await _settle(tester);
      expect(find.text('Zdjęcie w tle'), findsWidgets); // the sheet's title too
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(tester, () => !_shown(find.byType(PersonPhotosScreen)));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Zdjęcie profilowe')),
      );
      await leaveScreen(tester);
      expect(await backgroundsOfMaria(tester), [true]);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'D20 — without photos: "Ta osoba nie ma jeszcze zdjęć." and "Dodaj zdjęcie" → the correction with the '
    'sheet "Zdjęcia osoby" over it → a photo from the gallery → "Zapisz" → the view with "Zdjęcia · 1"',
    (tester) async {
      await withFamily(tester, mariaPhotos: false);
      picker.manyAnswers.add([
        File('${tmp.path}/galeria/wymyslone.jpg')
          ..createSync(recursive: true)
          ..writeAsBytesSync(fictionalPeoplePng(3, heads: 1)),
      ]);
      await pumpView(tester, maria);
      // The band is there without a background too — a plain one (v2.3, D21).
      expect(find.bySemanticsLabel('Zdjęcie w tle: brak'), findsOneWidget);
      await scrollTo(tester, find.text('Dodaj zdjęcie'));
      expect(find.text('Ta osoba nie ma jeszcze zdjęć.'), findsOneWidget);

      await tester.tap(find.text('Dodaj zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('Zdjęcia osoby')));
      await _settle(tester);
      expect(find.byType(PersonFormScreen), findsOneWidget);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel(RegExp('^Zdjęcia osoby: 1'))),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
      await _pumpUntil(tester, () => !_shown(find.byType(PersonFormScreen)));
      await _pumpUntil(tester, () => _shown(find.text('Zdjęcia · 1')));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await _settle(tester);
      expect(find.bySemanticsLabel('Zdjęcie profilowe'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D15 — one correction of a person at a time: from Maria\'s form, Jan\'s view, back to Maria in his tree '
    '— ✎ returns to the form already open instead of opening a second',
    (tester) async {
      await withFamily(tester, mariaPhotos: false);
      await pumpView(tester, maria);
      await tester.tap(find.byTooltip('Popraw wpis'));
      await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Maria Józefa');
      final Finder janCard = find.text('Jan Wymyślony');
      // To the top of the form's list (a text field has a Scrollable of its own, so not the first one),
      // clear of "Zapisz" pinned at the bottom.
      // The focused field would scroll itself back on screen at every frame.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(janCard);
      await _settle(tester);
      await tester.tap(janCard);
      await _pumpUntil(
        tester,
        () => _shown(find.text('Żona')) && _shown(find.byType(PersonScreen)),
      );
      await _settle(tester);
      // Jan's view over Maria's form; her view below it is off the stage.
      expect(find.byType(PersonScreen), findsOneWidget);
      expect(find.text('Żona'), findsOneWidget);
      await tester.tap(find.text('Maria'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Maria Wymyślona z d. Testowa')),
      );
      await _settle(tester);
      await tester.tap(find.byTooltip('Popraw wpis'));
      await _settle(tester);
      await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
      expect(
        find.byType(PersonFormScreen, skipOffstage: false),
        findsOneWidget,
      );
      // The same form, with what was typed in it.
      expect(find.text('Maria Józefa'), findsOneWidget);
      await cleanUp(tester);
    },
  );
}
