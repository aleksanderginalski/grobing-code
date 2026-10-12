import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A city label on the map of Poland (05_DESIGN/cmentarze.md, element 3).
class MapCity {
  const MapCity(this.name, this.point);

  final String name;
  final LatLng point;
}

/// A shape of water: its outer ring and its islands as holes.
class MapArea {
  const MapArea(this.outer, [this.holes = const []]);

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

/// The map of Poland bundled with the app (`assets/map/poland.json`, Natural Earth 1:10m, rebuilt by
/// `tool/map/extract_poland.dart`): nothing is fetched, so it draws offline from the first start
/// (ISSUE-014 AC-1). Since ISSUE-023 like R1: around Poland the sea, the lakes and the neighbours'
/// borders (05_DESIGN/cmentarze.md D29).
class PolandMapData {
  PolandMapData({
    required this.outline,
    required this.rivers,
    required this.cities,
    this.water = const [],
    this.lakes = const [],
    this.borders = const [],
  }) : bounds = LatLngBounds.fromPoints(outline);

  factory PolandMapData.fromJson(String source) {
    final Map<String, Object?> json =
        jsonDecode(source) as Map<String, Object?>;
    LatLng point(Object? p) {
      final List<Object?> pair = p! as List<Object?>;
      return LatLng((pair[0]! as num).toDouble(), (pair[1]! as num).toDouble());
    }

    List<LatLng> line(Object? l) => (l! as List<Object?>).map(point).toList();
    List<List<LatLng>> lines(String key) => [
      for (final Object? l in json[key] as List<Object?>? ?? const []) line(l),
    ];
    List<MapArea> areas(String key) => [
      for (final Object? a in json[key] as List<Object?>? ?? const [])
        if ((a! as List<Object?>).map(line).toList() case [
          final List<LatLng> outer,
          ...final List<List<LatLng>> holes,
        ])
          MapArea(outer, holes),
    ];

    return PolandMapData(
      outline: line(json['outline']),
      rivers: lines('rivers'),
      water: areas('water'),
      lakes: areas('lakes'),
      borders: lines('borders'),
      cities: [
        for (final Map<String, Object?> c
            in (json['cities']! as List<Object?>).cast<Map<String, Object?>>())
          MapCity(
            c['name']! as String,
            LatLng(
              (c['lat']! as num).toDouble(),
              (c['lon']! as num).toDouble(),
            ),
          ),
      ],
    );
  }

  static const String asset = 'assets/map/poland.json';

  static Future<PolandMapData> load([AssetBundle? bundle]) async =>
      PolandMapData.fromJson(await (bundle ?? rootBundle).loadString(asset));

  final List<LatLng> outline;
  final List<List<LatLng>> rivers;
  final List<MapCity> cities;

  /// The sea around Poland — the Baltic, and farther away the seas only the least zoom reaches.
  final List<MapArea> water;

  /// Lakes in Poland and the large ones abroad.
  final List<MapArea> lakes;

  /// The borders between the neighbours; Poland's own is [outline].
  final List<List<LatLng>> borders;

  /// Where the camera may be: the whole of Poland, and its centre never outside it.
  final LatLngBounds bounds;
}
