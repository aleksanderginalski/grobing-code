import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import 'data_state.dart';
import 'database.dart';

// Photos as rows of `media` and files under `DataLocation.mediaDir` (ISSUE-016; 05_DESIGN/zdjecie.md).
// The order of the steps keeps every backup restorable (D3): a file is written before its row, a delete
// removes only the row, and a file without a row goes only in [sweepOrphanMedia], under the data lock
// the backup holds. Writes go through drift's own API, so they ask for a background backup (ISSUE-010).

/// A new, unique path for a grave's photo, relative to the media directory. Built from the grave's id,
/// the time and a random part — never from what the photo shows.
String newGravePhotoPath(int graveId, {DateTime? now, Random? random}) =>
    'groby/$graveId/${_uniqueName(now, random)}.jpg';

/// A new, unique path for a person's photo (ISSUE-017). Not under a person: one photo may be on several
/// people (05_DESIGN/zdjecie.md, D). Never from what the photo shows.
String newPersonPhotoPath({DateTime? now, Random? random}) =>
    'zdjecia/${_uniqueName(now, random)}.jpg';

/// The time and a random part: `20261007-153012-1a2b3c4d`.
String _uniqueName(DateTime? now, Random? random) {
  final DateTime t = (now ?? DateTime.now()).toUtc();
  final String stamp = [
    t.year.toString().padLeft(4, '0'),
    t.month.toString().padLeft(2, '0'),
    t.day.toString().padLeft(2, '0'),
    '-',
    t.hour.toString().padLeft(2, '0'),
    t.minute.toString().padLeft(2, '0'),
    t.second.toString().padLeft(2, '0'),
  ].join();
  final Random r = random ?? Random.secure();
  final String suffix = List<String>.generate(
    8,
    (_) => r.nextInt(16).toRadixString(16),
  ).join();
  return '$stamp-$suffix';
}

/// The grave's photo (path relative to the media directory), or null. A grave has at most one
/// (05_DESIGN/grob.md D9); older data with several rows shows the first — the lowest id, the same
/// "first value" rule as ADR-006 D3.
Future<String?> gravePhotoPath(GrobingDatabase db, int graveId) async {
  final MediaFile? row =
      await (db.select(db.media)
            ..where((m) => m.graveId.equals(graveId))
            ..orderBy([(m) => OrderingTerm.asc(m.id)])
            ..limit(1))
          .getSingleOrNull();
  return row?.relativePath;
}

/// Makes [prepared] — a finished photo outside [mediaDir] (`PhotoPreparer`) — the grave's only photo.
/// Adding and changing are the same step. The file moves into [mediaDir] first, then one transaction
/// replaces the grave's rows; the files of replaced rows stay until the next sweep. Returns the new
/// path, relative to [mediaDir].
Future<String> setGravePhoto(
  GrobingDatabase db,
  Directory mediaDir,
  int graveId,
  File prepared,
) async {
  String relativePath = newGravePhotoPath(graveId);
  File target = File('${mediaDir.path}/$relativePath');
  while (await target.exists()) {
    relativePath = newGravePhotoPath(graveId);
    target = File('${mediaDir.path}/$relativePath');
  }
  await target.parent.create(recursive: true);
  await _move(prepared, target);
  try {
    await db.transaction(() async {
      await (db.delete(db.media)..where((m) => m.graveId.equals(graveId))).go();
      await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              relativePath: relativePath,
              graveId: Value(graveId),
            ),
          );
    });
  } on Object {
    // No row points at it, so nothing in a backup needs it: the file goes now, not at the next sweep.
    await _deleteQuietly(target);
    rethrow;
  }
  return relativePath;
}

/// Deletes the grave's photo (D1'). Only the rows go now; the file goes with the next sweep, so a backup
/// running at this moment still finds every file its snapshot names (D3).
Future<void> deleteGravePhoto(GrobingDatabase db, int graveId) =>
    (db.delete(db.media)..where((m) => m.graveId.equals(graveId))).go();

/// One photo in a person's list: its row and its file, relative to the media directory.
class PersonPhoto {
  const PersonPhoto({required this.mediaId, required this.relativePath});

  final int mediaId;
  final String relativePath;
}

/// The photos of [personId] in the order of their links: the first is the profile photo (GEDCOM 7:
/// "the first is the most-preferred value"; 05_DESIGN/zdjecia-osoby.md).
Future<List<PersonPhoto>> personPhotos(GrobingDatabase db, int personId) async {
  final List<TypedResult> rows =
      await (db.select(db.personMedia).join([
              innerJoin(
                db.media,
                db.media.id.equalsExp(db.personMedia.mediaId),
              ),
            ])
            ..where(db.personMedia.personId.equals(personId))
            ..orderBy([
              OrderingTerm.asc(db.personMedia.position),
              OrderingTerm.asc(db.personMedia.mediaId),
            ]))
          .get();
  return [
    for (final TypedResult r in rows)
      PersonPhoto(
        mediaId: r.readTable(db.media).id,
        relativePath: r.readTable(db.media).relativePath,
      ),
  ];
}

/// The ids of the people linked to the photo [mediaId], in the order the links were written.
Future<List<int>> photoPeopleIds(GrobingDatabase db, int mediaId) async => [
  for (final PersonMediaData l
      in await (db.select(db.personMedia)
            ..where((l) => l.mediaId.equals(mediaId))
            ..orderBy([(l) => OrderingTerm.asc(l.rowId)]))
          .get())
    l.personId,
];

/// Each of [personIds] that has a photo → the path of their profile photo (their first link).
Future<Map<int, String>> profilePhotoPaths(
  GrobingDatabase db,
  Iterable<int> personIds,
) async {
  final Map<int, String> paths = {};
  final List<int> ids = personIds.toList();
  if (ids.isEmpty) return paths;
  final List<TypedResult> rows =
      await (db.select(db.personMedia).join([
              innerJoin(
                db.media,
                db.media.id.equalsExp(db.personMedia.mediaId),
              ),
            ])
            ..where(db.personMedia.personId.isIn(ids))
            ..orderBy([
              OrderingTerm.asc(db.personMedia.position),
              OrderingTerm.asc(db.personMedia.mediaId),
            ]))
          .get();
  for (final TypedResult r in rows) {
    paths.putIfAbsent(
      r.readTable(db.personMedia).personId,
      () => r.readTable(db.media).relativePath,
    );
  }
  return paths;
}

/// A photo in an edit of a person's photos: one already saved, or one picked in this edit.
sealed class PhotoRef {
  const PhotoRef();
}

/// A photo that has a `media` row.
final class SavedPhoto extends PhotoRef {
  const SavedPhoto(this.mediaId);

  final int mediaId;

  @override
  bool operator ==(Object other) =>
      other is SavedPhoto && other.mediaId == mediaId;

  @override
  int get hashCode => mediaId.hashCode;
}

/// A photo picked in this edit: a prepared file outside the media directory (`PhotoPreparer`), not yet
/// a row. Each one is its own photo, so equality is identity.
final class NewPhoto extends PhotoRef {
  NewPhoto(this.prepared);

  final File prepared;
}

/// What an edit of one person's photos changes (05_DESIGN/zdjecia-osoby.md D1: it is written with the
/// person's "Zapisz", in the same transaction).
class PersonPhotoEdits {
  const PersonPhotoEdits({required this.photos, this.others = const {}});

  /// The person's photos after the edit, in their order: the first is the profile photo. A saved photo
  /// missing here is removed from this person only.
  final List<PhotoRef> photos;

  /// For each photo whose people changed: everyone else on it after the edit (05_DESIGN/zdjecie.md, D).
  /// A photo not here keeps its other people.
  final Map<PhotoRef, Set<int>> others;

  /// The photos of this edit that need a row: on this person or on someone else.
  List<NewPhoto> get newPhotos => [
    for (final PhotoRef p in {
      ...photos,
      for (final MapEntry<PhotoRef, Set<int>> e in others.entries)
        if (e.value.isNotEmpty) e.key,
    })
      if (p is NewPhoto) p,
  ];
}

/// Moves the prepared files of [photos] into [mediaDir] — before their rows, as every photo (ADR-008).
/// Each gets the time of now: a photo may wait in an open form for hours, a move keeps the file's old
/// time, and the sweep takes a file without a row that is older than an hour — this one has its row a
/// moment later (ISSUE-017, F4). Returns each photo's path, relative to [mediaDir]; on a failure the
/// files moved so far go back.
Future<Map<NewPhoto, String>> moveNewPersonPhotos(
  Directory mediaDir,
  Iterable<NewPhoto> photos, {
  DateTime Function()? clock,
}) async {
  final Map<NewPhoto, String> paths = {};
  try {
    for (final NewPhoto photo in photos) {
      String relativePath = newPersonPhotoPath();
      File target = File('${mediaDir.path}/$relativePath');
      while (await target.exists()) {
        relativePath = newPersonPhotoPath();
        target = File('${mediaDir.path}/$relativePath');
      }
      await target.parent.create(recursive: true);
      await _move(photo.prepared, target);
      paths[photo] = relativePath;
      await target.setLastModified((clock ?? DateTime.now)());
    }
  } on Object {
    await returnMovedPhotos(mediaDir, paths);
    rethrow;
  }
  return paths;
}

/// Puts the files [moveNewPersonPhotos] moved back where they were prepared, when the write they were
/// for did not happen: no row names them, so no backup needs them, and the form can try again. A file
/// that cannot go back is deleted.
Future<void> returnMovedPhotos(
  Directory mediaDir,
  Map<NewPhoto, String> paths,
) async {
  for (final MapEntry<NewPhoto, String> e in paths.entries) {
    final File moved = File('${mediaDir.path}/${e.value}');
    try {
      await _move(moved, e.key.prepared);
    } on FileSystemException {
      await _deleteQuietly(moved);
    }
  }
}

/// Writes [edits] for [personId]. Call it inside the transaction that writes the person, after
/// [moveNewPersonPhotos] gave [paths]:
/// - a row for each new photo;
/// - the person's links rewritten in the new order (positions 0…n−1);
/// - someone else added to a photo gets a link at the end of their own order, so their profile stays —
///   or, with no photos before, this one becomes it;
/// - a `media` row left with neither a grave nor a link goes; its file goes with the next sweep, so a
///   backup taken meanwhile still has every file its rows name (ADR-008, point 3).
Future<void> applyPersonPhotoEdits(
  GrobingDatabase db,
  int personId,
  PersonPhotoEdits edits,
  Map<NewPhoto, String> paths,
) async {
  final Map<NewPhoto, int> created = {};
  Future<int> idOf(PhotoRef photo) async => switch (photo) {
    SavedPhoto(:final int mediaId) => mediaId,
    final NewPhoto n =>
      created[n] ??= await db
          .into(db.media)
          .insert(MediaCompanion.insert(relativePath: paths[n]!)),
  };

  final List<int> ordered = [];
  for (final PhotoRef photo in edits.photos) {
    final int id = await idOf(photo);
    if (!ordered.contains(id)) ordered.add(id);
  }
  await (db.delete(
    db.personMedia,
  )..where((l) => l.personId.equals(personId))).go();
  for (final (int i, int id) in ordered.indexed) {
    await db
        .into(db.personMedia)
        .insert(
          PersonMediaCompanion.insert(
            personId: personId,
            mediaId: id,
            position: i,
          ),
        );
  }

  for (final MapEntry<PhotoRef, Set<int>> entry in edits.others.entries) {
    if (entry.key is NewPhoto && entry.value.isEmpty) continue;
    final int id = await idOf(entry.key);
    final Set<int> wanted = {...entry.value}..remove(personId);
    final Set<int> current = {...await photoPeopleIds(db, id)}
      ..remove(personId);
    for (final int other in current.difference(wanted)) {
      await (db.delete(
        db.personMedia,
      )..where((l) => l.personId.equals(other) & l.mediaId.equals(id))).go();
    }
    for (final int other in wanted.difference(current)) {
      final int last =
          (await db
                  .customSelect(
                    'SELECT coalesce(max(position), -1) AS p '
                    'FROM person_media WHERE person_id = ?',
                    variables: [Variable.withInt(other)],
                    readsFrom: {db.personMedia},
                  )
                  .getSingle())
              .read<int>('p');
      await db
          .into(db.personMedia)
          .insert(
            PersonMediaCompanion.insert(
              personId: other,
              mediaId: id,
              position: last + 1,
            ),
          );
    }
  }

  await (db.delete(db.media)..where(
        (m) =>
            m.graveId.isNull() &
            m.id.isNotInQuery(
              db.selectOnly(db.personMedia)
                ..addColumns([db.personMedia.mediaId]),
            ),
      ))
      .go();
}

/// Deletes the files under [mediaDir] that no `media` row names and that were last modified more than
/// [olderThan] ago, then the directories left empty (D3). The age spares a photo being added right now —
/// its file is written before its row. Run only under the data lock, so no backup is reading the
/// directory meanwhile. Returns how many files went.
Future<int> sweepOrphanMedia(
  GrobingDatabase db,
  Directory mediaDir, {
  Duration olderThan = const Duration(hours: 1),
  DateTime? now,
}) async {
  if (!await mediaDir.exists()) return 0;
  final Set<String> named = {
    for (final MediaFile m in await db.select(db.media).get()) m.relativePath,
  };
  final DateTime limit = (now ?? DateTime.now()).subtract(olderThan);
  int removed = 0;
  for (final File file in listMediaFiles(mediaDir)) {
    final String relative = mediaRelativePath(mediaDir, file);
    if (named.contains(relative)) continue;
    final DateTime modified = (await file.stat()).modified;
    if (modified.isAfter(limit)) continue;
    if (await _deleteQuietly(file)) removed++;
  }
  await _deleteEmptyDirectories(mediaDir);
  return removed;
}

/// Rename within the app's storage; copy and delete when the two are on different file systems.
Future<void> _move(File from, File to) async {
  try {
    await from.rename(to.path);
  } on FileSystemException {
    await from.copy(to.path);
    await _deleteQuietly(from);
  }
}

Future<bool> _deleteQuietly(File file) async {
  try {
    await file.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Removes empty directories below [root], deepest first; [root] itself stays.
Future<void> _deleteEmptyDirectories(Directory root) async {
  final List<Directory> dirs =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<Directory>()
          .toList()
        ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final Directory d in dirs) {
    try {
      if (d.listSync(followLinks: false).isEmpty) await d.delete();
    } on FileSystemException {
      // Gone already, or not empty after all: the next sweep tries again.
    }
  }
}
