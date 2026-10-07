import 'package:flutter/services.dart';

import '../data/cemeteries.dart';

const MethodChannel _channel = MethodChannel('grobing/external');

/// Opens a web address in another app (`ExternalLinks.kt`): Google Maps when installed, a browser
/// otherwise. Only ever after a tap — the app itself has no INTERNET permission, the other app loads the
/// page (ISSUE-015 D1, D2; NFR-005). False when no app takes it.
Future<bool> openExternalUrl(String url) async {
  try {
    return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The satellite photo of [point] in Google Maps. `geo:` cannot choose the layer — the Android canon
/// documents only `z` and `q` for it — while Maps URLs have `basemap=satellite` (ISSUE-015 D1).
String satelliteUrl(GeoPoint point) =>
    'https://www.google.com/maps/@?api=1&map_action=map'
    '&center=${point.lat.toStringAsFixed(5)},${point.lon.toStringAsFixed(5)}'
    '&zoom=17&basemap=satellite';
