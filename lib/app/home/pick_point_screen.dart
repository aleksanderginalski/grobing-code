import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/cemeteries.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'poland_map.dart';
import 'poland_map_data.dart';

/// The pick mode (05_DESIGN/cmentarze.md, elements 16–17): a tap sets the candle, the next one moves
/// it; "Zapisz" saves with the point, "Zapisz bez punktu" without (and, when correcting, takes the
/// candle off the map). Pops `true` once saved; closed without saving it pops nothing, and the window
/// comes back with what was typed.
class PickPointScreen extends StatefulWidget {
  const PickPointScreen({
    super.key,
    required this.mapData,
    required this.name,
    required this.onSave,
    this.initial,
    this.others = const [],
  });

  final PolandMapData mapData;
  final String name;

  /// Writes the cemetery; throws when the write fails.
  final Future<void> Function(GeoPoint? point) onSave;

  /// When correcting: the cemetery's current point.
  final GeoPoint? initial;

  /// The other saved cemeteries: shown, not tappable, so a cemetery can be set next to another one
  /// (05_DESIGN/cmentarze.md, element 16; D21).
  final List<MapPin> others;

  @override
  State<PickPointScreen> createState() => _PickPointScreenState();
}

class _PickPointScreenState extends State<PickPointScreen> {
  final MapController _map = MapController();
  late LatLng? _point = widget.initial == null
      ? null
      : LatLng(widget.initial!.lat, widget.initial!.lon);
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _save(LatLng? point) async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(
        point == null ? null : GeoPoint(point.latitude, point.longitude),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: GrobingColors.background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Wróć do okna',
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Wskaż cmentarz na mapie',
        style: TextStyle(
          color: GrobingColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    body: Stack(
      children: [
        PolandMap(
          data: widget.mapData,
          controller: _map,
          placed: _point,
          pins: widget.others,
          fitPadding: const EdgeInsets.fromLTRB(16, 96, 16, 16),
          onMapTap: _saving ? null : (p) => setState(() => _point = p),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 8,
          child: Material(
            color: GrobingColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                'Dotknij miejsca, gdzie leży ${widget.name}. '
                'Mapę możesz przybliżyć.',
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: Material(
      color: GrobingColors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_failed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: GrobingColors.error,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Nie udało się zapisać. Spróbuj jeszcze raz.',
                          style: TextStyle(color: GrobingColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              // The text button gives way when the text is large (system font size); "Zapisz" keeps its
              // size, it is the main action.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: GrobingColors.text,
                      ),
                      onPressed: _saving ? null : () => _save(null),
                      child: const Text(
                        'Zapisz bez punktu',
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: primaryButtonStyle.copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(120, 52)),
                    ),
                    onPressed: _point == null || _saving
                        ? null
                        : () => _save(_point),
                    child: const Text('Zapisz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
