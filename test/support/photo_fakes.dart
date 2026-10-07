import 'dart:io';

import 'package:grobing/app/photo/photo_picker.dart';
import 'package:grobing/app/photo/photo_preparer.dart';
import 'package:grobing/app/photo/photos.dart';
import 'package:grobing/dev/fictional_photo.dart';

// ISSUE-016 — the system parts of photos replaced for tests. Every picture is drawn in code
// (fictional_photo.dart): the family-data guard refuses image files in the repo, and no real photo is
// ever used (family-data.md).

/// A "picked" photo: a made-up gravestone PNG written to [dir], as the picker's cache copy would be.
File pickedPhoto(Directory dir, int n) {
  dir.createSync(recursive: true);
  return File('${dir.path}/wybrane-$n.png')
    ..writeAsBytesSync(fictionalGravestonePng(n), flush: true);
}

/// The system picker as a queue of answers: each [pick] takes the next file (null = the user cancels).
class FakePhotoPicker implements PhotoPicker {
  final List<File?> answers = [];
  final List<PhotoSource> asked = [];
  final List<File> discarded = [];

  /// When set, [pick] fails like a camera that cannot start.
  Object? error;

  @override
  Future<File?> pick(PhotoSource source) async {
    asked.add(source);
    if (error != null) throw error!;
    return answers.isEmpty ? null : answers.removeAt(0);
  }

  @override
  Future<void> discard(File picked) async {
    discarded.add(picked);
    if (picked.existsSync()) picked.deleteSync();
  }
}

/// The native preparer as a byte copy — the 2048 px JPEG is checked on the emulator (F1).
class FakePhotoPreparer implements PhotoPreparer {
  int calls = 0;

  /// When set, [prepare] fails like a picture the phone cannot decode.
  Object? error;

  @override
  Future<void> prepare(File source, File target) async {
    calls++;
    if (error != null) throw error!;
    target.writeAsBytesSync(source.readAsBytesSync(), flush: true);
  }
}

/// [Photos] under [root]: `media/`, `photo-work/`, and the given fakes.
Photos fakePhotos(
  Directory root, {
  FakePhotoPicker? picker,
  FakePhotoPreparer? preparer,
}) => Photos(
  mediaDir: Directory('${root.path}/media'),
  workDir: Directory('${root.path}/photo-work'),
  picker: picker ?? FakePhotoPicker(),
  preparer: preparer ?? FakePhotoPreparer(),
);
