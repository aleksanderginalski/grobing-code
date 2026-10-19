import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/person/person_screen.dart';
import 'package:grobing/app/photo/app_photos_screen.dart';
import 'package:grobing/app/photo/person_photo_viewer_screen.dart';
import 'package:grobing/app/photo/person_photos_screen.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/app/photo/profile_crop_screen.dart';
import 'package:grobing/app/tabs.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/glyphs.dart';
import 'package:grobing/app/widgets/wreath.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/clans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

import '../../support/a11y.dart';
import '../../support/glyphs.dart';
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
      // The header checked on the way: steps of 200 to the last row go past it since the view grew (ISSUE-042, 9a).
      await scrollTo(tester, find.text('Jak łączy się ze mną'));
      expect(find.text('Jak łączy się ze mną'), findsOneWidget);
      await scrollTo(tester, find.text('Jej mama Maria'));
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

      await tester.ensureVisible(find.text('Mama Anna'));
      await _settle(tester);
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
      // The upper text first: steps of 200 to the lower one went past it once the view grew (ISSUE-042, 9a).
      await scrollTo(
        tester,
        find.text('Rodziny jeszcze nie ma. Dodasz ją pod ✎.'),
      );
      expect(
        find.textContaining('Nie wiadomo jeszcze, jak łączy się z Tobą'),
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

  File galleryPhoto(int n, {int heads = 1}) =>
      File('${tmp.path}/galeria/wymyslone-$n.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(fictionalPeoplePng(n, heads: heads));

  Future<List<PersonPhoto>> photosOf(WidgetTester tester, int personId) async =>
      (await tester.runAsync(() => personPhotos(db, personId)))!;

  testWidgets(
    'ISSUE-048 AC-3, D24 (osoba.md v2.9) — without photos the circle of initials is a button with a badge '
    '("Zdjęcie profilowe: brak", tooltip "Dodaj zdjęcie") → the sheet "Zdjęcia osoby" at once, no form, no '
    '"Ze zdjęć w aplikacji" (no photo in the app) → a photo from the gallery → written at once: the portrait '
    'and "Zdjęcia · 1"; "Dodaj zdjęcie" at the bottom does the same for Jan (replaces D20\'s way through '
    '"Zapisz")',
    (tester) async {
      await withFamily(tester, mariaPhotos: false);
      picker.manyAnswers.add([galleryPhoto(3)]);
      await pumpView(tester, maria);
      // The band is there without a background too — a plain one (v2.3, D21).
      expect(find.bySemanticsLabel('Zdjęcie w tle: brak'), findsOneWidget);
      expect(find.bySemanticsLabel('Zdjęcie profilowe: brak'), findsOneWidget);
      expect(find.byTooltip('Dodaj zdjęcie'), findsOneWidget);
      expect(findGlyph(Glyphs.addPhotoAlternate), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe: brak'));
      await _pumpUntil(tester, () => _shown(find.text('Wybierz z galerii')));
      await _settle(tester);
      expect(find.text('Zdjęcia osoby'), findsOneWidget);
      expect(find.text('Ze zdjęć w\u00A0aplikacji'), findsNothing);
      expect(find.byType(PersonFormScreen), findsNothing);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Zdjęcie profilowe')),
      );
      await _settle(tester);
      expect(find.byType(PersonFormScreen), findsNothing);
      await scrollTo(tester, find.text('Zdjęcia · 1'));
      expect(find.text('Zdjęcia · 1'), findsOneWidget);
      await leaveScreen(tester);
      expect(await photosOf(tester, maria), hasLength(1));

      // Jan: "Dodaj zdjęcie" in the empty section — the same sheet, now with "Ze zdjęć w aplikacji"
      // (Maria has a photo), the camera, written at once.
      picker.answers.add(galleryPhoto(4));
      await pumpView(tester, jan);
      await scrollTo(tester, find.text('Ta osoba nie ma jeszcze zdjęć.'));
      await tester.tap(find.text('Dodaj zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('Zrób zdjęcie')));
      await _settle(tester);
      expect(find.text('Ze zdjęć w\u00A0aplikacji'), findsOneWidget);
      await tester.tap(find.text('Zrób zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('Zdjęcia · 1')));
      expect(find.byType(PersonFormScreen), findsNothing);
      await leaveScreen(tester);
      expect(await photosOf(tester, jan), hasLength(1));
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-048, ui review MAJOR — while the picked photos are prepared and written, the circle shows the '
    'progress and is inactive ("Zdjęcie profilowe: zapisuję zdjęcia"), "Dodaj zdjęcie" too: a second tap '
    'opens no second sheet; after the write both photos are there',
    (tester) async {
      await withFamily(tester, mariaPhotos: false);
      final _GatedPreparer gated = _GatedPreparer();
      photos = fakePhotos(tmp, picker: picker, preparer: gated);
      picker.manyAnswers.add([galleryPhoto(5), galleryPhoto(6, heads: 2)]);
      await pumpView(tester, maria);
      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe: brak'));
      await _pumpUntil(tester, () => _shown(find.text('Wybierz z galerii')));
      await _settle(tester);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(
        tester,
        () => _shown(
          find.bySemanticsLabel('Zdjęcie profilowe: zapisuję zdjęcia'),
        ),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Zdjęcie profilowe: zapisuję zdjęcia'),
        ),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel('Zdjęcie profilowe: zapisuję zdjęcia'),
        warnIfMissed: false,
      );
      await _settle(tester);
      expect(find.text('Wybierz z galerii'), findsNothing);
      await scrollTo(tester, find.text('Dodaj zdjęcie'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Dodaj zdjęcie'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );

      gated.open.complete();
      await _pumpUntil(tester, () => _shown(find.text('Zdjęcia · 2')));
      await leaveScreen(tester);
      expect(await photosOf(tester, maria), hasLength(2));
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-048 AC-1, AC-2 (zdjecia-osoby.md v1.5) — the portrait opens "Zdjęcie profilowe": "Obejrzyj '
    'zdjęcie", the line, the grid with the profile photo framed and selected, "Dodaj zdjęcia" — no ✎; '
    '"Obejrzyj zdjęcie" → the photo only to look at; another photo → the crop → "Gotowe" → the view with the '
    'new profile at once, its crop written, the background kept',
    (tester) async {
      await withFamily(tester);
      final List<PersonPhoto> before = await photosOf(tester, maria);
      await pumpView(tester, maria);
      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);
      expect(find.text('Zdjęcie profilowe'), findsOneWidget); // the bar
      expect(find.text('Obejrzyj zdjęcie'), findsOneWidget);
      expect(
        find.text('Dotknij zdjęcia, które ma być profilowym.'),
        findsOneWidget,
      );
      expect(find.text('Dodaj zdjęcia'), findsOneWidget);
      expect(find.text('Zapisz'), findsNothing);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            'Zdjęcie 1 z 2, profilowe, zaznaczone — popraw kadr',
          ),
        ),
        isSemantics(isSelected: true),
      );
      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();

      await tester.tap(find.text('Obejrzyj zdjęcie'));
      await _pumpUntil(
        tester,
        () => _shown(find.byType(PersonPhotoViewerScreen)),
      );
      await _settle(tester);
      expect(find.text('Ustaw jako tło'), findsNothing);
      expect(find.text('Usuń z tej osoby'), findsNothing);
      await tester.pageBack();
      await _pumpUntil(
        tester,
        () => !_shown(find.byType(PersonPhotoViewerScreen)),
      );
      await _settle(tester);

      await tester.tap(
        find.bySemanticsLabel('Zdjęcie 2 z 2 — ustaw jako profilowe'),
      );
      await _pumpUntil(
        tester,
        () =>
            _shown(find.byType(ProfileCropScreen)) &&
            tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Gotowe'),
                    )
                    .onPressed !=
                null,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Gotowe'));
      await _pumpUntil(tester, () => !_shown(find.byType(PersonPhotosScreen)));
      await _pumpUntil(tester, () => _shown(find.byType(PersonScreen)));
      await leaveScreen(tester);
      final List<PersonPhoto> after = await photosOf(tester, maria);
      expect(after.map((p) => p.mediaId), [
        before[1].mediaId,
        before[0].mediaId,
      ]);
      expect(after.first.crop, isNotNull, reason: 'the crop of "Gotowe"');
      expect(after.map((p) => p.isBackground), [true, false]);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-048 AC-4 (zdjecia-w-aplikacji.md) — Jan without photos: the circle → "Ze zdjęć w aplikacji" → '
    '"Najbliżsi" has his wife Maria with both her photos → one ticked → "Dodaj 1 zdjęcie" → Jan\'s view with '
    'the portrait; the photo is Jan\'s and still Maria\'s, one media row',
    (tester) async {
      await withFamily(tester);
      final List<PersonPhoto> marias = await photosOf(tester, maria);
      await pumpView(tester, jan);
      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe: brak'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Ze zdjęć w\u00A0aplikacji')),
      );
      await _settle(tester);
      await tester.tap(find.text('Ze zdjęć w\u00A0aplikacji'));
      await _pumpUntil(tester, () => _shown(find.byType(AppPhotosScreen)));
      await _settle(tester);
      final Finder screen = find.byType(AppPhotosScreen);
      expect(find.text('dla: Jan Wymyślony'), findsOneWidget);
      expect(
        find.text('Bez zdjęć, które Jan już ma. Dotknij zdjęć, które dodać.'),
        findsOneWidget,
      );
      expect(find.text('Najbliżsi'), findsOneWidget);
      expect(
        find.descendant(
          of: screen,
          matching: find.text('Maria Wymyślona z d. Testowa'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Dodaj'))
            .onPressed,
        isNull,
      );
      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();

      await tester.tap(
        find.bySemanticsLabel('Maria Wymyślona, zdjęcie 2 z 2 — zaznacz'),
      );
      await _settle(tester);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            'Maria Wymyślona, zdjęcie 2 z 2, zaznaczone — odznacz',
          ),
        ),
        isSemantics(isSelected: true),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Dodaj 1 zdjęcie'));
      await _pumpUntil(tester, () => !_shown(find.byType(AppPhotosScreen)));
      await _pumpUntil(
        tester,
        () => _shown(find.bySemanticsLabel('Zdjęcie profilowe')),
      );
      await leaveScreen(tester);
      expect((await photosOf(tester, jan)).map((p) => p.mediaId), [
        marias[1].mediaId,
      ]);
      expect(
        (await photosOf(tester, maria)).map((p) => p.mediaId),
        marias.map((p) => p.mediaId),
      );
      expect(
        await tester.runAsync(() => db.select(db.media).get()),
        hasLength(2),
      );
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-048 D25 — Maria\'s correction lies lower on the stack (her form → Jan\'s card → Jan\'s view → Maria '
    'in his tree): her portrait and her band return to that form instead of writing over it; "Zdjęcie w tle" '
    'has no "Ze zdjęć w aplikacji" (zdjecia-w-aplikacji.md D7)',
    (tester) async {
      await withFamily(tester);
      await pumpView(tester, maria);
      await tester.tap(find.byTooltip('Popraw wpis'));
      await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
      await _settle(tester);
      final Finder janCard = find.text('Jan Wymyślony');
      await tester.ensureVisible(janCard);
      await _settle(tester);
      await tester.tap(janCard);
      await _pumpUntil(
        tester,
        () => _shown(find.text('Żona')) && _shown(find.byType(PersonScreen)),
      );
      await _settle(tester);

      // Jan's band (his correction is not open): "Zdjęcie w tle" → its tile → the sheet of one photo.
      await tester.tap(find.bySemanticsLabel('Zdjęcie w tle: brak'));
      await _pumpUntil(tester, () => _shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);
      await tester.tap(find.text('Dodaj zdjęcie'));
      await _pumpUntil(tester, () => _shown(find.text('Wybierz z galerii')));
      await _settle(tester);
      expect(find.text('Ze zdjęć w\u00A0aplikacji'), findsNothing);
      await tester.tapAt(const Offset(20, 20)); // closes the sheet
      await _settle(tester);
      await tester.pageBack();
      await _pumpUntil(tester, () => !_shown(find.byType(PersonPhotosScreen)));
      await _settle(tester);

      await tester.tap(find.text('Maria'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Maria Wymyślona z d. Testowa')),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe'));
      await _pumpUntil(tester, () => _shown(find.text('Poprawa wpisu')));
      await _settle(tester);
      expect(find.byType(PersonPhotosScreen), findsNothing);
      expect(find.byType(PersonFormScreen), findsOneWidget);
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

  testWidgets(
    'ISSUE-044 AC-1, AC-4 — the wreath of the line under the portrait (osoba.md 3, 4a): the father\'s line on his '
    'son with "Ród: …"; a married woman half and half, "Ród: X · po mężu Y" with hard spaces; the name 8 dp '
    'under the knot; a person without a wreath has no line in words',
    (tester) async {
      await withFamily(tester);
      await tester.runAsync(() async {
        final int jozef =
            (await (db.select(db.persons)
                      ..where((p) => p.givenNames.equals('Józef'))
                      ..where((p) => p.surname.equals('Testowy')))
                    .getSingle())
                .id;
        await createClan(
          db,
          name: 'Testowscy',
          motif: WreathMotif.laur,
          colour: ClanColour.patyna,
          forPerson: jozef,
        );
        await createClan(
          db,
          name: 'Wymyślscy',
          motif: WreathMotif.dab,
          colour: ClanColour.stareZloto,
          forPerson: jan,
        );
      });
      final String nb = String.fromCharCode(0xA0);

      await pumpView(tester, maria);
      expect(
        find.text('Ród: Testowscy ·${nb}po${nb}mężu Wymyślscy'),
        findsOneWidget,
      );
      expect(find.byType(WreathView), findsOneWidget);
      final Rect wreath = tester.getRect(find.byType(WreathView));
      expect(wreath.width, 208);
      final Rect name = tester.getRect(
        find.text('Maria Wymyślona z d. Testowa'),
      );
      // C3: 8 dp under the knot, which ends at 0.91 of the box.
      expect(name.top, closeTo(wreath.top + 208 * 0.91 + 8, 1));
      // The wreath is outside the reader: the line in words carries it.
      expect(
        find.descendant(
          of: find.byType(WreathView),
          matching: find.byType(Semantics),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      await pumpView(tester, anna); // Jan's daughter: his line after him
      expect(find.text('Ród: Wymyślscy'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      await pumpView(
        tester,
        ewa,
      ); // only a mother in the tree: no father, no wreath
      expect(find.byType(WreathView), findsNothing);
      expect(find.textContaining('Ród:'), findsNothing);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ISSUE-046 AC-2 — 200% text on 360 dp: icons next to words grow with them (a section header 22 → 44 dp), '
    'the app bar\'s pen and back stay 24 dp; every button has a tap action and a target of 48 dp',
    (tester) async {
      // The test font draws every letter as a square, wider than Roboto: the bottom bar (lib/app/tabs.dart, its
      // icons fixed at 24 dp) overflows in it at 200 % and not on a phone — as in the tree's test of 200 %. Only
      // that overflow is let through; the bar in Roboto is the emulator's (Dev report → Emulator pass, 200 %).
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final String error = details.toString();
        if (error.contains('overflowed') &&
            error.contains('lib/app/tabs.dart')) {
          return;
        }
        previous?.call(details);
      };
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await withFamily(tester);
      // pumpView waits for "Rodzina", which at 200% is below the first screen and not built yet.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: GrobingTheme.dark,
          home: PersonScreen(database: db, personId: maria, photos: photos),
        ),
      );
      await _pumpUntil(tester, () => _shown(findGlyph(Glyphs.inkPen)));
      await _settle(tester);

      expect(tester.getSize(findGlyph(Glyphs.inkPen)), const Size(24, 24));
      expect(tester.getSize(findGlyph(Glyphs.arrowBack)), const Size(24, 24));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      await scrollTo(tester, find.text('Rodzina'));
      // The section header's icon (the tab "Osoby" has the same glyph and stays 24 dp).
      final Finder header = find.descendant(
        of: find
            .ancestor(of: find.text('Rodzina'), matching: find.byType(Row))
            .first,
        matching: findGlyph(Glyphs.group),
      );
      expect(tester.getSize(header), const Size(44, 44)); // 22 dp × 2
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();
      await cleanUp(tester);
      FlutterError.onError = previous;
    },
  );
}

/// A preparer that waits until [open] completes — the photos stay "being prepared" for as long as the test
/// needs (ui review of ISSUE-048, MAJOR).
class _GatedPreparer extends FakePhotoPreparer {
  final Completer<void> open = Completer<void>();

  @override
  Future<void> prepare(File source, File target) async {
    await open.future;
    return super.prepare(source, target);
  }
}
