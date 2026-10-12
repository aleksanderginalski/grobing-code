import 'package:drift/drift.dart';

import 'address_text.dart';
import 'cemeteries.dart';
import 'cemetery_plans.dart';
import 'database.dart';

/// A sector of a cemetery as the screens show it (05_DESIGN/cmentarz.md, elements 4 and 17; ISSUE-028,
/// ADR-016): its name, its zone or none, and how many graves of its cemetery have it in their address.
class Sector {
  const Sector({
    required this.id,
    required this.name,
    this.zone,
    required this.graveCount,
  });

  final int id;

  /// Without "Kwatera" in front: the screens put it there ("Kwatera B").
  final String name;

  /// The ring the author marked; null — a sector that lives in the addresses only (US-007 AC-4).
  final List<GeoPoint>? zone;
  final int graveCount;
}

/// Another sector of the cemetery already has the name — "b" and "B" are one (`address_text.dart`):
/// "Kwatera B już jest na liście — wybierz ją tam." (element 19).
class SectorNameTaken implements Exception {
  const SectorNameTaken(this.name);

  /// The name of the sector already there.
  final String name;

  @override
  String toString() => 'SectorNameTaken($name)';
}

/// The sectors of [cemeteryId] in the order they were added; the screens sort them. A new value after every
/// write to the sectors or to the graves (their counts).
Stream<List<Sector>> watchSectors(GrobingDatabase db, int cemeteryId) => db
    .customSelect(
      'SELECT s.id, s.name, s.zone, '
      '(SELECT COUNT(*) FROM graves g WHERE g.sector_id = s.id) AS grave_count '
      'FROM sectors s WHERE s.cemetery_id = ? ORDER BY s.id',
      variables: [Variable.withInt(cemeteryId)],
      readsFrom: {db.sectors, db.graves},
    )
    .watch()
    .map(
      (rows) => [
        for (final QueryRow r in rows)
          Sector(
            id: r.read<int>('id'),
            name: r.read<String>('name'),
            zone: switch (r.readNullable<String>('zone')) {
              final String json => decodeRing(json),
              null => null,
            },
            graveCount: r.read<int>('grave_count'),
          ),
      ],
    );

/// A new sector of [cemeteryId] with its zone ("Zaznacz kwaterę", elements 19a and 18); returns its id.
/// Throws [SectorNameTaken] when the cemetery has the name already.
Future<int> addSector(
  GrobingDatabase db,
  int cemeteryId, {
  required String name,
  required List<GeoPoint> zone,
}) => db.transaction(() async {
  final String clean = _name(name);
  await _requireFree(db, cemeteryId, sectorKey(clean));
  return db
      .into(db.sectors)
      .insert(
        SectorsCompanion.insert(
          cemeteryId: cemeteryId,
          name: clean,
          nameKey: sectorKey(clean),
          zone: Value(encodeRing(_ring(zone))),
        ),
      );
});

/// ✎ at a sector (element 19b): every address with it says the new name at once (ADR-016). Throws
/// [SectorNameTaken] when another sector of the cemetery has the name.
Future<void> renameSector(GrobingDatabase db, int sectorId, String name) =>
    db.transaction(() async {
      final SectorRow sector = await _sector(db, sectorId);
      final String clean = _name(name);
      final String key = sectorKey(clean);
      if (key != sector.nameKey) {
        await _requireFree(db, sector.cemeteryId, key);
      }
      await (db.update(db.sectors)..where((s) => s.id.equals(sectorId))).write(
        SectorsCompanion(name: Value(clean), nameKey: Value(key)),
      );
    });

/// "Narysuj strefę" and "Narysuj strefę od nowa" (element 18): the sector's zone, the old one replaced.
Future<void> setSectorZone(
  GrobingDatabase db,
  int sectorId,
  List<GeoPoint> zone,
) async {
  final int updated =
      await (db.update(db.sectors)..where((s) => s.id.equals(sectorId))).write(
        SectorsCompanion(zone: Value(encodeRing(_ring(zone)))),
      );
  if (updated != 1) throw StateError('No sector with id $sectorId');
}

/// "Usuń z planu" (element 19c, cmentarz.md D27): only the zone goes — the graves' addresses stay. A sector
/// left with neither a zone nor a grave goes with it.
Future<void> removeSectorZone(GrobingDatabase db, int sectorId) =>
    db.transaction(() async {
      await (db.update(db.sectors)..where((s) => s.id.equals(sectorId))).write(
        const SectorsCompanion(zone: Value(null)),
      );
      await dropSectorIfUnused(db, sectorId);
    });

/// The sector of an address typed in "Popraw grób" (05_DESIGN/grob.md, element 3b): the cemetery's sector
/// with that name — "b" finds "B" — or a new one without a zone; null when nothing was typed.
Future<int?> sectorForAddress(
  GrobingDatabase db,
  int cemeteryId,
  String? typed,
) async {
  final String? clean = addressPart(typed, sectorWord);
  if (clean == null) return null;
  final SectorRow? found = await _byKey(db, cemeteryId, sectorKey(clean));
  if (found != null) return found.id;
  return db
      .into(db.sectors)
      .insert(
        SectorsCompanion.insert(
          cemeteryId: cemeteryId,
          name: clean,
          nameKey: sectorKey(clean),
        ),
      );
}

/// Deletes [sectorId] when it has neither a zone nor a grave: such a sector is nowhere to be seen
/// (cmentarz.md D27).
Future<void> dropSectorIfUnused(GrobingDatabase db, int sectorId) =>
    db.customUpdate(
      'DELETE FROM sectors WHERE id = ? AND zone IS NULL '
      'AND NOT EXISTS (SELECT 1 FROM graves WHERE sector_id = ?)',
      variables: [Variable.withInt(sectorId), Variable.withInt(sectorId)],
      updates: {db.sectors},
      updateKind: UpdateKind.delete,
    );

String _name(String typed) =>
    addressPart(typed, sectorWord) ??
    (throw ArgumentError.value(typed, 'name', 'a sector needs a name'));

/// A zone is a ring of at least three corners (element 18: "potrzebne co najmniej 3").
List<GeoPoint> _ring(List<GeoPoint> zone) {
  if (zone.length < 3) {
    throw ArgumentError.value(zone.length, 'zone', 'needs 3 corners or more');
  }
  return zone;
}

Future<SectorRow> _sector(GrobingDatabase db, int sectorId) async {
  final SectorRow? row = await (db.select(
    db.sectors,
  )..where((s) => s.id.equals(sectorId))).getSingleOrNull();
  if (row == null) throw StateError('No sector with id $sectorId');
  return row;
}

Future<SectorRow?> _byKey(GrobingDatabase db, int cemeteryId, String key) =>
    (db.select(db.sectors)..where(
          (s) => s.cemeteryId.equals(cemeteryId) & s.nameKey.equals(key),
        ))
        .getSingleOrNull();

Future<void> _requireFree(
  GrobingDatabase db,
  int cemeteryId,
  String key,
) async {
  final SectorRow? taken = await _byKey(db, cemeteryId, key);
  if (taken != null) throw SectorNameTaken(taken.name);
}
