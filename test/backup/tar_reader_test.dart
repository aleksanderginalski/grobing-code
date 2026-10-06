import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/tar_reader.dart';
import 'package:grobing/backup/tar_writer.dart';

// ISSUE-009 AC-2 (ADR-004 pkt 6: "tar only with regular files and safe paths"): the restore's tar
// reader accepts exactly what `tar_writer.dart` writes and refuses everything else — before anything
// leaves the staging directory, and without writing outside it.

/// A ustar header written by hand, so that it can be wrong in one chosen way.
Uint8List _header(
  String name, {
  int size = 0,
  String type = '0',
  String magic = 'ustar',
  String prefix = '',
  int? checksumDelta,
}) {
  final Uint8List h = Uint8List(512);
  void put(int at, String s) => h.setRange(at, at + s.length, latin1.encode(s));
  put(0, name);
  put(100, '0000644');
  put(108, '0000000');
  put(116, '0000000');
  put(124, size.toRadixString(8).padLeft(11, '0'));
  put(136, '00000000000');
  put(156, type);
  put(257, magic);
  put(263, '00');
  put(345, prefix);
  h.fillRange(148, 156, 0x20);
  final int sum = h.fold(0, (s, b) => s + b) + (checksumDelta ?? 0);
  put(148, sum.toRadixString(8).padLeft(6, '0'));
  h[154] = 0;
  h[155] = 0x20;
  return h;
}

/// One file: header, content, zero padding.
List<int> _file(String path, List<int> data) => [
  ...tarFileHeader(path, data.length, DateTime.utc(2026, 10, 6)),
  ...data,
  ...tarPadding(data.length),
];

List<int> _raw(Uint8List header, List<int> data) => [
  ...header,
  ...data,
  ...tarPadding(data.length),
];

void main() {
  late Directory tmp;
  late Directory target;
  int runs = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_tar_reader_test');
    target = Directory('${tmp.path}/staging')..createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<List<TarEntry>> extract(
    List<int> archive, {
    int maxBytes = 1 << 20,
    bool Function(String)? accept,
  }) {
    // A fresh staging directory per archive, as restore has.
    target = Directory('${tmp.path}/staging-${runs++}')..createSync();
    return extractTar(
      Stream.fromIterable([
        // Odd chunk sizes: block boundaries never line up with stream chunks.
        for (int i = 0; i < archive.length; i += 333)
          archive.sublist(
            i,
            i + 333 > archive.length ? archive.length : i + 333,
          ),
      ]),
      target,
      maxBytes: maxBytes,
      accept: accept,
    );
  }

  test(
    'reads back what the writer writes: paths (also a long one with a prefix), '
    'sizes, SHA-256 and content',
    () async {
      final String longPath = 'media/${'a' * 90}/${'b' * 90}.jpg';
      final List<int> photo = List<int>.generate(70000, (i) => i % 251);
      final List<int> archive = [
        ..._file('grobing.db', utf8.encode('baza')),
        ..._file(longPath, photo),
        ..._file('manifest.json', utf8.encode('{}')),
        ...tarEnd(),
      ];

      final List<TarEntry> entries = await extract(archive);

      expect(entries.map((e) => e.path), [
        'grobing.db',
        longPath,
        'manifest.json',
      ]);
      expect(entries[1].size, photo.length);
      expect(entries[1].sha256, sha256.convert(photo).toString());
      expect(File('${target.path}/$longPath').readAsBytesSync(), photo);
      expect(File('${target.path}/grobing.db').readAsStringSync(), 'baza');
    },
  );

  test(
    'an empty file and trailing zero padding after the end are fine',
    () async {
      final List<TarEntry> entries = await extract([
        ..._file('grobing.db', const []),
        ...tarEnd(),
        ...Uint8List(512 * 18), // record padding as other tars write it
      ]);
      expect(entries.single.size, 0);
    },
  );

  for (final (String what, List<int> archive) in [
    ('a path with ..', _raw(_header('media/../../evil'), [0x41])),
    ('an absolute path', _raw(_header('/evil'), [0x41])),
    ('a path with a backslash', _raw(_header(r'media\evil'), [0x41])),
    ('a path with a space', _raw(_header('media/a b'), [0x41])),
    ('a non-ASCII path', _raw(_header('media/café'), [0x41])),
    ('a symbolic link', _raw(_header('media/link', type: '2'), const [])),
    ('a hard link', _raw(_header('media/link', type: '1'), const [])),
    ('a directory entry', _raw(_header('media/', type: '5'), const [])),
    (
      'a GNU long-name entry',
      _raw(_header('././@LongLink', type: 'L'), [0x41]),
    ),
    ('a wrong header checksum', _raw(_header('a', checksumDelta: 1), [0x41])),
    ('a non-ustar header', _raw(_header('a', magic: 'ustar '), [0x41])),
  ]) {
    test(
      'refuses $what, writing nothing outside the staging directory',
      () async {
        await expectLater(
          extract([...archive, ...tarEnd()]),
          throwsA(isA<TarFormatException>()),
        );
        expect(File('${tmp.path}/evil').existsSync(), isFalse);
        expect(File('/evil').existsSync(), isFalse);
      },
    );
  }

  test(
    'refuses the same path twice, and a file that is also a directory',
    () async {
      await expectLater(
        extract([
          ..._file('grobing.db', [1]),
          ..._file('grobing.db', [2]),
          ...tarEnd(),
        ]),
        throwsA(isA<TarFormatException>()),
      );
      await expectLater(
        extract([
          ..._file('media/a', [1]),
          ..._file('media/a/b', [2]),
          ...tarEnd(),
        ]),
        throwsA(isA<TarFormatException>()),
      );
      await expectLater(
        extract([
          ..._file('media/a/b', [1]),
          ..._file('media/a', [2]),
          ...tarEnd(),
        ]),
        throwsA(isA<TarFormatException>()),
      );
    },
  );

  test(
    'refuses an archive cut short, without its end, or with data after it',
    () async {
      final List<int> one = _file('grobing.db', List<int>.filled(1000, 7));
      await expectLater(
        extract(one.sublist(0, 700)),
        throwsA(isA<TarFormatException>()),
      );
      await expectLater(extract(one), throwsA(isA<TarFormatException>()));
      await expectLater(
        extract([...one, ...Uint8List(512)]),
        throwsA(isA<TarFormatException>()),
      );
      await expectLater(
        extract([...one, ...tarEnd(), 1]),
        throwsA(isA<TarFormatException>()),
      );
    },
  );

  test('refuses non-zero padding after a file', () async {
    final List<int> archive = [
      ..._file('grobing.db', [1]),
      ...tarEnd(),
    ];
    archive[513] = 9;
    await expectLater(extract(archive), throwsA(isA<TarFormatException>()));
  });

  test('refuses a path the caller does not accept', () async {
    await expectLater(
      extract([
        ..._file('other.txt', [1]),
        ...tarEnd(),
      ], accept: (p) => p == 'grobing.db'),
      throwsA(isA<TarFormatException>()),
    );
  });

  test('stops at the byte budget before writing past it', () async {
    await expectLater(
      extract([
        ..._file('grobing.db', List<int>.filled(600, 1)),
        ..._file('media/x', List<int>.filled(600, 2)),
        ...tarEnd(),
      ], maxBytes: 1000),
      throwsA(isA<TarBudgetException>()),
    );
    expect(File('${target.path}/media/x').existsSync(), isFalse);
  });
}
