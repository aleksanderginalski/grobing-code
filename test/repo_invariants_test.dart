import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/clans.dart';

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

  // NFR-005: the backup reaches Drive through the system window (ISSUE-008 AC-5). Since ISSUE-027 (ADR-003
  // pkt 4) the app has INTERNET for the cemetery's plan and the photo from above alone, every address in
  // lib/net/hosts.dart (test/net/hosts_test.dart), no cleartext. Debug and profile manifests add INTERNET for
  // the Flutter tools too; the release APK is checked with aapt (Verification in the item).
  test(
    'the main manifest asks for INTERNET and the phone\'s location (FINE with COARSE, ISSUE-029) and nothing else, '
    'without cleartext, says where the addresses are, and does not require GPS (ISSUE-027; ISSUE-008 AC-5 before '
    'it)',
    () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(
        RegExp(
          r'<uses-permission[^>]*android:name="([^"]+)"',
        ).allMatches(manifest).map((m) => m.group(1)),
        [
          'android.permission.INTERNET',
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        ],
      );
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
      expect(
        manifest,
        contains(
          '<uses-feature android:name="android.hardware.location.gps" '
          'android:required="false" />',
        ),
      );
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(manifest, contains('lib/net/hosts.dart'));
    },
  );

  // ISSUE-015 AC-5: the cemeteries from OpenStreetMap are a derived database under ODbL — the
  // repository says so next to the file and keeps the script that rebuilds it.
  test(
    'the cemetery database ships with its ODbL licence, origin and rebuild script (ISSUE-015 AC-5)',
    () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/cemeteries/poland_cemeteries.json'));
      expect(pubspec, contains('ODbL'));
      final String readme = File('README.md').readAsStringSync();
      expect(readme, contains('## Baza cmentarzy'));
      expect(readme, contains('ODbL 1.0, © autorzy OpenStreetMap'));
      expect(readme, contains('openstreetmap.org/copyright'));
      expect(
        File('tool/cemeteries/extract_cemeteries.dart').existsSync(),
        isTrue,
      );
    },
  );

  // ISSUE-044 (the author's decision R, family-data.md): the second exception of the family-data block — the
  // wreath motifs, one name in one folder, each a grey PNG with alpha, 640 × 640, as the guard in
  // grobing-agents checks it. A photo dropped there under that name fails here too.
  test(
    'the wreath motifs: one exception line in the family-data block, and in assets/wreaths only the motifs '
    'of WreathMotif, each a grey PNG with alpha, 640 × 640 (ISSUE-044)',
    () {
      final String gitignore = File(
        '.gitignore',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final int flutterDefaults = gitignore.indexOf('# --- Flutter defaults');
      final List<String> exceptions = [
        for (final String line in gitignore.split('\n'))
          if (line.startsWith('!') &&
              !line.startsWith('!/android/app/src/main/res/'))
            line,
      ];
      expect(exceptions, ['!/assets/wreaths/wieniec-*.png']);
      expect(
        gitignore.indexOf('\n!/assets/wreaths/wieniec-*.png\n'),
        lessThan(flutterDefaults),
      );

      final List<String> files = [
        for (final FileSystemEntity f in Directory('assets/wreaths').listSync())
          f.uri.pathSegments.last,
      ]..sort();
      expect(
        files,
        [for (final WreathMotif m in WreathMotif.values) 'wieniec-${m.key}.png']
          ..sort(),
      );
      for (final String name in files) {
        final List<int> head = File(
          'assets/wreaths/$name',
        ).readAsBytesSync().sublist(0, 26);
        int be32(int at) =>
            head[at] << 24 |
            head[at + 1] << 16 |
            head[at + 2] << 8 |
            head[at + 3];
        expect(head.sublist(0, 8), [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ], reason: name);
        expect(
          String.fromCharCodes(head.sublist(12, 16)),
          'IHDR',
          reason: name,
        );
        expect((be32(16), be32(20)), (640, 640), reason: name);
        expect(head[25], 4, reason: '$name: colour type 4 — grey with alpha');
      }
    },
  );
}
