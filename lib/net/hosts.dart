/// The only addresses the app ever talks to (NFR-005 → Notes; ADR-003 pkt 4; ISSUE-027 D4). The app has
/// the INTERNET permission for two things alone: a cemetery's plan from OpenStreetMap, downloaded once, and
/// the photo from above from GUGiK, shown online and never kept. Every address is here, every one is
/// `https`, and no family data goes to any of them: the plan query carries the cemetery's public point, the
/// photo the tiles around it. What a server learns is that this phone looks at that area (ADR-003 →
/// Consequences).
///
/// A new address is a decision of the author, not a line of code.
abstract final class Hosts {
  /// Overpass API instances for a cemetery's plan, asked in this order (D4). Both are run by the
  /// OpenStreetMap community in Germany. Their rules: about 10 000 requests a day; the app makes two per
  /// cemetery, once (https://dev.overpass-api.de/overpass-doc/en/preface/commons.html).
  static final List<Uri> overpass = [
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://overpass.private.coffee/api/interpreter'),
  ];

  /// GUGiK's orthophoto, WMTS `StandardResolution`, the EPSG:3857 tile matrix set, levels 0–19 — the
  /// web-mercator grid of the map itself (SPIKE-001 M7; read from GetCapabilities before ISSUE-027).
  static const String orthophotoTiles =
      'https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMTS/StandardResolution'
      '?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTOFOTOMAPA&STYLE=default'
      '&FORMAT=image/jpeg&TILEMATRIXSET=EPSG:3857&TILEMATRIX=EPSG:3857:{z}'
      '&TILEROW={y}&TILECOL={x}';

  /// The host of [orthophotoTiles] — asked whether the photo can be shown at all.
  static const String orthophotoHost = 'mapy.geoportal.gov.pl';

  /// The deepest level of [orthophotoTiles].
  static const int orthophotoMaxZoom = 19;

  /// Who asks: the app and its public repository — never the person (an Overpass instance refuses a
  /// request without a User-Agent, 406, seen in the cemetery database extract).
  static const String userAgent =
      'Grobing (+https://github.com/aleksanderginalski/grobing-code)';
}
