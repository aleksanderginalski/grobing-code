import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/places.dart';

/// The list of places bundled with the app (ISSUE-042, 05_DESIGN/zamieszkanie.md D7): `assets/places/places.db`,
/// built by tool/places/build_places.dart and not in git (README → Lista miejsc). SQLite opens files, not
/// assets, so the first use copies it to `places/` in the app's support directory — beside the family's data,
/// never in it: a backup takes `grobing.db` and `media/` only, and a restore swaps only those. A new version
/// of the app with another list (another size) copies it again. Opened read-only, once per run.
abstract final class BundledPlaces {
  static const String asset = 'assets/places/places.db';

  static Future<PlaceList>? _list;

  /// The list; a failed copy is tried again at the next call.
  static Future<PlaceList> open() => _list ??= _open().catchError((Object e) {
    _list = null;
    throw e;
  });

  static Future<PlaceList> _open() async {
    final Directory dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/places',
    );
    final File file = File('${dir.path}/places.db');
    final ByteData data = await rootBundle.load(asset);
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await dir.create(recursive: true);
      // A temporary name first: an interrupted copy never stands under the real one.
      final File partial = File('${file.path}.partial');
      await partial.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await partial.rename(file.path);
    }
    return PlaceList.openFile(file);
  }
}
