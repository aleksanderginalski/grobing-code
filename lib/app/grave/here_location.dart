import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

// "Gdzie jestem" on the cemetery's map (ISSUE-029; 05_DESIGN/cmentarz.md v7, elements 10, 10a, 12): the
// phone's position from the GNSS satellites alone (`HereLocation.kt`, D2 A — no Google services, nothing
// leaves the phone), only while a screen listens. The position is never written to a log: in real use it
// is where the family lies (NFR-005).

/// Below this accuracy the dot is not worth trusting (element 12a). **Temporary** (cmentarz.md D37, the
/// author's decision of 2026-10-12): the measurement at three graves (CURRENT_STATE → Parked) sets it.
const double weakSignalM = 15;

/// What the phone lets the app know (Android 12+ asks "Dokładna" or "Przybliżona" — the runtime permission
/// canon in ISSUE-029 → Prior art).
enum HereAccess {
  /// The satellites' position.
  precise,

  /// "about 3 square kilometers" — useless at a cemetery: no dot (element 10a (c)).
  approximate,

  /// Not given; asking again may show the system's window.
  denied,

  /// Refused twice (Android 11+): the system no longer asks — only the app's settings help.
  blocked,
}

/// One reading of the phone: a position, or that location was switched off in the phone.
sealed class HereSignal {
  const HereSignal();
}

/// A position: the accuracy is the radius in metres at the 68th percentile (`Location.getAccuracy()`); null
/// when the phone gave none.
class HereFix extends HereSignal {
  const HereFix(this.point, this.accuracyM);

  final LatLng point;
  final double? accuracyM;
}

/// Location was switched off in the phone (or back on: [on]).
class HereSwitched extends HereSignal {
  const HereSwitched({required this.on});

  final bool on;
}

/// The phone's position, behind an interface so the screens can be tested on a PC.
abstract interface class HereLocation {
  /// What the app may know now, without asking.
  Future<HereAccess> access();

  /// Asks the system — its window, when it still shows one; FINE and COARSE together (Android 12+).
  Future<HereAccess> request();

  /// Whether location is switched on in the phone.
  Future<bool> enabled();

  /// The positions while listened to, about once a second. One stream shared by every listener.
  Stream<HereSignal> signals();

  /// The app's page in the system settings — the way after [HereAccess.blocked].
  Future<void> openAppSettings();

  /// The system's location settings — "Włącz" when location is off in the phone.
  Future<void> openLocationSettings();
}

/// [HereLocation] over the channels of `HereLocation.kt`.
class PlatformHereLocation implements HereLocation {
  PlatformHereLocation();

  static const MethodChannel _channel = MethodChannel('grobing/location');

  // One native subscription for every listener: a second `receiveBroadcastStream` would cancel the first
  // on the native side.
  static final Stream<HereSignal> _signals = const EventChannel(
    'grobing/location/fixes',
  ).receiveBroadcastStream().map(_signal).asBroadcastStream();

  static HereSignal _signal(Object? event) {
    final Map<Object?, Object?> m = event! as Map<Object?, Object?>;
    if (m['on'] case final bool on) return HereSwitched(on: on);
    return HereFix(
      LatLng((m['lat']! as num).toDouble(), (m['lon']! as num).toDouble()),
      (m['accuracy'] as num?)?.toDouble(),
    );
  }

  static HereAccess _access(String? name) =>
      HereAccess.values.asNameMap()[name] ?? HereAccess.denied;

  @override
  Future<HereAccess> access() async {
    try {
      return _access(await _channel.invokeMethod<String>('access'));
    } on MissingPluginException {
      return HereAccess.denied;
    }
  }

  @override
  Future<HereAccess> request() async {
    try {
      return _access(await _channel.invokeMethod<String>('request'));
    } on PlatformException {
      return HereAccess.denied;
    } on MissingPluginException {
      return HereAccess.denied;
    }
  }

  @override
  Future<bool> enabled() async {
    try {
      return await _channel.invokeMethod<bool>('enabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Stream<HereSignal> signals() => _signals;

  @override
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on Object {
      // Nothing to open — the message stays.
    }
  }

  @override
  Future<void> openLocationSettings() async {
    try {
      await _channel.invokeMethod<void>('openLocationSettings');
    } on Object {
      // Nothing to open — the message stays.
    }
  }
}

/// The phone's position for every screen of the app, above the navigator like `MapNetwork`; tests put
/// their own in its place, or none — then the screens have no "gdzie jestem".
class MapHereLocation extends InheritedWidget {
  const MapHereLocation({
    super.key,
    required this.location,
    required super.child,
  });

  final HereLocation location;

  static HereLocation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapHereLocation>()?.location;

  @override
  bool updateShouldNotify(MapHereLocation old) => old.location != location;
}

/// One screen's "gdzie jestem" (element 10): on or off, what the phone allows, whether location is on in
/// the phone, and the last position. Listens only while on, and never after [dispose] — leaving the
/// screen switches it off (cmentarz.md → Navigation: nothing works in the background).
class HereTracker extends ChangeNotifier {
  HereTracker(this.location);

  final HereLocation location;

  bool _on = false;
  HereAccess? _access;
  bool _enabled = true;
  HereFix? _fix;
  StreamSubscription<HereSignal>? _sub;
  bool _disposed = false;

  bool get on => _on;
  HereAccess? get access => _access;

  /// Location switched on in the phone (element 10a: off → "Lokalizacja w telefonie jest wyłączona.").
  bool get enabled => _enabled;

  /// The last position while on with precise access; null before the first (element 10a (b)).
  HereFix? get fix => _on && _access == HereAccess.precise ? _fix : null;

  /// Switches on, asking the system when the app may not know yet. Returns what the phone allows: with
  /// [HereAccess.denied] or [HereAccess.blocked] it stays off.
  Future<HereAccess> turnOn() async {
    HereAccess a = await location.access();
    if (a == HereAccess.denied || a == HereAccess.blocked) {
      a = await location.request();
    }
    if (_disposed) return a;
    _access = a;
    if (a == HereAccess.precise || a == HereAccess.approximate) {
      _on = true;
      if (a == HereAccess.precise) {
        _enabled = await location.enabled();
        if (_disposed) return a;
        _sub ??= location.signals().listen(_onSignal, onError: (_) {});
      }
    }
    notifyListeners();
    return a;
  }

  void turnOff() {
    _on = false;
    _fix = null;
    unawaited(_sub?.cancel());
    _sub = null;
    notifyListeners();
  }

  /// After "Włącz" in the system's settings: asks again whether location is on.
  Future<void> recheck() async {
    if (!_on || _access != HereAccess.precise) return;
    final bool now = await location.enabled();
    if (_disposed || now == _enabled) return;
    _enabled = now;
    notifyListeners();
  }

  void _onSignal(HereSignal s) {
    switch (s) {
      case HereFix():
        _fix = s;
        _enabled = true;
      case HereSwitched(:final bool on):
        _enabled = on;
        if (!on) _fix = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

/// How far a point may lie outside the plan's box and still be "at the cemetery" (element 10, D31): a
/// grave on the outline with the phone's error around it.
const double atCemeteryMarginM = 100;

/// Whether [p] is at the cemetery — inside its box grown by [atCemeteryMarginM]; without a plan, within
/// 500 m of the cemetery's point.
bool atCemetery(LatLng p, {LatLngBoundsLike? box, LatLng? point}) {
  if (box != null) {
    const Distance d = Distance();
    final LatLng sw = d.offset(box.southWest, atCemeteryMarginM, 225);
    final LatLng ne = d.offset(box.northEast, atCemeteryMarginM, 45);
    return p.latitude >= sw.latitude &&
        p.latitude <= ne.latitude &&
        p.longitude >= sw.longitude &&
        p.longitude <= ne.longitude;
  }
  if (point == null) return false;
  return const Distance().as(LengthUnit.Meter, p, point) <= 500;
}

/// The corners of a box, without depending on flutter_map here.
typedef LatLngBoundsLike = ({LatLng southWest, LatLng northEast});

/// "2,5 km", "640 m", "312 km" — how far [p] is from [middle] (element 10a (a)): from 1 to 10 km with one
/// decimal, less in metres rounded to tens, more in whole kilometres ("9445,6 km" said nothing the whole
/// number does not — seen on the emulator).
String distanceText(LatLng p, LatLng middle) {
  final double m = const Distance().as(LengthUnit.Meter, p, middle);
  if (m < 1000) return '${math.max(10, (m / 10).round() * 10)} m';
  if (m >= 10000) return '${(m / 1000).round()} km';
  final String km = (m / 1000).toStringAsFixed(1).replaceAll('.', ',');
  return '$km km';
}

/// Whether the dot is not worth trusting (element 12a).
bool weakSignal(double? accuracyM) =>
    accuracyM != null && accuracyM > weakSignalM;

@visibleForTesting
HereSignal hereSignalOf(Object? event) => PlatformHereLocation._signal(event);
