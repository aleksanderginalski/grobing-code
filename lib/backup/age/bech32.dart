import 'dart:typed_data';

// Bech32 as age uses it: BIP173 without the 90-character limit, checksum always over the lowercase
// string (c2sp.org/age → Conventions; https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki).

const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const List<int> _generator = [
  0x3b6a57b2,
  0x26508e6d,
  0x1ea119fa,
  0x3d4233dd,
  0x2a1462b3,
];

/// Encodes [data] with the lowercase [hrp], e.g. `age` → `age1…`.
String bech32Encode(String hrp, List<int> data) {
  final List<int> values = _convertBits(data, 8, 5, pad: true);
  final List<int> checksum = _checksum(hrp, values);
  final StringBuffer out = StringBuffer('${hrp}1');
  for (final int v in [...values, ...checksum]) {
    out.write(_charset[v]);
  }
  return out.toString();
}

/// Decodes an all-lowercase or all-uppercase Bech32 string. Throws [FormatException].
({String hrp, Uint8List data}) bech32Decode(String text) {
  if (text != text.toLowerCase() && text != text.toUpperCase()) {
    throw const FormatException('Bech32 string mixes upper and lower case');
  }
  final String lower = text.toLowerCase();
  final int separator = lower.lastIndexOf('1');
  if (separator < 1 || separator + 7 > lower.length) {
    throw const FormatException('Bech32 separator in the wrong place');
  }
  final String hrp = lower.substring(0, separator);
  for (final int c in hrp.codeUnits) {
    if (c < 33 || c > 126) {
      throw const FormatException('Bech32 prefix has an invalid character');
    }
  }
  final List<int> values = [];
  for (final String c in lower.substring(separator + 1).split('')) {
    final int v = _charset.indexOf(c);
    if (v < 0) {
      throw const FormatException('Bech32 data has an invalid character');
    }
    values.add(v);
  }
  if (_polymod([..._expandHrp(hrp), ...values]) != 1) {
    throw const FormatException('Bech32 checksum does not match');
  }
  return (
    hrp: hrp,
    data: Uint8List.fromList(
      _convertBits(values.sublist(0, values.length - 6), 5, 8, pad: false),
    ),
  );
}

int _polymod(List<int> values) {
  int chk = 1;
  for (final int v in values) {
    final int top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (int i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) chk ^= _generator[i];
    }
  }
  return chk;
}

List<int> _expandHrp(String hrp) => [
  for (final int c in hrp.codeUnits) c >> 5,
  0,
  for (final int c in hrp.codeUnits) c & 31,
];

List<int> _checksum(String hrp, List<int> values) {
  final int mod =
      _polymod([..._expandHrp(hrp), ...values, 0, 0, 0, 0, 0, 0]) ^ 1;
  return [for (int i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
}

List<int> _convertBits(List<int> data, int from, int to, {required bool pad}) {
  int acc = 0;
  int bits = 0;
  final int maxValue = (1 << to) - 1;
  final int maxAcc = (1 << (from + to - 1)) - 1;
  final List<int> out = [];
  for (final int value in data) {
    if (value < 0 || value >> from != 0) {
      throw const FormatException('Bech32 value out of range');
    }
    acc = ((acc << from) | value) & maxAcc;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & maxValue);
    }
  }
  if (pad) {
    if (bits > 0) out.add((acc << (to - bits)) & maxValue);
  } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
    throw const FormatException('Bech32 data has invalid padding');
  }
  return out;
}
