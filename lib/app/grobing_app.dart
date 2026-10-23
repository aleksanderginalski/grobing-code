import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../backup/background.dart';
import '../backup/backup_service.dart';
import '../backup/restore_service.dart';
import '../data/cemetery_plans.dart';
import '../data/database.dart';
import '../net/overpass_plan_source.dart';
import 'data_state_screen.dart';
import 'grave/here_location.dart';
import 'home/home_screen.dart';
import 'map/plan_downloads.dart';
import 'photo/photos.dart';
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
    this.photos,
    this.planSource,
    this.backgroundPlans,
  });

  final GrobingDatabase database;
  final DataLocation location;
  final BackupService backup;

  /// Null where restore is not offered (tests of other screens).
  final RestoreService? restore;

  /// Opens the data again after a restore replaced it (`main.dart`).
  final Future<AppData> Function()? reopen;

  /// The photos' picker and preparer (tests replace them); by default the system ones, on [location].
  final Photos? photos;

  /// Where cemeteries' plans come from (tests replace it); by default the Overpass API (ISSUE-027).
  final PlanSource? planSource;

  /// The plans' downloads with the app closed (ISSUE-052 B1); null: none (tests of other screens).
  final BackgroundPlans? backgroundPlans;

  @override
  State<GrobingApp> createState() => _GrobingAppState();
}

class _GrobingAppState extends State<GrobingApp> with WidgetsBindingObserver {
  late GrobingDatabase _database = widget.database;
  late DataLocation _location = widget.location;
  late BackupService _backup = widget.backup;
  late RestoreService? _restore = widget.restore;
  late Photos _photos = widget.photos ?? Photos.platform(_location);
  late PlanDownloads _plans = _downloads(_database);

  /// "Gdzie jestem" for every cemetery screen (ISSUE-029): the satellites alone, only while listened to.
  final HereLocation _here = PlatformHereLocation();

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
    unawaited(_plans.downloadAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes.cancel());
    _plans.close();
    super.dispose();
  }

  PlanDownloads _downloads(GrobingDatabase database) => PlanDownloads(
    database: database,
    source: widget.planSource ?? OverpassPlanSource(),
  );

  /// Leaving the app asks too: it catches a change no write notified (D2). Alone it was not enough —
  /// swiping the app away right after leaving kills it before the request is stored (stop #2). `paused`
  /// also comes when a system window (file picker, camera) covers the app; the backup's quiet period
  /// and the data lock make that harmless.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_backup.requestBackgroundIfChanged());
      unawaited(_leavePlans());
    }
    // Back in the app: a plan that waited for the internet gets its chance (ISSUE-027 D3) — the phone
    // may have found a network while the app was away.
    if (state == AppLifecycleState.resumed) unawaited(_returnToPlans());
  }

  /// How many cemeteries lacked a plan when the app was left; null: not counted.
  int? _missingWhenLeft;

  /// Leaving the app hands the missing plans to the background (ISSUE-052 B1): it downloads them with the
  /// app closed, once the phone has a network.
  Future<void> _leavePlans() async {
    final BackgroundPlans? background = widget.backgroundPlans;
    if (background == null) return;
    try {
      final int missing = (await cemeteriesWithoutPlan(_database)).length;
      _missingWhenLeft = missing;
      if (missing > 0) await background.requestPlans();
    } on Object {
      // The next leaving asks again; the app's own downloads go on when it comes back.
    }
  }

  /// Plans the background stored while the app was away were written by another engine, so this one's
  /// screens heard nothing: fewer missing than when left → the plans' table is marked as changed, the
  /// screens read it again, and the backup hears of the new plans as of any write.
  Future<void> _returnToPlans() async {
    final int? left = _missingWhenLeft;
    _missingWhenLeft = null;
    if (left != null && left > 0) {
      try {
        final int missing = (await cemeteriesWithoutPlan(_database)).length;
        if (missing < left) {
          _database.markTablesUpdated([_database.cemeteryPlans]);
        }
      } on Object {
        // Read again at the next return; the plan is on disk either way.
      }
    }
    await _plans.downloadAll();
  }

  /// After a restore (or one interrupted after the old database was closed): the data on disk is
  /// the old or the new, never neither — open whichever it is and start over on "Stan danych".
  Future<void> _reload(String notice) async {
    final AppData data = await widget.reopen!();
    if (!mounted) return;
    unawaited(_changes.cancel());
    _changes = data.backup.watchChanges();
    _plans.close();
    setState(() {
      _database = data.database;
      _location = data.location;
      _backup = data.backup;
      _restore = data.restore;
      _photos = widget.photos ?? Photos.platform(data.location);
      _plans = _downloads(data.database);
      _generation++;
      _notice = notice;
    });
    unawaited(_plans.downloadAll());
  }

  @override
  Widget build(BuildContext context) {
    final Future<void> Function(String notice)? onRestored =
        widget.reopen == null ? null : _reload;
    Widget start() => HomeScreen(
      database: _database,
      location: _location,
      backup: _backup,
      restore: _restore,
      onRestored: onRestored,
      photos: _photos,
    );
    return MaterialApp(
      key: ValueKey<int>(_generation),
      title: 'Grobing',
      debugShowCheckedModeBanner: false,
      theme: GrobingTheme.dark,
      // Flutter's own texts — the back button, the text menu, closing a sheet for a screen reader — in
      // Polish whatever the phone's language, like every screen of the app (ISSUE-021, D1).
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Above the navigator: every cemetery screen, whatever opened it, has the plans' downloads.
      builder: (context, child) => MapHereLocation(
        location: _here,
        child: MapNetwork(plans: _plans, child: child!),
      ),
      // No `home`: Flutter refuses it next to `onGenerateInitialRoutes`. The home screen (the map of
      // Poland, ISSUE-014) is the only named route; after a restore "Stan danych" opens on top of it
      // with the notice.
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
