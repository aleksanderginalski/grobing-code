import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../data/database.dart';

/// Whether the data changed since the last successful backup, without reading the data (ISSUE-010,
/// D2). The stamp covers:
/// - the database's **file change counter** — header offset 24, which SQLite increments on every
///   committed change in rollback-journal mode, the one Grobing uses
///   (https://www.sqlite.org/fileformat2.html#file_change_counter); opening and reading leave it alone;
/// - the database file's size and modification time;
/// - each photo file's path, size and modification time — never its content.
///
/// Compared for equality, never "newer than", so a clock moved back cannot hide a change. A false
/// "changed" costs one backup too many; a false "unchanged" would skip one, so every part above only
/// ever adds detail.
Future<String> dataStamp(DataLocation location) async {
  final List<String> lines = [
    'grobing.db ${await _databaseHeader(location.databaseFile)}',
  ];
  for (final ({String name, FileStat stat}) file in await _dataFiles(
    location,
  )) {
    lines.add(
      file.stat.type == FileSystemEntityType.notFound
          ? '${file.name} missing'
          : '${file.name} ${file.stat.size} '
                '${file.stat.modified.microsecondsSinceEpoch}',
    );
  }
  return sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

/// When the data last changed: the newest modification time of the database file and the photo
/// files; null when there is no data at all. The background backup waits until this is quiet long
/// enough (ISSUE-010, D2).
Future<DateTime?> lastDataChange(DataLocation location) async {
  DateTime? last;
  for (final ({String name, FileStat stat}) file in await _dataFiles(
    location,
  )) {
    if (file.stat.type == FileSystemEntityType.notFound) continue;
    if (last == null || file.stat.modified.isAfter(last)) {
      last = file.stat.modified;
    }
  }
  return last;
}

/// The database file and every photo file, by their name in a backup, sorted.
Future<List<({String name, FileStat stat})>> _dataFiles(
  DataLocation location,
) async {
  final List<({String name, FileStat stat})> files = [
    (name: 'grobing.db', stat: await location.databaseFile.stat()),
  ];
  if (await location.mediaDir.exists()) {
    final List<File> photos = await location.mediaDir
        .list(recursive: true, followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    final int prefix = location.mediaDir.path.length + 1;
    final List<({String name, FileStat stat})> media = [
      for (final File photo in photos)
        (
          name: 'media/${photo.path.substring(prefix).replaceAll(r'\', '/')}',
          stat: await photo.stat(),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    files.addAll(media);
  }
  return files;
}

/// The file change counter, read from the header without opening the database.
Future<String> _databaseHeader(File database) async {
  if (!await database.exists()) return 'missing';
  final RandomAccessFile file = await database.open();
  try {
    final Uint8List header = await file.read(28);
    if (header.length < 28) return 'short';
    return '${ByteData.sublistView(header).getUint32(24)}';
  } finally {
    await file.close();
  }
}
