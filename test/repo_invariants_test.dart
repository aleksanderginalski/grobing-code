import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ISSUE-002 AC-1..4, AC-7: invariants of the repo that are expensive to break by accident.
void main() {
  test('only the Android platform exists (AC-1)', () {
    for (final String platform in ['ios', 'web', 'linux', 'macos', 'windows']) {
      expect(Directory(platform).existsSync(), isFalse, reason: platform);
    }
    expect(Directory('android').existsSync(), isTrue);
  });

  test(
    'Flutter version is pinned to 3.41.1 in pubspec.yaml (AC-2, ADR-002)',
    () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        RegExp(r'^  flutter: 3\.41\.1\s*$', multiLine: true).hasMatch(pubspec),
        isTrue,
      );
    },
  );

  test('package name is com.grobing.app (AC-3) — it must never change', () {
    final String gradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    expect(gradle, contains('namespace = "com.grobing.app"'));
    expect(gradle, contains('applicationId = "com.grobing.app"'));
    expect(
      File(
        'android/app/src/main/kotlin/com/grobing/app/MainActivity.kt',
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'family-data and secrets block stays on top of .gitignore (AC-4, family-data.md)',
    () {
      // core.autocrlf may check the file out with CRLF on Windows.
      final String gitignore = File(
        '.gitignore',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final int familyBlock = gitignore.indexOf('# --- Family data');
      final int flutterDefaults = gitignore.indexOf('# --- Flutter defaults');
      expect(familyBlock, 0);
      expect(flutterDefaults, greaterThan(familyBlock));
      for (final String entry in [
        '*.db',
        '*.sqlite',
        // Backup and key file are age files, the backup's inside is tar (ADR-004, ISSUE-006).
        '*.age',
        '*.tar',
        '*.jks',
        'key.properties',
      ]) {
        final int at = gitignore.indexOf('\n$entry\n');
        expect(at, greaterThan(-1), reason: entry);
        expect(
          at,
          lessThan(flutterDefaults),
          reason: '$entry above the Flutter defaults',
        );
      }
    },
  );

  test('no keystore inside the project tree (AC-7)', () {
    final List<String> keystores = Directory('.')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where(
          (p) => !p.startsWith('./build/') && !p.startsWith('./.dart_tool/'),
        )
        .where((p) => p.endsWith('.jks') || p.endsWith('.keystore'))
        .toList();
    expect(keystores, isEmpty);
  });

  // ISSUE-008 AC-4 (ADR-004 pkt 4): Android's cloud backup and device-to-device transfer carry no
  // Grobing data. allowBackup="false" alone does not stop D2D on Android 12+ (SPIKE-003, M7).
  test(
    'Android backup is off and both extraction rules exclude every domain (ISSUE-008 AC-4)',
    () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );

      final String rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(rules, isNot(contains('<include')));
      for (final String section in ['cloud-backup', 'device-transfer']) {
        final String body = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules)!.group(1)!;
        for (final String domain in [
          'root',
          'file',
          'database',
          'sharedpref',
          'external',
          'device_root',
          'device_file',
          'device_database',
          'device_sharedpref',
        ]) {
          expect(
            body,
            contains('<exclude domain="$domain" path="." />'),
            reason: '$section excludes $domain',
          );
        }
      }
    },
  );

  // ISSUE-008 AC-5, NFR-005: the backup reaches Drive through the system window; the app itself has
  // no network permission. Debug and profile manifests add INTERNET for the Flutter tools only; the
  // release APK is checked with aapt (Verification in the item).
  test(
    'the main manifest asks for no INTERNET permission (ISSUE-008 AC-5)',
    () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('android.permission.INTERNET"')));
    },
  );
}
