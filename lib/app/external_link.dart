import 'package:flutter/services.dart';

import '../data/cemeteries.dart';

const MethodChannel _channel = MethodChannel('grobing/external');

/// Opens a web address in another app (`ExternalLinks.kt`): Google Maps when installed, a browser
/// otherwise. Only ever after a tap — the other app loads the page, never this one (ISSUE-015 D1, D2;
/// NFR-005; the app's own addresses are in lib/net/hosts.dart, ISSUE-027). False when no app takes it.
Future<bool> openExternalUrl(String url) async {
  try {
    return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The system's screen for casting the phone's screen to a TV (`ExternalLinks.kt`; drzewo.md D29): the
/// system sends the picture, the app only opens the door — no Google Cast, nothing over the network from
/// here (NFR-005). False on a phone without that screen (ISSUE-036 AC-2).
Future<bool> openCastSettings() async {
  try {
    return await _channel.invokeMethod<bool>('openCastSettings') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// How long controls stay on the screen: [time], or longer when "Czas na działanie" in the accessibility
/// settings asks for more (`ExternalLinks.kt` — Android 10+; drzewo.md D40). [time] when the phone cannot say.
Future<Duration> recommendedTimeout(Duration time) async {
  try {
    // Read as any value: a channel that answers something else must not throw a cast error.
    final Object? ms = await _channel.invokeMethod<Object?>(
      'recommendedTimeout',
      {'ms': time.inMilliseconds},
    );
    return ms is int && ms > time.inMilliseconds
        ? Duration(milliseconds: ms)
        : time;
  } on PlatformException {
    return time;
  } on MissingPluginException {
    return time;
  }
}

/// The satellite photo of [point] in Google Maps. `geo:` cannot choose the layer — the Android canon
/// documents only `z` and `q` for it — while Maps URLs have `basemap=satellite` (ISSUE-015 D1).
String satelliteUrl(GeoPoint point) =>
    'https://www.google.com/maps/@?api=1&map_action=map'
    '&center=${point.lat.toStringAsFixed(5)},${point.lon.toStringAsFixed(5)}'
    '&zoom=17&basemap=satellite';
