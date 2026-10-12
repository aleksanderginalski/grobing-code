import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../../data/database.dart';
import '../map/plan_downloads.dart';
import 'cemetery_form.dart';
import 'pick_point_screen.dart';
import 'poland_map.dart';
import 'poland_map_data.dart';

/// A cemetery to correct: what the window and the pick mode start from.
typedef CemeteryToEdit = ({
  int id,
  String name,
  String? locality,
  GeoPoint? point,
});

/// Adding a cemetery by hand ([cemetery] null) or correcting one (05_DESIGN/cmentarze.md, elements 15–17):
/// the window, then the pick mode. Closing the pick mode brings the window back with what was typed;
/// cancelling the window ends it all. [pointOnly] skips the window — "Wskaż na mapie" of a cemetery without
/// a point (05_DESIGN/cmentarz.md, element 2a (e)); closing the pick mode then ends it.
///
/// One way for the ✎ on the map's sheet, the ✎ on the cemetery screen and "Wskaż na mapie" (ISSUE-027). A
/// cemetery saved with a point gets its plan downloaded (ISSUE-027 D3; a new point deleted the old plan —
/// `updateCemetery`). Returns the saved cemetery's id and point; null when nothing was saved.
Future<({int id, GeoPoint? point})?> editCemetery(
  BuildContext context, {
  required GrobingDatabase database,
  required Future<PolandMapData> mapData,
  required List<MapPin> others,
  CemeteryToEdit? cemetery,
  String name = '',
  bool pointOnly = false,
}) async {
  assert(!pointOnly || cemetery != null);
  final PlanDownloads? plans = MapNetwork.maybeOf(context)?.plans;
  final NavigatorState navigator = Navigator.of(context);
  final PolandMapData map = await mapData;
  String currentName = cemetery?.name ?? name;
  String? currentLocality = cemetery?.locality;
  GeoPoint? currentPoint = cemetery?.point;
  while (true) {
    if (!context.mounted) return null;
    if (!pointOnly) {
      final CemeteryFormValues? values = await showCemeteryForm(
        context,
        title: cemetery == null ? 'Nowy cmentarz' : 'Popraw cmentarz',
        name: currentName,
        locality: currentLocality,
      );
      if (values == null || !context.mounted) return null;
      currentName = values.name;
      currentLocality = values.locality;
    }
    int? savedId = cemetery?.id;
    final String pickName = currentName;
    final String? pickLocality = currentLocality;
    final bool? saved = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => PickPointScreen(
          mapData: map,
          name: pickName,
          initial: currentPoint,
          others: others,
          onSave: (point) async {
            currentPoint = point;
            if (cemetery == null) {
              savedId = await addCemetery(
                database,
                name: pickName,
                locality: pickLocality,
                point: point,
              );
            } else {
              await updateCemetery(
                database,
                cemetery.id,
                name: pickName,
                locality: pickLocality,
                point: point,
              );
            }
          },
        ),
      ),
    );
    if (saved == true) {
      if (currentPoint != null) unawaited(plans?.download(savedId!));
      return (id: savedId!, point: currentPoint);
    }
    if (pointOnly) return null;
  }
}
