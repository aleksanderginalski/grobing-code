import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/settings/settings_screen.dart';

// ISSUE-022 — the settings' words (05_DESIGN/ustawienia.md, elements 2 and 7): when and where the last
// backup is, and the app's version as pubspec.yaml gives it.

void main() {
  group('the settings\' words', () {
    test(
      'backupWhen: today, yesterday, otherwise the date — in the phone\'s time',
      () {
        final DateTime now = DateTime(2026, 10, 8, 16, 46);
        expect(
          backupWhen(DateTime(2026, 10, 8, 7, 5), now: now),
          'dziś, 07:05',
        );
        expect(
          backupWhen(DateTime(2026, 10, 7, 23, 59), now: now),
          'wczoraj, 23:59',
        );
        expect(
          backupWhen(DateTime(2026, 10, 3, 9, 30), now: now),
          '03.10.2026, 09:30',
        );
        expect(
          backupWhen(DateTime(2026, 9, 30, 12), now: DateTime(2026, 10, 1, 8)),
          'wczoraj, 12:00',
          reason: 'across a month',
        );
      },
    );

    test(
      'backupPlace: the provider of the picked file, nothing for one without a known name',
      () {
        expect(
          backupPlace(
            'content://com.google.android.apps.docs.storage/document/acc%3D1',
          ),
          'Dysk Google',
        );
        expect(
          backupPlace(
            'content://com.android.providers.downloads.documents/document/msf%3A31',
          ),
          'Pobrane',
        );
        expect(
          backupPlace(
            'content://com.android.externalstorage.documents/document/primary%3Akopia',
          ),
          'pamięć telefonu',
        );
        expect(backupPlace('content://com.example.cloud/document/1'), isNull);
        expect(backupPlace('fake://kopia.age'), isNull);
      },
    );

    test('the version in "O aplikacji" is the one in pubspec.yaml', () {
      final RegExpMatch? m = RegExp(
        r'^version:\s*([^+\s]+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync());
      expect(m?.group(1), appVersion);
    });
  });
}
