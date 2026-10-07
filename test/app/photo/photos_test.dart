import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/photo/photo_picker.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';

import '../../support/photo_fakes.dart';

// ISSUE-016 — `Photos`, between the screens and the data: a picked photo is prepared (D2'), kept (D3),
// and the picker's copy and the scratch file go either way. Pictures drawn in code, made-up people only.

void main() {
  late Directory tmp;
  late GrobingDatabase db;
  late int grave;
  late FakePhotoPicker picker;
  late FakePhotoPreparer preparer;
  late Photos photos;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_photos_app_test');
    db = GrobingDatabase(NativeDatabase.memory());
    final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
    picker = FakePhotoPicker();
    preparer = FakePhotoPreparer();
    photos = fakePhotos(tmp, picker: picker, preparer: preparer);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test(
    'US-005 AC-1, AC-2 — a picked photo becomes the grave\'s photo: prepared once, kept in the media '
    'directory, the picker\'s copy and the scratch file gone',
    () async {
      final File picked = pickedPhoto(Directory('${tmp.path}/cache'), 1);
      final List<int> bytes = picked.readAsBytesSync();

      await photos.setGravePhoto(db, grave, picked);

      expect(preparer.calls, 1);
      final String path = (await gravePhotoPath(db, grave))!;
      expect(photos.fileOf(path).readAsBytesSync(), bytes);
      expect(picker.discarded, [picked]);
      expect(picked.existsSync(), isFalse);
      expect(photos.workDir.listSync(), isEmpty);
    },
  );

  test(
    'a photo the phone cannot prepare is not kept: no row, nothing left in the work directory',
    () async {
      preparer.error = Exception('nie da się zdekodować');
      final File picked = pickedPhoto(Directory('${tmp.path}/cache'), 1);

      await expectLater(
        photos.setGravePhoto(db, grave, picked),
        throwsA(isA<Exception>()),
      );

      expect(await gravePhotoPath(db, grave), isNull);
      expect(photos.workDir.listSync(), isEmpty);
      expect(picker.discarded, [picked]);
    },
  );

  test('the picker is asked for the chosen source', () async {
    await photos.pick(PhotoSource.camera);
    await photos.pick(PhotoSource.gallery);

    expect(picker.asked, [PhotoSource.camera, PhotoSource.gallery]);
  });

  test('clearWork removes what an interrupted preparation left', () async {
    File('${photos.workDir.path}/przerwane.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);

    await photos.clearWork();

    expect(photos.workDir.existsSync(), isFalse);
  });
}
