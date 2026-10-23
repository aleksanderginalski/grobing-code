import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cemeteries.dart';
import '../../data/database.dart';
import '../../data/deletion.dart';
import '../map/plan_downloads.dart';
import '../widgets/deletion.dart';
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
///
/// A correction's window has "Usuń cmentarz" (element 15a, ISSUE-053): once the cemetery went, [onDeleted]
/// leaves what showed it and the bar with "Cofnij" comes (K2); [onRestored] follows "Cofnij".
Future<({int id, GeoPoint? point})?> editCemetery(
  BuildContext context, {
  required GrobingDatabase database,
  required Future<PolandMapData> mapData,
  required List<MapPin> others,
  CemeteryToEdit? cemetery,
  String name = '',
  bool pointOnly = false,
  VoidCallback? onDeleted,
  void Function(int id)? onRestored,
}) async {
  assert(!pointOnly || cemetery != null);
  final PlanDownloads? plans = MapNetwork.maybeOf(context)?.plans;
  final NavigatorState navigator = Navigator.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final PolandMapData map = await mapData;
  String currentName = cemetery?.name ?? name;
  String? currentLocality = cemetery?.locality;
  GeoPoint? currentPoint = cemetery?.point;
  DeletionSnapshot? deleted;
  while (true) {
    if (!context.mounted) return null;
    if (!pointOnly) {
      final CemeteryFormValues? values = await showCemeteryForm(
        context,
        title: cemetery == null ? 'Nowy cmentarz' : 'Popraw cmentarz',
        name: currentName,
        locality: currentLocality,
        onDelete: cemetery == null
            ? null
            : (formContext) async {
                deleted = await _confirmDelete(formContext, database, cemetery);
                return deleted != null;
              },
      );
      if (deleted case final DeletionSnapshot taken) {
        onDeleted?.call();
        unawaited(
          showUndoBar(
            messenger,
            database: database,
            message: 'Usunięto cmentarz „${cemetery!.name}”.',
            snapshot: taken,
            onRestored: () => onRestored?.call(cemetery.id),
          ),
        );
        return null;
      }
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

/// "Usunąć cmentarz?" (element 15a, D40): what the cemetery has goes with it; the people of its graves stay.
Future<DeletionSnapshot?> _confirmDelete(
  BuildContext context,
  GrobingDatabase database,
  CemeteryToEdit cemetery,
) async {
  final CemeteryDeletionPreview preview = await previewCemeteryDeletion(
    database,
    cemetery.id,
  );
  if (!context.mounted) return null;
  return confirmDeletion<DeletionSnapshot>(
    context,
    title: 'Usunąć cmentarz?',
    content: cemeteryDeletionContent(cemetery.name, preview),
    delete: () => deleteCemetery(database, cemetery.id),
  );
}

/// The words of "Usunąć cmentarz?" (cmentarze.md 15a): only what [p] says the cemetery has.
List<Widget> cemeteryDeletionContent(String name, CemeteryDeletionPreview p) {
  final List<String> own = [
    if (p.hasPlan) 'planem',
    if (p.hasSectors) 'kwaterami',
    if (p.hasPhoto) 'zdjęciem',
  ];
  if (p.graves == 0) {
    return [
      DeletionText(
        own.isEmpty
            ? '„$name” zniknie z\u00A0mapy.'
            : '„$name” zniknie z\u00A0mapy razem ${withWord(own.first)}${andList(own)}.',
      ),
    ];
  }
  final bool one = p.graves == 1;
  final List<String> ofGraves = [
    if (p.gravesWithPhoto > 0) one ? 'zdjęciem' : 'zdjęciami',
    if (p.gravesWithPin > 0) one ? 'pinezką' : 'pinezkami',
    if (p.gravesWithAddress > 0) one ? 'adresem' : 'adresami',
  ];
  final String graves = one ? '1\u00A0grobem' : '${p.graves}\u00A0grobami';
  final String from = one ? 'z\u00A0tego grobu' : 'z\u00A0tych grobów';
  return [
    DeletionText('„$name” zniknie z\u00A0mapy razem z:'),
    DeletionList([
      ofGraves.isEmpty
          ? graves
          : '$graves, z\u00A0${one ? 'jego' : 'ich'} ${andList(ofGraves)}',
      if (p.hasPlan || p.hasSectors)
        andList([if (p.hasPlan) 'planem', if (p.hasSectors) 'kwaterami']),
      if (p.hasPhoto) 'zdjęciem cmentarza',
    ]),
    if (p.people == 1)
      DeletionNote('Osoba $from zostaje w\u00A0aplikacji — bez grobu.')
    else if (p.people > 1)
      DeletionNote(
        'Osoby $from (${p.people}) zostają w\u00A0aplikacji — bez grobu.',
      ),
  ];
}
