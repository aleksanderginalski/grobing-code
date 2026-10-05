import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

/// What the "Stan danych" screen shows, and the measure that backup and restore are checked against
/// (NFR-002 → Method): the schema version, row counts and a fingerprint of the data.
class DataState {
  const DataState({
    required this.schemaVersion,
    required this.rowCounts,
    required this.mediaFileCount,
    required this.fingerprint,
  });

  /// `PRAGMA user_version` of the open database file.
  final int schemaVersion;

  /// Row count per table, tables ordered by name.
  final Map<String, int> rowCounts;
  final int mediaFileCount;

  /// SHA-256 (hex) of the data's content — see [readDataState].
  final String fingerprint;

  String get shortFingerprint => fingerprint.substring(0, 16);
}

/// Reads [DataState] from [db] and the photo files under [mediaDir].
///
/// The fingerprint is computed from **content, not the database file**: tables by name, rows ordered
/// by all their columns, every value in a fixed, length-prefixed encoding, then each photo file
/// (path relative to [mediaDir] + SHA-256 of its bytes) ordered by path. Page layout, `VACUUM INTO`
/// and rowid renumbering therefore do not change it, but any changed value or file does. Tables are
/// discovered from `sqlite_master`, so a table added by a later schema counts without code changes.
/// Changing this definition invalidates every fingerprint recorded before (README → Baza danych).
Future<DataState> readDataState(
  GeneratedDatabase db, {
  required Directory mediaDir,
}) async {
  final _Sha256Stream hash = _Sha256Stream();
  final Map<String, int> counts = {};

  final int version = (await db.customSelect('PRAGMA user_version').getSingle())
      .read<int>('user_version');

  final List<String> tables =
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name NOT LIKE 'sqlite_%' ORDER BY name",
              )
              .get())
          .map((r) => r.read<String>('name'))
          .toList();

  for (final String table in tables) {
    final String quoted = _quote(table);
    final List<String> columns =
        (await db.customSelect('PRAGMA table_info($quoted)').get())
            .map((r) => r.read<String>('name'))
            .toList();
    final String orderBy = List<String>.generate(
      columns.length,
      (i) => '${i + 1}',
    ).join(', ');
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT ${columns.map(_quote).join(', ')} FROM $quoted ORDER BY $orderBy',
        )
        .get();

    counts[table] = rows.length;
    hash
      ..addTag('T')
      ..addText(table)
      ..addInt(columns.length);
    columns.forEach(hash.addText);
    hash.addInt(rows.length);
    for (final QueryRow row in rows) {
      for (final String column in columns) {
        hash.addValue(row.data[column]);
      }
    }
  }

  final List<File> media = _mediaFiles(mediaDir);
  hash
    ..addTag('M')
    ..addInt(media.length);
  for (final File file in media) {
    final Digest content = await sha256.bind(file.openRead()).first;
    hash
      ..addText(_relativePath(mediaDir, file))
      ..addBytes(content.bytes);
  }

  return DataState(
    schemaVersion: version,
    rowCounts: counts,
    mediaFileCount: media.length,
    fingerprint: hash.close(),
  );
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

List<File> _mediaFiles(Directory mediaDir) {
  if (!mediaDir.existsSync()) return const [];
  final List<File> files = mediaDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList();
  files.sort(
    (a, b) => _relativePath(mediaDir, a).compareTo(_relativePath(mediaDir, b)),
  );
  return files;
}

String _relativePath(Directory root, File file) => file.path
    .substring(root.path.length)
    .replaceAll(r'\', '/')
    .replaceFirst(RegExp('^/+'), '');

/// SHA-256 over a stream of typed, length-prefixed fields, so that no two different inputs encode to
/// the same bytes (e.g. "ab" + "c" vs "a" + "bc", or the text "1" vs the integer 1).
class _Sha256Stream {
  _Sha256Stream() {
    _input = sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void addTag(String tag) => _input.add(ascii.encode(tag));

  void addInt(int value) {
    addTag('I');
    final ByteData data = ByteData(8)..setInt64(0, value);
    _input.add(data.buffer.asUint8List());
  }

  void addText(String value) {
    final List<int> bytes = utf8.encode(value);
    addTag('S');
    addInt(bytes.length);
    _input.add(bytes);
  }

  void addBytes(List<int> value) {
    addTag('B');
    addInt(value.length);
    _input.add(value);
  }

  void addValue(Object? value) {
    switch (value) {
      case null:
        addTag('N');
      case final int v:
        addInt(v);
      case final double v:
        addTag('R');
        final ByteData data = ByteData(8)..setFloat64(0, v);
        _input.add(data.buffer.asUint8List());
      case final String v:
        addText(v);
      case final Uint8List v:
        addBytes(v);
      default:
        throw ArgumentError('Unsupported SQLite value: ${value.runtimeType}');
    }
  }

  String close() {
    _input.close();
    _output.close();
    return _output.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
