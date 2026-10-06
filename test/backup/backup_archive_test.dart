import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/age/age.dart';
import 'package:grobing/backup/backup_archive.dart';
import 'package:grobing/backup/tar_writer.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';
import 'package:sqlite3/sqlite3.dart';

// ISSUE-008 AC-1 (the backup's content) and D2 (format v1): made-up data → `VACUUM INTO` snapshot →
// encrypted backup → opened again: the archive holds the database, the photos and the manifest last,
// and every number in the manifest matches the files and the live data.

/// One regular file of a ustar archive, read back for checking.
typedef _Entry = ({
  String path,
  Uint8List data,
  int mode,
  int checksum,
  int storedChecksum,
});

List<_Entry> _readTar(Uint8List tar) {
  final List<_Entry> entries = [];
  int offset = 0;
  String field(int at, int length) {
    final Uint8List bytes = Uint8List.sublistView(
      tar,
      offset + at,
      offset + at + length,
    );
    final int end = bytes.indexOf(0);
    return ascii.decode(end < 0 ? bytes : bytes.sublist(0, end));
  }

  while (true) {
    final Uint8List block = Uint8List.sublistView(tar, offset, offset + 512);
    if (block.every((b) => b == 0)) break;
    expect(field(257, 6), 'ustar', reason: 'ustar magic');
    expect(field(156, 1), '0', reason: 'regular file');
    final String prefix = field(345, 155);
    final String name = field(0, 100);
    final int size = int.parse(field(124, 12), radix: 8);
    final int stored = int.parse(field(148, 6), radix: 8);
    final Uint8List withSpaces = Uint8List.fromList(block)
      ..fillRange(148, 156, 0x20);
    entries.add((
      path: prefix.isEmpty ? name : '$prefix/$name',
      data: Uint8List.sublistView(tar, offset + 512, offset + 512 + size),
      mode: int.parse(field(100, 8), radix: 8),
      checksum: withSpaces.fold(0, (s, b) => s + b),
      storedChecksum: stored,
    ));
    offset += 512 + (size + 511) ~/ 512 * 512;
  }
  // Two zero blocks end the archive.
  expect(tar.length, offset + 1024);
  expect(tar.sublist(offset).every((b) => b == 0), isTrue);
  return entries;
}

void main() {
  late Directory tmp;
  late DataLocation live;
  late GrobingDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_archive_test');
    live = DataLocation.inDirectory(Directory('${tmp.path}/live'));
    live.databaseFile.parent.createSync(recursive: true);
    db = GrobingDatabase.atFile(live.databaseFile);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test(
    'backup of made-up data: database, photos, manifest last — all checksums, counts and the '
    'fingerprint match',
    () async {
      await addFictionalData(db, live.mediaDir);
      await addFictionalData(db, live.mediaDir);
      final DataState liveState = await readDataState(
        db,
        mediaDir: live.mediaDir,
      );

      final File snapshot = File('${tmp.path}/work/grobing.db');
      snapshot.parent.createSync();
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);

      final X25519Identity identity = X25519Identity.generate();
      final DateTime createdAt = DateTime.utc(2026, 10, 6, 12);
      final File output = File('${tmp.path}/kopia.age');
      final BackupManifest returned = await writeEncryptedBackup(
        snapshot: snapshot,
        mediaDir: live.mediaDir,
        recipient: identity.recipient,
        output: output,
        createdAt: createdAt,
      );

      final BytesBuilder tar = BytesBuilder();
      await for (final List<int> c in ageDecrypt(output.openRead(), [
        identity,
      ])) {
        tar.add(c);
      }
      final List<_Entry> entries = _readTar(tar.takeBytes());

      expect(entries.map((e) => e.path), [
        'grobing.db',
        'media/wymyslone/nota-1.txt',
        'media/wymyslone/nota-2.txt',
        'manifest.json',
      ]);
      for (final _Entry e in entries) {
        expect(
          e.storedChecksum,
          e.checksum,
          reason: '${e.path} header checksum',
        );
        expect(e.mode, 0x1a4, reason: '${e.path} mode 0644');
      }

      final BackupManifest manifest = BackupManifest.fromJson(
        jsonDecode(utf8.decode(entries.last.data)) as Map<String, Object?>,
      );
      expect(manifest.toJson(), returned.toJson());
      expect(manifest.formatVersion, 1);
      expect(manifest.createdAt, createdAt);
      expect(manifest.schemaVersion, 1);
      expect(manifest.recordCounts, liveState.rowCounts);
      expect(manifest.dataFingerprint, liveState.fingerprint);
      expect(
        manifest.files.map((f) => f.path),
        entries.take(3).map((e) => e.path),
      );
      for (final (int i, BackupFileEntry f) in manifest.files.indexed) {
        expect(f.size, entries[i].data.length, reason: f.path);
        expect(
          f.sha256,
          sha256.convert(entries[i].data).toString(),
          reason: f.path,
        );
      }
      expect(
        entries[1].data,
        File('${live.mediaDir.path}/wymyslone/nota-1.txt').readAsBytesSync(),
      );

      // The archived database is intact and has the live data's fingerprint.
      final File restored = File('${tmp.path}/restored/grobing.db');
      restored.parent.createSync();
      restored.writeAsBytesSync(entries.first.data);
      final GrobingDatabase opened = GrobingDatabase(
        NativeDatabase.opened(
          sqlite3.open(restored.path, mode: OpenMode.readOnly),
        ),
      );
      try {
        final String integrity =
            (await opened.customSelect('PRAGMA integrity_check').getSingle())
                .read<String>('integrity_check');
        expect(integrity, 'ok');
        expect(
          (await readDataState(opened, mediaDir: live.mediaDir)).fingerprint,
          liveState.fingerprint,
        );
      } finally {
        await opened.close();
      }
    },
  );

  test('an empty database backs up too (no photos)', () async {
    final File snapshot = File('${tmp.path}/grobing.db');
    await db.customStatement('VACUUM INTO ?', [snapshot.path]);
    final X25519Identity identity = X25519Identity.generate();
    final BackupManifest manifest = await writeEncryptedBackup(
      snapshot: snapshot,
      mediaDir: live.mediaDir,
      recipient: identity.recipient,
      output: File('${tmp.path}/kopia.age'),
      createdAt: DateTime.utc(2026),
    );
    expect(manifest.files.map((f) => f.path), ['grobing.db']);
    expect(manifest.recordCounts.values, everyElement(0));
  });

  group('ustar header', () {
    test('a path longer than 100 characters is split into prefix and name', () {
      final String path = 'media/${'a' * 60}/${'b' * 60}.jpg';
      final Uint8List header = tarFileHeader(path, 1, DateTime.utc(2026));
      String field(int at, int length) {
        final List<int> bytes = header.sublist(at, at + length);
        final int end = bytes.indexOf(0);
        return ascii.decode(end < 0 ? bytes : bytes.sublist(0, end));
      }

      expect('${field(345, 155)}/${field(0, 100)}', path);
    });

    test('paths outside the safe set are refused, not renamed', () {
      for (final String path in [
        '../grobing.db',
        'media/../x',
        '/abs',
        'media/zdjęcie.jpg',
        'media/a b.jpg',
        r'media\x.jpg',
      ]) {
        expect(
          () => tarFileHeader(path, 1, DateTime.utc(2026)),
          throwsA(isA<TarPathException>()),
          reason: path,
        );
      }
    });
  });
}
