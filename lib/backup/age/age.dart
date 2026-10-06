import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:pointycastle/key_derivators/api.dart' show ScryptParameters;
import 'package:pointycastle/key_derivators/scrypt.dart';

import 'bech32.dart';

// The age v1 file format (https://c2sp.org/age) — the subset Grobing uses: X25519 and scrypt
// recipients, binary (not armored) files, streaming in both directions. ADR-004: the backup must
// open without Grobing, with the official `age`, so this follows the specification, not another
// implementation; `dage` and `dartage` were rejected in SPIKE-003. Checked against the official test
// vectors (C2SP/CCTV, `age/testdata`) and the official CLI (ISSUE-008, AC-3).

/// Why an age file could not be decrypted — the outcomes the official test vectors name
/// (C2SP/CCTV `age/README.md` → `expect`).
enum AgeFailure {
  /// The header does not parse, or a stanza addressed to the identity is malformed.
  header,

  /// The header parses, but no identity unwraps the file key (e.g. a wrong passphrase).
  noMatch,

  /// The file key unwraps, but the header MAC does not match.
  hmac,

  /// The payload does not decrypt all the way to its end (corrupted or truncated file).
  payload,
}

class AgeException implements Exception {
  const AgeException(this.failure, this.message);

  final AgeFailure failure;
  final String message;

  @override
  String toString() => 'AgeException(${failure.name}): $message';
}

/// A recipient stanza: `-> type args…` followed by the base64 body.
class AgeStanza {
  AgeStanza(this.type, this.args, this.body);

  final String type;
  final List<String> args;
  final Uint8List body;
}

/// Wraps a file key for one recipient.
abstract interface class AgeRecipient {
  AgeStanza wrap(Uint8List fileKey);
}

/// Unwraps a file key. Returns null when no stanza is addressed to this identity; throws
/// [AgeException] ([AgeFailure.header]) when one that is addressed to it is malformed.
abstract interface class AgeIdentity {
  Uint8List? unwrap(List<AgeStanza> stanzas);
}

/// An X25519 public key, `age1…`. Not a secret: a background backup needs only this.
class X25519Recipient implements AgeRecipient {
  X25519Recipient._(this._publicKey);

  factory X25519Recipient.parse(String text) {
    final ({String hrp, Uint8List data}) decoded = _decodeKey(text);
    if (decoded.hrp != 'age' || decoded.data.length != 32) {
      throw const FormatException('Not an age X25519 recipient');
    }
    return X25519Recipient._(decoded.data);
  }

  final Uint8List _publicKey;

  String encode() => bech32Encode('age', _publicKey);

  @override
  AgeStanza wrap(Uint8List fileKey) {
    final Uint8List ephemeral = _randomBytes(32);
    final Uint8List share = _x25519(ephemeral, _basepoint);
    final Uint8List shared = _x25519(ephemeral, _publicKey);
    if (_isAllZero(shared)) {
      throw ArgumentError('Invalid X25519 recipient (low-order point)');
    }
    final Uint8List wrapKey = _hkdf(shared, [
      ...share,
      ..._publicKey,
    ], _x25519Label);
    return AgeStanza('X25519', [
      _encodeBase64(share),
    ], _seal(wrapKey, _zeroNonce, fileKey));
  }
}

/// An X25519 secret key, `AGE-SECRET-KEY-1…` — the identity that opens a backup.
class X25519Identity implements AgeIdentity {
  X25519Identity._(this._secret) : _publicKey = _x25519(_secret, _basepoint);

  factory X25519Identity.generate() => X25519Identity._(_randomBytes(32));

  factory X25519Identity.parse(String text) {
    final ({String hrp, Uint8List data}) decoded = _decodeKey(text);
    if (decoded.hrp != 'age-secret-key-' || decoded.data.length != 32) {
      throw const FormatException('Not an age X25519 identity');
    }
    return X25519Identity._(decoded.data);
  }

  final Uint8List _secret;
  final Uint8List _publicKey;

  X25519Recipient get recipient => X25519Recipient._(_publicKey);

  String encode() => bech32Encode('age-secret-key-', _secret).toUpperCase();

  @override
  Uint8List? unwrap(List<AgeStanza> stanzas) {
    for (final AgeStanza stanza in stanzas) {
      if (stanza.type != 'X25519') continue;
      if (stanza.args.length != 1) {
        throw _header('X25519 stanza needs one argument');
      }
      final Uint8List? share = _decodeBase64(stanza.args.first);
      if (share == null || share.length != 32) {
        throw _header('Invalid X25519 share');
      }
      // Before any decryption: mitigates partitioning oracle attacks (spec).
      if (stanza.body.length != _wrappedKeySize) {
        throw _header('Invalid X25519 body length');
      }
      final Uint8List shared = _x25519(_secret, share);
      if (_isAllZero(shared)) throw _header('X25519 shared secret is zero');
      final Uint8List wrapKey = _hkdf(shared, [
        ...share,
        ..._publicKey,
      ], _x25519Label);
      final Uint8List? fileKey = _open(wrapKey, _zeroNonce, stanza.body);
      if (fileKey != null) return fileKey;
    }
    return null;
  }
}

/// A passphrase recipient. Expensive by design (scrypt): run it off the UI isolate.
class ScryptRecipient implements AgeRecipient {
  ScryptRecipient(this._passphrase, {this.workFactor = defaultWorkFactor});

  /// log2 of the scrypt work factor; 18 is the official `age` default (SPIKE-003, M4: ~14 s and
  /// ~430 MB on the emulator in pure Dart).
  static const int defaultWorkFactor = 18;

  final String _passphrase;
  final int workFactor;

  @override
  AgeStanza wrap(Uint8List fileKey) {
    final Uint8List salt = _randomBytes(16);
    final Uint8List wrapKey = _scrypt(_passphrase, salt, workFactor);
    return AgeStanza('scrypt', [
      _encodeBase64(salt),
      '$workFactor',
    ], _seal(wrapKey, _zeroNonce, fileKey));
  }
}

/// A passphrase identity. Refuses work factors above [maxWorkFactor] (spec: SHOULD apply a limit;
/// the official `age` uses 22 — a file asking for more is rejected, not computed).
class ScryptIdentity implements AgeIdentity {
  ScryptIdentity(this._passphrase, {this.maxWorkFactor = 22});

  final String _passphrase;
  final int maxWorkFactor;

  static final RegExp _decimal = RegExp(r'^[1-9][0-9]*$');

  @override
  Uint8List? unwrap(List<AgeStanza> stanzas) {
    for (final AgeStanza stanza in stanzas) {
      if (stanza.type != 'scrypt') continue;
      if (stanzas.length != 1) throw _header('scrypt stanza must be alone');
      if (stanza.args.length != 2) {
        throw _header('scrypt stanza needs two arguments');
      }
      final Uint8List? salt = _decodeBase64(stanza.args[0]);
      if (salt == null || salt.length != 16) {
        throw _header('Invalid scrypt salt');
      }
      final int? workFactor = _decimal.hasMatch(stanza.args[1])
          ? int.tryParse(stanza.args[1])
          : null;
      if (workFactor == null || workFactor > maxWorkFactor) {
        throw _header('Invalid or too large scrypt work factor');
      }
      if (stanza.body.length != _wrappedKeySize) {
        throw _header('Invalid scrypt body length');
      }
      final Uint8List wrapKey = _scrypt(_passphrase, salt, workFactor);
      final Uint8List? fileKey = _open(wrapKey, _zeroNonce, stanza.body);
      if (fileKey != null) return fileKey;
    }
    return null;
  }
}

/// The identity file as `age-keygen` writes it: two comment lines, then the secret key. Encrypted
/// with a passphrase it is the file `age -d -i` opens after asking for that passphrase.
String encodeIdentityFile(X25519Identity identity, DateTime created) =>
    '# created: ${created.toUtc().toIso8601String().split('.').first}Z\n'
    '# public key: ${identity.recipient.encode()}\n'
    '${identity.encode()}\n';

/// Reads identities from identity file text; blank lines and `#` comments are skipped, as in `age`.
List<X25519Identity> parseIdentityFile(String text) => [
  for (final String line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty && !line.startsWith('#'))
      X25519Identity.parse(line.trim()),
];

/// Encrypts [plaintext] to [recipients] and returns the whole age file as a stream: header, nonce,
/// then 64 KiB chunks. Holds one chunk in memory, so the size of the input does not matter.
Stream<List<int>> ageEncrypt(
  Stream<List<int>> plaintext,
  List<AgeRecipient> recipients,
) async* {
  if (recipients.isEmpty) throw ArgumentError('No recipients');
  final Uint8List fileKey = _randomBytes(_fileKeySize);
  final List<AgeStanza> stanzas = [
    for (final AgeRecipient r in recipients) r.wrap(fileKey),
  ];
  if (stanzas.any((s) => s.type == 'scrypt') && stanzas.length != 1) {
    throw ArgumentError('A passphrase recipient must be the only one');
  }

  final BytesBuilder header = BytesBuilder(copy: false)
    ..add(ascii.encode('$_versionLine\n'));
  for (final AgeStanza stanza in stanzas) {
    header.add(ascii.encode('-> ${[stanza.type, ...stanza.args].join(' ')}\n'));
    final String body = _encodeBase64(stanza.body);
    final int fullLines = body.length ~/ _columns;
    for (int i = 0; i < fullLines; i++) {
      header.add(
        ascii.encode('${body.substring(i * _columns, (i + 1) * _columns)}\n'),
      );
    }
    // The body always ends with a line shorter than 64 columns, possibly empty.
    header.add(ascii.encode('${body.substring(fullLines * _columns)}\n'));
  }
  header.add(ascii.encode('---'));
  final List<int> mac = _hmac(
    _hkdf(fileKey, const [], 'header'),
    header.toBytes(),
  );
  header.add(ascii.encode(' ${_encodeBase64(mac)}\n'));
  yield header.takeBytes();

  final Uint8List nonce = _randomBytes(_payloadNonceSize);
  yield nonce;
  final Uint8List payloadKey = _hkdf(fileKey, nonce, 'payload');

  // A chunk is sealed as non-final only once more data is known to follow, so the final chunk is
  // never empty unless the whole payload is (the `dage` defect SPIKE-003 found: n × 64 KiB).
  final Uint8List chunk = Uint8List(_chunkSize);
  int filled = 0;
  int counter = 0;
  await for (final List<int> data in plaintext) {
    int offset = 0;
    while (offset < data.length) {
      if (filled == _chunkSize) {
        yield _seal(payloadKey, _chunkNonce(counter++, last: false), chunk);
        filled = 0;
      }
      final int n = min(_chunkSize - filled, data.length - offset);
      chunk.setRange(filled, filled + n, data, offset);
      filled += n;
      offset += n;
    }
  }
  yield _seal(
    payloadKey,
    _chunkNonce(counter, last: true),
    Uint8List.sublistView(chunk, 0, filled),
  );
}

/// Decrypts an age file with the first identity that unwraps its file key. Plaintext is released one
/// verified chunk at a time; anything wrong ends the stream with [AgeException].
Stream<List<int>> ageDecrypt(
  Stream<List<int>> file,
  List<AgeIdentity> identities,
) async* {
  final _ByteReader reader = _ByteReader(file);
  try {
    final _Header header = await _readHeader(reader);
    if (header.stanzas.any((s) => s.type == 'scrypt') &&
        header.stanzas.length != 1) {
      throw _header('scrypt stanza must be alone');
    }
    Uint8List? fileKey;
    for (final AgeIdentity identity in identities) {
      fileKey = identity.unwrap(header.stanzas);
      if (fileKey != null) break;
    }
    if (fileKey == null) {
      throw const AgeException(
        AgeFailure.noMatch,
        'No identity matches this file',
      );
    }
    final List<int> expectedMac = _hmac(
      _hkdf(fileKey, const [], 'header'),
      header.macInput,
    );
    if (!_constantTimeEquals(expectedMac, header.mac)) {
      throw const AgeException(AgeFailure.hmac, 'Header MAC does not match');
    }
    final Uint8List nonce = await reader.read(_payloadNonceSize);
    if (nonce.length != _payloadNonceSize) {
      throw _header('Payload nonce is missing');
    }
    final Uint8List payloadKey = _hkdf(fileKey, nonce, 'payload');

    for (int counter = 0; ; counter++) {
      final Uint8List sealed = await reader.read(_sealedChunkSize);
      if (sealed.isEmpty) throw _payload('File ends without a final chunk');
      Uint8List? plain;
      bool last;
      if (sealed.length < _sealedChunkSize) {
        // A short chunk is the final one; it is empty only when the whole payload is.
        if (counter > 0 && sealed.length == _tagSize) {
          throw _payload('Final chunk is empty');
        }
        last = true;
        plain = _open(payloadKey, _chunkNonce(counter, last: true), sealed);
      } else {
        last = false;
        plain = _open(payloadKey, _chunkNonce(counter, last: false), sealed);
        if (plain == null) {
          // A full-size chunk can also be the final one.
          last = true;
          plain = _open(payloadKey, _chunkNonce(counter, last: true), sealed);
        }
      }
      if (plain == null) throw _payload('Chunk $counter does not authenticate');
      yield plain;
      if (last) {
        if (!await reader.atEnd) throw _payload('Data after the final chunk');
        return;
      }
    }
  } finally {
    await reader.cancel();
  }
}

// --- Format internals -----------------------------------------------------------------------------

const String _versionLine = 'age-encryption.org/v1';
const String _x25519Label = 'age-encryption.org/v1/X25519';
const String _scryptLabel = 'age-encryption.org/v1/scrypt';
const int _fileKeySize = 16;
const int _tagSize = 16;
const int _wrappedKeySize = _fileKeySize + _tagSize;
const int _payloadNonceSize = 16;
const int _chunkSize = 64 * 1024;
const int _sealedChunkSize = _chunkSize + _tagSize;
const int _columns = 64;

/// Upper bound on the header we are willing to buffer — our files have one short stanza.
const int _maxHeaderSize = 1024 * 1024;

final Uint8List _basepoint = Uint8List(32)..[0] = 9;
final Uint8List _zeroNonce = Uint8List(12);
const DartChacha20 _chacha = DartChacha20.poly1305Aead();
const DartX25519 _x25519Algorithm = DartX25519();
final Random _random = Random.secure();

AgeException _header(String message) =>
    AgeException(AgeFailure.header, message);
AgeException _payload(String message) =>
    AgeException(AgeFailure.payload, message);

class _Header {
  _Header(this.stanzas, this.macInput, this.mac);

  final List<AgeStanza> stanzas;

  /// The header up to and including `---`, as the MAC covers it.
  final Uint8List macInput;
  final Uint8List mac;
}

Future<_Header> _readHeader(_ByteReader reader) async {
  final BytesBuilder raw = BytesBuilder(copy: true);

  Future<String> line() async {
    final Uint8List? bytes = await reader.readLine(_maxHeaderSize - raw.length);
    if (bytes == null) throw _header('Header is truncated or too long');
    raw.add(bytes);
    return latin1.decode(Uint8List.sublistView(bytes, 0, bytes.length - 1));
  }

  if (await line() != _versionLine) throw _header('Unsupported version line');

  final List<AgeStanza> stanzas = [];
  while (true) {
    final int lineStart = raw.length;
    final String text = await line();
    if (text.startsWith('---')) {
      if (stanzas.isEmpty) throw _header('Header has no stanzas');
      if (!text.startsWith('--- ')) throw _header('Malformed MAC line');
      final Uint8List? mac = _decodeBase64(text.substring(4));
      if (mac == null || mac.length != 32) throw _header('Malformed MAC');
      final Uint8List macInput = Uint8List.sublistView(
        raw.toBytes(),
        0,
        lineStart + 3,
      );
      return _Header(stanzas, macInput, mac);
    }
    if (!text.startsWith('-> ')) {
      throw _header('Expected a stanza or the MAC line');
    }
    final List<String> args = text.substring(3).split(' ');
    if (args.any((a) => a.isEmpty || !_isVisibleAscii(a))) {
      throw _header('Malformed stanza arguments');
    }
    final StringBuffer body = StringBuffer();
    while (true) {
      final String bodyLine = await line();
      if (bodyLine.length > _columns || !_isBase64Alphabet(bodyLine)) {
        throw _header('Malformed stanza body');
      }
      body.write(bodyLine);
      if (bodyLine.length < _columns) break;
    }
    final Uint8List? decoded = _decodeBase64(body.toString());
    if (decoded == null) throw _header('Stanza body is not canonical base64');
    stanzas.add(AgeStanza(args.first, args.sublist(1), decoded));
  }
}

/// Buffered reads of exact sizes and lines from a byte stream.
class _ByteReader {
  _ByteReader(Stream<List<int>> stream)
    : _input = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _input;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;
  bool _ended = false;

  int get _available => _buffer.length - _offset;

  Future<bool> _fill() async {
    if (_ended) return false;
    if (!await _input.moveNext()) {
      _ended = true;
      return false;
    }
    final List<int> next = _input.current;
    final int available = _available;
    _buffer = Uint8List(available + next.length)
      ..setRange(0, available, _buffer, _offset)
      ..setRange(available, available + next.length, next);
    _offset = 0;
    return true;
  }

  /// Up to [count] bytes; fewer only at the end of the stream.
  Future<Uint8List> read(int count) async {
    while (_available < count && await _fill()) {}
    final int n = min(count, _available);
    final Uint8List out = Uint8List.sublistView(_buffer, _offset, _offset + n);
    _offset += n;
    return out;
  }

  /// One line including its LF, or null if the stream ends first or the line exceeds [maxLength].
  Future<Uint8List?> readLine(int maxLength) async {
    int searched = 0;
    while (true) {
      final int end = _buffer.indexOf(0x0a, _offset + searched);
      if (end >= 0) {
        if (end - _offset + 1 > maxLength) return null;
        final Uint8List out = Uint8List.sublistView(_buffer, _offset, end + 1);
        _offset = end + 1;
        return out;
      }
      searched = _available;
      if (_available > maxLength || !await _fill()) return null;
    }
  }

  Future<bool> get atEnd async {
    while (_available == 0) {
      if (!await _fill()) return true;
    }
    return false;
  }

  Future<void> cancel() => _input.cancel();
}

Uint8List _chunkNonce(int counter, {required bool last}) {
  final Uint8List nonce = Uint8List(12);
  int c = counter;
  for (int i = 10; i >= 0 && c > 0; i--) {
    nonce[i] = c & 0xff;
    c >>= 8;
  }
  nonce[11] = last ? 1 : 0;
  return nonce;
}

Uint8List _seal(List<int> key, List<int> nonce, List<int> plaintext) {
  final SecretBox box = _chacha.encryptSync(
    plaintext,
    secretKey: SecretKeyData(key),
    nonce: nonce,
  );
  final Uint8List out = Uint8List(box.cipherText.length + _tagSize)
    ..setRange(0, box.cipherText.length, box.cipherText)
    ..setRange(
      box.cipherText.length,
      box.cipherText.length + _tagSize,
      box.mac.bytes,
    );
  return out;
}

/// Null when the tag does not authenticate.
Uint8List? _open(List<int> key, List<int> nonce, Uint8List sealed) {
  if (sealed.length < _tagSize) return null;
  final int split = sealed.length - _tagSize;
  try {
    final List<int> plain = _chacha.decryptSync(
      SecretBox(
        Uint8List.sublistView(sealed, 0, split),
        nonce: nonce,
        mac: Mac(Uint8List.sublistView(sealed, split)),
      ),
      secretKey: SecretKeyData(key),
    );
    return plain is Uint8List ? plain : Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    return null;
  }
}

/// HKDF-SHA-256 with a 32-byte output (RFC 5869; one expand block). An empty salt equals a zero
/// salt of hash length, because HMAC pads its key with zeros.
Uint8List _hkdf(List<int> ikm, List<int> salt, String info) {
  final List<int> prk = _hmac(salt, ikm);
  return Uint8List.fromList(_hmac(prk, [...utf8.encode(info), 1]));
}

List<int> _hmac(List<int> key, List<int> data) =>
    crypto.Hmac(crypto.sha256, key).convert(data).bytes;

Uint8List _scrypt(String passphrase, Uint8List salt, int workFactor) {
  final Scrypt scrypt = Scrypt()
    ..init(
      ScryptParameters(
        1 << workFactor,
        8,
        1,
        32,
        Uint8List.fromList([...ascii.encode(_scryptLabel), ...salt]),
      ),
    );
  // UTF-8, as the official CLI reads it — `dage` used UTF-16 code units and broke Polish passphrases.
  return scrypt.process(Uint8List.fromList(utf8.encode(passphrase)));
}

Uint8List _x25519(Uint8List scalar, Uint8List point) {
  final SecretKey shared = _x25519Algorithm.sharedSecretSync(
    keyPairData: SimpleKeyPairData(
      scalar,
      publicKey: SimplePublicKey(Uint8List(32), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    ),
    remotePublicKey: SimplePublicKey(point, type: KeyPairType.x25519),
  );
  return Uint8List.fromList((shared as SecretKeyData).bytes);
}

({String hrp, Uint8List data}) _decodeKey(String text) {
  try {
    return bech32Decode(text.trim());
  } on FormatException {
    throw const FormatException('Not a valid age key');
  }
}

/// Unpadded base64; null unless canonical (spec: decoders MUST reject non-canonical encodings).
Uint8List? _decodeBase64(String text) {
  if (!_isBase64Alphabet(text) || text.length % 4 == 1) return null;
  final Uint8List bytes;
  try {
    bytes = base64.decode(text.padRight((text.length + 3) ~/ 4 * 4, '='));
  } on FormatException {
    return null;
  }
  return _encodeBase64(bytes) == text ? bytes : null;
}

String _encodeBase64(List<int> bytes) =>
    base64.encode(bytes).replaceAll('=', '');

final RegExp _base64Alphabet = RegExp(r'^[A-Za-z0-9+/]*$');
bool _isBase64Alphabet(String text) => _base64Alphabet.hasMatch(text);

bool _isVisibleAscii(String text) =>
    text.codeUnits.every((c) => c >= 0x21 && c <= 0x7e);

bool _isAllZero(List<int> bytes) => bytes.every((b) => b == 0);

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));
