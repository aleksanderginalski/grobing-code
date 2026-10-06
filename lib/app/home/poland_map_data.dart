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

/// The map of Poland bundled with the app (`assets/map/poland.json`, Natural Earth 1:10m, rebuilt by
/// `tool/map/extract_poland.dart`): nothing is fetched, so it draws offline from the first start
/// (ISSUE-014 AC-1).
class PolandMapData {
  PolandMapData({
    required this.outline,
    required this.rivers,
    required this.cities,
  }) : bounds = LatLngBounds.fromPoints(outline);

  factory PolandMapData.fromJson(String source) {
    final Map<String, Object?> json =
        jsonDecode(source) as Map<String, Object?>;
    LatLng point(Object? p) {
      final List<Object?> pair = p! as List<Object?>;
      return LatLng((pair[0]! as num).toDouble(), (pair[1]! as num).toDouble());
    }

    return PolandMapData(
      outline: (json['outline']! as List<Object?>).map(point).toList(),
      rivers: [
        for (final Object? line in json['rivers']! as List<Object?>)
          (line! as List<Object?>).map(point).toList(),
      ],
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

  /// Where the camera may be: the whole of Poland, and its centre never outside it.
  final LatLngBounds bounds;
}
