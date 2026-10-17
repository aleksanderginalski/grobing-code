import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// One country of the world map: its shapes, and — when Natural Earth gives them — its code and Polish name.
class WorldCountry {
  const WorldCountry({
    this.code,
    this.name,
    required this.label,
    required this.rings,
  });

  /// ISO 3166-1 alpha-2, as the list of places keeps a residence's country.
  final String? code;
  final String? name;

  /// Where Natural Earth puts the country's name — and where a residence known only to its country stands
  /// (05_DESIGN/mapa-migracji.md, element 6 — O3).
  final LatLng label;

  /// The outer rings of its land, simplified (tool/map/extract_world.dart).
  final List<List<LatLng>> rings;
}

/// The world bundled with the app for the migration map (`assets/map/world.json`, Natural Earth 1:10m,
/// rebuilt by `tool/map/extract_world.dart`; ISSUE-045): nothing is fetched, so it draws offline (AC-4).
class WorldMapData {
  WorldMapData(this.countries)
    : byCode = {
        for (final WorldCountry c in countries)
          if (c.code case final String code) code: c,
      };

  factory WorldMapData.fromJson(String source) {
    final Map<String, Object?> json =
        jsonDecode(source) as Map<String, Object?>;
    List<LatLng> ring(Object? flat) {
      final List<Object?> v = flat! as List<Object?>;
      return [
        for (int i = 0; i + 1 < v.length; i += 2)
          LatLng((v[i]! as num).toDouble(), (v[i + 1]! as num).toDouble()),
      ];
    }

    return WorldMapData([
      for (final Map<String, Object?> c
          in (json['countries']! as List<Object?>).cast<Map<String, Object?>>())
        WorldCountry(
          code: c['code'] as String?,
          name: c['name'] as String?,
          label: LatLng(
            ((c['label']! as List<Object?>)[0]! as num).toDouble(),
            ((c['label']! as List<Object?>)[1]! as num).toDouble(),
          ),
          rings: [
            for (final Object? r in c['rings']! as List<Object?>) ring(r),
          ],
        ),
    ]);
  }

  static const String asset = 'assets/map/world.json';

  /// Read once while the app runs, in the background: half a megabyte of numbers would hold up a frame.
  static Future<WorldMapData> load([AssetBundle? bundle]) async {
    if (bundle != null) return _read(bundle);
    // The data is kept, not the future: a future remembers the zone it was made in, and a later screen in another one
    // waited for it for ever (found by qa's widget tests). A failed read is not kept: the next screen tries again.
    return _loaded ??= await _read(rootBundle);
  }

  static WorldMapData? _loaded;

  static Future<WorldMapData> _read(AssetBundle bundle) async =>
      compute(WorldMapData.fromJson, await bundle.loadString(asset));

  final List<WorldCountry> countries;
  final Map<String, WorldCountry> byCode;
}
