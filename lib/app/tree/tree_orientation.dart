import 'package:flutter/services.dart';

/// "Obróć" (05_DESIGN/drzewo.md D82; ISSUE-055): the Drzewo tab's own orientation — landscape (true) or portrait
/// (false), chosen with its button and kept while the app runs, as the tempo (D41). Null: the phone's own setting, as
/// before the button (the app is not locked in portrait). It holds on the phone's own rotation too. Only the tab
/// follows it — both parts and presentation mode's way back; a person's view, the other tabs and the way out of the
/// tree go back to the phone's setting, as they have no landscape layout (D76).
bool? treeLandscape;

/// The tab's choice, or the phone's setting without one. After a turn asked for here the surface of the Flutter view
/// is laid out anew on the Android side (MainActivity.onConfigurationChanged — found on the emulator, ISSUE-055).
Future<void> applyTreeOrientation() =>
    SystemChrome.setPreferredOrientations(switch (treeLandscape) {
      true => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      false => const [DeviceOrientation.portraitUp],
      null => const [],
    });

/// Back to the phone's setting when leaving the tab. From landscape portrait first, for a moment, as on the way out
/// of presentation: without it a locked rotation stayed landscape (presentation_mode.dart, seen on the emulator).
Future<void> releaseTreeOrientation() async {
  if (treeLandscape == null) return;
  if (treeLandscape!) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
  await SystemChrome.setPreferredOrientations(const []);
}
