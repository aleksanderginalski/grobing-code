import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';

import '../backup/backup_service.dart';
import '../backup/restore_service.dart';
import '../data/database.dart';
import 'data_state_screen.dart';
import 'start_screen.dart';
import 'theme.dart';

/// Everything the screens work on, opened together — and replaced together after a restore.
typedef AppData = ({
  GrobingDatabase database,
  DataLocation location,
  BackupService backup,
  RestoreService restore,
});

/// Root widget of Grobing (`root_widget` in project-config.example.md).
class GrobingApp extends StatefulWidget {
  const GrobingApp({
    super.key,
    required this.database,
    required this.location,
    required this.backup,
    this.restore,
    this.reopen,
  });

  final GrobingDatabase database;
  final DataLocation location;
  final BackupService backup;

  /// Null where restore is not offered (tests of other screens).
  final RestoreService? restore;

  /// Opens the data again after a restore replaced it (`main.dart`).
  final Future<AppData> Function()? reopen;

  @override
  State<GrobingApp> createState() => _GrobingAppState();
}

class _GrobingAppState extends State<GrobingApp> with WidgetsBindingObserver {
  late GrobingDatabase _database = widget.database;
  late DataLocation _location = widget.location;
  late BackupService _backup = widget.backup;
  late RestoreService? _restore = widget.restore;

  /// A new generation rebuilds every screen on the new data; nothing keeps the closed database.
  int _generation = 0;
  String? _notice;

  /// Every write asks for a background backup (ISSUE-010, D2) — one place for every screen, present and
  /// future; replaced together with the data after a restore.
  late StreamSubscription<Set<TableUpdate>> _changes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = _backup.watchChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes.cancel());
    super.dispose();
  }

  /// Leaving the app asks too: it catches a change no write notified (D2). Alone it was not enough —
  /// swiping the app away right after leaving kills it before the request is stored (stop #2). `paused`
  /// also comes when a system window (file picker, camera) covers the app; the backup's quiet period
  /// and the data lock make that harmless.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_backup.requestBackgroundIfChanged());
    }
  }

  /// After a restore (or one interrupted after the old database was closed): the data on disk is
  /// the old or the new, never neither — open whichever it is and start over on "Stan danych".
  Future<void> _reload(String notice) async {
    final AppData data = await widget.reopen!();
    if (!mounted) return;
    unawaited(_changes.cancel());
    _changes = data.backup.watchChanges();
    setState(() {
      _database = data.database;
      _location = data.location;
      _backup = data.backup;
      _restore = data.restore;
      _generation++;
      _notice = notice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Future<void> Function(String notice)? onRestored =
        widget.reopen == null ? null : _reload;
    Widget start() => StartScreen(
      database: _database,
      location: _location,
      backup: _backup,
      restore: _restore,
      onRestored: onRestored,
    );
    return MaterialApp(
      key: ValueKey<int>(_generation),
      title: 'Grobing',
      debugShowCheckedModeBanner: false,
      theme: GrobingTheme.dark,
      // No `home`: Flutter refuses it next to `onGenerateInitialRoutes`. The start screen is the only
      // named route; after a restore "Stan danych" opens on top of it with the notice.
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => start()),
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(builder: (_) => start()),
        if (_notice != null)
          MaterialPageRoute<void>(
            builder: (_) => DataStateScreen(
              database: _database,
              location: _location,
              backup: _backup,
              restore: _restore,
              onRestored: onRestored,
              notice: _notice,
            ),
          ),
      ],
    );
  }
}
