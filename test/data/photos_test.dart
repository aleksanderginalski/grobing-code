import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show OrderingTerm, TableUpdateQuery, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

// ISSUE-016 — the photos' data path (lib/data/photos.dart), happy path per AC: US-005 AC-1 a grave gets
// its photo · AC-2 the app keeps its own copy · one photo per grave, changed and deleted (D1') · the
// order of steps that keeps a backup restorable (D3): the file before the row, a delete takes only the
// row, the sweep takes files without a row once they are an hour old · every write asks for a backup.
// Pictures drawn in code, made-up people only (family-data.md).

void main() {
  late Directory tmp;
  late Directory mediaDir;
  late GrobingDatabase db;
  late int grave;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_photos_test');
    mediaDir = Directory('${tmp.path}/media');
    db = GrobingDatabase(NativeDatabase.memory());
    final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// A finished photo outside the media directory, as `PhotoPreparer` leaves it.
  File prepared(int n) => File('${tmp.path}/photo-work/gotowe-$n.jpg')
    ..createSync(recursive: true)
    ..writeAsBytesSync(fictionalGravestonePng(n), flush: true);

  Future<List<MediaFile>> rows() =>
      (db.select(db.media)..orderBy([(m) => OrderingTerm.asc(m.id)])).get();

  test(
    'US-005 AC-1, AC-2 — the grave gets its photo: the file moves into the media directory under '
    'groby/<id>/, one row names it, and the grave view shows it',
    () async {
      final File source = prepared(1);
      final List<int> bytes = source.readAsBytesSync();

      final String path = await setGravePhoto(db, mediaDir, grave, source);

      expect(path, startsWith('groby/$grave/'));
      expect(path, endsWith('.jpg'));
      final File kept = File('${mediaDir.path}/$path');
      expect(kept.readAsBytesSync(), bytes);
      // AC-2: the app's own copy — the file it was given is gone (moved), the kept one stays.
      expect(source.existsSync(), isFalse);
      final List<MediaFile> all = await rows();
      expect(all, hasLength(1));
      expect(all.single.graveId, grave);
      expect(all.single.personId, isNull);
      expect(all.single.relativePath, path);
      expect(await gravePhotoPath(db, grave), path);
      expect((await loadGrave(db, grave))!.photoPath, path);
    },
  );

  test(
    'D1\' — changing the photo leaves one row with the new file; the old file stays until the sweep',
    () async {
      final String first = await setGravePhoto(
        db,
        mediaDir,
        grave,
        prepared(1),
      );
      final String second = await setGravePhoto(
        db,
        mediaDir,
        grave,
        prepared(2),
      );

      expect(second, isNot(first));
      expect((await rows()).map((m) => m.relativePath), [second]);
      expect(File('${mediaDir.path}/$first').existsSync(), isTrue);
      expect(File('${mediaDir.path}/$second').existsSync(), isTrue);
    },
  );

  test(
    'D1\', D3 — deleting the photo removes the row only: the grave has no photo, the file waits for '
    'the sweep',
    () async {
      final String path = await setGravePhoto(db, mediaDir, grave, prepared(1));

      await deleteGravePhoto(db, grave);

      expect(await rows(), isEmpty);
      expect(await gravePhotoPath(db, grave), isNull);
      expect((await loadGrave(db, grave))!.photoPath, isNull);
      expect(File('${mediaDir.path}/$path').existsSync(), isTrue);
    },
  );

  test(
    'D3 — the sweep removes files without a row that are older than an hour, keeps a fresh one '
    '(being added right now) and every named one, and drops the emptied directories',
    () async {
      final String named = await setGravePhoto(
        db,
        mediaDir,
        grave,
        prepared(1),
      );
      final File old = File('${mediaDir.path}/groby/99/stare.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3])
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 2)),
        );
      final File fresh = File('${mediaDir.path}/groby/98/swieze.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([4, 5, 6]);

      final int removed = await sweepOrphanMedia(db, mediaDir);

      expect(removed, 1);
      expect(old.existsSync(), isFalse);
      expect(Directory('${mediaDir.path}/groby/99').existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(File('${mediaDir.path}/$named').existsSync(), isTrue);
      expect(mediaDir.existsSync(), isTrue);
    },
  );

  test('D3 — the sweep of a missing media directory does nothing', () async {
    expect(await sweepOrphanMedia(db, mediaDir), 0);
  });

  test(
    'older data with several rows for one grave shows the first one (the lowest id, ADR-006 D3)',
    () async {
      for (final String p in ['groby/x/pierwsze.jpg', 'groby/x/drugie.jpg']) {
        await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(relativePath: p, graveId: Value(grave)),
            );
      }

      expect(await gravePhotoPath(db, grave), 'groby/x/pierwsze.jpg');
    },
  );

  test(
    'the cemetery screen gets each grave\'s photo; a grave without one gets none',
    () async {
      final int cemetery = (await loadGrave(db, grave))!.cemeteryId;
      final int bare = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Ewa', surname: 'Testowa'),
      );
      final String path = await setGravePhoto(db, mediaDir, grave, prepared(1));

      final CemeteryGraves graves = (await loadCemeteryGraves(db, cemetery))!;

      expect(graves.graves.firstWhere((g) => g.id == grave).photoPath, path);
      expect(graves.graves.firstWhere((g) => g.id == bare).photoPath, isNull);
    },
  );

  test(
    'a new path is unique and says nothing about the picture: grave id, UTC time, random part',
    () {
      final String path = newGravePhotoPath(
        7,
        now: DateTime.utc(2026, 10, 7, 15, 4, 35),
        random: Random(1),
      );

      expect(
        path,
        matches(RegExp(r'^groby/7/20261007-150435-[0-9a-f]{8}\.jpg$')),
      );
      expect(
        newGravePhotoPath(7, now: DateTime.utc(2026, 10, 7, 15, 4, 35)),
        isNot(newGravePhotoPath(7, now: DateTime.utc(2026, 10, 7, 15, 4, 35))),
      );
    },
  );

  test(
    'adding, changing and deleting the photo notify the media table — what asks for a background '
    'backup (ISSUE-010)',
    () async {
      final List<int> updates = [];
      final sub = db
          .tableUpdates(TableUpdateQuery.onTable(db.media))
          .listen((_) => updates.add(1));

      await setGravePhoto(db, mediaDir, grave, prepared(1));
      await setGravePhoto(db, mediaDir, grave, prepared(2));
      await deleteGravePhoto(db, grave);
      await pumpEventQueue();
      await sub.cancel();

      expect(updates.length, greaterThanOrEqualTo(3));
    },
  );
}
