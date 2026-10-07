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
String newGravePhotoPath(int graveId, {DateTime? now, Random? random}) {
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
  return 'groby/$graveId/$stamp-$suffix.jpg';
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
