import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'cemeteries.dart' show GeoPoint;
import 'folding.dart';

// The list a residence's place is chosen from without the network (ISSUE-042, 05_DESIGN/zamieszkanie.md D7):
// countries and localities in `assets/places/places.db`, built on a PC by tool/places/build_places.dart
// from GeoNames and Natural Earth. The file is not in git (README → Lista miejsc). Plain Dart and sqlite3,
// so the tool shares the words with the app; the screens copy the asset out (`app/person/place_list_asset.dart`).

/// A country of the list: its Polish name and the point a map puts its label at — the residence's point
/// when only the country is known (AC-1).
class ListedCountry {
  const ListedCountry({
    required this.code,
    required this.name,
    required this.point,
  });

  /// ISO 3166-1 alpha-2, as GeoNames and Natural Earth give it.
  final String code;
  final String name;
  final GeoPoint point;
}

/// A locality of the list: the Polish name when GeoNames has one, else the local one; its unit of the
/// first order and country tell apart villages of the same name (element 19).
class ListedPlace {
  const ListedPlace({
    required this.geonamesId,
    required this.name,
    required this.unit,
    required this.countryCode,
    required this.countryName,
    required this.point,
  });

  final int geonamesId;
  final String name;

  /// "woj. testowe", "obw. przykładowy" — null when GeoNames gives none.
  final String? unit;
  final String countryCode;
  final String countryName;
  final GeoPoint point;
}

/// The list, open read-only. Synchronous: one search reads a few pages of an index (measured in ISSUE-042
/// → Dev report).
class PlaceList {
  PlaceList(this._db)
    : countries = List.unmodifiable(
        <ListedCountry>[
          for (final Row r in _db.select(
            'SELECT code, name, lat, lon FROM countries',
          ))
            ListedCountry(
              code: r['code'] as String,
              name: r['name'] as String,
              point: GeoPoint(_deg(r['lat'] as int), _deg(r['lon'] as int)),
            ),
        ]..sort(
          (ListedCountry a, ListedCountry b) =>
              placeKey(a.name).compareTo(placeKey(b.name)),
        ),
      ) {
    _countryNames = {for (final ListedCountry c in countries) c.code: c.name};
  }

  /// Read through a memory map: the file never changes while open, and a search reads pages without a
  /// system call each.
  factory PlaceList.openFile(File file) => PlaceList(
    sqlite3.open(file.path, mode: OpenMode.readOnly)
      ..execute('PRAGMA mmap_size = 33554432'),
  );

  final Database _db;

  /// Every country, in the order of their folded names.
  final List<ListedCountry> countries;
  late final Map<String, String> _countryNames;

  /// Localities whose name — or another of their names — has words starting with the words of [query],
  /// in order ("nowe z" finds "Nowe Zmyślino", "zmys" too). A match at the start of a name comes first, then
  /// the list's own order: population, the seat of a unit, the alphabet (tool/places/build_places.dart).
  List<ListedPlace> search(String query, {int limit = 30}) {
    final String key = placeKey(query);
    if (key.isEmpty) return const [];
    if (key.length <= shortKeyLength) {
      // One or two letters match tens of thousands of words: their first results are kept in the list.
      final List<Row> kept = _db.select(
        'SELECT places FROM short_keys WHERE key = ?',
        [key],
      );
      if (kept.isEmpty) return const [];
      final List<int> ids = [
        for (final String id in (kept.single['places'] as String).split(','))
          int.parse(id),
      ].take(limit).toList();
      final Map<int, ListedPlace> byId = {
        for (final Row r in _db.select(
          '$_columns WHERE p.id IN (${List.filled(ids.length, '?').join(',')})',
          ids,
        ))
          r['id'] as int: _place(r),
      };
      return [for (final int id in ids) ?byId[id]];
    }
    // Ordered and cut on the index of words alone, then only the places shown are read: joining every place
    // of a wide range first ("nov" — 7.6 thousand words) took 89 ms on the emulator's cold disk (measured).
    return [
      for (final Row r in _db.select(
        '$_columns JOIN (SELECT place, max(first) AS first FROM words '
        'WHERE key >= ? AND key < ? GROUP BY place '
        'ORDER BY first DESC, place LIMIT ?) w ON w.place = p.id '
        'ORDER BY w.first DESC, p.id',
        [key, _after(key), limit],
      ))
        _place(r),
    ];
  }

  static const String _columns =
      'SELECT p.id, p.geonames_id, p.name, p.country, u.name AS unit, p.lat, p.lon '
      'FROM places p LEFT JOIN units u ON u.id = p.unit';

  ListedPlace _place(Row r) => ListedPlace(
    geonamesId: r['geonames_id'] as int,
    name: r['name'] as String,
    unit: r['unit'] as String?,
    countryCode: r['country'] as String,
    countryName:
        _countryNames[r['country'] as String] ?? r['country'] as String,
    point: GeoPoint(_deg(r['lat'] as int), _deg(r['lon'] as int)),
  );

  /// Countries whose Polish name has words starting with the words of [query]: those whose name starts
  /// with it ([CountryMatches.atStart] — from 3 letters they stand over the localities, zamieszkanie.md D8),
  /// and those matched by a later word (element 20).
  CountryMatches searchCountries(String query) {
    final String key = placeKey(query);
    if (key.isEmpty) return (atStart: const [], inside: const []);
    final List<ListedCountry> first = [], inside = [];
    for (final ListedCountry c in countries) {
      final List<String> words = placeWords(c.name);
      if (words.join(' ').startsWith(key)) {
        first.add(c);
      } else {
        for (int i = 1; i < words.length; i++) {
          if (words.sublist(i).join(' ').startsWith(key)) {
            inside.add(c);
            break;
          }
        }
      }
    }
    return (atStart: first, inside: inside);
  }

  /// The country of [code], if the list has it.
  ListedCountry? country(String code) {
    for (final ListedCountry c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  void close() => _db.close();
}

/// The countries a query matches, in two groups (zamieszkanie.md element 20, D8).
typedef CountryMatches = ({
  List<ListedCountry> atStart,
  List<ListedCountry> inside,
});

/// Keys up to this length are answered from the list's table `short_keys` (tool/places/build_places.dart).
const int shortKeyLength = 2;

/// What a name is searched by: its folded words joined by one space — "Testowo-Zmyślin" → "testowo zmyslin".
String placeKey(String name) => placeWords(name).join(' ');

/// The words of a place's name for matching: lower case, without Polish diacritics ([fold]) and without
/// those of other Latin alphabets ("Šimyslai" → "simyslai" — typed on a Polish keyboard), split at spaces,
/// hyphens, apostrophes, dots and brackets.
List<String> placeWords(String name) {
  final List<int> units = fold(name).codeUnits.toList();
  final StringBuffer plain = StringBuffer();
  for (final int u in units) {
    plain.write(_latin[u] ?? String.fromCharCode(u));
  }
  return [
    for (final String w in plain.toString().split(_separators))
      if (w.isNotEmpty) w,
  ];
}

final RegExp _separators = RegExp(r"[\s\-'’.,()/]+");

/// Lower-case letters of other Latin alphabets in GeoNames' names → their plain letters. Polish ones are
/// already folded.
const Map<int, String> _latin = {
  0xE0: 'a',
  0xE1: 'a',
  0xE2: 'a',
  0xE3: 'a',
  0xE4: 'a',
  0xE5: 'a',
  0x101: 'a',
  0x103: 'a', //
  0xE6: 'ae', 0xE7: 'c', 0x10D: 'c', 0x109: 'c', 0x10F: 'd', 0x111: 'd', //
  0xE8: 'e',
  0xE9: 'e',
  0xEA: 'e',
  0xEB: 'e',
  0x113: 'e',
  0x117: 'e',
  0x11B: 'e', //
  0x11F: 'g',
  0x123: 'g',
  0xEC: 'i',
  0xED: 'i',
  0xEE: 'i',
  0xEF: 'i',
  0x12B: 'i',
  0x12F: 'i',
  0x131: 'i', //
  0x137: 'k',
  0x13A: 'l',
  0x13C: 'l',
  0x13E: 'l',
  0xF1: 'n',
  0x146: 'n',
  0x148: 'n', //
  0xF2: 'o',
  0xF4: 'o',
  0xF5: 'o',
  0xF6: 'o',
  0xF8: 'o',
  0x14D: 'o',
  0x151: 'o',
  0x153: 'oe', //
  0x155: 'r', 0x159: 'r', 0x161: 's', 0x15F: 's', 0x219: 's', 0xDF: 'ss', //
  0x163: 't',
  0x165: 't',
  0x21B: 't',
  0xF9: 'u',
  0xFA: 'u',
  0xFB: 'u',
  0xFC: 'u',
  0x16B: 'u',
  0x16F: 'u', //
  0x171: 'u', 0x173: 'u', 0xFD: 'y', 0xFF: 'y', 0x17E: 'z', //
};

/// The first string after every string starting with [key]: its last character one higher — UTF-8 keeps
/// the order of code points, so the range `[key, after)` is every key with that start.
String _after(String key) =>
    key.substring(0, key.length - 1) +
    String.fromCharCode(key.codeUnitAt(key.length - 1) + 1);

/// The list keeps degrees as integer ten-thousandths (tool/places/build_places.dart).
double _deg(int e4) => e4 / 10000;
