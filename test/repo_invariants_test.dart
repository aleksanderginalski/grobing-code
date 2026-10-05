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
}
