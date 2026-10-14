import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// The tree's presentation mode (05_DESIGN/drzewo.md element 11, D11, D16; ISSUE-034): the screen turned
/// landscape and the system bars hidden. A swipe from the edge shows them for a moment and they hide again
/// — immersive sticky, Android's mode for "presentation slides" (developer.android.com → Hide system bars for
/// immersive mode); a tap stays the app's, it puts a person in the middle. Nothing is sent anywhere: the
/// picture reaches a TV through the system's own "Przesyłaj ekran" (NFR-005).
Future<void> enterPresentation() async {
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await _untilLandscape();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/// Bars hidden while the screen was still turning left the app at the portrait size inside a landscape
/// window — 6 entries of 8 on the emulator (ISSUE-034, Dev report). So they go once the app sees the
/// landscape size, or after 2 s at most (a screen that does not turn). The view through the binding, so a
/// widget test can turn it.
Future<void> _untilLandscape() async {
  final ui.FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.implicitView;
  for (int i = 0; i < 40; i++) {
    if (view == null || view.physicalSize.width > view.physicalSize.height) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Back from presentation: the bars as the app has them (edge to edge — the default of a Flutter app
/// targeting Android 15+) and the orientation the phone's own setting gives (D2) — the app is not locked
/// in portrait. Portrait comes first, for a moment: without it a locked rotation stayed landscape (seen on
/// the emulator).
Future<void> leavePresentation() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  await SystemChrome.setPreferredOrientations(const []);
}
