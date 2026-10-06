// On a PC: the "Stan danych" numbers of an unpacked backup, computed by the same function as the
// screen (lib/data/data_state.dart), and the manifest checked against the files. The compatibility
// gate of ISSUE-008 (AC-3) and every trial restore after it.
//
//   age -d -i grobing-klucz.age grobing-kopia.age > kopia.tar     (asks for the passphrase)
//   mkdir kopia && tar -xf kopia.tar -C kopia
//   dart run tool/fingerprint.dart kopia
//
// Keep the unpacked copy outside every repository and delete it afterwards: it is the family's data.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:grobing/backup/backup_archive.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/fingerprint.dart <unpacked backup directory>',
    );
    exit(64);
  }
  final Directory root = Directory(args.single);
  final DataLocation location = DataLocation.inDirectory(root);
  final GrobingDatabase db = GrobingDatabase(
    NativeDatabase.opened(
      sqlite3.open(location.databaseFile.path, mode: OpenMode.readOnly),
    ),
  );
  final DataState state;
  final String integrity;
  try {
    integrity = (await db.customSelect('PRAGMA integrity_check').getSingle())
        .read<String>('integrity_check');
    state = await readDataState(db, mediaDir: location.mediaDir);
  } finally {
    await db.close();
  }

  stdout
    ..writeln('integrity_check: $integrity')
    ..writeln('schema_version:  ${state.schemaVersion}')
    ..writeln(
      'fingerprint:     ${state.shortFingerprint}  (${state.fingerprint})',
    );
  state.rowCounts.forEach((table, count) => stdout.writeln('  $table: $count'));
  stdout.writeln('  media files: ${state.mediaFileCount}');

  bool ok = integrity == 'ok';
  final File manifestFile = File('${root.path}/$backupManifestName');
  if (manifestFile.existsSync()) {
    final BackupManifest manifest = BackupManifest.fromJson(
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>,
    );
    stdout.writeln(
      'manifest:        format ${manifest.formatVersion}, ${manifest.createdAt}',
    );
    ok &= _check(
      'fingerprint = manifest',
      state.fingerprint == manifest.dataFingerprint,
    );
    ok &= _check(
      'schema_version = manifest',
      state.schemaVersion == manifest.schemaVersion,
    );
    ok &= _check(
      'record counts = manifest',
      _sameCounts(state.rowCounts, manifest.recordCounts),
    );
    bool filesOk = true;
    for (final BackupFileEntry entry in manifest.files) {
      final File file = File('${root.path}/${entry.path}');
      final bool same =
          file.existsSync() &&
          file.lengthSync() == entry.size &&
          sha256.convert(file.readAsBytesSync()).toString() == entry.sha256;
      if (!same) stdout.writeln('  MISMATCH ${entry.path}');
      filesOk &= same;
    }
    ok &= _check(
      '${manifest.files.length} files: size and SHA-256 = manifest',
      filesOk,
    );
    ok &= _check(
      'no files beyond the manifest',
      state.mediaFileCount + 1 == manifest.files.length,
    );
  } else {
    stdout.writeln('manifest:        none (not an unpacked backup?)');
  }
  exit(ok ? 0 : 1);
}

bool _check(String what, bool passed) {
  stdout.writeln('${passed ? 'OK      ' : 'FAILED  '} $what');
  return passed;
}

bool _sameCounts(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
