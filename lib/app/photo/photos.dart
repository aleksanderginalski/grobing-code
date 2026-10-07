import 'dart:io';
import 'dart:math';

import '../../data/database.dart';
import '../../data/photos.dart' as data;
import 'photo_picker.dart';
import 'photo_preparer.dart';

/// What the screens need for photos (ISSUE-016): where the kept photos live, the picker and the
/// preparer. One object, passed down like the database, so a test can swap the system parts.
class Photos {
  Photos({
    required this.mediaDir,
    required this.workDir,
    required this.picker,
    required this.preparer,
  });

  /// The system picker and the native preparer; the work directory sits next to the media directory,
  /// outside it, so a half-made photo never reaches a backup (D3).
  factory Photos.platform(DataLocation location) => Photos(
    mediaDir: location.mediaDir,
    workDir: Directory('${location.mediaDir.parent.path}/photo-work'),
    picker: const SystemPhotoPicker(),
    preparer: const PlatformPhotoPreparer(),
  );

  final Directory mediaDir;

  /// Scratch space for photos being prepared — emptied at start ([clearWork]).
  final Directory workDir;
  final PhotoPicker picker;
  final PhotoPreparer preparer;

  /// The kept photo at [relativePath] (a `media` row's path).
  File fileOf(String relativePath) => File('${mediaDir.path}/$relativePath');

  /// Asks the user for a photo; null when they cancel.
  Future<File?> pick(PhotoSource source) => picker.pick(source);

  /// Makes [picked] the grave's only photo: shrinks it (D2'), then hands it to the data layer, which
  /// writes the file before the row (D3). The picker's copy and the scratch file go either way.
  Future<void> setGravePhoto(
    GrobingDatabase db,
    int graveId,
    File picked,
  ) async {
    await workDir.create(recursive: true);
    final File prepared = File('${workDir.path}/${_scratchName()}.jpg');
    try {
      await preparer.prepare(picked, prepared);
      await data.setGravePhoto(db, mediaDir, graveId, prepared);
    } finally {
      if (await prepared.exists()) await prepared.delete();
      await picker.discard(picked);
    }
  }

  /// Deletes the grave's photo (D1'); the file goes with the next sweep (D3).
  Future<void> deleteGravePhoto(GrobingDatabase db, int graveId) =>
      data.deleteGravePhoto(db, graveId);

  /// Removes what an interrupted preparation left behind. At start, before any photo is picked.
  Future<void> clearWork() async {
    try {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    } on FileSystemException {
      // The next start tries again.
    }
  }

  static String _scratchName() {
    final Random r = Random.secure();
    return List<String>.generate(
      16,
      (_) => r.nextInt(16).toRadixString(16),
    ).join();
  }
}
