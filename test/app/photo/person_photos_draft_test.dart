import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/photo/person_photos_draft.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';

import '../../support/photo_fakes.dart';

// ISSUE-017 — a person's photos while the form is open (05_DESIGN/zdjecia-osoby.md D1): nothing is
// written until "Zapisz", "Odrzuć" drops the prepared files, a photo that cannot be read is counted and
// the others stay, the profile and the people on a photo change only the draft. ISSUE-018: the crop of a
// link — loaded with the saved photos, set with the profile or alone, a change only of the draft, no
// change when put back, gone with a removed photo. Pictures drawn in code, made-up people only
// (family-data.md).

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late _Fakes fakes;
  late Photos photos;
  late int jan;
  late int anna;
  late int grave;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_draft_test');
    db = GrobingDatabase(NativeDatabase.memory());
    fakes = _Fakes();
    photos = fakePhotos(tmp, picker: fakes.picker, preparer: fakes.preparer);
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
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  List<File> work() => photos.workDir.existsSync()
      ? photos.workDir.listSync().whereType<File>().toList()
      : const [];

  File picked(int n) => pickedPhoto(Directory('${tmp.path}/cache'), n);

  test(
    '"Odrzuć" — the draft drops every prepared file it made; nothing was written',
    () async {
      final PersonPhotosDraft draft = PersonPhotosDraft(
        database: db,
        photos: photos,
      );
      await draft.addPicked([picked(1), picked(2)]);
      expect(draft.count, 2);
      expect(work(), hasLength(2));
      expect(fakes.picker.discarded, hasLength(2), reason: "picker's copies");

      draft.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(work(), isEmpty);
      expect(await db.select(db.media).get(), isEmpty);
    },
  );

  test(
    'a photo that cannot be read is counted ("1 z 2"), the other one stays',
    () async {
      final PersonPhotosDraft draft = PersonPhotosDraft(
        database: db,
        photos: photos,
      );
      fakes.preparer.failOn = 2;
      await draft.addPicked([picked(1), picked(2)]);
      expect(draft.count, 1);
      expect(draft.failure, (failed: 1, of: 2));
      expect(draft.preparing, 0);
      draft.dispose();
    },
  );

  test(
    'a correction starts from the saved photos without changes; the profile and the people on a photo '
    'change only the draft, and putting them back means no change',
    () async {
      final PersonPhotosDraft first = PersonPhotosDraft(
        database: db,
        photos: photos,
        personId: jan,
      );
      await first.addPicked([picked(1), picked(2)]);
      await photos.writeWithPersonPhotos<void>(
        db,
        first.edits(),
        (also) => updatePersonEntry(
          db,
          jan,
          const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
          alsoWrite: also,
        ),
      );
      first.dispose();

      final PersonPhotosDraft draft = PersonPhotosDraft(
        database: db,
        photos: photos,
        personId: jan,
        graveId: grave,
      );
      await draft.load();
      expect(draft.count, 2);
      expect(draft.hasChanges, isFalse);
      expect(draft.edits(), isNull);

      final DraftPhoto second = draft.items[1];
      draft.setProfile(second);
      expect(draft.profile, second);
      expect(draft.hasChanges, isTrue);
      draft.setProfile(draft.items[1]);
      expect(draft.hasChanges, isFalse, reason: 'the old order again');

      await draft.setOthers(second, {anna});
      expect(await draft.othersOf(second), {anna});
      expect(draft.hasChanges, isTrue);
      await draft.setOthers(second, {});
      expect(draft.hasChanges, isFalse, reason: 'the saved people again');

      final ({List<PersonChoice> all, List<int> inGrave}) choices = await draft
          .choices();
      expect(choices.inGrave, [jan, anna]);

      // Nothing of this reached the database.
      expect(
        (await personPhotos(db, jan)).map((p) => p.mediaId),
        draft.items.map((p) => (p.ref as SavedPhoto).mediaId),
      );
      expect(await photoPeopleIds(db, (second.ref as SavedPhoto).mediaId), [
        jan,
      ]);
      draft.dispose();
    },
  );

  test(
    'ISSUE-018 — the crop: loaded with the saved photos; set with the profile ("Ustaw jako profilowe" → '
    '"Gotowe") or alone ("Popraw kadr"); the same crop again is no change; a removed photo takes its crop; '
    '"Zapisz" carries only crops set in this edit',
    () async {
      const PhotoCrop face = PhotoCrop(
        left: 10,
        top: 20,
        width: 200,
        height: 200,
      );
      const PhotoCrop other = PhotoCrop(
        left: 50,
        top: 0,
        width: 150,
        height: 150,
      );
      final PersonPhotosDraft first = PersonPhotosDraft(
        database: db,
        photos: photos,
        personId: jan,
      );
      await first.addPicked([picked(1), picked(2)]);
      first.setCrop(first.items.first, face);
      await photos.writeWithPersonPhotos<void>(
        db,
        first.edits(),
        (also) => updatePersonEntry(
          db,
          jan,
          const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
          alsoWrite: also,
        ),
      );
      first.dispose();

      final PersonPhotosDraft draft = PersonPhotosDraft(
        database: db,
        photos: photos,
        personId: jan,
      );
      await draft.load();
      final DraftPhoto profile = draft.items[0];
      final DraftPhoto second = draft.items[1];
      expect(draft.cropOf(profile), face);
      expect(draft.cropOf(second), isNull);
      expect(draft.hasChanges, isFalse);

      draft.setCrop(profile, face);
      expect(draft.hasChanges, isFalse, reason: 'the saved crop again');

      draft.setProfile(second, crop: other);
      expect(draft.profile, second);
      expect(draft.cropOf(second), other);
      expect(draft.cropOf(profile), face, reason: 'its own crop stays');
      expect(draft.edits()!.crops, {second.ref: other});

      draft.remove(second);
      expect(draft.cropOf(second), isNull);
      expect(draft.edits()!.crops, isEmpty);
      expect(draft.hasChanges, isTrue, reason: 'a photo removed');

      // Nothing of this reached the database.
      expect((await personPhotos(db, jan)).map((p) => p.crop), [face, null]);
      draft.dispose();
    },
  );
}

/// The picker and a preparer that fails on its n-th call (a picture the phone cannot decode).
class _Fakes {
  final FakePhotoPicker picker = FakePhotoPicker();
  final _CountingPreparer preparer = _CountingPreparer();
}

class _CountingPreparer extends FakePhotoPreparer {
  int? failOn;

  @override
  Future<void> prepare(File source, File target) {
    if (calls + 1 == failOn) {
      calls++;
      throw const FileSystemException('cannot decode');
    }
    return super.prepare(source, target);
  }
}
