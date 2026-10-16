import 'dart:io';

import 'package:grobing/data/places.dart';
import 'package:sqlite3/sqlite3.dart';

// A made-up list of places in the layout tool/places/build_places.dart writes (ISSUE-042) — for tests of
// lib/data/places.dart and of the choice of a place, never the real asset: the real list is not in git, and
// its names are real places. Words as the tool makes them (placeWords), short keys of up to
// [shortKeyLength] letters as the tool keeps them. Made-up names only (family-data.md).

typedef FakeCountry = ({String code, String name, double lat, double lon});

class FakePlace {
  const FakePlace(
    this.name, {
    required this.country,
    this.unit,
    this.lat = 50,
    this.lon = 20,
    this.otherNames = const [],
  });

  final String name;
  final String country;
  final String? unit;
  final double lat, lon;

  /// Search words only — a local or historic name ("Zmyślinów"); the row shows [name].
  final List<String> otherNames;
}

/// Writes the list to `places.db` in [dir]: [places] in the order of results (their rank), GeoNames ids
/// 9000001, 9000002, … in the same order.
File writeFakePlaceList(
  Directory dir, {
  required List<FakeCountry> countries,
  required List<FakePlace> places,
}) {
  final File file = File('${dir.path}/places.db');
  if (file.existsSync()) file.deleteSync();
  final Database db = sqlite3.open(file.path);
  db.execute('''
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE countries (
      code TEXT PRIMARY KEY, name TEXT NOT NULL, lat INTEGER NOT NULL, lon INTEGER NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE units (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE places (
      id INTEGER PRIMARY KEY, geonames_id INTEGER NOT NULL, name TEXT NOT NULL, country TEXT NOT NULL,
      unit INTEGER, lat INTEGER NOT NULL, lon INTEGER NOT NULL
    );
    CREATE TABLE words (
      key TEXT NOT NULL, place INTEGER NOT NULL, first INTEGER NOT NULL, PRIMARY KEY (key, place)
    ) WITHOUT ROWID;
    CREATE TABLE short_keys (key TEXT PRIMARY KEY, places TEXT NOT NULL) WITHOUT ROWID;
  ''');
  int e4(double d) => (d * 10000).round();
  for (final FakeCountry c in countries) {
    db.execute('INSERT INTO countries VALUES (?, ?, ?, ?)', [
      c.code,
      c.name,
      e4(c.lat),
      e4(c.lon),
    ]);
  }
  final Map<String, int> units = {};
  final Map<String, (List<int>, List<int>)> short = {};
  for (final (int i, FakePlace p) in places.indexed) {
    final int id = i + 1;
    int? unit;
    if (p.unit case final String name) {
      unit = units[name] ??= units.length + 1;
      db.execute('INSERT OR IGNORE INTO units VALUES (?, ?)', [unit, name]);
    }
    db.execute('INSERT INTO places VALUES (?, ?, ?, ?, ?, ?, ?)', [
      id,
      9000000 + id,
      p.name,
      p.country,
      unit,
      e4(p.lat),
      e4(p.lon),
    ]);
    final Map<String, int> keys = {};
    for (final String name in [p.name, ...p.otherNames]) {
      final List<String> w = placeWords(name);
      for (int j = 0; j < w.length; j++) {
        final String key = w.sublist(j).join(' ');
        if (j == 0 || !keys.containsKey(key)) keys[key] = j == 0 ? 1 : 0;
      }
    }
    final Map<String, int> shortFirst = {};
    for (final MapEntry<String, int> k in keys.entries) {
      db.execute('INSERT INTO words VALUES (?, ?, ?)', [k.key, id, k.value]);
      for (int n = 1; n <= shortKeyLength && n <= k.key.length; n++) {
        final String s = k.key.substring(0, n).trimRight();
        if (s.length != n) continue;
        if ((shortFirst[s] ?? -1) < k.value) shortFirst[s] = k.value;
      }
    }
    for (final MapEntry<String, int> s in shortFirst.entries) {
      final (List<int> atStart, List<int> inside) = short[s.key] ??= ([], []);
      (s.value == 1 ? atStart : inside).add(id);
    }
  }
  for (final MapEntry<String, (List<int>, List<int>)> s in short.entries) {
    db.execute('INSERT INTO short_keys VALUES (?, ?)', [
      s.key,
      [...s.value.$1, ...s.value.$2].take(30).join(','),
    ]);
  }
  db.close();
  return file;
}

/// The made-up countries the tests use.
const List<FakeCountry> fakeCountries = [
  (code: 'XA', name: 'Kraj Wymyślony', lat: 49.5, lon: 31.5),
  (code: 'XB', name: 'Kraj Przykładowy', lat: 52.1, lon: 19.4),
  (code: 'XC', name: 'Wymyślonia', lat: 47.25, lon: 9.75),
];

/// The made-up localities the tests use, in the order of results.
const List<FakePlace> fakePlaces = [
  FakePlace(
    'Zmyślin',
    country: 'XB',
    unit: 'woj. testowe',
    lat: 51.25,
    lon: 22.5,
    otherNames: ['Zmyślinów'],
  ),
  FakePlace('Zmyślin', country: 'XA', unit: 'obw. przykładowy'),
  FakePlace('Nowe Zmyślino', country: 'XB', unit: 'woj. testowe'),
  FakePlace(
    'Wymyślowo',
    country: 'XA',
    unit: 'obw. przykładowy',
    otherNames: ['Vymyslovo'],
  ),
  FakePlace('Przezmyślonek', country: 'XB'),
  FakePlace('Testowo-Zmyślin', country: 'XB', unit: 'woj. testowe'),
  FakePlace('Šimyslai', country: 'XC'),
];
