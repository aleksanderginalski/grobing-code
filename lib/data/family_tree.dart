import 'package:drift/drift.dart';

import 'database.dart';
import 'graves.dart' show QualifiedDate, watchTables;
import 'kinship.dart';
import 'photos.dart' show ProfilePhoto, profilePhotos;

// The whole family at once, for the Drzewo tab (05_DESIGN/drzewo.md v1.6, ISSUE-033): everyone, every union
// and who "ja" is, read in a handful of queries rather than a person at a time — the tree moves its middle
// from person to person and lays out up to the whole family (SPIKE-002 M1: about 100 people). Read only.

/// One person on the tree.
class TreePerson {
  const TreePerson({
    required this.id,
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.sex,
    this.birth,
    this.death,
    this.dead = false,
    this.profile,
  });

  final int id;
  final String? givenNames;
  final String? surname;
  final String? birthSurname;

  /// Null: not known — the kinship names go neutral (ISSUE-025 D2).
  final Sex? sex;

  /// The first birth and death written (ADR-006 D3).
  final QualifiedDate? birth;
  final QualifiedDate? death;

  /// A death or a burial is written, with or without a date — the candle on the node (style-b.md rule 8).
  final bool dead;
  final ProfilePhoto? profile;
}

/// One union: its one or two partners in the order written, its children by birth (those without a date
/// last), whether there was a wedding, and when the union began — "together since", else the wedding — to
/// order a person's unions (families.dart does the same).
class TreeUnion {
  const TreeUnion({
    required this.familyId,
    required this.partners,
    required this.children,
    this.married = false,
    this.startKey,
  });

  final int familyId;
  final List<int> partners;
  final List<int> children;
  final bool married;
  final int? startKey;
}

/// The family as the tree reads it.
class FamilyTreeData {
  FamilyTreeData({required this.people, required this.unions, this.meId})
    : kin = KinGraph.of(
        partners: {for (final TreeUnion u in unions) u.familyId: u.partners},
        children: {for (final TreeUnion u in unions) u.familyId: u.children},
        married: {
          for (final TreeUnion u in unions)
            if (u.married) u.familyId,
        },
      );

  final Map<int, TreePerson> people;
  final List<TreeUnion> unions;

  /// "Ja"; null until chosen (settings.mePersonId).
  final int? meId;

  /// The paths between people for "kim jest dla Ciebie" (ISSUE-025 D2).
  final KinGraph kin;
}

/// Everyone, every union and "ja", again after every write to a table the tree reads.
Stream<FamilyTreeData> watchFamilyTree(GrobingDatabase db) =>
    watchTables(db, 'family_tree', {
      db.persons,
      db.families,
      db.familyPartners,
      db.familyChildren,
      db.events,
      db.burials,
      db.personMedia,
      db.media,
      db.settings,
    }, () => loadFamilyTree(db));

Future<FamilyTreeData> loadFamilyTree(GrobingDatabase db) async {
  final List<Person> persons = await db.select(db.persons).get();

  // The first event of each kind written counts, as on every screen (ADR-006 D3).
  final Map<(int, EventType), QualifiedDate?> personDates = {};
  final Set<int> withDeath = {};
  final Map<(int, EventType), QualifiedDate?> familyDates = {};
  final Set<int> married = {};
  for (final Event e
      in await (db.select(db.events)
            ..where(
              (e) => e.type.isInValues(const [
                EventType.birth,
                EventType.death,
                EventType.marriage,
                EventType.together,
              ]),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get()) {
    if (e.personId case final int person?) {
      personDates.putIfAbsent((person, e.type), () => QualifiedDate.ofEvent(e));
      if (e.type == EventType.death) withDeath.add(person);
    } else if (e.familyId case final int family?) {
      familyDates.putIfAbsent((family, e.type), () => QualifiedDate.ofEvent(e));
      if (e.type == EventType.marriage) married.add(family);
    }
  }
  final Set<int> buried = {
    for (final Burial b in await db.select(db.burials).get()) b.personId,
  };
  final Map<int, ProfilePhoto> profiles = await profilePhotos(db, [
    for (final Person p in persons) p.id,
  ]);
  final Map<int, TreePerson> people = {
    for (final Person p in persons)
      p.id: TreePerson(
        id: p.id,
        givenNames: p.givenNames,
        surname: p.surname,
        birthSurname: p.birthSurname,
        sex: p.sex,
        birth: personDates[(p.id, EventType.birth)],
        death: personDates[(p.id, EventType.death)],
        dead: withDeath.contains(p.id) || buried.contains(p.id),
        profile: profiles[p.id],
      ),
  };

  final Map<int, List<int>> partners = {};
  for (final FamilyPartner fp in await (db.select(
    db.familyPartners,
  )..orderBy([(f) => OrderingTerm.asc(f.rowId)])).get()) {
    (partners[fp.familyId] ??= []).add(fp.personId);
  }
  final Map<int, List<int>> children = {};
  for (final FamilyChildrenData fc in await (db.select(
    db.familyChildren,
  )..orderBy([(c) => OrderingTerm.asc(c.id)])).get()) {
    (children[fc.familyId] ??= []).add(fc.personId);
  }
  int? birthKey(int person) {
    final QualifiedDate? b = people[person]?.birth;
    return b == null ? null : _dateKey(b);
  }

  final List<TreeUnion> unions = [
    for (final Family f in await (db.select(
      db.families,
    )..orderBy([(f) => OrderingTerm.asc(f.id)])).get())
      if ((partners[f.id] ?? const []).isNotEmpty ||
          (children[f.id] ?? const []).isNotEmpty)
        TreeUnion(
          familyId: f.id,
          partners: [
            for (final int p in partners[f.id] ?? const <int>[])
              if (people.containsKey(p)) p,
          ],
          // By birth (GEDCOM 7: "chronological by birth"), those without a date last, then in the order
          // written — a stable sort over the order of the rows.
          children: _byKey([
            for (final int c in children[f.id] ?? const <int>[])
              if (people.containsKey(c)) c,
          ], birthKey),
          married: married.contains(f.id),
          startKey: switch (familyDates[(f.id, EventType.together)] ??
              familyDates[(f.id, EventType.marriage)]) {
            final QualifiedDate d? => _dateKey(d),
            null => null,
          },
        ),
  ];

  final Setting? settings = await (db.select(
    db.settings,
  )..where((s) => s.id.equals(1))).getSingleOrNull();
  final int? me = settings?.mePersonId;
  return FamilyTreeData(
    people: people,
    unions: unions,
    meId: me != null && people.containsKey(me) ? me : null,
  );
}

/// A date as a number that orders it — the first bound of "między" (families.dart does the same).
int _dateKey(QualifiedDate d) =>
    d.from.year * 10000 + (d.from.month ?? 0) * 100 + (d.from.day ?? 0);

/// [items] by [key], those without one last, the order given kept among equals.
List<int> _byKey(List<int> items, int? Function(int) key) {
  final List<(int, int)> indexed = [
    for (int i = 0; i < items.length; i++) (i, items[i]),
  ];
  indexed.sort((a, b) {
    final int? ka = key(a.$2), kb = key(b.$2);
    if (ka != kb) {
      if (ka == null) return 1;
      if (kb == null) return -1;
      return ka.compareTo(kb);
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final (int, int) e in indexed) e.$2];
}
