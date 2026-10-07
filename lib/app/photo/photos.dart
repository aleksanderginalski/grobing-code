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

  /// Several photos from the gallery (a person's — zdjecie.md v1.3, A2); empty when cancelled.
  Future<List<File>> pickMany() => picker.pickMany();

  /// Makes a person's photo out of [picked], without writing anything: the prepared file waits in the
  /// work directory until the person's "Zapisz" (zdjecia-osoby.md D1), or goes with [discard]. The
  /// picker's copy goes either way.
  Future<data.NewPhoto> preparePersonPhoto(File picked) async {
    await workDir.create(recursive: true);
    final File prepared = File('${workDir.path}/${_scratchName()}.jpg');
    try {
      await preparer.prepare(picked, prepared);
      return data.NewPhoto(prepared);
    } on Object {
      if (await prepared.exists()) await prepared.delete();
      rethrow;
    } finally {
      await picker.discard(picked);
    }
  }

  /// Removes the prepared file of a photo that will not be saved ("Odrzuć", D1).
  Future<void> discard(data.NewPhoto photo) async {
    try {
      if (await photo.prepared.exists()) await photo.prepared.delete();
    } on FileSystemException {
      // The next start clears the work directory anyway.
    }
  }

  /// Runs [write] — a person's write — with [edits] in its transaction (zdjecia-osoby.md D1): the new
  /// photos' files move into the media directory first (ADR-008), and go back when the write fails, so
  /// "Zapisz" can be tried again. Without [edits] it is [write] alone.
  Future<T> writeWithPersonPhotos<T>(
    GrobingDatabase db,
    data.PersonPhotoEdits? edits,
    Future<T> Function(Future<void> Function(int personId)? alsoWrite) write,
  ) async {
    if (edits == null) return write(null);
    final Map<data.NewPhoto, String> paths = await data.moveNewPersonPhotos(
      mediaDir,
      edits.newPhotos,
    );
    try {
      return await write(
        (personId) => data.applyPersonPhotoEdits(db, personId, edits, paths),
      );
    } on Object {
      await data.returnMovedPhotos(mediaDir, paths);
      rethrow;
    }
  }

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
