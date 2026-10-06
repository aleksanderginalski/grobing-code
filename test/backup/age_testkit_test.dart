import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/age/age.dart';

// ISSUE-008 AC-3 (D3): our age module against the official test vectors (C2SP/CCTV, see
// age_testkit/README.md). Each vector names the outcome: success with the payload's SHA-256, or which
// failure. For failures with a `payload`, everything released before the error must match it too.

const String _dir = 'test/backup/age_testkit';

String _outcome(AgeFailure failure) => switch (failure) {
  AgeFailure.header => 'header failure',
  AgeFailure.noMatch => 'no match',
  AgeFailure.hmac => 'HMAC failure',
  AgeFailure.payload => 'payload failure',
};

({Map<String, List<String>> keys, Uint8List file}) _parse(Uint8List bytes) {
  int split = -1;
  for (int i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x0a && bytes[i + 1] == 0x0a) {
      split = i;
      break;
    }
  }
  expect(split, greaterThan(0), reason: 'vector header');
  final Map<String, List<String>> keys = {};
  for (final String line
      in latin1.decode(bytes.sublist(0, split)).split('\n')) {
    final int colon = line.indexOf(': ');
    keys
        .putIfAbsent(line.substring(0, colon), () => [])
        .add(line.substring(colon + 2));
  }
  Uint8List file = bytes.sublist(split + 2);
  if (keys['compressed']?.single == 'zlib') {
    file = Uint8List.fromList(zlib.decode(file));
  }
  return (keys: keys, file: file);
}

void main() {
  final List<File> vectors =
      Directory(_dir)
          .listSync()
          .whereType<File>()
          .where((f) => !f.uri.pathSegments.last.contains('.'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the vector set is complete (92 files, no armor, no hybrid)', () {
    expect(vectors, hasLength(92));
  });

  for (final File vector in vectors) {
    final String name = vector.uri.pathSegments.last;
    test(name, () async {
      final v = _parse(vector.readAsBytesSync());
      final List<AgeIdentity> identities = [
        for (final String s in v.keys['identity'] ?? const <String>[])
          X25519Identity.parse(s),
        for (final String p in v.keys['passphrase'] ?? const <String>[])
          ScryptIdentity(p),
      ];
      final BytesBuilder released = BytesBuilder();
      String outcome = 'success';
      try {
        await for (final List<int> chunk in ageDecrypt(
          Stream.value(v.file),
          identities,
        )) {
          released.add(chunk);
        }
      } on AgeException catch (e) {
        outcome = _outcome(e.failure);
      }
      expect(
        outcome,
        v.keys['expect']!.single,
        reason: v.keys['comment']?.single,
      );
      final String? payload = v.keys['payload']?.single;
      if (payload != null) {
        expect(sha256.convert(released.takeBytes()).toString(), payload);
      }
    });
  }
}
