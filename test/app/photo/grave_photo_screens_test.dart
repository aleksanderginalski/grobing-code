import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/grave/cemetery_screen.dart';
import 'package:grobing/app/grave/grave_screen.dart';
import 'package:grobing/app/photo/photo_picker.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

import '../../support/photo_fakes.dart';

// ISSUE-016 — the gravestone photo on the screens (05_DESIGN/grob.md v3, zdjecie.md v1.1, cmentarz.md
// v3), happy path per AC: US-005 AC-1 "Dodaj zdjęcie" → the source sheet → the photo above the title ·
// the viewer: the whole photo, double tap zooms (SC 2.5.1) · change and delete with the window (D1') ·
// a failed save says so · the thumbnail on the cemetery screen (D9). Pictures drawn in code, made-up
// people only (family-data.md).

/// Lets drift's streams, file I/O and writes settle between frames (widget tests run in a fake clock).
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

final Finder _photo = find.bySemanticsLabel('Zdjęcie nagrobka — otwórz');

/// A route or a sheet runs to its end: the first frame builds it, the next ones animate it.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// The photo is decoded and laid out — until then its field has no height (the file loads in real
/// time, which `_pumpUntil` lets run).
bool _photoShown(WidgetTester tester) {
  final Finder image = find.descendant(
    of: _photo,
    matching: find.byType(Image),
  );
  return image.evaluate().isNotEmpty && tester.getSize(image).height > 0;
}

final Finder _addPhoto = find.text('Dodaj zdjęcie nagrobka');

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late int cemetery;
  late int grave;
  late FakePhotoPicker picker;
  late FakePhotoPreparer preparer;
  late Photos photos;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_grave_photo_test');
    db = GrobingDatabase(NativeDatabase.memory());
    picker = FakePhotoPicker();
    preparer = FakePhotoPreparer();
    photos = fakePhotos(tmp, picker: picker, preparer: preparer);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: the image loader may still hold a file it was reading; the system's temp directory
      // is cleaned later, and nothing in it is real (pictures drawn in code).
    }
  });

  Future<void> withGrave(WidgetTester tester, {bool photo = false}) async {
    await tester.runAsync(() async {
      cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
      grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
      );
      if (photo) {
        final File prepared = File('${tmp.path}/gotowe.jpg')
          ..writeAsBytesSync(fictionalGravestonePng(1));
        await setGravePhoto(db, photos.mediaDir, grave, prepared);
      }
    });
  }

  /// Takes the screen down before the test reads the database itself (a screen's stream holds the
  /// database lock in the fake clock's zone — grave_screens_test.dart), then closes it.
  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    PaintingBinding.instance.imageCache.clear();
    await tester.runAsync(db.close);
  }

  Future<String?> photoInDb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    return (await tester.runAsync<String?>(() => gravePhotoPath(db, grave)));
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: GrobingTheme.dark, home: screen),
    );
    await _pumpUntil(
      tester,
      () => find.text('Jan Wymyślony').evaluate().isNotEmpty,
    );
  }

  testWidgets(
    'US-005 AC-1, D12 — the field "Dodaj zdjęcie nagrobka" in the place of the photo, above the title → the '
    'sheet (gallery first, then camera) → the picked photo stands there and the field goes',
    (tester) async {
      await withGrave(tester);
      picker.answers.add(pickedPhoto(Directory('${tmp.path}/cache'), 1));
      await pumpScreen(
        tester,
        GraveScreen(database: db, graveId: grave, photos: photos),
      );
      expect(_photo, findsNothing);
      // D12 (stop #2): the field stands where the photo will, above the grave's title; the row of actions
      // has only "Dodaj osobę".
      expect(
        tester.getCenter(_addPhoto).dy,
        lessThan(tester.getCenter(find.text('Grób')).dy),
      );
      expect(find.text('Dodaj zdjęcie'), findsNothing);

      await tester.tap(_addPhoto);
      await _settle(tester);
      expect(find.text('Zdjęcie nagrobka'), findsOneWidget);
      final double gallery = tester
          .getCenter(find.text('Wybierz z galerii'))
          .dy;
      final double camera = tester.getCenter(find.text('Zrób zdjęcie')).dy;
      expect(
        gallery,
        lessThan(camera),
        reason: 'gallery first (zdjecie.md D1)',
      );

      await tester.tap(find.text('Wybierz z galerii'));
      await _pumpUntil(tester, () => _photoShown(tester));

      expect(picker.asked, [PhotoSource.gallery]);
      expect(_addPhoto, findsNothing);
      expect(find.text('Dodaj osobę'), findsOneWidget);
      expect(await photoInDb(tester), isNotNull);
      await cleanUp(tester);
    },
  );

  testWidgets('closing the sheet or the picker changes nothing', (
    tester,
  ) async {
    await withGrave(tester);
    await pumpScreen(
      tester,
      GraveScreen(database: db, graveId: grave, photos: photos),
    );

    await tester.tap(_addPhoto);
    await _settle(tester);
    await tester.tapAt(const Offset(180, 100));
    await _settle(tester);
    await tester.tap(_addPhoto);
    await _settle(tester);
    await tester.tap(find.text('Zrób zdjęcie'));
    await _pumpUntil(tester, () => picker.asked.isNotEmpty);
    await _settle(tester);

    expect(picker.asked, [PhotoSource.camera]);
    expect(_addPhoto, findsOneWidget);
    expect(find.textContaining('Nie udało się'), findsNothing);
    expect(await photoInDb(tester), isNull);
    await cleanUp(tester);
  });

  testWidgets(
    'US-005 AC-1 — "Zrób zdjęcie": the camera\'s photo stands above the title and the field goes (US-005 '
    'review: the camera had no happy path)',
    (tester) async {
      await withGrave(tester);
      picker.answers.add(pickedPhoto(Directory('${tmp.path}/cache'), 3));
      await pumpScreen(
        tester,
        GraveScreen(database: db, graveId: grave, photos: photos),
      );

      await tester.tap(_addPhoto);
      await _settle(tester);
      await tester.tap(find.text('Zrób zdjęcie'));
      await _pumpUntil(tester, () => _photoShown(tester));

      expect(picker.asked, [PhotoSource.camera]);
      expect(_addPhoto, findsNothing);
      expect(await photoInDb(tester), startsWith('groby/$grave/'));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'a photo that cannot be prepared: the message with its icon, no photo, "Dodaj zdjęcie" stays',
    (tester) async {
      await withGrave(tester);
      preparer.error = Exception('nie da się zdekodować');
      picker.answers.add(pickedPhoto(Directory('${tmp.path}/cache'), 1));
      await pumpScreen(
        tester,
        GraveScreen(database: db, graveId: grave, photos: photos),
      );

      await tester.tap(_addPhoto);
      await _settle(tester);
      await tester.tap(find.text('Wybierz z galerii'));
      final Finder message = find.text(
        'Nie udało się zapisać zdjęcia. Spróbuj jeszcze raz.',
      );
      await _pumpUntil(tester, () => message.evaluate().isNotEmpty);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(_photo, findsNothing);
      expect(_addPhoto, findsOneWidget);
      expect(await photoInDb(tester), isNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'the viewer: the whole photo with the grave\'s name, double tap zooms in and back (SC 2.5.1)',
    (tester) async {
      await withGrave(tester, photo: true);
      await pumpScreen(
        tester,
        GraveScreen(database: db, graveId: grave, photos: photos),
      );
      await _pumpUntil(tester, () => _photoShown(tester));

      await tester.tap(_photo);
      await _settle(tester);
      expect(find.text('Grób'), findsOneWidget);
      expect(find.text('Zdjęcie nagrobka'), findsOneWidget);
      expect(find.text('Zmień zdjęcie'), findsOneWidget);
      expect(find.text('Usuń zdjęcie'), findsOneWidget);

      double scale() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      expect(scale(), 1);
      final Offset at = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await _settle(tester);
      expect(scale(), closeTo(2.5, 0.001));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await _settle(tester);
      expect(scale(), 1);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D1\' — "Zmień zdjęcie" replaces the photo: the viewer shows the new one, the grave keeps one',
    (tester) async {
      await withGrave(tester, photo: true);
      final String before = (await tester.runAsync<String?>(
        () => gravePhotoPath(db, grave),
      ))!;
      picker.answers.add(pickedPhoto(Directory('${tmp.path}/cache'), 2));
      await pumpScreen(
        tester,
        GraveScreen(database: db, graveId: grave, photos: photos),
      );
      await _pumpUntil(tester, () => _photoShown(tester));
      await tester.tap(_photo);
      await _settle(tester);

      await tester.tap(find.text('Zmień zdjęcie'));
      await _settle(tester);
      // ui review (MAJOR): while the sheet is open nothing is being saved, so the viewer says nothing of
      // the kind (zdjecie.md, B — "zmiana w toku" only after the choice).
      expect(find.text('Zapisuję zdjęcie…'), findsNothing);
      await tester.tap(find.text('Wybierz z galerii'));
      // The viewer shows the whole file (a FileImage); the grave view below decodes a smaller copy.
      bool viewerShowsNew() => find
          .byType(Image)
          .evaluate()
          .map((e) => (e.widget as Image).image)
          .whereType<FileImage>()
          .any(
            (p) =>
                p.file.path.contains('groby') && !p.file.path.endsWith(before),
          );
      await _pumpUntil(tester, viewerShowsNew);
      expect(find.text('Zmień zdjęcie'), findsOneWidget);

      final String? after = await photoInDb(tester);
      expect(after, isNotNull);
      expect(after, isNot(before));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D1\' — "Usuń zdjęcie" asks first: "Zostaw" keeps it; "Usuń" deletes it and returns to the grave, '
    'where "Dodaj zdjęcie" is back',
    (tester) async {
      await withGrave(tester, photo: true);
      await pumpScreen(
        tester,
        GraveScreen(database: db, graveId: grave, photos: photos),
      );
      await _pumpUntil(tester, () => _photoShown(tester));
      await tester.tap(_photo);
      await _settle(tester);

      await tester.tap(find.text('Usuń zdjęcie'));
      await _settle(tester);
      expect(find.text('Usunąć zdjęcie?'), findsOneWidget);
      expect(
        find.text(
          'Zdjęcia nie będzie w aplikacji ani w kolejnych kopiach. '
          'Jeśli jest w galerii telefonu, tam zostaje.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Zostaw'));
      await _settle(tester);
      expect(find.text('Usunąć zdjęcie?'), findsNothing);
      expect(find.text('Zmień zdjęcie'), findsOneWidget);

      await tester.tap(find.text('Usuń zdjęcie'));
      await _settle(tester);
      await tester.tap(find.text('Usuń'));
      await _pumpUntil(tester, () => _addPhoto.evaluate().isNotEmpty);
      await _settle(tester);

      expect(_photo, findsNothing);
      expect(find.text('Zmień zdjęcie'), findsNothing);
      expect(await photoInDb(tester), isNull);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'D9 (cmentarz.md v3) — the card of a grave with a photo has its thumbnail; a grave without one has '
    'none',
    (tester) async {
      await withGrave(tester, photo: true);
      await tester.runAsync(
        () => addPersonToNewGrave(
          db,
          cemeteryId: cemetery,
          entry: const PersonEntry(givenNames: 'Ewa', surname: 'Testowa'),
        ),
      );
      await pumpScreen(
        tester,
        CemeteryScreen(database: db, cemeteryId: cemetery, photos: photos),
      );

      final Finder thumbnails = find.byWidgetPredicate(
        (w) => w is Image && w.width == 56 && w.height == 56,
      );
      expect(thumbnails, findsOneWidget);
      expect(
        find.ancestor(of: thumbnails, matching: find.byType(InkWell)),
        findsWidgets,
      );
      await cleanUp(tester);
    },
  );
}
