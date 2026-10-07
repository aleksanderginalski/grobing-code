import 'dart:io';

import 'package:flutter/services.dart';

/// The longer side of every photo the app keeps, in pixels (D2', decided by the author at stop #1 of
/// ISSUE-016): about twice the width of a phone screen, so an inscription or a face can be zoomed.
const int photoMaxEdge = 2048;

/// JPEG quality of the kept photo (D2').
const int photoJpegQuality = 85;

/// Makes the photo the app keeps out of a picked one. Behind an interface so the data path can be
/// tested on a PC, where the native side does not exist.
abstract interface class PhotoPreparer {
  /// Writes [target]: a JPEG, the longer side at most [photoMaxEdge] (a smaller photo keeps its size),
  /// upright, without EXIF. Throws when [source] cannot be read as a picture.
  Future<void> prepare(File source, File target);
}

/// [PhotoPreparer] over the native channel in `PhotoPreparation.kt`.
class PlatformPhotoPreparer implements PhotoPreparer {
  const PlatformPhotoPreparer();

  static const MethodChannel _channel = MethodChannel('com.grobing.app/photos');

  @override
  Future<void> prepare(File source, File target) =>
      _channel.invokeMethod<void>('prepare', {
        'source': source.path,
        'target': target.path,
        'maxEdge': photoMaxEdge,
        'quality': photoJpegQuality,
      });
}
