import 'dart:io';
import 'dart:typed_data';

/// A made-up "gravestone photo" for the debug data (ISSUE-016): drawn here, pixel by pixel — a grey
/// stone with a darker plate on a green background and gravel below. Never a photo from a disk or the
/// network (family-data.md), and no image file in the repo (the family-data guard refuses those).
/// [batch] shifts the colours a little, so batches can be told apart.
Uint8List fictionalGravestonePng(
  int batch, {
  int width = 480,
  int height = 360,
}) {
  final Uint8List rgb = Uint8List(width * height * 3);
  final int tint = (batch * 23) % 40;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final double fx = x / width;
      final double fy = y / height;
      final bool stone = fx > 0.25 && fx < 0.75 && fy > 0.18 && fy < 0.78;
      final bool plate = fx > 0.36 && fx < 0.64 && fy > 0.30 && fy < 0.62;
      final bool ground = fy >= 0.78;
      final (int r, int g, int b) = plate
          ? (52, 54, 58)
          : stone
          ? (128 + tint, 130 + tint, 134 + tint)
          : ground
          ? (104 + (x * 7 + y * 13) % 18, 98 + (x * 11 + y * 5) % 16, 88)
          : (60, 80 + (y % 9), 62);
      final int i = (y * width + x) * 3;
      rgb[i] = r;
      rgb[i + 1] = g;
      rgb[i + 2] = b;
    }
  }
  return _png(width, height, rgb);
}

/// Made-up "old photos" of people for the debug data (ISSUE-017), drawn like the gravestone: a sepia
/// ground and [heads] simple figures — a head and shoulders each. One figure is a "portrait", two a
/// "wedding photo" to share between two made-up people. Nobody is meant.
Uint8List fictionalPeoplePng(
  int batch, {
  required int heads,
  int width = 480,
  int height = 360,
}) {
  final Uint8List rgb = Uint8List(width * height * 3);
  final int tint = (batch * 17) % 30;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final double fx = x / width;
      final double fy = y / height;
      (int, int, int) colour = (
        150 - (fy * 70).round() + tint,
        128 - (fy * 60).round() + tint,
        96 - (fy * 45).round(),
      );
      for (int h = 0; h < heads; h++) {
        final double cx = (h + 1) / (heads + 1);
        final double dx = (fx - cx) * width / height;
        final bool head =
            dx * dx / 0.012 + (fy - 0.36) * (fy - 0.36) / 0.022 <= 1;
        final bool shoulders =
            fy > 0.58 && dx * dx / 0.03 + (fy - 1.0) * (fy - 1.0) / 0.2 <= 1;
        if (head) colour = (214, 192, 156);
        if (shoulders) colour = (58 + h * 20, 48 + h * 18, 38 + h * 14);
      }
      final int i = (y * width + x) * 3;
      rgb[i] = colour.$1;
      rgb[i + 1] = colour.$2;
      rgb[i + 2] = colour.$3;
    }
  }
  return _png(width, height, rgb);
}

/// A minimal PNG (truecolour, 8 bits, no filter): signature, IHDR, IDAT, IEND.
Uint8List _png(int width, int height, Uint8List rgb) {
  final BytesBuilder raw = BytesBuilder(copy: false);
  for (int y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    raw.add(Uint8List.sublistView(rgb, y * width * 3, (y + 1) * width * 3));
  }
  final ByteData header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return (BytesBuilder(copy: false)
        ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', Uint8List.fromList(zlib.encode(raw.takeBytes()))))
        ..add(_chunk('IEND', Uint8List(0))))
      .takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final Uint8List typeBytes = Uint8List.fromList(type.codeUnits);
  final ByteData length = ByteData(4)..setUint32(0, data.length);
  final ByteData crc = ByteData(4)
    ..setUint32(0, _crc32([...typeBytes, ...data]));
  return (BytesBuilder(copy: false)
        ..add(length.buffer.asUint8List())
        ..add(typeBytes)
        ..add(data)
        ..add(crc.buffer.asUint8List()))
      .takeBytes();
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  int c = 0xFFFFFFFF;
  for (final int b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
