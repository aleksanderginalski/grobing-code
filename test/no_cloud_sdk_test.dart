import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ISSUE-002 AC-5 + PROJECT_BRIEF §Security: no Firebase and no SDK that sends data off the phone
// (analytics, crash reporting, ads, push). Checks the resolved lockfile, so transitive packages count.
final List<RegExp> _forbidden = [
  RegExp(r'^firebase'),
  RegExp(r'^cloud_firestore'),
  RegExp(r'crashlytics'),
  RegExp(r'analytics'),
  RegExp(r'^sentry'),
  RegExp(r'^bugsnag'),
  RegExp(r'^datadog'),
  RegExp(r'^appcenter'),
  RegExp(r'^amplitude'),
  RegExp(r'^mixpanel'),
  RegExp(r'^posthog'),
  RegExp(r'^instabug'),
  RegExp(r'^onesignal'),
  RegExp(r'^google_mobile_ads'),
];

void main() {
  test(
    'pubspec.lock contains no Firebase, analytics or crash-reporting package',
    () {
      final String lock = File('pubspec.lock').readAsStringSync();
      final List<String> packages = RegExp(
        r'^  ([a-z0-9_]+):\s*$',
        multiLine: true,
      ).allMatches(lock).map((m) => m.group(1)!).toList();

      expect(packages, isNotEmpty, reason: 'lockfile parsed');
      expect(packages, contains('flutter_test'));

      final List<String> offending = packages
          .where((p) => _forbidden.any((r) => r.hasMatch(p)))
          .toList();
      expect(offending, isEmpty);
    },
  );
}
