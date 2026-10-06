import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'tar_writer.dart';

// Reads the ustar archive inside a backup — strictly the subset `tar_writer.dart` writes (ADR-004
// pkt 6: "tar only with regular files and safe paths"). The archive comes from a file the user picked,
// so everything about it is checked before it can touch the phone's data: it is only ever extracted
// into a private staging directory, under a byte budget.

/// The archive is not one this app wrote: a wrong header, entry type, path or end.
class TarFormatException implements Exception {
  const TarFormatException(this.message);

  final String message;

  @override
  String toString() => 'TarFormatException: $message';
}

/// The archive holds more bytes than the budget allows (ISSUE-009, D2).
class TarBudgetException implements Exception {
  const TarBudgetException();
}

/// One extracted file, with the size and SHA-256 measured while it was written.
class TarEntry {
  const TarEntry({
    required this.path,
    required this.size,
    required this.sha256,
  });

  final String path;
  final int size;
  final String sha256;
}

/// Extracts [archive] into [target] and returns its files in archive order. Accepts only regular
/// files with safe, unique paths that [accept] allows, valid header checksums, zero padding and the
/// two zero end blocks with nothing but zeros after them. Stops once file contents exceed [maxBytes].
Future<List<TarEntry>> extractTar(
  Stream<List<int>> archive,
  Directory target, {
  required int maxBytes,
  bool Function(String path)? accept,
}) async {
  final _BlockReader reader = _BlockReader(archive);
  final List<TarEntry> entries = [];
  final Set<String> seen = {};
  final Set<String> directories = {};
  int total = 0;
  try {
    while (true) {
      final Uint8List header = await reader.read(tarBlockSize);
      if (header.length < tarBlockSize) {
        throw const TarFormatException('Archive ends without its end blocks');
      }
      if (_isZero(header)) {
        final Uint8List second = await reader.read(tarBlockSize);
        if (second.length < tarBlockSize || !_isZero(second)) {
          throw const TarFormatException('Incomplete end of archive');
        }
        if (!await reader.restIsZero()) {
          throw const TarFormatException('Data after the end of archive');
        }
        return entries;
      }

      _checkHeader(header);
      final String path = _path(header);
      if (!isSafeTarPath(path)) throw const TarFormatException('Unsafe path');
      if (accept != null && !accept(path)) {
        throw const TarFormatException('Unexpected file in archive');
      }
      // A file and a directory of the same name, or the same file twice, would overwrite each other.
      final List<String> segments = path.split('/');
      final List<String> parents = [
        for (int i = 1; i < segments.length; i++) segments.take(i).join('/'),
      ];
      if (seen.contains(path) ||
          directories.contains(path) ||
          parents.any(seen.contains)) {
        throw const TarFormatException('Duplicate path');
      }
      seen.add(path);
      directories.addAll(parents);
      final int size = _octal(header, 124, 12);
      total += size;
      if (total > maxBytes) throw const TarBudgetException();

      final File file = File('${target.path}/$path');
      await file.parent.create(recursive: true);
      final _Sha256Sink digest = _Sha256Sink();
      final IOSink sink = file.openWrite();
      try {
        int remaining = size;
        while (remaining > 0) {
          final Uint8List chunk = await reader.read(min(remaining, 64 * 1024));
          if (chunk.isEmpty) {
            throw const TarFormatException('Archive ends inside a file');
          }
          digest.add(chunk);
          sink.add(chunk);
          remaining -= chunk.length;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final int padding = (tarBlockSize - size % tarBlockSize) % tarBlockSize;
      final Uint8List pad = await reader.read(padding);
      if (pad.length != padding || !_isZero(pad)) {
        throw const TarFormatException('Invalid padding after a file');
      }
      entries.add(TarEntry(path: path, size: size, sha256: digest.close()));
    }
  } finally {
    await reader.cancel();
  }
}

/// Checksum, regular-file type and the ustar magic — exactly as `tarFileHeader` writes them.
void _checkHeader(Uint8List header) {
  final int stored = _octal(header, 148, 8);
  int sum = 0;
  for (int i = 0; i < tarBlockSize; i++) {
    sum += (i >= 148 && i < 156) ? 0x20 : header[i];
  }
  if (sum != stored) throw const TarFormatException('Header checksum');
  final int type = header[156];
  if (type != 0x30 && type != 0) {
    throw const TarFormatException('Not a regular file');
  }
  if (_text(header, 257, 6) != 'ustar' || _text(header, 263, 2) != '00') {
    throw const TarFormatException('Not a ustar header');
  }
}

String _path(Uint8List header) {
  final String name = _text(header, 0, 100);
  final String prefix = _text(header, 345, 155);
  if (name.isEmpty) throw const TarFormatException('Empty name');
  return prefix.isEmpty ? name : '$prefix/$name';
}

/// NUL-terminated ASCII; anything outside ASCII is not a name this app wrote.
String _text(Uint8List header, int offset, int length) {
  final int end = header.indexOf(0, offset);
  final int stop = (end < 0 || end > offset + length) ? offset + length : end;
  final Uint8List bytes = Uint8List.sublistView(header, offset, stop);
  if (bytes.any((b) => b > 0x7f)) {
    throw const TarFormatException('Non-ASCII header field');
  }
  return ascii.decode(bytes);
}

/// Octal digits, optionally padded with spaces and ended by NUL or space; no GNU base-256.
int _octal(Uint8List header, int offset, int length) {
  final String field = _text(header, offset, length).trim();
  if (field.isEmpty || !RegExp(r'^[0-7]+$').hasMatch(field)) {
    throw const TarFormatException('Invalid octal field');
  }
  return int.parse(field, radix: 8);
}

bool _isZero(List<int> bytes) => bytes.every((b) => b == 0);

/// Exact-size reads from a byte stream.
class _BlockReader {
  _BlockReader(Stream<List<int>> input)
    : _input = StreamIterator<List<int>>(input);

  final StreamIterator<List<int>> _input;
  List<int> _chunk = const [];
  int _offset = 0;

  /// [count] bytes, or fewer only at the end of the stream.
  Future<Uint8List> read(int count) async {
    final BytesBuilder out = BytesBuilder(copy: false);
    while (out.length < count) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) break;
        _chunk = _input.current;
        _offset = 0;
        continue;
      }
      final int n = min(count - out.length, _chunk.length - _offset);
      out.add(Uint8List.fromList(_chunk.sublist(_offset, _offset + n)));
      _offset += n;
    }
    return out.takeBytes();
  }

  Future<bool> restIsZero() async {
    while (true) {
      final Uint8List block = await read(64 * 1024);
      if (block.isEmpty) return true;
      if (!_isZero(block)) return false;
    }
  }

  Future<void> cancel() => _input.cancel();
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
