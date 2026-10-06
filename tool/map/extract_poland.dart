// On a PC: rebuilds assets/map/poland.json — the outline of Poland, its rivers and nine cities — from
// Natural Earth 1:10m (public domain, https://www.naturalearthdata.com/about/terms-of-use/). The app
// draws the map from this file alone, so the map of Poland works offline from the first start
// (ISSUE-014, ADR-007).
//
// The three source files are not in the repository. Download them from
// https://github.com/nvkelso/natural-earth-vector/tree/master/geojson into one directory:
//   ne_10m_admin_0_countries.geojson
//   ne_10m_rivers_lake_centerlines.geojson
//   ne_10m_populated_places_simple.geojson
// then:
//   dart run tool/map/extract_poland.dart <that directory>

import 'dart:convert';
import 'dart:io';

/// The cities on the map (05_DESIGN/cmentarze.md, element 3): Natural Earth's ASCII name → the Polish
/// one shown in the app. Voivodeship capitals spread over the whole country — orientation, not an atlas.
const Map<String, String> _cities = {
  'Szczecin': 'Szczecin',
  'Gdansk': 'Gdańsk',
  'Bialystok': 'Białystok',
  'Poznan': 'Poznań',
  'Warsaw': 'Warszawa',
  'Lodz': 'Łódź',
  'Wroclaw': 'Wrocław',
  'Lublin': 'Lublin',
  'Krakow': 'Kraków',
};

/// Rivers up to this Natural Earth rank: the Vistula, the Oder and their main tributaries.
const int _maxRiverRank = 7;

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/map/extract_poland.dart <directory with the Natural Earth files>',
    );
    exit(64);
  }
  final String dir = args.single;
  Map<String, Object?> read(String name) =>
      jsonDecode(File('$dir/$name.geojson').readAsStringSync())
          as Map<String, Object?>;
  List<Map<String, Object?>> features(Map<String, Object?> collection) =>
      (collection['features']! as List<Object?>).cast<Map<String, Object?>>();
  Map<String, Object?> props(Map<String, Object?> f) =>
      f['properties']! as Map<String, Object?>;

  // Outline: the single polygon of Poland (Natural Earth has no islands for it at 1:10m).
  final Map<String, Object?> poland = features(
    read('ne_10m_admin_0_countries'),
  ).singleWhere((f) => props(f)['ADM0_A3'] == 'POL');
  final Map<String, Object?> geometry =
      poland['geometry']! as Map<String, Object?>;
  final List<Object?> polygon = geometry['type'] == 'MultiPolygon'
      ? ((geometry['coordinates']! as List<Object?>).single! as List<Object?>)
      : geometry['coordinates']! as List<Object?>;
  final List<List<double>> ring = _points(polygon.first!);

  // Rivers: kept only inside the outline, cut where they leave it.
  final List<List<List<double>>> rivers = [];
  for (final Map<String, Object?> f in features(
    read('ne_10m_rivers_lake_centerlines'),
  )) {
    final Object? rank = props(f)['scalerank'];
    final Map<String, Object?>? g = f['geometry'] as Map<String, Object?>?;
    if (g == null || rank is! num || rank > _maxRiverRank) continue;
    final List<Object?> lines = g['type'] == 'MultiLineString'
        ? g['coordinates']! as List<Object?>
        : [g['coordinates']];
    for (final Object? line in lines) {
      List<List<double>> current = [];
      for (final List<double> p in _points(line!)) {
        if (_inside(p, ring)) {
          current.add(p);
        } else {
          if (current.length > 1) rivers.add(current);
          current = [];
        }
      }
      if (current.length > 1) rivers.add(current);
    }
  }

  final List<Map<String, Object>> cities = [];
  for (final Map<String, Object?> f in features(
    read('ne_10m_populated_places_simple'),
  )) {
    final Map<String, Object?> p = props(f);
    final String? polish = _cities[p['nameascii']];
    if (polish == null || p['adm0_a3'] != 'POL') continue;
    cities.add({
      'name': polish,
      'lat': _round((p['latitude']! as num).toDouble()),
      'lon': _round((p['longitude']! as num).toDouble()),
    });
  }
  if (cities.length != _cities.length) {
    stderr.writeln(
      'Expected ${_cities.length} cities, found ${cities.length}.',
    );
    exit(1);
  }

  List<List<double>> latLon(List<List<double>> line) => [
    for (final List<double> p in line) [_round(p[1]), _round(p[0])],
  ];
  final Map<String, Object> out = {
    'source':
        'Natural Earth 1:10m (public domain) — tool/map/extract_poland.dart',
    'outline': latLon(ring),
    'rivers': [for (final List<List<double>> r in rivers) latLon(r)],
    'cities': cities,
  };
  final File file = File('assets/map/poland.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(out));
  stdout.writeln(
    'outline ${ring.length} points · rivers ${rivers.length} lines · '
    'cities ${cities.length} · ${file.lengthSync()} bytes → ${file.path}',
  );
}

/// GeoJSON positions are `[lon, lat]`.
List<List<double>> _points(Object line) => [
  for (final Object? p in line as List<Object?>)
    [
      ((p! as List<Object?>)[0]! as num).toDouble(),
      ((p as List<Object?>)[1]! as num).toDouble(),
    ],
];

/// Ray casting, `[lon, lat]` against `[lon, lat]` ring.
bool _inside(List<double> p, List<List<double>> ring) {
  bool inside = false;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final double xi = ring[i][0], yi = ring[i][1];
    final double xj = ring[j][0], yj = ring[j][1];
    if ((yi > p[1]) != (yj > p[1]) &&
        p[0] < (xj - xi) * (p[1] - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// Four decimal places: about 10 m, far below what the map of Poland can show.
double _round(double v) => (v * 10000).round() / 10000;
