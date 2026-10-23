import 'package:drift/drift.dart';

import 'database.dart';
import 'sectors.dart' show dropSectorIfUnused;

// Deleting what was added (ISSUE-053; 05_DESIGN/brand/style-b.md rule 16 — "wszystko, co można dodać, można też
// usunąć"): a cemetery, a grave, a person's burial in a grave, a person, a grave's pin and a family line. Each
// deletion is one transaction and returns what it took — the rows as they were, with their ids — so "Cofnij"
// puts them back as they were (mechanism H: no bin, no `deleted_at`, no change of the schema). A photo's file
// stays on the disk until the next sweep (`photos.dart` → sweepOrphanMedia, at a backup and at the start), so
// the rows put back find their files. The people of a grave or a cemetery never go with it: they stay, without
// that grave (the author at /pm 2026-10-23: "te osoby nie są usuwane a raczej tracą przypisany grób").

/// What a deletion took, to put back with "Cofnij" (K2): the rows it deleted — inserted again parents first,
/// with the same ids — and the rows it changed in place, written back over them afterwards.
class DeletionSnapshot {
  DeletionSnapshot._();

  final List<({int order, int seq, Future<void> Function() insert})> _taken =
      [];
  final List<Future<void> Function()> _changed = [];

  /// The people whose burials it took: a burial does not come back to someone who lies in another grave by then.
  final Set<int> _buried = {};

  /// Keeps [rows] of [table], deleted by the caller.
  void _keep<T extends Table, D>(
    GrobingDatabase db,
    TableInfo<T, D> table,
    Iterable<Insertable<D>> rows,
  ) {
    final List<Insertable<D>> kept = rows.toList();
    if (kept.isEmpty) return;
    _taken.add((
      order: _parentsFirst(db).indexOf(table.actualTableName),
      seq: _taken.length,
      insert: () async {
        for (final Insertable<D> row in kept) {
          await db.into(table).insert(row, mode: InsertMode.insertOrAbort);
        }
      },
    ));
  }

  /// Keeps [row] of [table] as it was, before the caller changes it in place.
  void _keepBefore<T extends Table, D>(
    GrobingDatabase db,
    TableInfo<T, D> table,
    Insertable<D> row,
  ) => _changed.add(() => db.update(table).replace(row));
}

/// The tables in the order their rows can be inserted: everything a row points at comes before it.
List<String> _parentsFirst(GrobingDatabase db) => [
  for (final TableInfo<Table, Object?> t in <TableInfo<Table, Object?>>[
    db.clans,
    db.persons,
    db.families,
    db.familyPartners,
    db.familyChildren,
    db.events,
    db.cemeteries,
    db.cemeteryPlans,
    db.sectors,
    db.graves,
    db.burials,
    db.assertions,
    db.media,
    db.personMedia,
    db.residences,
  ])
    t.actualTableName,
];

/// "Cofnij" cannot put a burial back: the person was added to another grave after the deletion — "Usuń z grobu",
/// then "Dodaj osobę" elsewhere, while the bar still stood (grob.md D23: nobody lies in two graves). Nothing is
/// written.
class RestoreRefused implements Exception {
  const RestoreRefused(this.personId);

  final int personId;
}

/// "Cofnij" (K2): what [snapshot] took comes back in one transaction — the same rows with the same ids, and
/// the rows it changed as they were. Through drift, so the screens and the background backup hear it. Throws
/// [RestoreRefused] when one of its people lies in another grave by now.
Future<void> restoreDeletion(GrobingDatabase db, DeletionSnapshot snapshot) =>
    db.transaction(() async {
      for (final int person in snapshot._buried) {
        if (await (db.select(db.burials)
                  ..where((b) => b.personId.equals(person))
                  ..limit(1))
                .getSingleOrNull() !=
            null) {
          throw RestoreRefused(person);
        }
      }
      final List<({int order, int seq, Future<void> Function() insert})> taken =
          [...snapshot._taken]..sort(
            (a, b) => a.order != b.order ? a.order - b.order : a.seq - b.seq,
          );
      for (final t in taken) {
        await t.insert();
      }
      for (final Future<void> Function() back in snapshot._changed) {
        await back();
      }
    });

// ---- the grave and the cemetery (05_DESIGN/grob.md 3d, D28; cmentarze.md 15a, D40) ----

/// What the window "Usunąć grób?" says (grob.md 3d): whether the grave has a photo, a pin and an address, and
/// the people who stay without it, in the order they were entered.
class GraveDeletionPreview {
  const GraveDeletionPreview({
    required this.name,
    required this.hasPhoto,
    required this.hasPin,
    required this.hasAddress,
    required this.people,
  });

  final String? name;
  final bool hasPhoto;
  final bool hasPin;
  final bool hasAddress;
  final List<({String? givenNames, String? surname})> people;
}

Future<GraveDeletionPreview> previewGraveDeletion(
  GrobingDatabase db,
  int graveId,
) async {
  final Grave grave = await _grave(db, graveId);
  final List<Person> people =
      await (db.select(db.persons).join([
              innerJoin(
                db.burials,
                db.burials.personId.equalsExp(db.persons.id),
              ),
            ])
            ..where(db.burials.graveId.equals(graveId))
            ..orderBy([OrderingTerm.asc(db.burials.id)]))
          .map((r) => r.readTable(db.persons))
          .get();
  final MediaFile? photo =
      await (db.select(db.media)
            ..where((m) => m.graveId.equals(graveId))
            ..limit(1))
          .getSingleOrNull();
  return GraveDeletionPreview(
    name: grave.name,
    hasPhoto: photo != null,
    hasPin: grave.lat != null && grave.lon != null,
    hasAddress:
        grave.sectorId != null || grave.row != null || grave.plot != null,
    people: [
      for (final Person p in people)
        (givenNames: p.givenNames, surname: p.surname),
    ],
  );
}

/// "Usuń grób" (grob.md 3d, D28): any grave. Its burials go with their claims — the people stay, without this
/// grave; its gravestone photo goes, its pin and address with its row; a sector left with neither a zone nor a
/// grave goes, as when an address changes (cmentarz.md D27).
Future<DeletionSnapshot> deleteGrave(GrobingDatabase db, int graveId) =>
    db.transaction(() async {
      final DeletionSnapshot taken = DeletionSnapshot._();
      await _takeGrave(db, taken, graveId);
      return taken;
    });

Future<void> _takeGrave(
  GrobingDatabase db,
  DeletionSnapshot taken,
  int graveId,
) async {
  final Grave grave = await _grave(db, graveId);
  final List<Burial> burials = await (db.select(
    db.burials,
  )..where((b) => b.graveId.equals(graveId))).get();
  await _takeBurials(db, taken, burials);
  await _takeMedia(db, taken, (m) => m.graveId.equals(graveId), grave: true);
  taken._keep(db, db.graves, [grave]);
  await (db.delete(db.graves)..where((g) => g.id.equals(graveId))).go();
  if (grave.sectorId case final int sectorId) {
    final SectorRow? sector = await _sector(db, sectorId);
    await dropSectorIfUnused(db, sectorId);
    if (sector != null && await _sector(db, sectorId) == null) {
      taken._keep(db, db.sectors, [sector]);
    }
  }
}

/// What the window "Usunąć cmentarz?" says (cmentarze.md 15a): its graves and the people in them, whether it
/// has a plan, sectors and a photo, and what of these its graves have.
class CemeteryDeletionPreview {
  const CemeteryDeletionPreview({
    required this.graves,
    required this.people,
    required this.gravesWithPhoto,
    required this.gravesWithPin,
    required this.gravesWithAddress,
    required this.hasPlan,
    required this.hasSectors,
    required this.hasPhoto,
  });

  final int graves;

  /// Different people buried in its graves.
  final int people;
  final int gravesWithPhoto;
  final int gravesWithPin;
  final int gravesWithAddress;
  final bool hasPlan;
  final bool hasSectors;
  final bool hasPhoto;
}

Future<CemeteryDeletionPreview> previewCemeteryDeletion(
  GrobingDatabase db,
  int cemeteryId,
) async {
  await _cemetery(db, cemeteryId);
  final List<Grave> graves = await (db.select(
    db.graves,
  )..where((g) => g.cemeteryId.equals(cemeteryId))).get();
  final Set<int> graveIds = {for (final Grave g in graves) g.id};
  final Set<int> people = {
    for (final Burial b in await (db.select(
      db.burials,
    )..where((b) => b.graveId.isIn(graveIds))).get())
      b.personId,
  };
  final Set<int> withPhoto = {
    for (final MediaFile m in await (db.select(
      db.media,
    )..where((m) => m.graveId.isIn(graveIds))).get())
      m.graveId!,
  };
  return CemeteryDeletionPreview(
    graves: graves.length,
    people: people.length,
    gravesWithPhoto: withPhoto.length,
    gravesWithPin: graves.where((g) => g.lat != null && g.lon != null).length,
    gravesWithAddress: graves
        .where((g) => g.sectorId != null || g.row != null || g.plot != null)
        .length,
    // A plan the screens show: "W OpenStreetMap nie ma planu" is a row too, and no plan to lose (dev pass).
    hasPlan:
        await (db.select(db.cemeteryPlans)..where(
              (p) =>
                  p.cemeteryId.equals(cemeteryId) &
                  p.status.equalsValue(PlanStatus.ok),
            ))
            .getSingleOrNull() !=
        null,
    hasSectors:
        await (db.select(db.sectors)
              ..where((s) => s.cemeteryId.equals(cemeteryId))
              ..limit(1))
            .getSingleOrNull() !=
        null,
    hasPhoto:
        await (db.select(db.media)
              ..where((m) => m.cemeteryId.equals(cemeteryId))
              ..limit(1))
            .getSingleOrNull() !=
        null,
  );
}

/// "Usuń cmentarz" (cmentarze.md 15a, D40): any cemetery. Its graves go as [deleteGrave] takes one — the people
/// stay, without a grave — then its plan, its sectors and its photo.
Future<DeletionSnapshot> deleteCemetery(GrobingDatabase db, int cemeteryId) =>
    db.transaction(() async {
      final DeletionSnapshot taken = DeletionSnapshot._();
      final Cemetery cemetery = await _cemetery(db, cemeteryId);
      for (final Grave g in await (db.select(
        db.graves,
      )..where((g) => g.cemeteryId.equals(cemeteryId))).get()) {
        await _takeGrave(db, taken, g.id);
      }
      final CemeteryPlanRow? plan = await (db.select(
        db.cemeteryPlans,
      )..where((p) => p.cemeteryId.equals(cemeteryId))).getSingleOrNull();
      if (plan != null) {
        taken._keep(db, db.cemeteryPlans, [plan]);
        await (db.delete(
          db.cemeteryPlans,
        )..where((p) => p.cemeteryId.equals(cemeteryId))).go();
      }
      taken._keep(
        db,
        db.sectors,
        await (db.select(
          db.sectors,
        )..where((s) => s.cemeteryId.equals(cemeteryId))).get(),
      );
      await (db.delete(
        db.sectors,
      )..where((s) => s.cemeteryId.equals(cemeteryId))).go();
      await _takeMedia(
        db,
        taken,
        (m) => m.cemeteryId.equals(cemeteryId),
        grave: false,
      );
      taken._keep(db, db.cemeteries, [cemetery]);
      await (db.delete(
        db.cemeteries,
      )..where((c) => c.id.equals(cemeteryId))).go();
      return taken;
    });

/// The photos [where] picks — a grave's ([grave]) or a cemetery's. One that someone is also on stays for them,
/// without the grave or the cemetery; the rest go (their files with the next sweep).
Future<void> _takeMedia(
  GrobingDatabase db,
  DeletionSnapshot taken,
  Expression<bool> Function($MediaTable m) where, {
  required bool grave,
}) async {
  for (final MediaFile m in await (db.select(db.media)..where(where)).get()) {
    final bool onSomeone =
        await (db.select(db.personMedia)
              ..where((l) => l.mediaId.equals(m.id))
              ..limit(1))
            .getSingleOrNull() !=
        null;
    if (onSomeone) {
      taken._keepBefore(db, db.media, m);
      await (db.update(db.media)..where((x) => x.id.equals(m.id))).write(
        grave
            ? const MediaCompanion(graveId: Value(null))
            : const MediaCompanion(cemeteryId: Value(null)),
      );
    } else {
      taken._keep(db, db.media, [m]);
      await (db.delete(db.media)..where((x) => x.id.equals(m.id))).go();
    }
  }
}

// ---- a person's burial (05_DESIGN/wpis-osoby.md 12a; grob.md D29) ----

/// The grave a person is taken out of, as the window "Usunąć z grobu?" names it: its name, or its cemetery's.
Future<({String? graveName, String cemeteryName})> graveLabel(
  GrobingDatabase db,
  int graveId,
) async {
  final Grave grave = await _grave(db, graveId);
  final Cemetery cemetery = await _cemetery(db, grave.cemeteryId);
  return (graveName: grave.name, cemeteryName: cemetery.name);
}

/// "Usuń z grobu" (wpis-osoby.md 12a): [personId]'s burial in [graveId] goes with its claims. The person stays,
/// buried nowhere — and so free for "Dodaj osobę" in another grave (grob.md D22) — with their dates, the burial
/// date too: it is a fact about them, not about the grave.
Future<DeletionSnapshot> removeFromGrave(
  GrobingDatabase db,
  int personId,
  int graveId,
) => db.transaction(() async {
  final List<Burial> burials =
      await (db.select(db.burials)..where(
            (b) => b.personId.equals(personId) & b.graveId.equals(graveId),
          ))
          .get();
  if (burials.isEmpty) {
    throw StateError('Person $personId is not in grave $graveId');
  }
  final DeletionSnapshot taken = DeletionSnapshot._();
  await _takeBurials(db, taken, burials);
  return taken;
});

Future<void> _takeBurials(
  GrobingDatabase db,
  DeletionSnapshot taken,
  List<Burial> burials,
) async {
  final Set<int> ids = {for (final Burial b in burials) b.id};
  if (ids.isEmpty) return;
  taken._buried.addAll(burials.map((b) => b.personId));
  taken._keep(
    db,
    db.assertions,
    await (db.select(db.assertions)..where((a) => a.burialId.isIn(ids))).get(),
  );
  await (db.delete(db.assertions)..where((a) => a.burialId.isIn(ids))).go();
  taken._keep(db, db.burials, burials);
  await (db.delete(db.burials)..where((b) => b.id.isIn(ids))).go();
}

// ---- a person (05_DESIGN/wpis-osoby.md 12) ----

/// A union of the person in the window "Usunąć osobę?": who of it stays — the partner, and how many children.
typedef UnionLeft = ({
  ({String? givenNames, String? surname})? partner,
  int children,
});

/// What the window "Usunąć osobę?" lists (wpis-osoby.md 12) — only what the person has.
class PersonDeletionPreview {
  const PersonDeletionPreview({
    required this.isMe,
    required this.burial,
    required this.unions,
    required this.hasParents,
    required this.residences,
    required this.ownPhotos,
    required this.sharedPhotos,
  });

  /// "Ja" cannot be deleted (wpis-osoby.md 12): the tree and the names of kinship stand on it.
  final bool isMe;

  /// The grave of their first burial.
  final ({String? graveName, String cemeteryName})? burial;
  final List<UnionLeft> unions;

  /// A child in a family of parents.
  final bool hasParents;
  final int residences;

  /// Photos nobody else is on, and not a grave's or a cemetery's: they go with the person.
  final int ownPhotos;

  /// Photos with someone else on them, or a grave's or a cemetery's: they stay.
  final int sharedPhotos;
}

Future<PersonDeletionPreview> previewPersonDeletion(
  GrobingDatabase db,
  int personId,
) async {
  await _person(db, personId);
  final Burial? burial =
      await (db.select(db.burials)
            ..where((b) => b.personId.equals(personId))
            ..orderBy([(b) => OrderingTerm.asc(b.id)])
            ..limit(1))
          .getSingleOrNull();
  final List<UnionLeft> unions = [];
  for (final FamilyPartner link in await (db.select(
    db.familyPartners,
  )..where((p) => p.personId.equals(personId))).get()) {
    final List<Person> others =
        await (db.select(db.persons).join([
              innerJoin(
                db.familyPartners,
                db.familyPartners.personId.equalsExp(db.persons.id),
              ),
            ])..where(
              db.familyPartners.familyId.equals(link.familyId) &
                  db.familyPartners.personId.equals(personId).not(),
            ))
            .map((r) => r.readTable(db.persons))
            .get();
    final int children = (await (db.select(
      db.familyChildren,
    )..where((c) => c.familyId.equals(link.familyId))).get()).length;
    unions.add((
      partner: others.isEmpty
          ? null
          : (
              givenNames: others.first.givenNames,
              surname: others.first.surname,
            ),
      children: children,
    ));
  }
  int own = 0;
  int shared = 0;
  for (final PersonMediaData link in await (db.select(
    db.personMedia,
  )..where((l) => l.personId.equals(personId))).get()) {
    if (await _mediaStaysWithout(db, link.mediaId, personId)) {
      shared++;
    } else {
      own++;
    }
  }
  return PersonDeletionPreview(
    isMe: await _meId(db) == personId,
    burial: burial == null ? null : await graveLabel(db, burial.graveId),
    unions: unions,
    hasParents:
        await (db.select(db.familyChildren)
              ..where((c) => c.personId.equals(personId))
              ..limit(1))
            .getSingleOrNull() !=
        null,
    residences: (await (db.select(
      db.residences,
    )..where((r) => r.personId.equals(personId))).get()).length,
    ownPhotos: own,
    sharedPhotos: shared,
  );
}

/// "Usuń osobę" (wpis-osoby.md 12): the person with everything that is theirs — their events and burials with
/// the claims, their place in unions and in their family of parents, their residences, their links to photos
/// and the photos nobody else is on. A union left without what makes one — a partner, and two people — goes
/// whole, its dates too, as "Usuń związek" takes it (rodzina.md D8); its people stay. Never "ja" (StateError).
Future<DeletionSnapshot> deletePerson(GrobingDatabase db, int personId) =>
    db.transaction(() async {
      if (await _meId(db) == personId) {
        throw StateError('Person $personId is "ja"');
      }
      final Person person = await _person(db, personId);
      final DeletionSnapshot taken = DeletionSnapshot._();

      final List<Event> events = await (db.select(
        db.events,
      )..where((e) => e.personId.equals(personId))).get();
      await _takeEvents(db, taken, events);
      await _takeBurials(
        db,
        taken,
        await (db.select(
          db.burials,
        )..where((b) => b.personId.equals(personId))).get(),
      );

      final List<FamilyPartner> partners = await (db.select(
        db.familyPartners,
      )..where((p) => p.personId.equals(personId))).get();
      taken._keep(db, db.familyPartners, partners);
      await (db.delete(
        db.familyPartners,
      )..where((p) => p.personId.equals(personId))).go();
      final List<FamilyChildrenData> asChild = await (db.select(
        db.familyChildren,
      )..where((c) => c.personId.equals(personId))).get();
      await _takeChildLinks(db, taken, asChild);
      for (final int family in {
        for (final FamilyPartner p in partners) p.familyId,
        for (final FamilyChildrenData c in asChild) c.familyId,
      }) {
        await _takeFamilyIfEmpty(db, taken, family);
      }

      taken._keep(
        db,
        db.residences,
        await (db.select(
          db.residences,
        )..where((r) => r.personId.equals(personId))).get(),
      );
      await (db.delete(
        db.residences,
      )..where((r) => r.personId.equals(personId))).go();

      final List<PersonMediaData> links = await (db.select(
        db.personMedia,
      )..where((l) => l.personId.equals(personId))).get();
      final List<int> alone = [
        for (final PersonMediaData l in links)
          if (!await _mediaStaysWithout(db, l.mediaId, personId)) l.mediaId,
      ];
      taken._keep(db, db.personMedia, links);
      await (db.delete(
        db.personMedia,
      )..where((l) => l.personId.equals(personId))).go();
      taken._keep(
        db,
        db.media,
        await (db.select(db.media)..where((m) => m.id.isIn(alone))).get(),
      );
      await (db.delete(db.media)..where((m) => m.id.isIn(alone))).go();

      taken._keep(db, db.persons, [person]);
      await (db.delete(db.persons)..where((p) => p.id.equals(personId))).go();
      return taken;
    });

/// The photo stays when [personId] goes: someone else is on it, or it is a grave's or a cemetery's.
Future<bool> _mediaStaysWithout(
  GrobingDatabase db,
  int mediaId,
  int personId,
) async {
  final MediaFile m = await (db.select(
    db.media,
  )..where((x) => x.id.equals(mediaId))).getSingle();
  if (m.graveId != null || m.cemeteryId != null) return true;
  return await (db.select(db.personMedia)
            ..where(
              (l) =>
                  l.mediaId.equals(mediaId) & l.personId.equals(personId).not(),
            )
            ..limit(1))
          .getSingleOrNull() !=
      null;
}

Future<void> _takeEvents(
  GrobingDatabase db,
  DeletionSnapshot taken,
  List<Event> events,
) async {
  final Set<int> ids = {for (final Event e in events) e.id};
  if (ids.isEmpty) return;
  taken._keep(
    db,
    db.assertions,
    await (db.select(db.assertions)..where((a) => a.eventId.isIn(ids))).get(),
  );
  await (db.delete(db.assertions)..where((a) => a.eventId.isIn(ids))).go();
  taken._keep(db, db.events, events);
  await (db.delete(db.events)..where((e) => e.id.isIn(ids))).go();
}

Future<void> _takeChildLinks(
  GrobingDatabase db,
  DeletionSnapshot taken,
  List<FamilyChildrenData> links,
) async {
  final Set<int> ids = {for (final FamilyChildrenData l in links) l.id};
  if (ids.isEmpty) return;
  taken._keep(
    db,
    db.assertions,
    await (db.select(
      db.assertions,
    )..where((a) => a.familyChildId.isIn(ids))).get(),
  );
  await (db.delete(
    db.assertions,
  )..where((a) => a.familyChildId.isIn(ids))).go();
  taken._keep(db, db.familyChildren, links);
  await (db.delete(db.familyChildren)..where((c) => c.id.isIn(ids))).go();
}

/// [familyId] after someone left it: one or two partners and two people make a family (`families.dart` →
/// saveFamily); with less it goes whole — its links, its dates and its claims — and its people stay.
Future<void> _takeFamilyIfEmpty(
  GrobingDatabase db,
  DeletionSnapshot taken,
  int familyId,
) async {
  final List<FamilyPartner> partners = await (db.select(
    db.familyPartners,
  )..where((p) => p.familyId.equals(familyId))).get();
  final List<FamilyChildrenData> children = await (db.select(
    db.familyChildren,
  )..where((c) => c.familyId.equals(familyId))).get();
  if (partners.isNotEmpty && partners.length + children.length >= 2) return;
  await _takeChildLinks(db, taken, children);
  taken._keep(db, db.familyPartners, partners);
  await (db.delete(
    db.familyPartners,
  )..where((p) => p.familyId.equals(familyId))).go();
  await _takeEvents(
    db,
    taken,
    await (db.select(
      db.events,
    )..where((e) => e.familyId.equals(familyId))).get(),
  );
  taken._keep(
    db,
    db.assertions,
    await (db.select(
      db.assertions,
    )..where((a) => a.familyId.equals(familyId))).get(),
  );
  await (db.delete(
    db.assertions,
  )..where((a) => a.familyId.equals(familyId))).go();
  taken._keep(
    db,
    db.families,
    await (db.select(db.families)..where((f) => f.id.equals(familyId))).get(),
  );
  await (db.delete(db.families)..where((f) => f.id.equals(familyId))).go();
}

// ---- the pin (05_DESIGN/cmentarz.md 12b, D43) ----

/// "Usuń pinezkę" (cmentarz.md 12b): the grave without its pin — the point, its source, accuracy and date; the
/// address stays. "Cofnij" writes back the same pin.
Future<DeletionSnapshot> deleteGravePin(GrobingDatabase db, int graveId) =>
    db.transaction(() async {
      final Grave grave = await _grave(db, graveId);
      final DeletionSnapshot taken = DeletionSnapshot._()
        .._keepBefore(db, db.graves, grave);
      await (db.update(db.graves)..where((g) => g.id.equals(graveId))).write(
        const GravesCompanion(
          lat: Value(null),
          lon: Value(null),
          positionSource: Value(null),
          positionAccuracyM: Value(null),
          positionRecordedAt: Value(null),
        ),
      );
      return taken;
    });

// ---- the family line (05_DESIGN/wieniec.md F7, D21) ----

/// "Usuń ród" (wieniec.md F7, D21): the line, and the choice of it at the people who chose it. A wreath is worked
/// out from the tree (ADR-021), so they get what the rule gives without the line — the father's, or none; a
/// "Bez wieńca" chosen at someone stays.
Future<DeletionSnapshot> deleteClan(GrobingDatabase db, int clanId) =>
    db.transaction(() async {
      final ClanRow clan = await (db.select(
        db.clans,
      )..where((c) => c.id.equals(clanId))).getSingle();
      final DeletionSnapshot taken = DeletionSnapshot._();
      for (final Person p in await (db.select(
        db.persons,
      )..where((p) => p.clanId.equals(clanId))).get()) {
        taken._keepBefore(db, db.persons, p);
      }
      await (db.update(db.persons)..where((p) => p.clanId.equals(clanId)))
          .write(const PersonsCompanion(clanId: Value(null)));
      taken._keep(db, db.clans, [clan]);
      await (db.delete(db.clans)..where((c) => c.id.equals(clanId))).go();
      return taken;
    });

// ---- reading ----

Future<Grave> _grave(GrobingDatabase db, int graveId) async =>
    await (db.select(
      db.graves,
    )..where((g) => g.id.equals(graveId))).getSingleOrNull() ??
    (throw StateError('No grave with id $graveId'));

Future<Cemetery> _cemetery(GrobingDatabase db, int cemeteryId) async =>
    await (db.select(
      db.cemeteries,
    )..where((c) => c.id.equals(cemeteryId))).getSingleOrNull() ??
    (throw StateError('No cemetery with id $cemeteryId'));

Future<Person> _person(GrobingDatabase db, int personId) async =>
    await (db.select(
      db.persons,
    )..where((p) => p.id.equals(personId))).getSingleOrNull() ??
    (throw StateError('No person with id $personId'));

Future<SectorRow?> _sector(GrobingDatabase db, int sectorId) => (db.select(
  db.sectors,
)..where((s) => s.id.equals(sectorId))).getSingleOrNull();

Future<int?> _meId(GrobingDatabase db) async =>
    (await db.select(db.settings).getSingleOrNull())?.mePersonId;
