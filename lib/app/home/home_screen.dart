import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../backup/backup_service.dart';
import '../../backup/restore_service.dart';
import '../../data/cemeteries.dart';
import '../../data/database.dart';
import '../external_link.dart';
import '../grave/cemetery_screen.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../settings/settings_screen.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/candle.dart';
import 'cemetery_base.dart';
import 'cemetery_card.dart';
import 'cemetery_form.dart';
import 'cemetery_search.dart';
import 'pick_point_screen.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  late Stream<List<CemeterySummary>> _cemeteries = watchCemeteries(
    widget.database,
  );
  late final Future<PolandMapData> _mapData = widget.mapData != null
      ? Future.value(widget.mapData)
      : PolandMapData.load();
  final MapController _map = MapController();

  /// The database of cemeteries: read once, on the first entry into the search, and kept.
  Future<CemeteryBase>? _base;

  /// The ids of the open sheet: one cemetery, several (a group), or none.
  List<int> _selected = const [];
  List<CemeterySummary> _current = const [];

  /// The open sheet, measured once drawn, to keep the selected candle above it.
  final GlobalKey _sheetKey = GlobalKey();

  /// Room kept free at the bottom of the whole of Poland: about a sheet's height (ui review).
  static const double _sheetRoom = 150;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Opens the sheet of [ids] and, once it is drawn, keeps their candle above it — a group's too
  /// (05_DESIGN/cmentarze.md, element 4).
  void _select(List<int> ids, {bool zoomIn = false}) {
    setState(() => _selected = ids);
    final GeoPoint? p = ids.isEmpty ? null : _byId(ids.first)?.point;
    if (p == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(LatLng(p.lat, p.lon), zoomIn: zoomIn);
    });
  }

  /// Moves the map so [point] is not under the sheet; from the search also zooms in on it.
  void _reveal(LatLng point, {required bool zoomIn}) {
    final MapCamera camera = _map.camera;
    final double sheet = _sheetKey.currentContext?.size?.height ?? _sheetRoom;
    // From the search: 2³ = 8× the whole of Poland, unless already closer.
    final double zoom = zoomIn
        ? math.max(camera.zoom, (camera.minZoom ?? camera.zoom) + 3)
        : camera.zoom;
    final Offset at = camera.latLngToScreenOffset(point);
    final bool hidden = at.dy > camera.size.height - sheet - 24;
    if (zoomIn || hidden) {
      _map.move(point, zoom, offset: Offset(0, -sheet / 2));
    }
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
        _showSaved(id, point);
      case null:
        break;
    }
  }

  /// Quiet confirmation (style-b.md rule 10): the saved candle and its sheet.
  void _showSaved(int id, GeoPoint? point) {
    setState(() => _selected = [id]);
    if (point == null) return;
    final LatLng p = LatLng(point.lat, point.lon);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(p, zoomIn: false);
    });
  }

  /// Adding by hand ([cemetery] null) or correcting: the window, then the pick mode. Closing the pick
  /// mode brings the window back with what was typed; cancelling the window ends it all.
  Future<void> _edit(CemeterySummary? cemetery, {String name = ''}) async {
    final PolandMapData map = await _mapData;
    String currentName = cemetery?.name ?? name;
    String? currentLocality = cemetery?.locality;
    GeoPoint? currentPoint = cemetery?.point;
    while (true) {
      if (!mounted) return;
      final CemeteryFormValues? values = await showCemeteryForm(
        context,
        title: cemetery == null ? 'Nowy cmentarz' : 'Popraw cmentarz',
        name: currentName,
        locality: currentLocality,
      );
      if (values == null || !mounted) return;
      currentName = values.name;
      currentLocality = values.locality;
      int? savedId = cemetery?.id;
      final bool? saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PickPointScreen(
            mapData: map,
            name: values.name,
            initial: currentPoint,
            others: _pins(except: cemetery?.id),
            onSave: (point) async {
              currentPoint = point;
              if (cemetery == null) {
                savedId = await addCemetery(
                  widget.database,
                  name: values.name,
                  locality: values.locality,
                  point: point,
                );
              } else {
                await updateCemetery(
                  widget.database,
                  cemetery.id,
                  name: values.name,
                  locality: values.locality,
                  point: point,
                );
              }
            },
          ),
        ),
      );
      if (saved == true && mounted) {
        _showSaved(savedId!, currentPoint);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selected.isEmpty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _selected = const []);
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
          icon: const Icon(Icons.settings_outlined),
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
              Icon(Icons.search, color: GrobingColors.textMuted),
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
    return PolandMap(
      data: map.data!,
      controller: _map,
      pins: _pins(),
      // Poland stands under the search, above the sheet's room (05_DESIGN/cmentarze.md, element 3).
      fitPadding: const EdgeInsets.fromLTRB(16, 16, 16, _sheetRoom),
      selected: _selected.toSet(),
      onPins: _select,
      onMapTap: (_) {
        if (_selected.isNotEmpty) setState(() => _selected = const []);
      },
    );
  }

  Widget _bottomCard(Widget child) => Positioned(
    left: 16,
    right: 16,
    bottom: 16 + MediaQuery.paddingOf(context).bottom,
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
        icon: const Icon(Icons.add_location_alt_outlined),
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

  /// A sheet to the bottom edge, its content above the gesture bar. The handle means what it shows:
  /// dragging the sheet down closes it, like a tap on the map.
  Widget _sheet(Widget child) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 0) {
          setState(() => _selected = const []);
        }
      },
      child: Material(
        key: _sheetKey,
        color: GrobingColors.surface,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
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

  /// Elements 6–8.
  Widget _cemeterySheet(CemeterySummary c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                c.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GrobingColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            color: GrobingColors.amber,
            tooltip: 'Popraw cmentarz',
            onPressed: () => _edit(c),
          ),
        ],
      ),
      if (c.locality != null)
        Text(
          c.locality!,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      const SizedBox(height: 8),
      _iconLine(
        Icons.people_outline,
        '${gravesLabel(c.graveCount)} · ${peopleLabel(c.personCount)}',
      ),
      if (c.point == null) ...[
        const SizedBox(height: 4),
        _iconLine(Icons.location_off_outlined, 'Bez punktu na mapie'),
      ],
      const SizedBox(height: 16),
      // The candle leads to a place of memory (style-b.md rule 8), in the colour of the label.
      FilledButton.icon(
        style: primaryButtonStyle,
        onPressed: () => _openCemetery(c),
        icon: const CandleIcon(size: 22, color: GrobingColors.background),
        label: const Text('Otwórz cmentarz'),
      ),
    ],
  );

  Widget _iconLine(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 18, color: GrobingColors.textMuted),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
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
