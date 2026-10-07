import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

import '../support/photo_fakes.dart';

// ISSUE-017 — people's photos in the data layer (lib/data/photos.dart, schema v4), happy path per AC:
// several photos and one profile · one photo on several people, one file · removing from one person
// keeps it for the others · D2: a person ticked later, from another grave · written with the person, in
// one transaction (D3) · F4: a photo that waited in the form is not swept · a failed write gives the
// files back. Pictures drawn in code, made-up people only (family-data.md).

void main() {
  late Directory tmp;
  late Directory mediaDir;
  late GrobingDatabase db;
  late int grave;
  late int otherGrave;
  late int anna;
  late int jan;
  late int jozef;

  const PersonEntry annaEntry = PersonEntry(
    givenNames: 'Anna',
    surname: 'Wymyślona',
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_person_photos_test');
    mediaDir = Directory('${tmp.path}/media');
    db = GrobingDatabase(NativeDatabase.memory());
    final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: annaEntry,
    );
    anna = (await db.select(db.persons).getSingle()).id;
    jan = await addPersonToGrave(
      db,
      graveId: grave,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
    otherGrave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Józef', surname: 'Zmyślony'),
    );
    jozef = (await loadGrave(db, otherGrave))!.people.single.id;
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// A photo prepared in the form and waiting for "Zapisz" — three hours already, as at grandmother's.
  NewPhoto waiting(int n) {
    final File f = File('${tmp.path}/photo-work/gotowe-$n.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(fictionalPeoplePng(n, heads: 1), flush: true);
    f.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 3)));
    return NewPhoto(f);
  }

  /// "Zapisz" of [personId]'s correction with [edits], as the form does it.
  Future<void> save(int personId, PersonPhotoEdits edits, {PersonEntry? as}) =>
      fakePhotos(tmp).writeWithPersonPhotos<void>(
        db,
        edits,
        (alsoWrite) => updatePersonEntry(
          db,
          personId,
          as ?? annaEntry,
          alsoWrite: alsoWrite,
        ),
      );

  Future<List<int>> photosOf(int personId) async => [
    for (final PersonPhoto p in await personPhotos(db, personId)) p.mediaId,
  ];

  List<File> mediaFiles() => mediaDir.existsSync()
      ? mediaDir.listSync(recursive: true).whereType<File>().toList()
      : const [];

  test(
    'US-005 AC-1, AC-2 + several photos, one profile — two new photos are saved with the person: files '
    'in media/zdjecia/, two links in order, the first is the profile in the grave view',
    () async {
      final NewPhoto a = waiting(1);
      final NewPhoto b = waiting(2);
      await save(anna, PersonPhotoEdits(photos: [a, b]));

      final List<PersonPhoto> photos = await personPhotos(db, anna);
      expect(photos, hasLength(2));
      expect(
        photos.map((p) => p.relativePath),
        everyElement(startsWith('zdjecia/')),
      );
      for (final PersonPhoto p in photos) {
        expect(File('${mediaDir.path}/${p.relativePath}').existsSync(), isTrue);
      }
      // AC-2: the app's own copy — the prepared files moved in.
      expect(a.prepared.existsSync(), isFalse);
      expect(b.prepared.existsSync(), isFalse);
      final BuriedPerson inGrave = (await loadGrave(
        db,
        grave,
      ))!.people.firstWhere((p) => p.id == anna);
      expect(inGrave.profilePhotoPath, photos.first.relativePath);
    },
  );

  test(
    '"Ustaw jako profilowe" — the photo moves to the first place of this person only',
    () async {
      await save(anna, PersonPhotoEdits(photos: [waiting(1), waiting(2)]));
      final List<int> before = await photosOf(anna);

      await save(
        anna,
        PersonPhotoEdits(
          photos: [SavedPhoto(before[1]), SavedPhoto(before[0])],
        ),
      );

      expect(await photosOf(anna), [before[1], before[0]]);
      final Map<int, String> profiles = await profilePhotoPaths(db, [anna]);
      expect(profiles[anna], (await personPhotos(db, anna)).first.relativePath);
    },
  );

  test(
    'one photo on several people, one file — ticking Jan writes his link; he had no photos, so it '
    'is his profile; one media row, one file',
    () async {
      final NewPhoto wedding = waiting(1);
      await save(
        anna,
        PersonPhotoEdits(
          photos: [wedding],
          others: {
            wedding: {jan},
          },
        ),
      );

      final List<int> annas = await photosOf(anna);
      expect(await photosOf(jan), annas);
      expect(await db.select(db.media).get(), hasLength(1));
      expect(mediaFiles(), hasLength(1));
      expect(await photoPeopleIds(db, annas.single), [anna, jan]);
      final Map<int, String> profiles = await profilePhotoPaths(db, [
        anna,
        jan,
      ]);
      expect(profiles[jan], profiles[anna]);
    },
  );

  test(
    'a photo removed from one person stays with the others; removed from the last one, its row goes '
    'and its file only with the sweep an hour later (ADR-008)',
    () async {
      final NewPhoto wedding = waiting(1);
      await save(
        anna,
        PersonPhotoEdits(
          photos: [wedding],
          others: {
            wedding: {jan},
          },
        ),
      );
      final int shared = (await photosOf(anna)).single;

      await save(anna, const PersonPhotoEdits(photos: []));
      expect(await photosOf(anna), isEmpty);
      expect(await photosOf(jan), [shared]);
      expect(await db.select(db.media).get(), hasLength(1));

      await save(
        jan,
        const PersonPhotoEdits(photos: []),
        as: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
      );
      expect(await db.select(db.media).get(), isEmpty);
      expect(mediaFiles(), hasLength(1), reason: 'a backup may still name it');
      expect(await sweepOrphanMedia(db, mediaDir), 0, reason: 'fresh');
      expect(
        await sweepOrphanMedia(
          db,
          mediaDir,
          now: DateTime.now().add(const Duration(hours: 2)),
        ),
        1,
      );
      expect(mediaFiles(), isEmpty);
    },
  );

  test(
    'D2 — a person ticked later, from another grave: the link goes to the end of their order, so a '
    'profile they already have stays',
    () async {
      await save(
        jozef,
        PersonPhotoEdits(photos: [waiting(1)]),
        as: const PersonEntry(givenNames: 'Józef', surname: 'Zmyślony'),
      );
      final int jozefsProfile = (await photosOf(jozef)).single;
      await save(anna, PersonPhotoEdits(photos: [waiting(2)]));
      final int group = (await photosOf(anna)).single;

      // Later: in Anna's form, Józef is ticked on her photo.
      await save(
        anna,
        PersonPhotoEdits(
          photos: [SavedPhoto(group)],
          others: {
            SavedPhoto(group): {jozef},
          },
        ),
      );

      expect(await photosOf(jozef), [jozefsProfile, group]);
      expect(await photoPeopleIds(db, group), containsAll([anna, jozef]));
      final List<PersonChoice> all = (await loadPersonChoices(
        db,
        graveId: grave,
      )).all;
      expect(all.map((c) => c.id), containsAll([anna, jan, jozef]));
    },
  );

  test(
    'loadPersonChoices — everyone, and who lies in this grave in the order entered; the place of a '
    'person from another grave',
    () async {
      final ({List<PersonChoice> all, List<int> inGrave}) choices =
          await loadPersonChoices(db, graveId: grave);
      expect(choices.inGrave, [anna, jan]);
      expect(choices.all, hasLength(3));
      final PersonChoice j = choices.all.firstWhere((c) => c.id == jozef);
      expect(j.cemeteryName, 'Cmentarz Wymyślony');
      expect(j.graveName, isNull);
    },
  );

  test(
    'F4 — a photo that waited in the form for hours gets the time of now when it moves in: a sweep '
    'between the move and the row keeps it',
    () async {
      final NewPhoto old = waiting(1);
      final Map<NewPhoto, String> paths = await moveNewPersonPhotos(mediaDir, [
        old,
      ]);
      final File moved = File('${mediaDir.path}/${paths[old]}');

      // The moment between the move and the transaction — the backup's sweep runs here.
      expect(await sweepOrphanMedia(db, mediaDir), 0);
      expect(moved.existsSync(), isTrue);
      expect(
        DateTime.now().difference(moved.lastModifiedSync()).inMinutes,
        lessThan(1),
      );
    },
  );

  test(
    'a failed write keeps nothing and gives the files back: no row, no link, the prepared file where '
    'it was — "Zapisz" can be tried again',
    () async {
      final NewPhoto photo = waiting(1);
      final List<int> bytes = photo.prepared.readAsBytesSync();
      final Photos photos = fakePhotos(tmp);

      await expectLater(
        photos.writeWithPersonPhotos<void>(
          db,
          PersonPhotoEdits(photos: [photo]),
          (alsoWrite) => updatePersonEntry(
            db,
            anna,
            annaEntry,
            alsoWrite: (id) async {
              await alsoWrite!(id);
              throw StateError('the write fails after the photo rows');
            },
          ),
        ),
        throwsStateError,
      );

      expect(await db.select(db.media).get(), isEmpty);
      expect(await db.select(db.personMedia).get(), isEmpty);
      expect(mediaFiles(), isEmpty);
      expect(photo.prepared.readAsBytesSync(), bytes);

      await save(anna, PersonPhotoEdits(photos: [photo]));
      expect(await photosOf(anna), hasLength(1));
    },
  );

  test(
    'a new photo removed from this person but ticked on another is still saved for the other (window '
    'C1\': "Zdjęcie zostaje u: …")',
    () async {
      final NewPhoto photo = waiting(1);
      await save(
        anna,
        PersonPhotoEdits(
          photos: const [],
          others: {
            photo: {jan},
          },
        ),
      );
      expect(await photosOf(anna), isEmpty);
      expect(await photosOf(jan), hasLength(1));
    },
  );

  test('every person photo write asks for a backup (ISSUE-010)', () async {
    final List<Set<String>> updates = [];
    final sub = db.tableUpdates().listen(
      (u) => updates.add({for (final t in u) t.table}),
    );
    await save(anna, PersonPhotoEdits(photos: [waiting(1)]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(updates.expand((u) => u), containsAll(['media', 'person_media']));
  });
}
