import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../external_link.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/candle.dart';
import 'cemetery_base.dart';
import 'cemetery_form.dart';
import 'poland_map.dart';
import 'poland_map_data.dart';

/// The preview of a cemetery from the database, before adding it (05_DESIGN/cmentarze.md, element 14):
/// the map zoomed in on its point with an outlined candle, and the satellite photo one tap away —
/// the database has errors and repeated names, so the name alone does not make the place certain (D18).
/// "Dodaj ten cmentarz" opens the window over the preview, so "Anuluj" comes back here (Navigation);
/// a saved cemetery pops its id.
class BasePreviewScreen extends StatefulWidget {
  const BasePreviewScreen({
    super.key,
    required this.cemetery,
    required this.onSave,
    this.mapData,
    this.saved = const [],
    this.openUrl = openExternalUrl,
  });

  final BaseCemetery cemetery;

  /// Saves the cemetery with what the window returned; its id.
  final Future<int> Function(CemeteryFormValues values) onSave;

  /// Null: the bundled map could not be read — the card still works.
  final PolandMapData? mapData;

  /// The family's candles around, shown but not tappable.
  final List<MapPin> saved;
  final Future<bool> Function(String url) openUrl;

  @override
  State<BasePreviewScreen> createState() => _BasePreviewScreenState();
}

class _BasePreviewScreenState extends State<BasePreviewScreen> {
  final MapController _map = MapController();

  /// What was typed in the window, kept when the save failed, so nothing has to be typed again.
  CemeteryFormValues? _typed;
  bool _saveFailed = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _openSatellite() async {
    final bool opened = await widget.openUrl(
      satelliteUrl(widget.cemetery.point),
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie ma aplikacji, która to otworzy.')),
      );
    }
  }

  /// The window with the name and locality from the database (element 15, D20), then the save.
  Future<void> _add() async {
    final CemeteryFormValues? values = await showCemeteryForm(
      context,
      title: 'Nowy cmentarz',
      name: _typed?.name ?? widget.cemetery.name,
      locality: _typed == null ? widget.cemetery.locality : _typed!.locality,
      fromBase: true,
    );
    if (values == null || !mounted) return;
    try {
      final int id = await widget.onSave(values);
      if (mounted) Navigator.of(context).pop(id);
    } catch (_) {
      // Like the pick mode (element 17): the message in the error colour with its icon; the preview
      // stays, and the window comes back with what was typed.
      if (mounted) {
        setState(() {
          _typed = values;
          _saveFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final BaseCemetery c = widget.cemetery;
    final LatLng point = LatLng(c.point.lat, c.point.lon);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GrobingColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Cmentarz z bazy',
          style: TextStyle(
            color: GrobingColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.mapData == null
                ? const Center(
                    child: Text(
                      'Nie udało się narysować mapy.',
                      style: TextStyle(color: GrobingColors.textMuted),
                    ),
                  )
                : PolandMap(
                    data: widget.mapData!,
                    controller: _map,
                    pins: widget.saved,
                    placed: point,
                    placedLook: PinLook.outlined,
                    focus: point,
                  ),
          ),
          _card(c),
        ],
      ),
    );
  }

  Widget _card(BaseCemetery c) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      16 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Material(
      color: GrobingColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shownName(c),
              style: TextStyle(
                color: c.name.isEmpty
                    ? GrobingColors.textMuted
                    : GrobingColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              joinPlaceLine([c.place, 'woj. ${c.voivodeship}']),
              style: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 14,
              ),
            ),
            if (c.kind != null)
              Text(
                c.kind!,
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 4),
            _satelliteLink(),
            if (_saveFailed)
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
                    Flexible(
                      child: Text(
                        'Nie udało się zapisać. Spróbuj jeszcze raz.',
                        style: TextStyle(
                          color: GrobingColors.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: primaryButtonStyle,
              onPressed: _add,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Dodaj ten cmentarz'),
            ),
          ],
        ),
      ),
    ),
  );

  /// An external link (style-b.md rule 1): text in amber, underlined, and the ↗ arrow — as an icon,
  /// because Android draws the character U+2197 as a colour emoji (seen on the emulator). At least
  /// 48 dp high, growing — and wrapping — with a large system font, the arrow growing with the text.
  Widget _satelliteLink() => Semantics(
    link: true,
    label: 'Zobacz zdjęcie satelitarne, w innej aplikacji',
    excludeSemantics: true,
    child: InkWell(
      onTap: _openSatellite,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Zobacz zdjęcie satelitarne',
                style: TextStyle(
                  color: GrobingColors.amber,
                  fontSize: 15,
                  decoration: TextDecoration.underline,
                  decorationColor: GrobingColors.amber,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.north_east,
              size: MediaQuery.textScalerOf(context).scale(16),
              color: GrobingColors.amber,
            ),
          ],
        ),
      ),
    ),
  );
}
