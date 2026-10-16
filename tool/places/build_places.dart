// On a PC: builds assets/places/places.db — the countries and localities the residence's place is chosen
// from without the network (ISSUE-042, 05_DESIGN/zamieszkanie.md D7, elements 17–22).
//
// Localities: GeoNames (CC BY 4.0, https://www.geonames.org/) — every populated place of Poland, Ukraine,
// Belarus and Lithuania (the borders before 1945) and, for the world, the towns over 5000 people and the
// seats of units of the first order (`cities5000`; `cities1000` made the file 18 MB, over the 15 MB of the
// plan). Countries and their label points: Natural Earth 1:10m admin-0 (public domain). The app shows the
// source under the results, as CC BY asks.
//
// The file is NOT in the repository: `*.db` is in .gitignore (the family-data block), so the names of all
// these places — those on the content guard's list too — never reach a commit, and the guard stays as it
// is (ISSUE-042 → Implementation plan, G1). Build it before the first `flutter build` of a clean clone.
//
// The source files are not in the repository either. README → "Lista miejsc" has the addresses; unpack
// them into one directory:
//   PL.txt  UA.txt  BY.txt  LT.txt  cities5000.txt  alternateNamesV2.txt  admin1CodesASCII.txt
//   ne_10m_admin_0_countries.geojson
// then:
//   dart run tool/places/build_places.dart <that directory>

import 'dart:convert';
import 'dart:io';

import 'package:grobing/app/polish.dart';
import 'package:grobing/data/places.dart' show placeWords, shortKeyLength;
import 'package:sqlite3/sqlite3.dart';

/// Every populated place of these countries, not only the towns (the family's villages are there).
const List<String> _wholeCountries = ['PL', 'UA', 'BY', 'LT'];

/// A section of a city (a district) is not a locality: a residence names the city.
const Set<String> _notLocalities = {'PPLX'};

/// How much a resident of these countries weighs in the order of results: the family is Polish, so a
/// Polish town comes before a bigger city far away with the same start, while a world city still comes
/// before a Polish village (measured in ISSUE-042 → Dev report).
const Map<String, int> _countryWeight = {'PL': 10, 'UA': 3, 'BY': 3, 'LT': 3};

/// The order of results with the same weighted population: the capital, then seats of units, then the
/// rest — before the alphabet (GeoNames gives the population of towns, villages mostly have 0).
const Map<String, int> _featureRank = {
  'PPLC': 6,
  'PPLA': 5,
  'PPLA2': 4,
  'PPLA3': 3,
  'PPLA4': 2,
  'PPLA5': 2,
};

/// Units of the four countries GeoNames has no Polish name for (2026-10 dump).
const Map<String, String> _unitPolish = {
  'BY.01': 'obw. brzeski',
  'BY.02': 'obw. homelski',
  'BY.03': 'obw. grodzieński',
  'BY.06': 'obw. mohylewski',
  'UA.12': 'Kijów',
  'UA.20': 'Sewastopol',
};

/// Queries this short are answered from a table of their first results: a range of one letter is about
/// 60 thousand words, too many to sort at every key press (measured).
const int _shortKey = shortKeyLength;
const int _resultsKept = 30;

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/places/build_places.dart <directory with the source files>',
    );
    exit(64);
  }
  final String dir = args.single;
  final Stopwatch clock = Stopwatch()..start();

  // Countries — Natural Earth: the Polish name and the point where a map puts the country's label.
  final Map<String, Object?> ne =
      jsonDecode(
            File('$dir/ne_10m_admin_0_countries.geojson').readAsStringSync(),
          )
          as Map<String, Object?>;
  final Map<String, _Country> countries = {};
  for (final Map<String, Object?> f
      in (ne['features']! as List<Object?>).cast<Map<String, Object?>>()) {
    final Map<String, Object?> p = f['properties']! as Map<String, Object?>;
    final String code = p['ISO_A2_EH']! as String;
    final String? name = p['NAME_PL'] as String?;
    if (code == '-99' || name == null || name.isEmpty) continue;
    // A country in several features (none in 10m today) keeps the sovereign one.
    countries.putIfAbsent(
      code,
      () => _Country(
        code,
        name.trim(),
        (p['LABEL_Y']! as num).toDouble(),
        (p['LABEL_X']! as num).toDouble(),
      ),
    );
  }

  // Localities — the four countries whole, the world from cities5000; one row per GeoNames id.
  final Map<int, _Place> places = {};
  final Map<String, int> skippedCountry = {};
  void readPlaces(String file, {required bool all}) {
    for (final String line in File('$dir/$file').readAsLinesSync()) {
      final List<String> c = line.split('\t');
      if (c.length < 15 || c[6] != 'P' || _notLocalities.contains(c[7])) {
        continue;
      }
      final String country = c[8];
      if (!all && _wholeCountries.contains(country)) continue;
      if (!countries.containsKey(country)) {
        skippedCountry[country] = (skippedCountry[country] ?? 0) + 1;
        continue;
      }
      final int id = int.parse(c[0]);
      places[id] ??= _Place(
        id: id,
        name: c[1].trim(),
        ascii: c[2].trim(),
        otherNames: all && _wholeCountries.contains(country)
            ? _latinNames(c[3])
            : const [],
        lat: double.parse(c[4]),
        lon: double.parse(c[5]),
        feature: c[7],
        country: country,
        unitCode: c[10].isEmpty ? null : '$country.${c[10]}',
        population: int.tryParse(c[14]) ?? 0,
      );
    }
  }

  for (final String c in _wholeCountries) {
    readPlaces('$c.txt', all: true);
  }
  final int whole = places.length;
  readPlaces('cities5000.txt', all: false);

  // Units of the first order — their GeoNames ids, for their Polish names below.
  final Map<String, ({int id, String name})> units = {};
  for (final String line in File(
    '$dir/admin1CodesASCII.txt',
  ).readAsLinesSync()) {
    final List<String> c = line.split('\t');
    if (c.length < 4) continue;
    units[c[0]] = (id: int.parse(c[3]), name: c[1].trim());
  }

  // Polish names — of the localities and of the units. Read as a stream: the file is about 800 MB.
  final Set<int> wanted = {
    ...places.keys,
    for (final ({int id, String name}) u in units.values) u.id,
  };
  final Map<int, List<_AltName>> polish = {};
  await for (final String line in File(
    '$dir/alternateNamesV2.txt',
  ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.contains('\tpl\t')) continue;
    final List<String> c = line.split('\t');
    if (c.length < 8 || c[2] != 'pl') continue;
    final int id = int.parse(c[1]);
    if (!wanted.contains(id)) continue;
    (polish[id] ??= []).add(
      _AltName(
        c[3].trim(),
        preferred: c[4] == '1',
        short: c[5] == '1',
        colloquial: c[6] == '1',
        historic: c[7] == '1',
      ),
    );
  }

  // The unit's name shown in a result's second line: "woj. testowe", "obw. przykładowy".
  final Map<String, String> unitNames = {
    for (final MapEntry<String, ({int id, String name})> u in units.entries)
      u.key:
          _unitPolish[u.key] ??
          _unitShown(_shownPolish(polish[u.value.id]) ?? u.value.name),
  };

  // In the order of the results: population, the place's rank, then the Polish alphabet. The row's id
  // is that order, so the app sorts by an integer it already has.
  final List<_Place> ordered = places.values.toList();
  for (final _Place p in ordered) {
    final List<_AltName> pl = polish[p.id] ?? const [];
    p.shown = _shownPolish(pl) ?? p.name;
    p.searchNames = {
      p.shown,
      p.name,
      p.ascii,
      for (final _AltName a in pl) a.name,
      ...p.otherNames,
    };
  }
  int weighted(_Place p) => p.population * (_countryWeight[p.country] ?? 1);
  ordered.sort((a, b) {
    int c = weighted(b).compareTo(weighted(a));
    if (c != 0) return c;
    c = (_featureRank[b.feature] ?? 0).compareTo(_featureRank[a.feature] ?? 0);
    if (c != 0) return c;
    c = polishCompare(a.shown, b.shown);
    return c != 0 ? c : a.id.compareTo(b.id);
  });

  final File out = File('assets/places/places.db');
  final File partial = File('${out.path}.partial');
  out.parent.createSync(recursive: true);
  if (partial.existsSync()) partial.deleteSync();
  final Database db = sqlite3.open(partial.path);
  try {
    db.execute('PRAGMA journal_mode = OFF');
    db.execute('PRAGMA synchronous = OFF');
    db.execute('''
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
      CREATE TABLE countries (
        code TEXT PRIMARY KEY, name TEXT NOT NULL, lat INTEGER NOT NULL, lon INTEGER NOT NULL
      ) WITHOUT ROWID;
      CREATE TABLE units (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
      CREATE TABLE places (
        id INTEGER PRIMARY KEY,
        geonames_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        country TEXT NOT NULL,
        unit INTEGER,
        lat INTEGER NOT NULL,
        lon INTEGER NOT NULL
      );
      CREATE TABLE words (
        key TEXT NOT NULL, place INTEGER NOT NULL, first INTEGER NOT NULL,
        PRIMARY KEY (key, place)
      ) WITHOUT ROWID;
      CREATE TABLE short_keys (key TEXT PRIMARY KEY, places TEXT NOT NULL) WITHOUT ROWID;
    ''');
    db.execute('BEGIN');
    final PreparedStatement meta = db.prepare('INSERT INTO meta VALUES (?, ?)');
    String day(String file) => File(
      '$dir/$file',
    ).lastModifiedSync().toIso8601String().substring(0, 10);
    for (final List<String> m in [
      ['source', 'GeoNames (CC BY 4.0) · Natural Earth 1:10m admin-0'],
      ['geonames', day('cities5000.txt')],
      ['naturalEarth', day('ne_10m_admin_0_countries.geojson')],
      ['tool', 'tool/places/build_places.dart'],
    ]) {
      meta.execute(m);
    }
    meta.close();

    final PreparedStatement country = db.prepare(
      'INSERT INTO countries VALUES (?, ?, ?, ?)',
    );
    for (final _Country c in countries.values) {
      country.execute([c.code, c.name, _e4(c.lat), _e4(c.lon)]);
    }
    country.close();

    final Map<String, int> unitIds = {};
    final PreparedStatement unit = db.prepare(
      'INSERT INTO units (id, name) VALUES (?, ?)',
    );
    final PreparedStatement place = db.prepare(
      'INSERT INTO places VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    final PreparedStatement word = db.prepare(
      'INSERT OR REPLACE INTO words VALUES (?, ?, ?)',
    );
    int words = 0;
    // The first results of every key of up to [_shortKey] letters, as the search orders them: matches
    // at a name's start, then inside; rows come in the list's order, so the first kept are the first.
    final Map<String, (List<int>, List<int>)> short = {};
    for (int i = 0; i < ordered.length; i++) {
      final _Place p = ordered[i];
      final int rowId = i + 1;
      int? unitId;
      final String? unitName = unitNames[p.unitCode];
      if (unitName != null) {
        unitId = unitIds[p.unitCode!];
        if (unitId == null) {
          unitId = unitIds[p.unitCode!] = unitIds.length + 1;
          unit.execute([unitId, unitName]);
        }
      }
      place.execute([
        rowId,
        p.id,
        p.shown,
        p.country,
        unitId,
        _e4(p.lat),
        _e4(p.lon),
      ]);
      // A word start found at the start of a name ("first") is shown before one inside it.
      final Map<String, int> keys = {};
      for (final String name in p.searchNames) {
        final List<String> w = placeWords(name);
        for (int j = 0; j < w.length; j++) {
          final String key = w.sublist(j).join(' ');
          if (j == 0 || !keys.containsKey(key)) keys[key] = j == 0 ? 1 : 0;
        }
      }
      final Map<String, int> shortFirst = {};
      for (final MapEntry<String, int> k in keys.entries) {
        word.execute([k.key, rowId, k.value]);
        words++;
        for (int n = 1; n <= _shortKey && n <= k.key.length; n++) {
          final String s = k.key.substring(0, n).trimRight();
          if (s.length != n) continue;
          if ((shortFirst[s] ?? -1) < k.value) shortFirst[s] = k.value;
        }
      }
      for (final MapEntry<String, int> s in shortFirst.entries) {
        final (List<int> atStart, List<int> inside) = short[s.key] ??= ([], []);
        final List<int> into = s.value == 1 ? atStart : inside;
        if (into.length < _resultsKept) into.add(rowId);
      }
    }
    final PreparedStatement shortKey = db.prepare(
      'INSERT INTO short_keys VALUES (?, ?)',
    );
    for (final MapEntry<String, (List<int>, List<int>)> s in short.entries) {
      shortKey.execute([
        s.key,
        [...s.value.$1, ...s.value.$2].take(_resultsKept).join(','),
      ]);
    }
    shortKey.close();
    unit.close();
    place.close();
    word.close();
    db.execute('COMMIT');
    db.execute('VACUUM');
    stdout.writeln(
      'countries ${countries.length} · units ${unitIds.length} · places ${ordered.length} '
      '(whole ${_wholeCountries.join('/')} $whole, world cities5000 ${ordered.length - whole}) · '
      'Polish names ${ordered.where((p) => p.shown != p.name).length} · word rows $words',
    );
    if (skippedCountry.isNotEmpty) {
      stdout.writeln(
        'without a country in Natural Earth (skipped): '
        '${skippedCountry.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
      );
    }
  } finally {
    db.close();
  }
  if (out.existsSync()) out.deleteSync();
  partial.renameSync(out.path);
  stdout.writeln(
    '${out.lengthSync()} bytes → ${out.path} · ${clock.elapsed.inSeconds} s',
  );
}

/// The Polish name shown: the preferred one, else the first that is neither historic, colloquial nor
/// short. A historic Polish name ("Zmyślinów") stays a search word only.
String? _shownPolish(List<_AltName>? names) {
  if (names == null) return null;
  final List<_AltName> plain = [
    for (final _AltName a in names)
      if (!a.historic && !a.colloquial && a.name.isNotEmpty) a,
  ];
  for (final _AltName a in plain) {
    if (a.preferred) return a.name;
  }
  for (final _AltName a in plain) {
    if (!a.short) return a.name;
  }
  return plain.isEmpty ? null : plain.first.name;
}

/// "województwo testowe" → "woj. testowe", "Obwód przykładowy" → "obw. przykładowy" (05_DESIGN/
/// zamieszkanie.md, element 19), "Okręg zmyślony" → "okręg zmyślony" (GeoNames writes it both ways);
/// other units as they are.
String _unitShown(String name) {
  final String n = name.trim();
  final String lower = n.toLowerCase();
  for (final (String word, String short) in const [
    ('województwo ', 'woj. '),
    ('obwód ', 'obw. '),
    ('okręg ', 'okręg '),
  ]) {
    if (lower.startsWith(word)) return '$short${n.substring(word.length)}';
  }
  return n;
}

/// Other names of a village spelled the Polish way — GeoNames keeps the Polish spelling of many villages
/// of Ukraine, Belarus and Lithuania among the other names, without a language; the search finds them, the
/// result shows the name of the list. Only names with a Polish letter: the transliterations next to them
/// ("Vymyslanka", "Wymyslianka") tripled the words of these countries and nobody types them (measured).
List<String> _latinNames(String column) => [
  for (final String n in column.split(','))
    if (_latin.hasMatch(n.trim()) && _polishLetter.hasMatch(n)) n.trim(),
];

final RegExp _latin = RegExp(r"^[A-Za-zÀ-ɏ\s\-.']+$");
final RegExp _polishLetter = RegExp('[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]');

/// Degrees in integer tenths of a thousandth (about 11 m) — a locality's centre, 3–4 bytes in SQLite.
int _e4(double degrees) => (degrees * 10000).round();

class _Country {
  _Country(this.code, this.name, this.lat, this.lon);

  final String code, name;
  final double lat, lon;
}

class _AltName {
  _AltName(
    this.name, {
    required this.preferred,
    required this.short,
    required this.colloquial,
    required this.historic,
  });

  final String name;
  final bool preferred, short, colloquial, historic;
}

class _Place {
  _Place({
    required this.id,
    required this.name,
    required this.ascii,
    required this.otherNames,
    required this.lat,
    required this.lon,
    required this.feature,
    required this.country,
    required this.unitCode,
    required this.population,
  });

  final int id;
  final String name, ascii, feature, country;
  final List<String> otherNames;
  final double lat, lon;
  final String? unitCode;
  final int population;
  late String shown;
  late Set<String> searchNames;
}
