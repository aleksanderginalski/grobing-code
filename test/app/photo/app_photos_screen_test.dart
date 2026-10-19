import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/photo/app_photos_screen.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/data/database.dart' show DateQualifier;
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';

import '../../support/a11y.dart';

// ISSUE-048 AC-5 — "Zdjęcia w aplikacji" (05_DESIGN/zdjecia-w-aplikacji.md) with hundreds of photos: the
// filter by a person's name leaves only their groups (D1); a group photo stands under every person on it
// and a tick belongs to the photo — framed in each group, counted once (D2, D5); ticks stay through the
// filter; the grid is built lazily; a photo whose file is missing cannot be ticked (*States*); "Dodaj N
// zdjęć" pops the photos in the order ticked, back pops nothing. Made-up people only (family-data.md):
// surnames from the invented stems.

const List<String> _stems = ['Wymyśl', 'Zmyśl', 'Testow', 'Przykład'];

/// 60 invented people, 5 photos each — 300 — and one group photo (id 9000) shared by the first two of the
/// "Zmyśl" family; photo 9001 has no file.
AppPhotos _hundreds() {
  final List<AppPhotoGroup> groups = [];
  for (int i = 0; i < 60; i++) {
    final String stem = _stems[i % 4];
    final PersonChoice person = PersonChoice(
      id: i + 1,
      givenNames: 'Osoba${i + 1}',
      surname: '${stem}ska',
      birth: QualifiedDate(DateQualifier.exact, PartialDate(1900 + i)),
    );
    final List<PersonPhoto> photos = [
      for (int k = 0; k < 5; k++)
        PersonPhoto(mediaId: i * 10 + k + 1, relativePath: 'p/${i}_$k.png'),
    ];
    if (i == 1 || i == 5) {
      photos[0] = const PersonPhoto(mediaId: 9000, relativePath: 'p/grupa.png');
    }
    if (i == 9) {
      photos[4] = const PersonPhoto(mediaId: 9001, relativePath: 'p/brak.png');
    }
    groups.add(
      AppPhotoGroup(person: person, profile: photos.first, photos: photos),
    );
  }
  return AppPhotos(nearest: const [], others: groups, missing: {9001});
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('grobing_app_photos'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The screen pushed over a host that keeps what it pops.
  Future<List<List<PersonPhoto>?>> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final List<List<PersonPhoto>?> popped = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: GrobingTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await Navigator.of(context).push<List<PersonPhoto>>(
                MaterialPageRoute(
                  builder: (_) => AppPhotosScreen(
                    photos: _hundreds(),
                    fileOf: (p) => File('${tmp.path}/$p'),
                    personName: 'Jan Wymyślony',
                    firstName: 'Jan',
                  ),
                ),
              ),
            ),
            child: const Text('otwórz'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets(
    'AC-5 — 300 photos: built lazily; "zmysl" leaves only the "Zmyśl" groups; the group photo framed in both of '
    'its groups and counted once; the tick stays through the filter; "Dodaj 2 zdjęcia" pops them in order',
    (tester) async {
      final List<List<PersonPhoto>?> popped = await pumpScreen(tester);
      expect(find.text('dla: Jan Wymyślony'), findsOneWidget);
      expect(find.text('Inne osoby'), findsOneWidget);
      expect(find.text('Najbliżsi'), findsNothing);
      expect(
        find.byType(Image).evaluate().length,
        lessThan(60),
        reason: 'only what is on screen is built, not 300 photos',
      );

      await tester.enterText(find.byType(TextField), 'zmysl');
      await tester.pumpAndSettle();
      expect(find.textContaining('Wymyślska'), findsNothing);
      expect(find.textContaining('Testowska'), findsNothing);
      expect(find.text('Osoba2 Zmyślska'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel('Osoba2 Zmyślska, zdjęcie 1 z 5 — zaznacz'),
      );
      await tester.pumpAndSettle();
      // The same photo under Osoba6 — framed there too.
      await tester.scrollUntilVisible(
        find.text('Osoba6 Zmyślska'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          'Osoba6 Zmyślska, zdjęcie 1 z 5, zaznaczone — odznacz',
        ),
        findsOneWidget,
      );
      expect(find.text('Dodaj 1 zdjęcie'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel('Osoba6 Zmyślska, zdjęcie 3 z 5 — zaznacz'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'osoba1 wymysl');
      await tester.pumpAndSettle();
      // The list keeps its offset from before the filter; back to its top.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.text('Osoba1 Wymyślska'), findsOneWidget);
      expect(
        find.text('Dodaj 2 zdjęcia'),
        findsOneWidget,
        reason: 'ticks kept',
      );

      await tester.tap(find.text('Dodaj 2 zdjęcia'));
      await tester.pumpAndSettle();
      expect(popped.single!.map((p) => p.mediaId), [9000, 53]);
    },
  );

  testWidgets(
    'a photo whose file is missing is inactive; nothing ticked — "Dodaj" is off; back pops nothing; every '
    'button has a tap action and a 48 dp target',
    (tester) async {
      final List<List<PersonPhoto>?> popped = await pumpScreen(tester);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      // The filter cuts the ending of a word of 5 letters or more (matchesQuery, as "Kto jest na
      // zdjęciu?"): "zmysl" → "zmy", the "Zmyśl" groups; Osoba10 is the third of them.
      await tester.enterText(find.byType(TextField), 'zmysl');
      await tester.pumpAndSettle();
      final Finder missing = find.bySemanticsLabel(
        'Osoba10 Zmyślska, zdjęcie 5 z 5, nie da się otworzyć zdjęcia',
      );
      await tester.scrollUntilVisible(
        missing,
        300,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(missing),
        isSemantics(isEnabled: false, hasEnabledState: true),
      );
      await tester.tap(missing, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Dodaj'), findsOneWidget);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectEveryButtonTappable(tester);
      semantics.dispose();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(popped, [null]);
    },
  );

  testWidgets(
    'nothing matches — "Nie ma osoby ze zdjęciami pasującej do „…”."',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'nikt');
      await tester.pumpAndSettle();
      expect(
        find.text('Nie ma osoby ze zdjęciami pasującej do „nikt”.'),
        findsOneWidget,
      );
      expect(find.text('Inne osoby'), findsNothing);
    },
  );
}
