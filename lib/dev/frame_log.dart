import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Each frame's build and raster time to the log — the measurement of the tree's moves (ISSUE-033 D6, its
/// manual step 6; later ISSUE-032 on the phone). `dumpsys gfxinfo` sees no Flutter frames (SPIKE-002 M3), so
/// the engine's own timings are read. Only with `--dart-define=FRAME_LOG=true`, and never in release.
void startFrameLog() {
  if (kReleaseMode || !const bool.fromEnvironment('FRAME_LOG')) return;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final FrameTiming t in timings) {
      debugPrint(
        'GROBING_FRAME build=${t.buildDuration.inMicroseconds} '
        'raster=${t.rasterDuration.inMicroseconds}',
      );
    }
  });
}
