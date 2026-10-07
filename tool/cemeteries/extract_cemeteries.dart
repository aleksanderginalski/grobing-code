// On a PC: rebuilds assets/cemeteries/poland_cemeteries.json — the cemeteries of Poland from
// OpenStreetMap, each with its locality and voivodeship — so a cemetery can be added from a database
// without the network (ISSUE-015; 05_DESIGN/cmentarze.md, elements 12–14).
//
// Data © autorzy OpenStreetMap, ODbL 1.0 (https://www.openstreetmap.org/copyright). The extract is a
// derived database, so it is published under the same licence, and the app shows the attribution under
// the results. Voivodeships: Natural Earth 1:10m (public domain).
//
// The three source files are not in the repository. README → "Baza cmentarzy" has the two Overpass
// queries and the Natural Earth address; put the files into one directory:
//   osm_cemeteries.json
//   osm_places.json
//   ne_10m_admin_1_states_provinces.geojson
// then:
//   dart run tool/cemeteries/extract_cemeteries.dart <that directory>

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:grobing/app/polish.dart';

/// How far a place reaches, in km: the locality shown is the place with the least distance divided by
/// its reach, so a town 3 km away wins over a hamlet 1 km away (ISSUE-014 D9, measured: 7 of 8; plain
/// nearest: 5 of 8). Every place within its reach is also a search word (8 of 8).
const Map<String, double> _reach = {
  'city': 12,
  'town': 5,
  'village': 2.5,
  'hamlet': 1.5,
  'suburb': 2.5,
};

/// Places a cemetery can be "in"; a suburb is only a district in brackets (05_DESIGN/cmentarze.md,
/// element 12: "w mieście z dzielnicą w nawiasie").
const Set<String> _settlements = {'city', 'town', 'village', 'hamlet'};
const Set<String> _withDistricts = {'city', 'town'};

/// Same name (or both unnamed) and same locality closer than this: one cemetery mapped twice
/// (ISSUE-015 D6; the falsifier: 16 532 objects → 16 043 cemeteries).
const double _mergeKm = 0.3;

/// Tags with other names people use — the colloquial one is often in `loc_name` ("Stare Powązki").
const List<String> _otherNames = [
  'alt_name',
  'loc_name',
  'official_name',
  'short_name',
  'old_name',
  'name:pl',
];

const Map<String, String> _denominations = {
  'roman_catholic': 'rzymskokatolicki',
  'catholic': 'katolicki',
  'lutheran': 'ewangelicki',
  'evangelical': 'ewangelicki',
  'orthodox': 'prawosławny',
  'russian_orthodox': 'prawosławny',
  'polish_orthodox': 'prawosławny',
  'greek_catholic': 'greckokatolicki',
  'old_catholic': 'starokatolicki',
  'mariavite': 'mariawicki',
  'protestant': 'protestancki',
  'baptist': 'baptystyczny',
  'methodist': 'metodystyczny',
};

const Map<String, String> _religions = {
  'christian': 'chrześcijański',
  'jewish': 'żydowski',
  'muslim': 'muzułmański',
};

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/cemeteries/extract_cemeteries.dart <directory with the source files>',
    );
    exit(64);
  }
  final String dir = args.single;
  Map<String, Object?> read(String name) =>
      jsonDecode(File('$dir/$name').readAsStringSync()) as Map<String, Object?>;

  final Map<String, Object?> cemeteryFile = read('osm_cemeteries.json');
  final String osmBase =
      (cemeteryFile['osm3s']! as Map<String, Object?>)['timestamp_osm_base']!
          as String;
  final List<Map<String, Object?>> elements =
      (cemeteryFile['elements']! as List<Object?>).cast();

  final _Grid places = _Grid();
  for (final Map<String, Object?> e
      in (read('osm_places.json')['elements']! as List<Object?>)
          .cast<Map<String, Object?>>()) {
    final Map<String, Object?>? tags = e['tags'] as Map<String, Object?>?;
    final String? kind = tags?['place'] as String?;
    final String? name = (tags?['name'] ?? tags?['name:pl']) as String?;
    if (kind == null || name == null || !_reach.containsKey(kind)) continue;
    places.add(
      _Place(
        (e['lat']! as num).toDouble(),
        (e['lon']! as num).toDouble(),
        name.trim(),
        kind,
      ),
    );
  }

  final List<_Voivodeship> voivodeships = [
    for (final Map<String, Object?> f
        in (read('ne_10m_admin_1_states_provinces.geojson')['features']!
                as List<Object?>)
            .cast<Map<String, Object?>>())
      if ((f['properties']! as Map<String, Object?>)['adm0_a3'] == 'POL')
        _Voivodeship.fromFeature(f),
  ]..sort((a, b) => a.name.compareTo(b.name));
  if (voivodeships.length != 16) {
    stderr.writeln('Expected 16 voivodeships, found ${voivodeships.length}.');
    exit(1);
  }

  final List<_Row> rows = [];
  int outsideVoivodeships = 0, noLocality = 0;
  for (final Map<String, Object?> e in elements) {
    final Map<String, Object?>? center = e['center'] as Map<String, Object?>?;
    final double lat = ((center ?? e)['lat']! as num).toDouble();
    final double lon = ((center ?? e)['lon']! as num).toDouble();
    final Map<String, Object?> tags =
        (e['tags'] as Map<String, Object?>?) ?? const {};
    final String name = ((tags['name'] ?? tags['name:pl'] ?? '') as String)
        .trim();
    final Set<String> other = {
      for (final String key in _otherNames)
        for (final String v in ((tags[key] as String?) ?? '').split(';'))
          if (v.trim().isNotEmpty && v.trim() != name) v.trim(),
    };
    final String kind =
        _denominations[tags['denomination']] ??
        _religions[tags['religion']] ??
        '';

    final List<(_Place, double)> near = places.around(lat, lon);
    final _Place? locality = _locality(near);
    if (locality == null) noLocality++;
    String district = '';
    if (locality != null && _withDistricts.contains(locality.kind)) {
      (_Place, double)? best;
      for (final (_Place, double) n in near) {
        if (n.$1.kind == 'suburb' &&
            n.$2 <= _reach['suburb']! &&
            (best == null || n.$2 < best.$2)) {
          best = n;
        }
      }
      if (best != null && best.$1.name != locality.name) {
        district = best.$1.name;
      }
    }
    final Set<String> words = {
      for (final (_Place, double) n in near)
        if (n.$2 <= _reach[n.$1.kind]! &&
            n.$1.name != locality?.name &&
            n.$1.name != district)
          n.$1.name,
    };

    int voivodeship = voivodeships.indexWhere((v) => v.contains(lat, lon));
    if (voivodeship < 0) {
      // Just outside the coarse 1:10m border: the nearest voivodeship.
      outsideVoivodeships++;
      double best = double.infinity;
      for (int i = 0; i < voivodeships.length; i++) {
        final double d = voivodeships[i].distanceKm(lat, lon);
        if (d < best) {
          best = d;
          voivodeship = i;
        }
      }
    }

    rows.add(
      _Row(
        name: name,
        other: other,
        lat: lat,
        lon: lon,
        kind: kind,
        locality: locality?.name ?? '',
        district: district,
        voivodeship: voivodeship,
        words: words,
      ),
    );
  }

  // Merge one cemetery mapped twice (D6): sorted so its copies stand next to each other.
  rows.sort(
    (a, b) => _compare([a.locality, a.name], [b.locality, b.name]) != 0
        ? _compare([a.locality, a.name], [b.locality, b.name])
        : a.lat.compareTo(b.lat),
  );
  final List<_Row> kept = [];
  for (final _Row r in rows) {
    _Row? same;
    for (int i = kept.length - 1; i >= 0 && i >= kept.length - 30; i--) {
      final _Row k = kept[i];
      if (k.locality == r.locality &&
          k.name == r.name &&
          _km(k.lat, k.lon, r.lat, r.lon) < _mergeKm) {
        same = k;
        break;
      }
    }
    if (same == null) {
      kept.add(r);
    } else {
      same.other.addAll(r.other);
      same.words.addAll(r.words);
      if (same.kind.isEmpty) same.kind = r.kind;
    }
  }

  // In the order the results show them (lib/app/home/cemetery_base.dart, byShownName): the app only
  // checks it, instead of sorting 16 thousand names at the first search.
  String shown(_Row r) => r.name.isEmpty ? 'Cmentarz bez nazwy' : r.name;
  String place(_Row r) =>
      r.district.isEmpty ? r.locality : '${r.locality} (${r.district})';
  kept.sort((a, b) {
    final int c = polishCompare(shown(a), shown(b));
    return c != 0 ? c : polishCompare(place(a), place(b));
  });
  final List<String> kinds = {
    for (final _Row r in kept)
      if (r.kind.isNotEmpty) r.kind,
  }.toList()..sort();

  final Map<String, Object> out = {
    'source':
        'OpenStreetMap, Overpass API (landuse=cemetery, amenity=grave_yard in Poland), '
        'OSM base $osmBase; voivodeships: Natural Earth 1:10m admin-1 (public domain) — '
        'tool/cemeteries/extract_cemeteries.dart',
    'license':
        'ODbL 1.0 — © autorzy OpenStreetMap — https://www.openstreetmap.org/copyright',
    'osmBase': osmBase,
    'voivodeships': [for (final _Voivodeship v in voivodeships) v.name],
    'kinds': kinds,
    'fields': [
      'name',
      'otherNames',
      'lat',
      'lon',
      'kind',
      'locality',
      'district',
      'voivodeship',
      'nearby',
    ],
    'cemeteries': [
      for (final _Row r in kept)
        [
          r.name,
          r.other.toList()..sort(),
          _round(r.lat),
          _round(r.lon),
          r.kind.isEmpty ? -1 : kinds.indexOf(r.kind),
          r.locality,
          r.district,
          r.voivodeship,
          r.words.toList()..sort(),
        ],
    ],
  };
  final File file = File('assets/cemeteries/poland_cemeteries.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(out));
  final int named = kept.where((r) => r.name.isNotEmpty).length;
  stdout.writeln(
    'OSM base $osmBase · ${elements.length} objects → ${kept.length} cemeteries · '
    'named $named (${(100 * named / kept.length).round()}%) · '
    'voivodeship by distance $outsideVoivodeships · without locality $noLocality · '
    '${file.lengthSync()} bytes → ${file.path}',
  );
}

/// The locality shown: the settlement with the least distance divided by its reach (D9 of ISSUE-014).
_Place? _locality(List<(_Place, double)> near) {
  _Place? best;
  double bestScore = double.infinity;
  for (final (_Place p, double d) in near) {
    if (!_settlements.contains(p.kind)) continue;
    final double score = d / _reach[p.kind]!;
    if (score < bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

int _compare(List<String> a, List<String> b) {
  for (int i = 0; i < a.length; i++) {
    final int c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

class _Place {
  _Place(this.lat, this.lon, this.name, this.kind);

  final double lat, lon;
  final String name, kind;
}

class _Row {
  _Row({
    required this.name,
    required this.other,
    required this.lat,
    required this.lon,
    required this.kind,
    required this.locality,
    required this.district,
    required this.voivodeship,
    required this.words,
  });

  final String name;
  final Set<String> other;
  final double lat, lon;
  String kind;
  final String locality, district;
  final int voivodeship;
  final Set<String> words;
}

/// Places in cells of 0.1°, so a cemetery looks only at its neighbourhood.
class _Grid {
  final Map<int, List<_Place>> _cells = {};

  static int _key(int i, int j) => i * 10000 + j;

  void add(_Place p) => _cells
      .putIfAbsent(_key((p.lat * 10).floor(), (p.lon * 10).floor()), () => [])
      .add(p);

  /// Places with their distance in km: two cells around (at least 14 km — more than a city's
  /// reach), wider while nothing settled is found.
  List<(_Place, double)> around(double lat, double lon) {
    final int ci = (lat * 10).floor(), cj = (lon * 10).floor();
    for (final int r in const [2, 5, 10]) {
      final List<(_Place, double)> found = [
        for (int i = ci - r; i <= ci + r; i++)
          for (int j = cj - r; j <= cj + r; j++)
            for (final _Place p in _cells[_key(i, j)] ?? const <_Place>[])
              (p, _km(lat, lon, p.lat, p.lon)),
      ];
      if (found.any((n) => _settlements.contains(n.$1.kind))) return found;
    }
    return const [];
  }
}

class _Voivodeship {
  _Voivodeship(this.name, this.ring);

  factory _Voivodeship.fromFeature(Map<String, Object?> f) {
    final Map<String, Object?> props = f['properties']! as Map<String, Object?>;
    final Map<String, Object?> g = f['geometry']! as Map<String, Object?>;
    final List<Object?> polygon = g['type'] == 'MultiPolygon'
        ? ((g['coordinates']! as List<Object?>).first! as List<Object?>)
        : g['coordinates']! as List<Object?>;
    return _Voivodeship(
      (props['name_pl']! as String).replaceFirst('województwo ', ''),
      [
        for (final Object? p in polygon.first! as List<Object?>)
          [
            ((p! as List<Object?>)[0]! as num).toDouble(),
            ((p as List<Object?>)[1]! as num).toDouble(),
          ],
      ],
    );
  }

  final String name;

  /// `[lon, lat]`, the outer ring (Natural Earth gives each voivodeship one polygon).
  final List<List<double>> ring;

  bool contains(double lat, double lon) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final double xi = ring[i][0], yi = ring[i][1];
      final double xj = ring[j][0], yj = ring[j][1];
      if ((yi > lat) != (yj > lat) &&
          lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  double distanceKm(double lat, double lon) =>
      ring.map((p) => _km(lat, lon, p[1], p[0])).reduce(math.min);
}

/// Equirectangular distance — exact enough within tens of kilometres.
double _km(double lat1, double lon1, double lat2, double lon2) {
  final double x =
      (lon2 - lon1) *
      math.pi /
      180 *
      math.cos((lat1 + lat2) / 2 * math.pi / 180);
  final double y = (lat2 - lat1) * math.pi / 180;
  return 6371 * math.sqrt(x * x + y * y);
}

/// Five decimal places: about 1 m.
double _round(double v) => (v * 100000).round() / 100000;
