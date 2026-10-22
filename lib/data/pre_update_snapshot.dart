import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Where the snapshots of the database before an update live: next to the database, in the app's
/// private storage — never in Downloads, never in the backup.
Directory preUpdateSnapshotDir(Directory dataDir) =>
    Directory('${dataDir.path}/pre-update');

/// How many snapshots stay — one per schema version the phone has updated from, the newest kept.
const int preUpdateSnapshotsKept = 3;

/// The snapshot taken before the database moves from [version] to a newer schema.
File preUpdateSnapshotFile(Directory dir, int version) =>
    File('${dir.path}/grobing-v$version.db');

final RegExp _snapshotName = RegExp(r'^grobing-v(\d+)\.db$');

/// ISSUE-041 (K3): before a new version of the app migrates the database, keep a consistent copy of it
/// at the old schema version, so a migration that turns out wrong can be undone by a fixed version
/// reading the snapshot (README → Wydanie). The backup cannot be that copy: the start asks for one right
/// after the migration (retro 1, R6), and it overwrites the one backup file.
///
/// Only the database: a migration changes rows, never photo files. Nothing happens when there is no
/// database yet (first install) or it is already at [currentVersion] — a restore migrates in its own
/// staging (restore_service.dart), so its data arrives here current.
///
/// Opened read-write on purpose: a hot journal left by an interrupted write is rolled back on the first
/// read, so the version read and the copy made are the committed ones — a raw read of the file header
/// could see a half-written migration (https://www.sqlite.org/atomiccommit.html, 4.2). `VACUUM INTO`
/// writes a temporary name first, so an interrupted snapshot never leaves a half file under the real one.
///
/// One line in logcat after a snapshot — release builds too — so an update from the store can be checked
/// on the phone, where the app's private storage is out of reach (ISSUE-032, AC-2). Versions and size
/// only: no path, nothing from the data.
///
/// Returns the snapshot, or null when none was needed.
File? takePreUpdateSnapshot({
  required File database,
  required Directory dir,
  int currentVersion = GrobingDatabase.currentSchemaVersion,
  int keep = preUpdateSnapshotsKept,
}) {
  if (!database.existsSync()) return null;
  final Database raw = sqlite3.open(database.path, mode: OpenMode.readWrite);
  try {
    configureConnection(raw);
    final int version = raw.userVersion;
    // 0 is a database drift has not created yet — nothing to keep.
    if (version == 0 || version >= currentVersion) return null;
    dir.createSync(recursive: true);
    final File snapshot = preUpdateSnapshotFile(dir, version);
    final File partial = File('${snapshot.path}.partial');
    if (partial.existsSync()) partial.deleteSync();
    raw.execute('VACUUM INTO ?', [partial.path]);
    partial.renameSync(snapshot.path);
    _keepNewest(dir, keep);
    debugPrint(
      'GROBING_SNAPSHOT v$version -> v$currentVersion ${snapshot.lengthSync()} B',
    );
    return snapshot;
  } finally {
    raw.close();
  }
}

/// Deletes all but the [keep] snapshots of the highest versions, and partial files of interrupted runs.
void _keepNewest(Directory dir, int keep) {
  final List<({int version, File file})> snapshots = [];
  for (final FileSystemEntity e in dir.listSync()) {
    if (e is! File) continue;
    final String name = e.uri.pathSegments.last;
    final RegExpMatch? m = _snapshotName.firstMatch(name);
    if (m != null) {
      snapshots.add((version: int.parse(m.group(1)!), file: e));
    } else if (name.endsWith('.partial')) {
      e.deleteSync();
    }
  }
  snapshots.sort((a, b) => b.version.compareTo(a.version));
  for (final ({int version, File file}) old in snapshots.skip(keep)) {
    old.file.deleteSync();
  }
}
