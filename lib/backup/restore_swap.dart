import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Replacing the phone's data with a validated restore, so that an interruption at any point leaves
// the old data or the new data — never neither (ISSUE-009, AC-4). The pattern is SQLite's own
// (https://www.sqlite.org/atomiccommit.html): the intent is recorded durably first, and the next start
// finishes the job. A marker file is the commit point:
//   no marker  → nothing has changed yet; leftovers of a preparation are deleted;
//   marker     → the new data is validated and complete; every start rolls the swap forward.
// Each step is one `rename` and every step can run again, so recovery may stop and resume anywhere.
//
// Layout inside the app's data directory (`DataLocation.inDirectory`):
//   grobing.db, media/, backup.json     the live data
//   restore-staging/new/                the validated restore, same layout
//   restore-old/                        the replaced data, deleted once the marker is gone
//   restore.json                        the marker: which items to swap

const String restoreMarkerName = 'restore.json';
const String restoreStagingName = 'restore-staging';
const String restoreIncomingName = 'new';
const String restoreOldName = 'restore-old';

/// The database file's companions. A database is never paired with another one's journal
/// (https://www.sqlite.org/howtocorrupt.html → "Mispairing database files and hot journals"), so the
/// old database's companions leave before the new database arrives.
const List<String> _databaseCompanions = ['-journal', '-wal', '-shm'];

/// The directory a restore is prepared in (`restore-staging/new`).
Directory restoreIncomingDir(Directory dataDir) =>
    Directory('${dataDir.path}/$restoreStagingName/$restoreIncomingName');

/// Commits the restore prepared in [restoreIncomingDir]: writes the marker, then swaps. The live
/// database must already be closed.
Future<void> commitRestore(
  Directory dataDir, {
  @visibleForTesting void Function(String step)? onStep,
}) async {
  final Directory incoming = restoreIncomingDir(dataDir);
  if (!await File('${incoming.path}/$_databaseName').exists()) {
    throw StateError('No prepared restore');
  }
  // A backup without photos still replaces the photo directory: old photos must not survive.
  await Directory('${incoming.path}/$_mediaName').create();
  final List<String> items = [
    for (final FileSystemEntity e in incoming.listSync())
      e.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
  ]..sort();
  final File marker = File('${dataDir.path}/$restoreMarkerName');
  final File temporary = File('${marker.path}.tmp');
  await temporary.writeAsString(jsonEncode({'items': items}), flush: true);
  await temporary.rename(marker.path);
  onStep?.call('marker');
  await completePendingRestore(dataDir, onStep: onStep);
}

/// Finishes a committed restore, or clears the leftovers of one that was never committed. Runs at
/// every start, before the database is opened (`main.dart`), and right after [commitRestore]. Returns
/// whether a restore was completed.
Future<bool> completePendingRestore(
  Directory dataDir, {
  @visibleForTesting void Function(String step)? onStep,
}) async {
  final File marker = File('${dataDir.path}/$restoreMarkerName');
  final Directory staging = Directory('${dataDir.path}/$restoreStagingName');
  final Directory old = Directory('${dataDir.path}/$restoreOldName');
  final Directory incoming = restoreIncomingDir(dataDir);

  if (!await marker.exists()) {
    // Not committed (or committed and finished): the live data is the truth.
    await _delete(File('${marker.path}.tmp'));
    await _delete(staging);
    await _delete(old);
    return false;
  }

  final List<String> items = [
    for (final Object? item
        in (jsonDecode(await marker.readAsString())
                as Map<String, Object?>)['items']!
            as List<Object?>)
      item! as String,
  ];
  await old.create(recursive: true);
  for (final String item in items) {
    final String live = '${dataDir.path}/$item';
    final String aside = '${old.path}/$item';
    final String fresh = '${incoming.path}/$item';
    if (item == _databaseName) {
      // While the marker exists the new database has never been opened, so a journal next to the
      // live name always belongs to the old one.
      for (final String suffix in _databaseCompanions) {
        await _moveAside('$live$suffix', '$aside$suffix');
      }
    }
    if (await _exists(fresh)) {
      // Not moved in yet: the live item (if any) goes aside first, then the new one takes its place.
      await _moveAside(live, aside);
      onStep?.call('aside:$item');
      await _rename(fresh, live);
      onStep?.call('in:$item');
    }
  }
  await marker.delete();
  onStep?.call('committed');
  await _delete(old);
  await _delete(staging);
  return true;
}

const String _databaseName = 'grobing.db';
const String _mediaName = 'media';

Future<bool> _exists(String path) async =>
    await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

/// Moves [from] to [to] when [from] exists; whatever was at [to] goes first.
Future<void> _moveAside(String from, String to) async {
  if (!await _exists(from)) return;
  await _deletePath(to);
  await _rename(from, to);
}

Future<void> _rename(String from, String to) async {
  switch (await FileSystemEntity.type(from)) {
    case FileSystemEntityType.directory:
      await Directory(from).rename(to);
    case FileSystemEntityType.notFound:
      return;
    default:
      await File(from).rename(to);
  }
}

Future<void> _deletePath(String path) async {
  switch (await FileSystemEntity.type(path)) {
    case FileSystemEntityType.directory:
      await Directory(path).delete(recursive: true);
    case FileSystemEntityType.notFound:
      return;
    default:
      await File(path).delete();
  }
}

Future<void> _delete(FileSystemEntity entity) => _deletePath(entity.path);
