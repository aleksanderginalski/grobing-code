import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/presentation_mode.dart';

// ISSUE-034 — what the tree's presentation mode asks of the system (05_DESIGN/drzewo.md element 11, D2; Dev
// report): landscape first, the bars hidden only once the view is landscape — hidden while the screen was
// turning, they left the app at the portrait size in 6 entries of 8 on the emulator — and on the way back the
// bars, portrait for a moment, then the phone's own setting.

void main() {
  late List<String> chrome;

  setUp(() {
    chrome = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations' ||
              call.method == 'SystemChrome.setEnabledSystemUIMode') {
            chrome.add('${call.method.substring(13)} ${call.arguments}');
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  testWidgets('enter — landscape first; the bars hide once the view has turned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    bool done = false;
    enterPresentation().then((_) => done = true);
    await tester.pump();
    expect(chrome, [
      'setPreferredOrientations '
          '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]',
    ]);

    // Still portrait: the bars wait.
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, isFalse);
    expect(chrome, hasLength(1));

    tester.view.physicalSize = const Size(2400, 1080);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
    expect(chrome.last, 'setEnabledSystemUIMode SystemUiMode.immersiveSticky');
  });

  testWidgets(
    'enter — a screen that does not turn gets the bars hidden after 2 s',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      bool done = false;
      enterPresentation().then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, isTrue);
      expect(chrome, [
        'setPreferredOrientations '
            '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]',
        'setEnabledSystemUIMode SystemUiMode.immersiveSticky',
      ]);
    },
  );

  testWidgets(
    'leave — the bars edge to edge, portrait for a moment, then the phone\'s own setting (D2)',
    (tester) async {
      await leavePresentation();
      expect(chrome, [
        'setEnabledSystemUIMode SystemUiMode.edgeToEdge',
        'setPreferredOrientations [DeviceOrientation.portraitUp]',
        'setPreferredOrientations []',
      ]);
    },
  );
}
