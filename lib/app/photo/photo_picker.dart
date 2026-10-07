import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// Where a photo comes from (05_DESIGN/zdjecie.md, A2–A3).
enum PhotoSource { gallery, camera }

/// Picking one photo. Behind an interface so the screens can be tested without a system window.
abstract interface class PhotoPicker {
  /// The picked photo as a file the app may read; null when the user cancels.
  Future<File?> pick(PhotoSource source);

  /// Removes the copy [pick] left in the app's cache, once the app has its own.
  Future<void> discard(File picked);
}

/// [PhotoPicker] over the image_picker package: the Android Photo Picker (every photo and album on the
/// phone, also one taken long ago — ISSUE-016 stop #1) and the system camera. No storage or camera
/// permission. The photo comes back at its original size; the app shrinks it itself (`PhotoPreparer`,
/// D2').
class SystemPhotoPicker implements PhotoPicker {
  const SystemPhotoPicker();

  /// image_picker_android 0.8.13+17 uses the Android Photo Picker only when asked to: by default it
  /// sends ACTION_GET_CONTENT, whose window on Android 16 wants "Done" even for one photo (measured
  /// 2026-10-07, ui review of ISSUE-016). With the Photo Picker one tap on a photo returns it.
  static void _usePhotoPicker() {
    final ImagePickerPlatform platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) platform.useAndroidPhotoPicker = true;
  }

  @override
  Future<File?> pick(PhotoSource source) async {
    _usePhotoPicker();
    final XFile? picked = await ImagePicker().pickImage(
      source: switch (source) {
        PhotoSource.gallery => ImageSource.gallery,
        PhotoSource.camera => ImageSource.camera,
      },
      requestFullMetadata: false,
    );
    return picked == null ? null : File(picked.path);
  }

  /// Only a file inside the app's cache, where the package copies what it returns — never anything
  /// outside the app.
  @override
  Future<void> discard(File picked) async {
    final String cache = (await getTemporaryDirectory()).path;
    if (!picked.absolute.path.startsWith('$cache${Platform.pathSeparator}')) {
      return;
    }
    try {
      await picked.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
