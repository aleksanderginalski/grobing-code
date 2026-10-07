import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/data_state.dart';
import '../data/database.dart';
import 'age/age.dart';
import 'tar_writer.dart';

// The backup file, format v1 (ADR-004 pkt 2, ISSUE-008 D2): an age file to one X25519 recipient,
// holding a ustar archive with
//   grobing.db          — a `VACUUM INTO` snapshot of the database
//   media/<path>        — every photo file, ordered by path
//   manifest.json       — last, so each checksum is taken in the same pass that archives the file.
// The first real backup freezes this: restore must read every format version ever written, so any
// change is a new `format_version`, never an edit of this one.

const int backupFormatVersion = 1;
const String backupDatabaseName = 'grobing.db';
const String backupMediaPrefix = 'media/';
const String backupManifestName = 'manifest.json';

class BackupException implements Exception {
  const BackupException(this.message);

  /// Polish, shown on the "Stan danych" screen. Never carries family data or secrets.
  final String message;

  @override
  String toString() => message;
}

class BackupFileEntry {
  const BackupFileEntry({
    required this.path,
    required this.size,
    required this.sha256,
  });

  factory BackupFileEntry.fromJson(Map<String, Object?> json) =>
      BackupFileEntry(
        path: json['path']! as String,
        size: json['size']! as int,
        sha256: json['sha256']! as String,
      );

  final String path;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => {
    'path': path,
    'size': size,
    'sha256': sha256,
  };
}

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.createdAt,
    required this.schemaVersion,
    required this.recordCounts,
    required this.dataFingerprint,
    required this.files,
  });

  factory BackupManifest.fromJson(Map<String, Object?> json) => BackupManifest(
    formatVersion: json['format_version']! as int,
    createdAt: DateTime.parse(json['created_at']! as String),
    schemaVersion: json['schema_version']! as int,
    recordCounts: (json['record_counts']! as Map<String, Object?>).map(
      (k, v) => MapEntry(k, v! as int),
    ),
    dataFingerprint: json['data_fingerprint']! as String,
    files: [
      for (final Object? f in json['files']! as List<Object?>)
        BackupFileEntry.fromJson(f! as Map<String, Object?>),
    ],
  );

  final int formatVersion;

  /// When the snapshot was taken (UTC) — restore shows "kopia z dnia…".
  final DateTime createdAt;

  /// `PRAGMA user_version` of the snapshot; restore migrates older ones (ADR-004 pkt 5).
  final int schemaVersion;
  final Map<String, int> recordCounts;

  /// The "Stan danych" fingerprint of the backed-up data (`lib/data/data_state.dart`): restore checks
  /// its result against this one number (NFR-002 → Method).
  final String dataFingerprint;

  /// Every archived file except the manifest itself; sizes let restore check free space first.
  final List<BackupFileEntry> files;

  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'schema_version': schemaVersion,
    'record_counts': recordCounts,
    'data_fingerprint': dataFingerprint,
    'files': [for (final BackupFileEntry f in files) f.toJson()],
  };
}

/// Writes the encrypted backup of [snapshot] (a `VACUUM INTO` copy of the database) and the photos in
/// [mediaDir] to [output], encrypted to [recipient]. Streams throughout: memory does not grow with
/// the data (SPIKE-003, M4). Pure Dart — runs in a background isolate and on a PC.
Future<BackupManifest> writeEncryptedBackup({
  required File snapshot,
  required Directory mediaDir,
  required X25519Recipient recipient,
  required File output,
  required DateTime createdAt,
}) async {
  // One list of photo files for the fingerprint and the archive (ISSUE-016, D3): a photo added between
  // two listings would be archived but not counted, and no restore would accept the backup. Listed after
  // the snapshot, and a photo's file is written before its row, so every row in the snapshot has its file.
  final List<File> media = listMediaFiles(mediaDir);

  // Counts and fingerprint from the snapshot, read-only: the backup never writes to what it copies.
  final GrobingDatabase db = GrobingDatabase(
    NativeDatabase.opened(sqlite3.open(snapshot.path, mode: OpenMode.readOnly)),
  );
  final DataState state;
  try {
    state = await readDataState(db, mediaDir: mediaDir, mediaFiles: media);
  } finally {
    await db.close();
  }

  final List<BackupFileEntry> entries = [];
  late final BackupManifest manifest;
  final IOSink sink = output.openWrite();
  try {
    await sink.addStream(
      ageEncrypt(
        _archive(
          sources: [
            (path: backupDatabaseName, file: snapshot),
            for (final File f in media)
              (
                path: '$backupMediaPrefix${mediaRelativePath(mediaDir, f)}',
                file: f,
              ),
          ],
          createdAt: createdAt,
          entries: entries,
          manifest: () => manifest = BackupManifest(
            formatVersion: backupFormatVersion,
            createdAt: createdAt,
            schemaVersion: state.schemaVersion,
            recordCounts: state.rowCounts,
            dataFingerprint: state.fingerprint,
            files: List.unmodifiable(entries),
          ),
        ),
        [recipient],
      ),
    );
    await sink.flush();
  } finally {
    await sink.close();
  }
  return manifest;
}

/// The tar stream: each file with its header and padding, checksummed while it is archived, then the
/// manifest built from those checksums, then the end blocks.
Stream<List<int>> _archive({
  required List<({String path, File file})> sources,
  required DateTime createdAt,
  required List<BackupFileEntry> entries,
  required BackupManifest Function() manifest,
}) async* {
  for (final ({String path, File file}) source in sources) {
    final int size = await source.file.length();
    try {
      yield tarFileHeader(source.path, size, createdAt);
    } on TarPathException {
      throw const BackupException(
        'Nazwa pliku zdjęcia nie mieści się w formacie kopii.',
      );
    }
    final _Sha256Sink digest = _Sha256Sink();
    int read = 0;
    await for (final List<int> chunk in source.file.openRead()) {
      read += chunk.length;
      if (read > size) break;
      digest.add(chunk);
      yield chunk;
    }
    if (read != size) {
      throw const BackupException(
        'Plik zmienił się w trakcie kopii. Spróbuj jeszcze raz.',
      );
    }
    yield tarPadding(size);
    entries.add(
      BackupFileEntry(path: source.path, size: size, sha256: digest.close()),
    );
  }
  final Uint8List json = Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest().toJson()),
    ),
  );
  yield tarFileHeader(backupManifestName, json.length, createdAt);
  yield json;
  yield tarPadding(json.length);
  yield tarEnd();
}

class _Sha256Sink {
  _Sha256Sink() {
    _input = sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  void add(List<int> bytes) => _input.add(bytes);

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
