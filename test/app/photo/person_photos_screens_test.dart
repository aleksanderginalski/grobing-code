import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/grave/person_form_screen.dart';
import 'package:grobing/app/photo/photo_picker.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/app/photo/profile_circle.dart';
import 'package:grobing/app/photo/profile_crop_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

import '../../support/photo_fakes.dart';

// ISSUE-017 — people's photos on the screens (05_DESIGN/zdjecia-osoby.md v1, zdjecie.md v1.3, wpis-osoby.md
// v4, grob.md v4), happy path per AC: US-005 AC-1 from the form's element 1a (several from the gallery)
// to the profile photo in the grave's card · "Ustaw jako profilowe" · "Kto jest na zdjęciu?" with this
// grave first, the filter, and a person from another grave ticked later (D2) · "Odrzuć" keeps nothing ·
// the window C1' says who keeps a shared photo. ISSUE-018 (kadr-profilowego.md v1, zdjecie.md v1.4): "Ustaw
// jako profilowe" through the crop screen, the crop in the header, the form's circle and the grave's card,
// "Popraw kadr" opening on the saved crop, back from the crop changing nothing. Pictures drawn in code,
// made-up people only (family-data.md).

/// Lets drift, file I/O and image loading run between frames (widget tests run in a fake clock).
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
  late int grave;
  late int jan;
  late int anna;
  late int jozef;
  late FakePhotoPicker picker;
  late Photos photos;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_person_photo_screens');
    db = GrobingDatabase(NativeDatabase.memory());
    picker = FakePhotoPicker();
    photos = fakePhotos(tmp, picker: picker);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: the image loader may still hold a file; nothing in it is real.
    }
  });

  /// Jan and Anna in one grave, Józef in another; [janPhotos] and [shared] made through the data layer;
  /// [janCrop] on Jan's first photo.
  Future<void> withPeople(
    WidgetTester tester, {
    int janPhotos = 0,
    bool sharedFromAnna = false,
    PhotoCrop? janCrop,
  }) async {
    await tester.runAsync(() async {
      final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
      grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
      );
      jan = (await db.select(db.persons).getSingle()).id;
      anna = await addPersonToGrave(
        db,
        graveId: grave,
        entry: const PersonEntry(givenNames: 'Anna', surname: 'Wymyślona'),
      );
      final int other = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Józef', surname: 'Zmyślony'),
      );
      jozef = (await loadGrave(db, other))!.people.single.id;

      NewPhoto drawn(int n) => NewPhoto(
        File('${tmp.path}/photo-work/narysowane-$n.jpg')
          ..createSync(recursive: true)
          ..writeAsBytesSync(fictionalPeoplePng(n, heads: 1 + n % 2)),
      );
      if (janPhotos > 0) {
        final List<NewPhoto> his = [
          for (int i = 1; i <= janPhotos; i++) drawn(i),
        ];
        await photos.writeWithPersonPhotos<void>(
          db,
          PersonPhotoEdits(photos: his, crops: {his.first: ?janCrop}),
          (also) => updatePersonEntry(
            db,
            jan,
            const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
            alsoWrite: also,
          ),
        );
      }
      if (sharedFromAnna) {
        final NewPhoto wedding = drawn(9);
        await photos.writeWithPersonPhotos<void>(
          db,
          PersonPhotoEdits(
            photos: [wedding],
            others: {
              wedding: {jan},
            },
          ),
          (also) => updatePersonEntry(
            db,
            anna,
            const PersonEntry(givenNames: 'Anna', surname: 'Wymyślona'),
            alsoWrite: also,
          ),
        );
      }
    });
  }

  /// Takes the screens down before the test reads the database itself (a screen's stream holds the
  /// lock in the fake clock's zone — grave_screens_test.dart).
  Future<void> leaveScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    PaintingBinding.instance.imageCache.clear();
  }

  Future<void> pumpGrave(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: GraveScreen(database: db, graveId: grave, photos: photos),
      ),
    );
    await _pumpUntil(tester, () => _shown(find.text('Jan Wymyślony')));
  }

  /// The grave view → Jan's card → his form (correction).
  Future<void> openJan(WidgetTester tester) async {
    await tester.tap(find.text('Jan Wymyślony'));
    await _settle(tester);
    await _pumpUntil(tester, () => _shown(find.byType(PersonFormScreen)));
  }

  Future<void> saveForm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await _pumpUntil(tester, () => !_shown(find.byType(PersonFormScreen)));
  }

  Future<List<String>> photosOf(WidgetTester tester, int person) async =>
      (await tester.runAsync(
        () async => [
          for (final PersonPhoto p in await personPhotos(db, person))
            p.relativePath,
        ],
      ))!;

  Finder cardImage(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)),
    matching: find.byType(Image),
  );

  /// The crop the profile circle in [scope] shows (ISSUE-018).
  PhotoCrop? circleCrop(WidgetTester tester, Finder scope) => tester
      .widget<ProfileCircle>(
        find.descendant(of: scope, matching: find.byType(ProfileCircle)),
      )
      .crop;

  Future<List<PhotoCrop?>> cropsOf(WidgetTester tester, int person) async =>
      (await tester.runAsync(
        () async => [
          for (final PersonPhoto p in await personPhotos(db, person)) p.crop,
        ],
      ))!;

  /// A double tap in the middle of the crop area (kadr-profilowego.md v1.2, D7'): the photo grows ×2 there.
  Future<void> doubleTapMiddle(WidgetTester tester) async {
    final Offset middle = tester
        .getRect(find.bySemanticsLabel('Kadr profilowego — zdjęcie w okręgu'))
        .center;
    await tester.tapAt(middle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(middle);
    await _settle(tester);
  }

  /// The crop screen is up and has read the photo's size: "Gotowe" can be pressed.
  Future<void> cropReady(WidgetTester tester) => _pumpUntil(
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

  testWidgets(
    'US-005 AC-1 — element 1a: "Dodaj zdjęcie" → the sheet "Zdjęcia osoby" → two photos from the '
    'gallery → the circle and "2 zdjęcia" before saving → "Zapisz" → the profile photo in the card',
    (tester) async {
      await withPeople(tester);
      picker.manyAnswers.add([
        pickedPhoto(Directory('${tmp.path}/cache'), 1),
        pickedPhoto(Directory('${tmp.path}/cache'), 2),
      ]);
      await pumpGrave(tester);
      expect(cardImage('Jan Wymyślony'), findsNothing);
      await openJan(tester);

      // ui review (MAJOR): the label does not hide the tap — a screen reader, Switch Access and Voice
      // Access can press it (WCAG 2.2 SC 4.1.2).
      expect(
        tester.getSemantics(find.bySemanticsLabel('Dodaj zdjęcie osoby')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(find.bySemanticsLabel('Dodaj zdjęcie osoby'));
      await _settle(tester);
      expect(find.text('Zdjęcia osoby'), findsOneWidget);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(tester, () => _shown(find.text('2 zdjęcia')));
      expect(picker.discarded, hasLength(2), reason: "the picker's copies go");

      await saveForm(tester);
      await _pumpUntil(tester, () => _shown(cardImage('Jan Wymyślony')));
      expect(cardImage('Anna Wymyślona'), findsNothing, reason: 'D11');

      await leaveScreen(tester);
      expect(await photosOf(tester, jan), hasLength(2));
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'the person\'s photos and the viewer: the profile in the header, "Ustaw jako profilowe" → the crop → '
    '"Gotowe" → "Zdjęcie profilowe" and "Popraw kadr" (zdjecie.md v1.4); "Kto jest na zdjęciu?" — this '
    'grave first, the filter, Józef from another grave ticked later (D2) → "Na zdjęciu" names him → saved '
    'with "Zapisz"',
    (tester) async {
      await withPeople(tester, janPhotos: 2);
      final List<String> before = await photosOf(tester, jan);
      await pumpGrave(tester);
      await openJan(tester);
      await _pumpUntil(tester, () => _shown(find.text('2 zdjęcia')));

      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby: 2 — otwórz'));
      await _settle(tester);
      expect(find.text('Profilowe'), findsOneWidget);
      expect(find.text('Wszystkie zdjęcia · 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Dodaj zdjęcie osoby'), findsOneWidget);
      for (final String label in [
        'Zdjęcie profilowe — otwórz',
        'Zdjęcie 1 z 2, profilowe — otwórz',
        'Zdjęcie 2 z 2 — otwórz',
        'Dodaj zdjęcie osoby',
      ]) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasTapAction: true),
          reason: label,
        );
      }

      await tester.tap(find.bySemanticsLabel('Zdjęcie 2 z 2 — otwórz'));
      await _settle(tester);
      expect(find.text('2 z 2'), findsOneWidget);
      expect(find.byTooltip('Następne zdjęcie'), findsOneWidget);
      expect(find.text('Zdjęcie osoby'), findsOneWidget);
      await tester.tap(find.text('Ustaw jako profilowe'));
      await _settle(tester);
      await cropReady(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Gotowe'));
      await _settle(tester);
      expect(find.text('1 z 2'), findsOneWidget);
      expect(find.text('Ustaw jako profilowe'), findsNothing);
      expect(find.text('Zdjęcie profilowe'), findsOneWidget);
      expect(find.text('Popraw kadr'), findsOneWidget);

      // D: who is on the photo.
      await _pumpUntil(
        tester,
        () =>
            tester
                .widget<TextButton>(find.widgetWithText(TextButton, 'Zmień'))
                .onPressed !=
            null,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Zmień'));
      await _settle(tester);
      expect(find.text('Kto jest na zdjęciu?'), findsOneWidget);
      expect(find.text('W tym grobie'), findsOneWidget);
      expect(find.text('ta osoba'), findsOneWidget);
      expect(find.text('Anna Wymyślona'), findsOneWidget);
      expect(find.text('Inne osoby'), findsOneWidget);
      expect(find.text('Józef Zmyślony'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zmy');
      await tester.pump();
      expect(find.text('Anna Wymyślona'), findsNothing);
      expect(find.text('W tym grobie'), findsNothing);
      await tester.tap(find.text('Józef Zmyślony'));
      await tester.pump();
      await tester.tap(find.text('Gotowe'));
      await _settle(tester);
      await _pumpUntil(
        tester,
        () => _shown(
          find.textContaining(
            'Jan Wymyślony, Józef Zmyślony',
            findRichText: true,
          ),
        ),
      );

      await tester.pageBack();
      await _settle(tester);
      expect(
        find.text('Zmiany zdjęć zapiszą się razem z wpisem osoby.'),
        findsOneWidget,
      );
      await tester.pageBack();
      await _settle(tester);
      await saveForm(tester);

      await leaveScreen(tester);
      expect(await photosOf(tester, jan), [before[1], before[0]]);
      expect(await photosOf(tester, jozef), [before[1]]);
      // "Gotowe" on the crop screen writes the crop, even untouched (kadr-profilowego.md K5); Józef's
      // link has none.
      expect((await cropsOf(tester, jan)).first, isNotNull);
      expect(await cropsOf(tester, jozef), [null]);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-018 AC 1 — a group photo made the profile through its crop: a tap on the right face and a '
    'double tap → "Gotowe"; the header, the form\'s circle and — after "Zapisz" — the grave\'s card show '
    'that crop, and it is on Jan\'s link',
    (tester) async {
      await withPeople(tester, janPhotos: 1, sharedFromAnna: true);
      await pumpGrave(tester);
      await openJan(tester);
      await _pumpUntil(tester, () => _shown(find.text('2 zdjęcia')));
      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby: 2 — otwórz'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Zdjęcie 2 z 2 — otwórz'));
      await _settle(tester);
      await tester.tap(find.text('Ustaw jako profilowe'));
      await _settle(tester);
      await cropReady(tester);
      expect(find.text('Kadr profilowego'), findsOneWidget);
      // v1.2 (the author's choice at stop #2): no hint and no zoom buttons.
      expect(
        find.text('Przesuń zdjęcie palcem albo dotknij twarzy.'),
        findsNothing,
      );
      expect(find.byTooltip('Powiększ'), findsNothing);
      final Rect area = tester.getRect(
        find.bySemanticsLabel('Kadr profilowego — zdjęcie w okręgu'),
      );
      await tester.tapAt(Offset(area.right - 20, area.center.dy));
      await _settle(tester);
      await doubleTapMiddle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Gotowe'));
      await _settle(tester);
      expect(find.text('Zdjęcie profilowe'), findsOneWidget);

      await tester.pageBack();
      await _settle(tester);
      final PhotoCrop header = circleCrop(
        tester,
        find.bySemanticsLabel('Zdjęcie profilowe — otwórz'),
      )!;
      // A square inside the photo, zoomed and moved right of the middle (the middle is left 60).
      expect(header.width, header.height);
      expect(header.width, lessThan(360));
      expect(header.left, greaterThan(60));
      expect(header.left + header.width, lessThanOrEqualTo(480));
      await tester.pageBack();
      await _settle(tester);
      expect(
        circleCrop(tester, find.bySemanticsLabel('Zdjęcia osoby: 2 — otwórz')),
        header,
      );
      await saveForm(tester);
      await _pumpUntil(tester, () => _shown(cardImage('Jan Wymyślony')));
      expect(
        circleCrop(
          tester,
          find.ancestor(
            of: find.text('Jan Wymyślony'),
            matching: find.byType(InkWell),
          ),
        ),
        header,
      );

      await leaveScreen(tester);
      expect((await cropsOf(tester, jan)).first, header);
      // Anna's link to the same photo keeps having none (AC 2: a crop per person).
      expect(await cropsOf(tester, anna), [null]);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-018 AC 3 — "Popraw kadr" opens on the saved crop: "Gotowe" untouched changes nothing; '
    'a double tap → "Gotowe" → "Zapisz" writes the new crop',
    (tester) async {
      const PhotoCrop saved = PhotoCrop(
        left: 200,
        top: 40,
        width: 200,
        height: 200,
      );
      await withPeople(tester, janPhotos: 1, janCrop: saved);
      await pumpGrave(tester);
      expect(
        circleCrop(
          tester,
          find.ancestor(
            of: find.text('Jan Wymyślony'),
            matching: find.byType(InkWell),
          ),
        ),
        saved,
      );
      await openJan(tester);
      await _pumpUntil(tester, () => _shown(find.text('1 zdjęcie')));
      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby: 1 — otwórz'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe — otwórz'));
      await _settle(tester);
      expect(find.text('Zdjęcie profilowe'), findsOneWidget);
      await tester.tap(find.text('Popraw kadr'));
      await _settle(tester);
      await cropReady(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Gotowe'));
      await _settle(tester);
      await tester.pageBack();
      await _settle(tester);
      expect(
        find.text('Zmiany zdjęć zapiszą się razem z wpisem osoby.'),
        findsNothing,
        reason: 'the same crop is no change',
      );

      await tester.tap(find.bySemanticsLabel('Zdjęcie profilowe — otwórz'));
      await _settle(tester);
      await tester.tap(find.text('Popraw kadr'));
      await _settle(tester);
      await cropReady(tester);
      await doubleTapMiddle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Gotowe'));
      await _settle(tester);
      await tester.pageBack();
      await _settle(tester);
      expect(
        find.text('Zmiany zdjęć zapiszą się razem z wpisem osoby.'),
        findsOneWidget,
      );
      await tester.pageBack();
      await _settle(tester);
      await saveForm(tester);

      await leaveScreen(tester);
      final PhotoCrop corrected = (await cropsOf(tester, jan)).single!;
      expect(corrected.width, lessThan(saved.width));
      // A double tap in the middle of the circle grows the photo there: the middle stays.
      expect(
        corrected.left + corrected.width / 2,
        closeTo(saved.left + saved.width / 2, 1),
      );
      expect(
        corrected.top + corrected.height / 2,
        closeTo(saved.top + saved.height / 2, 1),
      );
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'ISSUE-018 D9 — back from the crop screen changes nothing: the photo is not the profile and has no '
    'crop, no window',
    (tester) async {
      await withPeople(tester, janPhotos: 2);
      await pumpGrave(tester);
      await openJan(tester);
      await _pumpUntil(tester, () => _shown(find.text('2 zdjęcia')));
      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby: 2 — otwórz'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Zdjęcie 2 z 2 — otwórz'));
      await _settle(tester);
      await tester.tap(find.text('Ustaw jako profilowe'));
      await _settle(tester);
      await cropReady(tester);
      await doubleTapMiddle(tester);
      await tester.pageBack();
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('2 z 2'), findsOneWidget);
      expect(find.text('Zdjęcie osoby'), findsOneWidget);
      expect(find.text('Ustaw jako profilowe'), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);
      expect(
        find.text('Zmiany zdjęć zapiszą się razem z wpisem osoby.'),
        findsNothing,
      );
      await leaveScreen(tester);
      expect(await cropsOf(tester, jan), [null, null]);
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'US-005 AC-1 — "Zrób zdjęcie" from the person\'s photos: one photo from the camera joins the grid '
    'and is saved with "Zapisz" (US-005 review: the camera had no happy path)',
    (tester) async {
      await withPeople(tester, janPhotos: 1);
      picker.answers.add(pickedPhoto(Directory('${tmp.path}/cache'), 4));
      await pumpGrave(tester);
      await openJan(tester);
      await _pumpUntil(tester, () => _shown(find.text('1 zdjęcie')));
      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby: 1 — otwórz'));
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel('Dodaj zdjęcie osoby'));
      await _settle(tester);
      await tester.tap(find.text('Zrób zdjęcie'));
      await _pumpUntil(
        tester,
        () => _shown(find.text('Wszystkie zdjęcia · 2')),
      );
      expect(picker.asked, [PhotoSource.camera]);

      await tester.pageBack();
      await _settle(tester);
      expect(find.text('2 zdjęcia'), findsOneWidget);
      await saveForm(tester);

      await leaveScreen(tester);
      expect(await photosOf(tester, jan), hasLength(2));
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    '"Odrzuć" — a photo added and not saved: the window names the photos, and nothing is written',
    (tester) async {
      await withPeople(tester);
      picker.manyAnswers.add([pickedPhoto(Directory('${tmp.path}/cache'), 1)]);
      await pumpGrave(tester);
      await openJan(tester);
      await tester.tap(find.bySemanticsLabel('Dodaj zdjęcie osoby'));
      await _settle(tester);
      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(tester, () => _shown(find.text('1 zdjęcie')));

      await tester.pageBack();
      await _settle(tester);
      expect(
        find.text('Wpisane dane i zmiany zdjęć nie zostaną zapisane.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Odrzuć'));
      await _settle(tester);
      await _pumpUntil(tester, () => !_shown(find.byType(PersonFormScreen)));

      // That the prepared file is dropped is tested on PersonPhotosDraft itself
      // (person_photos_draft_test.dart): here the circle shows that file, and on Windows the test's image
      // loader keeps it open, so it cannot be deleted while the screen is up.
      await leaveScreen(tester);
      await tester.runAsync(() async {
        expect(await db.select(db.media).get(), isEmpty);
        expect(await db.select(db.personMedia).get(), isEmpty);
        await db.close();
      });
    },
  );

  testWidgets(
    'the window C1\' — a shared photo removed from Jan says Anna keeps it and that he will have no '
    'photo; after "Zapisz" Anna still has it',
    (tester) async {
      await withPeople(tester, sharedFromAnna: true);
      await pumpGrave(tester);
      await openJan(tester);
      await _pumpUntil(tester, () => _shown(find.text('1 zdjęcie')));
      await tester.tap(find.bySemanticsLabel('Zdjęcia osoby: 1 — otwórz'));
      await _settle(tester);
      await tester.tap(
        find.bySemanticsLabel('Zdjęcie 1 z 1, profilowe — otwórz'),
      );
      await _settle(tester);
      expect(
        find.byTooltip('Następne zdjęcie'),
        findsNothing,
        reason: 'B3 only with more',
      );
      await _pumpUntil(
        tester,
        () => _shown(
          find.textContaining(
            'Jan Wymyślony, Anna Wymyślona',
            findRichText: true,
          ),
        ),
      );

      await tester.tap(find.text('Usuń z tej osoby'));
      await _settle(tester);
      expect(find.text('Usunąć zdjęcie z tej osoby?'), findsOneWidget);
      expect(
        find.text(
          'Zdjęcie zostaje u: Anna Wymyślona. Osoba nie będzie miała zdjęcia.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Usuń'));
      await _settle(tester);
      expect(find.text('Ta osoba nie ma zdjęć.'), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);
      expect(find.text('Dodaj zdjęcie'), findsOneWidget);
      await saveForm(tester);

      await leaveScreen(tester);
      expect(await photosOf(tester, jan), isEmpty);
      expect(await photosOf(tester, anna), hasLength(1));
      await tester.runAsync(db.close);
    },
  );
}
