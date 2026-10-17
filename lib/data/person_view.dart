import 'package:drift/drift.dart';

import 'claims.dart';
import 'database.dart';
import 'families.dart';
import 'family_tree.dart' show loadFamilyTree;
import 'graves.dart';
import 'kinship.dart';
import 'photos.dart';
import 'residences.dart';
import 'wreaths.dart';

/// Where the person lies, as the "Pochówek" row shows it (05_DESIGN/osoba.md element 9): their first
/// burial (ADR-006 D3) — the grave and its cemetery.
class BurialPlace {
  const BurialPlace({
    required this.graveId,
    required this.cemeteryId,
    required this.cemeteryName,
    this.graveName,
    this.sector,
    this.row,
    this.plot,
  });

  final int graveId;
  final int cemeteryId;
  final String cemeteryName;
  final String? graveName;
  final String? sector;
  final String? row;
  final String? plot;
}

/// One person on the chain from "ja" (osoba.md element 7): the step that reaches them and who they are.
class ChainLink {
  const ChainLink({
    required this.step,
    this.sex,
    this.givenNames,
    this.surname,
    this.profile,
  });

  final KinStep step;
  final Sex? sex;
  final String? givenNames;
  final String? surname;
  final ProfilePhoto? profile;
}

/// Everything the person's view shows (osoba.md, ISSUE-024).
class PersonView {
  const PersonView({
    required this.id,
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.sex,
    this.bio,
    required this.isLiving,
    this.birth,
    this.death,
    this.profile,
    this.backgroundPath,
    required this.photoCount,
    required this.firstPhotos,
    this.burial,
    this.residences = const [],
    required this.relations,
    required this.relativeProfiles,
    this.meId,
    this.chain,
    this.wreath = PersonWreath.empty,
  });

  /// The wreath of the person's family line around the portrait (element 3, 4a — ISSUE-044).
  final PersonWreath wreath;

  final int id;
  final String? givenNames;
  final String? surname;
  final String? birthSurname;
  final Sex? sex;
  final String? bio;
  final bool isLiving;

  /// The first birth and death written (ADR-006 D3).
  final QualifiedDate? birth;
  final QualifiedDate? death;

  /// The profile photo — the first link — and its crop.
  final ProfilePhoto? profile;

  /// The background photo (ADR-013), relative to the media directory.
  final String? backgroundPath;

  final int photoCount;

  /// The first four photos, in the order of the links, for the row of thumbnails (element 10).
  final List<String> firstPhotos;

  final BurialPlace? burial;

  /// Where the person lived, in the order of the years (element 9a, ISSUE-042).
  final List<Residence> residences;

  /// One level of family for the mini tree (element 6).
  final PersonRelations relations;

  /// The relatives' profile photos, by person.
  final Map<int, ProfilePhoto> relativeProfiles;

  /// Who "ja" is; null when not chosen yet.
  final int? meId;

  /// The chain from "ja" to this person, without "ja"; empty when this person is "ja", null when
  /// nothing joins them (or "ja" is not chosen).
  final List<ChainLink>? chain;
}

/// The view of [personId], again after every write to a table it reads; null when there is no such
/// person (e.g. deleted).
Stream<PersonView?> watchPersonView(GrobingDatabase db, int personId) =>
    watchTables(db, 'person_view', {
      db.persons,
      db.families,
      db.familyPartners,
      db.familyChildren,
      db.events,
      db.assertions,
      db.burials,
      db.graves,
      db.sectors,
      db.cemeteries,
      db.media,
      db.personMedia,
      db.settings,
      db.residences,
      db.clans,
    }, () => loadPersonView(db, personId));

Future<PersonView?> loadPersonView(GrobingDatabase db, int personId) async {
  final Person? p = await (db.select(
    db.persons,
  )..where((p) => p.id.equals(personId))).getSingleOrNull();
  if (p == null) return null;

  final List<PersonPhoto> photos = await personPhotos(db, personId);
  final PersonRelations relations = await loadRelations(db, personId);
  final int? meId = (await (db.select(
    db.settings,
  )..where((s) => s.id.equals(1))).getSingleOrNull())?.mePersonId;

  List<KinStep>? steps;
  if (meId != null) {
    steps = (await KinGraph.load(db)).path(meId, personId);
  }
  final List<int> stepIds = [for (final KinStep s in steps ?? []) s.personId];
  final Map<int, Person> chainPeople = {
    for (final Person q in await (db.select(
      db.persons,
    )..where((q) => q.id.isIn(stepIds))).get())
      q.id: q,
  };

  final Set<int> relatives = {
    for (final FamilyMember m in relations.parents) m.id,
    for (final PersonUnion u in relations.unions) ...[
      ?u.partner?.id,
      for (final FamilyMember c in u.children) c.id,
    ],
    ...stepIds,
  };
  final Map<int, ProfilePhoto> profiles = await profilePhotos(db, {
    ...relatives,
    personId,
  });

  return PersonView(
    id: p.id,
    givenNames: p.givenNames,
    surname: p.surname,
    birthSurname: p.birthSurname,
    sex: p.sex,
    bio: p.bio,
    isLiving: p.isLiving,
    birth: await _date(db, personId, EventType.birth),
    death: await _date(db, personId, EventType.death),
    profile: profiles[personId],
    backgroundPath: photos
        .where((ph) => ph.isBackground)
        .firstOrNull
        ?.relativePath,
    photoCount: photos.length,
    firstPhotos: [for (final PersonPhoto ph in photos.take(4)) ph.relativePath],
    burial: await _burialPlace(db, personId),
    residences: await residencesOf(db, personId),
    relations: relations,
    relativeProfiles: profiles,
    meId: meId,
    // The wreath needs the fathers and husbands of the whole tree (B2, B4), as the tree reads it.
    wreath: (await loadFamilyTree(db)).wreaths.of(personId),
    chain: steps == null
        ? null
        : [
            for (final KinStep s in steps)
              ChainLink(
                step: s,
                sex: chainPeople[s.personId]?.sex,
                givenNames: chainPeople[s.personId]?.givenNames,
                surname: chainPeople[s.personId]?.surname,
                profile: profiles[s.personId],
              ),
          ],
  );
}

Future<QualifiedDate?> _date(
  GrobingDatabase db,
  int personId,
  EventType type,
) async {
  final Event? first = await firstEvent(db, personId: personId, type: type);
  return first == null ? null : QualifiedDate.ofEvent(first);
}

Future<BurialPlace?> _burialPlace(GrobingDatabase db, int personId) async {
  final Burial? burial = await firstBurial(db, personId);
  if (burial == null) return null;
  final TypedResult r = await (db.select(db.graves).join([
    innerJoin(db.cemeteries, db.cemeteries.id.equalsExp(db.graves.cemeteryId)),
  ])..where(db.graves.id.equals(burial.graveId))).getSingle();
  final Grave g = r.readTable(db.graves);
  return BurialPlace(
    graveId: g.id,
    cemeteryId: g.cemeteryId,
    cemeteryName: r.readTable(db.cemeteries).name,
    graveName: g.name,
    sector: g.sectorId == null
        ? null
        : (await (db.select(
            db.sectors,
          )..where((s) => s.id.equals(g.sectorId!))).getSingle()).name,
    row: g.row,
    plot: g.plot,
  );
}
