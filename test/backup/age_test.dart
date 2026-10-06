import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/backup/age/age.dart';

// ISSUE-008 AC-3 (D3): the encryption direction, which the official vectors cannot test — round
// trips through our module, chunk boundaries (the `dage` defect: n × 64 KiB) and the identity file.
// The official CLI is the other half of the gate (Verification in the item).

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final BytesBuilder out = BytesBuilder();
  await for (final List<int> chunk in stream) {
    out.add(chunk);
  }
  return out.takeBytes();
}

Uint8List _bytes(int size) =>
    Uint8List.fromList(List<int>.generate(size, (i) => (i * 7 + 3) % 251));

/// [data] in pieces of [piece] bytes, as a file stream would deliver it.
Stream<List<int>> _pieces(Uint8List data, int piece) => Stream.fromIterable([
  for (int i = 0; i < data.length; i += piece)
    Uint8List.sublistView(
      data,
      i,
      i + piece > data.length ? data.length : i + piece,
    ),
]);

Matcher _fails(AgeFailure failure) =>
    throwsA(isA<AgeException>().having((e) => e.failure, 'failure', failure));

void main() {
  const int chunk = 64 * 1024;

  group('X25519 round trip', () {
    for (final int size in [
      0,
      1,
      chunk - 1,
      chunk,
      chunk + 1,
      2 * chunk,
      2 * chunk + 1,
      200000,
    ]) {
      test('$size bytes', () async {
        final X25519Identity identity = X25519Identity.generate();
        final Uint8List plain = _bytes(size);
        final Uint8List file = await _collect(
          ageEncrypt(_pieces(plain, 1000), [identity.recipient]),
        );
        expect(
          await _collect(ageDecrypt(Stream.value(file), [identity])),
          plain,
        );
      });
    }
  });

  test(
    'a payload of exactly n × 64 KiB ends with a full final chunk, not an empty one',
    () async {
      final X25519Identity identity = X25519Identity.generate();
      final Uint8List file = await _collect(
        ageEncrypt(Stream.value(_bytes(2 * chunk)), [identity.recipient]),
      );
      final int header = utf8
          .decode(file, allowMalformed: true)
          .indexOf('\n---');
      final int headerEnd = file.indexOf(0x0a, header + 1) + 1;
      // header + 16-byte nonce + two sealed chunks (64 KiB + 16-byte tag each), nothing more.
      expect(file.length - headerEnd, 16 + 2 * (chunk + 16));
    },
  );

  test('recipient and identity survive encode → parse', () {
    final X25519Identity identity = X25519Identity.generate();
    final String recipient = identity.recipient.encode();
    expect(recipient, startsWith('age1'));
    expect(identity.encode(), startsWith('AGE-SECRET-KEY-1'));
    expect(X25519Recipient.parse(recipient).encode(), recipient);
    expect(
      X25519Identity.parse(identity.encode()).recipient.encode(),
      recipient,
    );
  });

  test('the example key from the specification gives its recipient', () {
    expect(
      X25519Identity.parse(
        'AGE-SECRET-KEY-1GFPYYSJZGFPYYSJZGFPYYSJZGFPYYSJZGFPYYSJZGFPYYSJZGFPQ4EGAEX',
      ).recipient.encode(),
      'age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj',
    );
  });

  test('the identity file looks like age-keygen output and parses back', () {
    final X25519Identity identity = X25519Identity.generate();
    final String text = encodeIdentityFile(
      identity,
      DateTime.utc(2026, 10, 6, 12, 30),
    );
    final List<String> lines = const LineSplitter().convert(text);
    expect(lines, [
      '# created: 2026-10-06T12:30:00Z',
      '# public key: ${identity.recipient.encode()}',
      identity.encode(),
    ]);
    expect(parseIdentityFile(text).single.encode(), identity.encode());
  });

  test('a backup key file uses the age default work factor (18)', () {
    expect(ScryptRecipient.defaultWorkFactor, 18);
    expect(ScryptRecipient('x').workFactor, 18);
  });

  group('passphrase (scrypt; low work factor to keep the test fast)', () {
    const String passphrase = 'zażółć gęślą jaźń';
    late Uint8List file;
    final Uint8List plain = _bytes(chunk + 5);

    setUpAll(() async {
      file = await _collect(
        ageEncrypt(Stream.value(plain), [
          ScryptRecipient(passphrase, workFactor: 10),
        ]),
      );
    });

    test('Polish passphrase round trip (UTF-8, as the official CLI)', () async {
      expect(
        await _collect(
          ageDecrypt(Stream.value(file), [ScryptIdentity(passphrase)]),
        ),
        plain,
      );
    });

    test('wrong passphrase → no match', () async {
      await expectLater(
        _collect(ageDecrypt(Stream.value(file), [ScryptIdentity('zazolc')])),
        _fails(AgeFailure.noMatch),
      );
    });

    test('one flipped bit in the payload → payload failure', () async {
      final Uint8List bad = Uint8List.fromList(file)..[file.length - 30] ^= 1;
      await expectLater(
        _collect(ageDecrypt(Stream.value(bad), [ScryptIdentity(passphrase)])),
        _fails(AgeFailure.payload),
      );
    });

    test('cut at the chunk boundary → payload failure', () async {
      // Remove the whole final chunk (5 bytes + 16-byte tag): the first chunk is not final.
      final Uint8List cut = Uint8List.sublistView(file, 0, file.length - 21);
      await expectLater(
        _collect(ageDecrypt(Stream.value(cut), [ScryptIdentity(passphrase)])),
        _fails(AgeFailure.payload),
      );
    });

    test('a passphrase recipient cannot be mixed with others', () async {
      await expectLater(
        _collect(
          ageEncrypt(Stream.value(plain), [
            ScryptRecipient(passphrase, workFactor: 10),
            X25519Identity.generate().recipient,
          ]),
        ),
        throwsArgumentError,
      );
    });
  });
}
