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
    this.burial,
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

  /// The first burial's date — the latest a death without its own date can be (time slider, drzewo.md D32).
  final QualifiedDate? burial;

  /// A death or a burial is written, with or without a date — the candle on the node (style-b.md rule 8).
  final bool dead;
  final ProfilePhoto? profile;
}

/// One union: its one or two partners in the order written, its children by birth (those without a date
/// last), whether there was a wedding, and when the union began — "together since", else the wedding — to
/// order a person's unions (families.dart does the same). A union with neither date begins, for that
/// order, with its oldest child (drzewo.md D31 — TimeNets: "marriage ← oldest child's birth"): last, a
/// widow's first marriage would come after her second and move the tree (ISSUE-037 D3).
class TreeUnion {
  const TreeUnion({
    required this.familyId,
    required this.partners,
    required this.children,
    this.married = false,
    this.startKey,
    this.together,
    this.marriage,
    this.ended = false,
    this.end,
  });

  final int familyId;
  final List<int> partners;
  final List<int> children;
  final bool married;
  final int? startKey;

  /// The dates the time slider reads (drzewo.md element 6): "razem od", the wedding, the end — each may be
  /// written without its date.
  final QualifiedDate? together;
  final QualifiedDate? marriage;

  /// The union ended — a divorce or a parting, with [end] or without a date (rodzina.md A6).
  final bool ended;
  final QualifiedDate? end;
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
  final Set<int> ended = {};
  for (final Event e
      in await (db.select(db.events)
            ..where(
              (e) => e.type.isInValues(const [
                EventType.birth,
                EventType.death,
                EventType.burial,
                EventType.marriage,
                EventType.together,
                EventType.end,
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
      if (e.type == EventType.end) ended.add(family);
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
        burial: personDates[(p.id, EventType.burial)],
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

  final List<TreeUnion> unions = [];
  for (final Family f in await (db.select(
    db.families,
  )..orderBy([(f) => OrderingTerm.asc(f.id)])).get()) {
    if ((partners[f.id] ?? const []).isEmpty &&
        (children[f.id] ?? const []).isEmpty) {
      continue;
    }
    // By birth (GEDCOM 7: "chronological by birth"), those without a date last, then in the order written
    // — a stable sort over the order of the rows.
    final List<int> kids = _byKey([
      for (final int c in children[f.id] ?? const <int>[])
        if (people.containsKey(c)) c,
    ], birthKey);
    final QualifiedDate? together = familyDates[(f.id, EventType.together)];
    final QualifiedDate? marriage = familyDates[(f.id, EventType.marriage)];
    unions.add(
      TreeUnion(
        familyId: f.id,
        partners: [
          for (final int p in partners[f.id] ?? const <int>[])
            if (people.containsKey(p)) p,
        ],
        children: kids,
        married: married.contains(f.id),
        startKey: switch (together ?? marriage) {
          final QualifiedDate d? => _dateKey(d),
          null => kids.isEmpty ? null : birthKey(kids.first),
        },
        together: together,
        marriage: marriage,
        ended: ended.contains(f.id),
        end: familyDates[(f.id, EventType.end)],
      ),
    );
  }

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
