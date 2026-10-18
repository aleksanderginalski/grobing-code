import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../backup/backup_service.dart';
import '../../backup/restore_service.dart';
import '../../data/cemeteries.dart';
import '../../data/database.dart';
import '../../data/photos.dart' show cemeteryPhotoPath;
import '../external_link.dart';
import '../grave/cemetery_screen.dart';
import '../map/plan_downloads.dart';
import '../photo/add_photo_field.dart';
import '../photo/photo_picker.dart';
import '../photo/photo_source_sheet.dart';
import '../photo/photo_viewer_screen.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../settings/settings_screen.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/candle.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'cemetery_base.dart';
import 'cemetery_card.dart';
import 'cemetery_edit.dart';
import 'cemetery_search.dart';
import 'poland_map.dart';
import 'poland_map_data.dart';

/// The home screen (ISSUE-014; 05_DESIGN/cmentarze.md): the map of Poland with a candle on every
/// cemetery of the family, the search, adding and correcting a cemetery, and the gear to the settings
/// (ISSUE-022). The first route of the app: the Mapa tab of the bottom bar.
/// It replaces the start screen of ISSUE-002.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.database,
    required this.location,
    required this.backup,
    this.restore,
    this.onRestored,
    this.mapData,
    this.base,
    this.openUrl = openExternalUrl,
    this.photos,
  });

  final GrobingDatabase database;
  final DataLocation location;
  final BackupService backup;
  final RestoreService? restore;
  final Future<void> Function(String notice)? onRestored;

  /// The map, when already loaded (tests); otherwise read from the bundled asset.
  final PolandMapData? mapData;

  /// The cemeteries of Poland, when already loaded (tests); otherwise read from the bundled asset on
  /// the first entry into the search (ISSUE-015 D5).
  final Future<CemeteryBase>? base;

  /// Opens the satellite photo in another app (tests replace it).
  final Future<bool> Function(String url) openUrl;

  /// Photos for the cemetery and grave screens (ISSUE-016); null only in tests of other features.
  final Photos? photos;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late Stream<List<CemeterySummary>> _cemeteries = watchCemeteries(
    widget.database,
  );
  late final Future<PolandMapData> _mapData = widget.mapData != null
      ? Future.value(widget.mapData)
      : PolandMapData.load();
  final MapController _map = MapController();

  /// The box of Poland, once the map is read: where "the whole of Poland" is.
  LatLngBounds? _poland;

  /// The database of cemeteries: read once, on the first entry into the search, and kept.
  Future<CemeteryBase>? _base;

  /// The ids of the open sheet: one cemetery, several (a group), or none.
  List<int> _selected = const [];
  List<CemeterySummary> _current = const [];

  /// The open sheet, measured once drawn, to keep the selected candle above it.
  final GlobalKey _sheetKey = GlobalKey();

  /// A cemetery's sheet with its photo and a one-line name (element 6a), before it is measured — about
  /// 190 dp (05_DESIGN/cmentarze.md D30). The glide reads the drawn sheet; this is only its first guess.
  static const double _sheetRoom = 190;

  /// The whole of Poland at the least zoom: 16 dp at every side, in the middle of the map (D30). The room
  /// for a sheet of D26 v2.6 — `min(sheet, what is left under Poland at full width)`, split between the top
  /// and the bottom — never changes this zoom: where a sheet fits under Poland the width sets the zoom
  /// anyway, and where it does not the room is what is left. So Poland keeps the whole width on every phone,
  /// and on a short one an open sheet covers its south (the candle's rule — ui review, ISSUE-023). Measured
  /// before: a fixed room of 214 dp made Poland 145 dp wide on 360 × 640 dp.
  static const EdgeInsets _polandPadding = EdgeInsets.all(16);

  /// D30: the map glides between Poland in the middle and Poland above the sheet — about 300 ms,
  /// slowing down at the end (Material's standard decelerate). Made in [initState], not lazily: a screen
  /// closed before its map was read would make it first in [dispose], where its ticker can no longer look
  /// up the tree (seen in the tests, ISSUE-023).
  late final AnimationController _glide;
  LatLng? _glideFrom;
  LatLng? _glideTo;

  /// The cemetery whose photo is being saved, and the one whose save failed (element 6a).
  int? _photoSaving;
  int? _photoFailed;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_glideStep);
  }

  @override
  void dispose() {
    _glide.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Opens the sheet of [ids] and, once it is drawn, keeps their candle above it — a group's too
  /// (05_DESIGN/cmentarze.md, element 4).
  void _select(List<int> ids, {bool zoomIn = false}) {
    setState(() {
      _selected = ids;
      _photoFailed = null;
    });
    final GeoPoint? p = ids.isEmpty ? null : _byId(ids.first)?.point;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reveal(p == null ? null : LatLng(p.lat, p.lon), zoomIn: zoomIn);
      }
    });
  }

  /// Closes the sheet; with the whole of Poland on the screen the map glides back to the middle (D30).
  void _closeSheet() {
    if (_selected.isEmpty) return;
    setState(() {
      _selected = const [];
      _photoFailed = null;
    });
    final MapCamera camera = _map.camera;
    final LatLngBounds? poland = _poland;
    if (poland != null && _atWholePoland(camera)) {
      _glideCentre(
        CameraFit.bounds(
          bounds: poland,
          padding: _polandPadding,
        ).fit(camera).center,
      );
    }
  }

  /// The least zoom: the whole of Poland, where the map stands in the middle without a sheet (D2).
  bool _atWholePoland(MapCamera camera) =>
      camera.zoom <= (camera.minZoom ?? camera.zoom) + 0.01;

  /// Moves the map so [point] is not under the sheet; from the search also zooms in on it. At the whole
  /// of Poland the map glides up instead, so Poland stands above the sheet (D30) — unless the candle would
  /// still be under it (a short screen), when the candle's rule wins.
  void _reveal(LatLng? point, {required bool zoomIn}) {
    final MapCamera camera = _map.camera;
    final double sheet = _sheetKey.currentContext?.size?.height ?? _sheetRoom;
    bool hiddenAt(MapCamera c) =>
        point != null &&
        c.latLngToScreenOffset(point).dy > c.size.height - sheet - 24;
    final LatLngBounds? poland = _poland;
    if (!zoomIn && poland != null && _atWholePoland(camera)) {
      final LatLng lifted = _liftedCentre(camera, poland, sheet);
      if (!hiddenAt(camera.withPosition(center: lifted))) {
        _glideCentre(lifted);
        return;
      }
    }
    if (point == null) return;
    // From the search: 2³ = 8× the whole of Poland, unless already closer.
    final double zoom = zoomIn
        ? math.max(camera.zoom, (camera.minZoom ?? camera.zoom) + 3)
        : camera.zoom;
    if (zoomIn || hiddenAt(camera)) {
      _glide.stop();
      _map.move(point, zoom, offset: Offset(0, -sheet / 2));
    }
  }

  /// The centre at which the whole of Poland ends 16 dp above a sheet [sheet] high — or, when it is taller
  /// than the room above the sheet, starts 16 dp below the top.
  LatLng _liftedCentre(MapCamera camera, LatLngBounds poland, double sheet) {
    final MapCamera middle = camera.withPosition(
      center: CameraFit.bounds(
        bounds: poland,
        padding: _polandPadding,
      ).fit(camera).center,
    );
    final double top = middle.latLngToScreenOffset(poland.northWest).dy;
    final double bottom = middle.latLngToScreenOffset(poland.southEast).dy;
    final double up = math.min(
      bottom - (middle.size.height - sheet - 16),
      top - 16,
    );
    if (up <= 0) return middle.center;
    return middle.screenOffsetToLatLng(
      Offset(middle.size.width / 2, middle.size.height / 2 + up),
    );
  }

  /// Glides the map's centre to [target] at the same zoom; with "Usuń animacje" in the system it jumps.
  void _glideCentre(LatLng target) {
    final MapCamera camera = _map.camera;
    if (MediaQuery.disableAnimationsOf(context)) {
      _glide.stop();
      _map.move(target, camera.zoom);
      return;
    }
    _glideFrom = camera.center;
    _glideTo = target;
    _glide.forward(from: 0);
  }

  void _glideStep() {
    final LatLng? from = _glideFrom, to = _glideTo;
    if (from == null || to == null) return;
    final double t = Curves.easeOutCubic.transform(_glide.value);
    _map.move(
      LatLng(
        lerpDouble(from.latitude, to.latitude, t)!,
        lerpDouble(from.longitude, to.longitude, t)!,
      ),
      _map.camera.zoom,
    );
  }

  List<MapPin> _pins({int? except}) => [
    for (final CemeterySummary c in _current)
      if (c.point != null && c.id != except)
        (id: c.id, point: LatLng(c.point!.lat, c.point!.lon), name: c.name),
  ];

  CemeterySummary? _byId(int id) {
    for (final CemeterySummary c in _current) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The gear: the settings, with "Stan danych" a level down (05_DESIGN/ustawienia.md, D1).
  Future<void> _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        database: widget.database,
        location: widget.location,
        backup: widget.backup,
        restore: widget.restore,
        onRestored: widget.onRestored,
        photos: widget.photos,
      ),
    ),
  );

  Future<void> _openSearch() async {
    // The preview draws the map too; a map that cannot be read leaves the card working.
    final PolandMapData? map = await _mapData.then<PolandMapData?>(
      (m) => m,
      onError: (Object _) => null,
    );
    if (!mounted) return;
    final SearchOutcome? outcome = await Navigator.of(context)
        .push<SearchOutcome>(
          MaterialPageRoute(
            builder: (_) => CemeterySearchScreen(
              cemeteries: _current,
              base: _base ??= widget.base ?? CemeteryBase.load(),
              saveFromBase: (cemetery, values) => addCemetery(
                widget.database,
                name: values.name,
                locality: values.locality,
                point: cemetery.point,
              ),
              mapData: map,
              pins: _pins(),
              openUrl: widget.openUrl,
            ),
          ),
        );
    if (!mounted) return;
    switch (outcome) {
      case OpenCemetery(:final int id):
        _select([id], zoomIn: true);
      case AddByHand(:final String name):
        await _edit(null, name: name);
      case AddedFromBase(:final int id, :final GeoPoint point):
        // The plan of a cemetery from the database: downloaded at once, nothing shows it here (D34).
        unawaited(MapNetwork.maybeOf(context)?.plans?.download(id));
        _showSaved(id, point);
      case null:
        break;
    }
  }

  /// Quiet confirmation (style-b.md rule 10): the saved candle and its sheet.
  void _showSaved(int id, GeoPoint? point) {
    setState(() => _selected = [id]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reveal(
          point == null ? null : LatLng(point.lat, point.lon),
          zoomIn: false,
        );
      }
    });
  }

  /// Adding by hand ([cemetery] null) or correcting — one way with the cemetery screen's ✎
  /// (`cemetery_edit.dart`); the saved candle and its sheet show it.
  Future<void> _edit(CemeterySummary? cemetery, {String name = ''}) async {
    final ({int id, GeoPoint? point})? saved = await editCemetery(
      context,
      database: widget.database,
      mapData: _mapData,
      others: _pins(except: cemetery?.id),
      cemetery: cemetery == null
          ? null
          : (
              id: cemetery.id,
              name: cemetery.name,
              locality: cemetery.locality,
              point: cemetery.point,
            ),
      name: name,
    );
    if (saved != null && mounted) _showSaved(saved.id, saved.point);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selected.isEmpty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _closeSheet();
    },
    child: Scaffold(
      // Element 18: the sheets stand above the bar, which keeps clear of the gesture bar itself.
      bottomNavigationBar: GrobingTabBar(
        active: AppTab.map,
        database: widget.database,
        photos: widget.photos,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _bar(),
            _searchField(),
            const SizedBox(height: 8),
            Expanded(child: _mapArea()),
          ],
        ),
      ),
    ),
  );

  /// Element 1: the candle and "Grobing" — the app's sign — and the gear to the settings.
  Widget _bar() => SizedBox(
    height: 64,
    child: Row(
      children: [
        const SizedBox(width: 16),
        const CandleIcon(size: 24),
        const SizedBox(width: 10),
        const Text(
          'Grobing',
          style: TextStyle(
            color: GrobingColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const GrobingIcon(Glyphs.settings, applyTextScaling: false),
          color: GrobingColors.textMuted,
          tooltip: 'Ustawienia',
          onPressed: _openSettings,
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  /// Element 2: only an entry into the search mode.
  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: Material(
      color: GrobingColors.surface,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openSearch,
        child: const SizedBox(
          height: 56,
          child: Row(
            children: [
              SizedBox(width: 16),
              GrobingIcon(Glyphs.search, color: GrobingColors.textMuted),
              SizedBox(width: 12),
              Text(
                'Szukaj cmentarza',
                style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _mapArea() => FutureBuilder<PolandMapData>(
    future: _mapData,
    builder: (context, map) => StreamBuilder<List<CemeterySummary>>(
      stream: _cemeteries,
      builder: (context, snapshot) {
        if (snapshot.hasData) _current = snapshot.data!;
        final List<int> selected = [
          for (final int id in _selected)
            if (_byId(id) != null) id,
        ];
        return Stack(
          children: [
            Positioned.fill(child: _map0(map)),
            if (snapshot.hasError)
              _bottomCard(_readError())
            else if (snapshot.hasData && _current.isEmpty)
              _bottomCard(_empty())
            else if (selected.length == 1)
              _sheet(_cemeterySheet(_byId(selected.single)!))
            else if (selected.length > 1)
              _sheet(_groupSheet(selected.map(_byId).nonNulls.toList())),
          ],
        );
      },
    ),
  );

  Widget _map0(AsyncSnapshot<PolandMapData> map) {
    if (map.hasError) {
      // The data is bundled: an error here is a fault of the app, not of the phone.
      return const Center(
        child: Text(
          'Nie udało się narysować mapy.',
          style: TextStyle(color: GrobingColors.textMuted),
        ),
      );
    }
    if (!map.hasData) return const SizedBox.shrink();
    _poland = map.data!.bounds;
    return PolandMap(
      data: map.data!,
      controller: _map,
      pins: _pins(),
      // Poland in the middle, with room for a sheet (05_DESIGN/cmentarze.md, element 3, D30).
      fitPadding: _polandPadding,
      selected: _selected.toSet(),
      onPins: _select,
      onMapTap: (_) => _closeSheet(),
      // A finger wins over the glide.
      onPointerDown: _glide.stop,
    );
  }

  /// Element 5 and the read error: a card above the bottom bar, which keeps clear of the gesture bar itself
  /// — so no margin for it here (ui review, ISSUE-023: it was counted twice since ISSUE-022).
  Widget _bottomCard(Widget child) => Positioned(
    left: 16,
    right: 16,
    bottom: 16,
    child: Material(
      color: GrobingColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  /// Element 5: what will be here, and one action.
  Widget _empty() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Tu pojawią się cmentarze rodziny.',
        textAlign: TextAlign.center,
        style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        style: primaryButtonStyle,
        onPressed: _openSearch,
        icon: const GrobingIcon(Glyphs.addLocationAlt),
        label: const Text('Dodaj cmentarz'),
      ),
    ],
  );

  Widget _readError() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Nie udało się odczytać cmentarzy.',
        textAlign: TextAlign.center,
        style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
      const SizedBox(height: 14),
      OutlinedButton(
        style: secondaryButtonStyle,
        onPressed: () =>
            setState(() => _cemeteries = watchCemeteries(widget.database)),
        child: const Text('Spróbuj ponownie'),
      ),
    ],
  );

  /// A sheet down to the bottom bar (element 18), which keeps clear of the gesture bar itself — so 20 dp
  /// under the content and no margin for the gesture bar a second time (ui review, ISSUE-023). The handle
  /// means what it shows: dragging the sheet down closes it, like a tap on the map.
  Widget _sheet(Widget child) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 0) _closeSheet();
      },
      child: Material(
        key: _sheetKey,
        color: GrobingColors.surface,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: GrobingColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );

  /// Element 7 (ISSUE-012): the cemetery's graves. The sheet stays open underneath, so back returns to
  /// it with the new counts (05_DESIGN/cmentarz.md D7).
  Future<void> _openCemetery(CemeterySummary c) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CemeteryScreen(
        database: widget.database,
        cemeteryId: c.id,
        photos: widget.photos,
      ),
    ),
  );

  /// The source sheet, then the system picker or camera; null when the user cancels either.
  Future<File?> _pickPhoto(Photos photos) async {
    final PhotoSource? source = await showPhotoSourceSheet(
      context,
      title: 'Zdjęcie cmentarza',
    );
    if (source == null) return null;
    return photos.pick(source);
  }

  /// "Dodaj zdjęcie" (element 6a): kept at once, without a form, like a gravestone's (ISSUE-023 D3); the
  /// sheet shows it.
  Future<void> _addPhoto(CemeterySummary c, Photos photos) async {
    if (_photoSaving != null) return;
    setState(() => _photoFailed = null);
    try {
      final File? picked = await _pickPhoto(photos);
      if (picked == null || !mounted) return;
      setState(() => _photoSaving = c.id);
      await photos.setCemeteryPhoto(widget.database, c.id, picked);
    } on Object {
      if (mounted) setState(() => _photoFailed = c.id);
    } finally {
      if (mounted) setState(() => _photoSaving = null);
    }
  }

  /// The photo on the whole screen (05_DESIGN/zdjecie.md, B), where it can be changed or deleted — as a
  /// gravestone's (D3).
  Future<void> _openPhoto(CemeterySummary c, Photos photos, String path) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PhotoViewerScreen(
            title: c.name,
            subtitle: 'Zdjęcie cmentarza',
            file: photos.fileOf(path),
            pickReplacement: () => _pickPhoto(photos),
            replace: (picked) async {
              await photos.setCemeteryPhoto(widget.database, c.id, picked);
              return photos.fileOf(
                (await cemeteryPhotoPath(widget.database, c.id))!,
              );
            },
            onDelete: () => photos.deleteCemeteryPhoto(widget.database, c.id),
          ),
        ),
      );

  /// Element 6a: the photo, or the field in its place — 96 × 80 dp, left of the name.
  Widget _photoSlot(CemeterySummary c, Photos photos) {
    if (c.photoPath case final String path?) {
      return _CemeteryPhoto(
        file: photos.fileOf(path),
        onTap: () => _openPhoto(c, photos, path),
      );
    }
    if (_photoSaving == c.id) return const _SavingCemeteryPhoto();
    return AddPhotoField(
      label: 'Dodaj zdjęcie',
      onTap: () => _addPhoto(c, photos),
      width: _CemeteryPhoto.width,
      height: _CemeteryPhoto.height,
      iconSize: 24,
      captionStyle: const TextStyle(
        color: GrobingColors.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      radius: 12,
      padding: const EdgeInsets.all(8),
    );
  }

  /// Elements 6–8, and 6a: the photo left of the name, the ✎ in the top right corner.
  Widget _cemeterySheet(CemeterySummary c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.photos case final Photos photos?) ...[
            _photoSlot(c, photos),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: widget.photos == null ? 12 : 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (c.locality != null)
                    Text(
                      c.locality!,
                      style: const TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 8),
                  _iconLine(
                    Glyphs.group,
                    '${gravesLabel(c.graveCount)} · ${peopleLabel(c.personCount)}',
                  ),
                  if (c.point == null) ...[
                    const SizedBox(height: 4),
                    _iconLine(Glyphs.locationOff, 'Bez punktu na mapie'),
                  ],
                ],
              ),
            ),
          ),
          // Element 8 "in the line of the name": next to the photo the name starts 2 dp from the top, so the
          // ✎ moves up to the middle of its first line — the target stays 48 × 48 (ui review, ISSUE-023).
          Transform.translate(
            offset: Offset(
              0,
              widget.photos == null
                  ? 0
                  : 2 +
                        MediaQuery.textScalerOf(context).scale(18) * 1.33 / 2 -
                        24,
            ),
            child: IconButton(
              icon: const GrobingIcon(Glyphs.inkPen, applyTextScaling: false),
              color: GrobingColors.amber,
              tooltip: 'Popraw cmentarz',
              onPressed: () => _edit(c),
            ),
          ),
        ],
      ),
      if (_photoFailed == c.id)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: PhotoErrorLine(
            'Nie udało się zapisać zdjęcia. Spróbuj jeszcze raz.',
          ),
        ),
      const SizedBox(height: 16),
      // The candle leads to a place of memory (style-b.md rule 8), in the colour of the label.
      FilledButton.icon(
        style: primaryButtonStyle,
        onPressed: () => _openCemetery(c),
        icon: const CandleIcon(
          size: 22,
          color: GrobingColors.background,
          applyTextScaling: true,
        ),
        label: const Text('Otwórz cmentarz'),
      ),
    ],
  );

  Widget _iconLine(Glyph icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GrobingIcon(icon, size: 18, color: GrobingColors.textMuted),
      const SizedBox(width: 6),
      // Next to the photo the line is narrower: it wraps rather than run past the ✎.
      Flexible(
        child: Text(
          text,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ),
    ],
  );

  /// Element 9.
  Widget _groupSheet(List<CemeterySummary> group) {
    final List<CemeterySummary> sorted = [...group]
      ..sort((a, b) => polishCompare(a.name, b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${cemeteriesLabel(group.length)} w tym miejscu',
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 13,
            ),
          ),
        ),
        for (final CemeterySummary c in sorted) ...[
          const Divider(height: 1, color: GrobingColors.outline),
          CemeteryCard(
            cemetery: c,
            inSheet: true,
            onTap: () => _select([c.id]),
          ),
        ],
      ],
    );
  }
}

/// Element 6a: the cemetery's own photo, 96 × 80 dp, radius 12, cut from the middle (style-b.md rule 14:
/// only a thumbnail is cut; all of it is one tap away, in the viewer). Decoded at the size it is shown.
class _CemeteryPhoto extends StatelessWidget {
  const _CemeteryPhoto({required this.file, required this.onTap});

  static const double width = 96;
  static const double height = 80;

  final File file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    // As the field (AddPhotoField): its own node, or it merges into the sheet, and the tap of its own, or
    // Switch Access and Voice Access only read it (WCAG 2.2 SC 4.1.2).
    container: true,
    button: true,
    label: 'Zdjęcie cmentarza — otwórz',
    onTap: onTap,
    excludeSemantics: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: GrobingColors.background,
        child: InkWell(
          onTap: onTap,
          child: Image.file(
            file,
            width: width,
            height: height,
            fit: BoxFit.cover,
            // Cut from the middle of a landscape photo, the box's width would blur it (ui review).
            cacheWidth: coverDecodeWidth(context, width),
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox(
              width: width,
              height: height,
              child: GrobingIcon(
                Glyphs.brokenImage,
                color: GrobingColors.textMuted,
                applyTextScaling: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Element 6a while the chosen photo is being kept: its place on the surface with the progress
/// indicator — no words, there is no room for them; a screen reader hears them.
class _SavingCemeteryPhoto extends StatelessWidget {
  const _SavingCemeteryPhoto();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Zapisuję zdjęcie…',
    liveRegion: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: const ColoredBox(
        color: GrobingColors.background,
        child: SizedBox(
          width: _CemeteryPhoto.width,
          height: _CemeteryPhoto.height,
          child: Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    ),
  );
}
