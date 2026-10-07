import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/photo/profile_crop_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

// ISSUE-018 — the crop screen alone (05_DESIGN/kadr-profilowego.md v1.2: K1, K2, K5, States): K1 with the
// person, no hint and no zoom buttons (the author's choice at stop #2) · a double tap grows the photo ×2 at
// the point and, at 128 px (D5), goes back to the whole (D7', SC 2.5.1) · a tap brings a point to the
// middle · "Gotowe" pops the square under the circle, untouched the link's own crop · back pops nothing
// (D9) · an unreadable file: the message, "Gotowe" inactive. A picture drawn in code (480 × 360), made-up
// people only.

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

/// A tap waits out the double-tap timeout, its glide starts in the next frame, and a route goes a frame
/// after its animation: three pumps.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory tmp;
  late File photo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_crop_screen');
    photo = File('${tmp.path}/slub.png')
      ..writeAsBytesSync(fictionalPeoplePng(1, heads: 2));
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: the image loader may still hold the file; nothing in it is real.
    }
  });

  /// Opens the crop screen on [file] from a host page; the returned list gets what it pops.
  Future<List<PhotoCrop?>> open(
    WidgetTester tester,
    File file, {
    PhotoCrop? initial,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final List<PhotoCrop?> popped = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => popped.add(
                  await Navigator.of(context).push<PhotoCrop>(
                    MaterialPageRoute(
                      builder: (_) => ProfileCropScreen(
                        file: file,
                        personName: 'Anna Wymyślona',
                        initial: initial,
                      ),
                    ),
                  ),
                ),
                child: const Text('otwórz'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otwórz'));
    await _settle(tester);
    return popped;
  }

  Finder gotowe() => find.widgetWithText(FilledButton, 'Gotowe');
  bool ready(WidgetTester tester) =>
      tester.widget<FilledButton>(gotowe()).onPressed != null;
  Rect area(WidgetTester tester) => tester.getRect(
    find.bySemanticsLabel('Kadr profilowego — zdjęcie w okręgu'),
  );

  Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await _settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(gotowe());
    await _settle(tester);
  }

  testWidgets(
    'K1, K2, K5 (v1.2): the title and the person, no hint and no zoom buttons; two double taps in the '
    'middle reach 128 px (360 → 180 → 128) and "Gotowe" pops that square around the middle (D5, D7\')',
    (tester) async {
      final List<PhotoCrop?> popped = await open(tester, photo);
      await _pumpUntil(tester, () => ready(tester));

      expect(find.text('Kadr profilowego'), findsOneWidget);
      expect(find.text('Anna Wymyślona'), findsOneWidget);
      expect(
        find.text('Przesuń zdjęcie palcem albo dotknij twarzy.'),
        findsNothing,
      );
      expect(find.byTooltip('Pomniejsz'), findsNothing);
      expect(find.byTooltip('Powiększ'), findsNothing);
      expect(find.byType(IconButton), findsOneWidget, reason: 'only back');

      await doubleTapAt(tester, area(tester).center);
      await doubleTapAt(tester, area(tester).center);
      await done(tester);
      expect(popped, [
        const PhotoCrop(left: 176, top: 116, width: 128, height: 128),
      ]);
    },
  );

  testWidgets(
    'a double tap at the largest zoom goes back to the whole: the circle over the shorter side again',
    (tester) async {
      final List<PhotoCrop?> popped = await open(tester, photo);
      await _pumpUntil(tester, () => ready(tester));
      for (int i = 0; i < 3; i++) {
        await doubleTapAt(tester, area(tester).center);
      }
      await done(tester);
      expect(popped, [
        const PhotoCrop(left: 60, top: 0, width: 360, height: 360),
      ]);
    },
  );

  testWidgets(
    'a double tap right of the middle grows the photo there: the point goes to the middle',
    (tester) async {
      final List<PhotoCrop?> popped = await open(tester, photo);
      await _pumpUntil(tester, () => ready(tester));
      await doubleTapAt(tester, area(tester).center + const Offset(60, 0));
      await done(tester);
      final PhotoCrop crop = popped.single!;
      expect(crop.width, 180);
      // From the middle a double tap in the middle would give left 150; right of it, more.
      expect(crop.left, greaterThan(150));
      expect(crop.top, 90);
    },
  );

  testWidgets(
    'a tap brings the point to the middle (after the double-tap timeout): zoomed in, a tap right of '
    'the middle moves the square right',
    (tester) async {
      final List<PhotoCrop?> popped = await open(tester, photo);
      await _pumpUntil(tester, () => ready(tester));
      await doubleTapAt(tester, area(tester).center);
      await tester.tapAt(area(tester).center + const Offset(60, 0));
      await _settle(tester);
      await done(tester);
      final PhotoCrop crop = popped.single!;
      expect(crop.width, 180);
      expect(crop.left, greaterThan(150));
      expect(crop.top, 90);
    },
  );

  testWidgets(
    'a tap during the glide of a double tap keeps the whole step (ui review): the size stays 180 px',
    (tester) async {
      final List<PhotoCrop?> popped = await open(tester, photo);
      await _pumpUntil(tester, () => ready(tester));
      await tester.tapAt(area(tester).center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(area(tester).center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(area(tester).center);
      await _settle(tester);
      await done(tester);
      expect(popped.single!.width, 180);
    },
  );

  testWidgets(
    'the link\'s own crop: the screen opens on it and "Gotowe" untouched pops it back',
    (tester) async {
      const PhotoCrop saved = PhotoCrop(
        left: 260,
        top: 60,
        width: 160,
        height: 160,
      );
      final List<PhotoCrop?> popped = await open(tester, photo, initial: saved);
      await _pumpUntil(tester, () => ready(tester));
      await done(tester);
      expect(popped, [saved]);
    },
  );

  testWidgets('D9 — back pops nothing, without a window', (tester) async {
    final List<PhotoCrop?> popped = await open(tester, photo);
    await _pumpUntil(tester, () => ready(tester));
    await doubleTapAt(tester, area(tester).center);
    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ProfileCropScreen), findsNothing);
    expect(popped, [null]);
  });

  testWidgets(
    'an unreadable file: "Nie udało się otworzyć zdjęcia.", "Gotowe" inactive',
    (tester) async {
      await open(tester, File('${tmp.path}/nie-ma.jpg'));
      await _pumpUntil(
        tester,
        () =>
            find.text('Nie udało się otworzyć zdjęcia.').evaluate().isNotEmpty,
      );
      expect(ready(tester), isFalse);
    },
  );

  testWidgets(
    'a file whose header reads but whose picture does not decode: "błąd odczytu", "Gotowe" inactive '
    '(ui review)',
    (tester) async {
      final List<int> whole = photo.readAsBytesSync();
      final File cut = File('${tmp.path}/uciety.png')
        ..writeAsBytesSync(whole.sublist(0, 60));
      await open(tester, cut);
      await _pumpUntil(
        tester,
        () =>
            find.text('Nie udało się otworzyć zdjęcia.').evaluate().isNotEmpty,
      );
      expect(ready(tester), isFalse);
    },
  );
}
