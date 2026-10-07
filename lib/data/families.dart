import 'package:drift/drift.dart';

import 'claims.dart';
import 'database.dart';
import 'graves.dart';

// Families as the "Rodzina" section of the person form shows them and the family sheet writes them
// (ISSUE-019; 05_DESIGN/rodzina.md, wpis-osoby.md v5.1). A family is a union, married or not, with its
// children; a person in several unions is in several families (FR-002). Its source is a claim on the
// family, and each child's link has its own (ADR-011). Writes go through drift's own API, so they notify
// `tableUpdates` and ask for a background backup (ISSUE-010).

/// One person in a family, as the family screens name them.
class FamilyMember {
  const FamilyMember({
    required this.id,
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.birth,
    this.death,
  });

  final int id;
  final String? givenNames;
  final String? surname;
  final String? birthSurname;

  /// The first birth and death written (ADR-006 D3).
  final QualifiedDate? birth;
  final QualifiedDate? death;
}

/// One union of a person (05_DESIGN/wpis-osoby.md 9a d): the other partner — none in a family of one
/// parent — the children of this pair, and the start and end of the union.
class PersonUnion {
  const PersonUnion({
    required this.familyId,
    this.partner,
    required this.children,
    this.marriage,
    this.end,
  });

  final int familyId;
  final FamilyMember? partner;

  /// By birth (GEDCOM 7: "chronological by birth"), those without a date last.
  final List<FamilyMember> children;
  final QualifiedDate? marriage;
  final QualifiedDate? end;
}

/// A person's families (05_DESIGN/wpis-osoby.md 9a): their parents' and their own unions.
class PersonRelations {
  const PersonRelations({
    this.parentsFamilyId,
    required this.parents,
    required this.unions,
  });

  /// The family the person is a child in; null when none is written.
  final int? parentsFamilyId;
  final List<FamilyMember> parents;

  /// By marriage date, those without one last, in the order written.
  final List<PersonUnion> unions;
}

/// A family on the family sheet (05_DESIGN/rodzina.md A).
class FamilyDetail {
  const FamilyDetail({
    required this.id,
    required this.partners,
    required this.children,
    required this.marriage,
    required this.end,
  });

  final int id;

  /// In the order written.
  final List<FamilyMember> partners;

  /// By birth, those without a date last (rodzina.md A8).
  final List<FamilyMember> children;

  /// More than one claim — another source spoke too — and the sheet leaves the date alone, as the
  /// person form does (ISSUE-012 D1).
  final DatedFact marriage;
  final DatedFact end;
}

/// Someone on the family sheet: a person already in the app, or a new one typed there (rodzina.md A3').
sealed class MemberDraft {
  const MemberDraft();
}

class ExistingMember extends MemberDraft {
  const ExistingMember(this.personId);

  final int personId;
}

class NewMember extends MemberDraft {
  const NewMember({this.givenNames, this.surname});

  final String? givenNames;
  final String? surname;
}

/// The family sheet as it is saved: a new family ([familyId] null) or a correction of one.
class FamilyDraft {
  const FamilyDraft({
    this.familyId,
    required this.partners,
    required this.children,
    this.marriage,
    this.end,
  });

  final int? familyId;
  final List<MemberDraft> partners;
  final List<MemberDraft> children;
  final QualifiedDate? marriage;
  final QualifiedDate? end;
}

/// The relations of [personId], again after every write to a table they read — the claims too: a
/// correction of a family may write only them (a family from before v6 gets its claim).
Stream<PersonRelations> watchRelations(GrobingDatabase db, int personId) =>
    watchTables(db, 'family_relations', {
      db.families,
      db.familyPartners,
      db.familyChildren,
      db.persons,
      db.events,
      db.assertions,
    }, () => loadRelations(db, personId));

Future<PersonRelations> loadRelations(GrobingDatabase db, int personId) async {
  // One family of parents (rodzina.md D5); should an older write have left two, the first one counts.
  final FamilyChildrenData? asChild =
      await (db.select(db.familyChildren)
            ..where((c) => c.personId.equals(personId))
            ..orderBy([(c) => OrderingTerm.asc(c.id)])
            ..limit(1))
          .getSingleOrNull();
  final List<int> ownFamilies =
      await (db.selectOnly(db.familyPartners)
            ..addColumns([db.familyPartners.familyId])
            ..where(db.familyPartners.personId.equals(personId)))
          .map((r) => r.read(db.familyPartners.familyId)!)
          .get();
  final List<PersonUnion> unions = [];
  for (final int family in ownFamilies) {
    final List<FamilyMember> partners = await _partners(db, family);
    final FamilyMember? other = partners
        .where((p) => p.id != personId)
        .firstOrNull;
    unions.add(
      PersonUnion(
        familyId: family,
        partner: other,
        children: await _children(db, family),
        marriage: await _familyDate(db, family, EventType.marriage),
        end: await _familyDate(db, family, EventType.end),
      ),
    );
  }
  // Mergesort keeps the order written among those with the same key.
  _stableSortBy(
    unions,
    (PersonUnion u) => u.marriage == null ? null : _dateKey(u.marriage!),
  );
  return PersonRelations(
    parentsFamilyId: asChild?.familyId,
    parents: asChild == null ? const [] : await _partners(db, asChild.familyId),
    unions: unions,
  );
}

/// The family for the sheet; null when there is no such family.
Future<FamilyDetail?> loadFamily(GrobingDatabase db, int familyId) async {
  final Family? family = await (db.select(
    db.families,
  )..where((f) => f.id.equals(familyId))).getSingleOrNull();
  if (family == null) return null;
  return FamilyDetail(
    id: familyId,
    partners: await _partners(db, familyId),
    children: await _children(db, familyId),
    marriage: await _familyFact(db, familyId, EventType.marriage),
    end: await _familyFact(db, familyId, EventType.end),
  );
}

/// Who already is a child in a family other than [exceptFamilyId] — "ma już rodziców" on the person
/// picker (05_DESIGN/rodzina.md B, D5).
Future<Set<int>> peopleWithParents(
  GrobingDatabase db, {
  int? exceptFamilyId,
}) async => {
  for (final FamilyChildrenData c
      in await (db.select(db.familyChildren)..where(
            (c) => exceptFamilyId == null
                ? const Constant(true)
                : c.familyId.equals(exceptFamilyId).not(),
          ))
          .get())
    c.personId,
};

/// Writes the family sheet, all or nothing (05_DESIGN/rodzina.md → "Zapis jest całością"); returns the
/// family's id. New people are written with their names only (D4). A new family gets a claim from the
/// notes; so does one from before v6, which had none (ADR-011). A child's new link gets its own claim;
/// a link that goes takes its claims with it. The marriage and end dates are corrected in place, as the
/// person form corrects a person's (ISSUE-012 D1): a date with more than one claim stays as it is, a
/// cleared one goes with its only claim.
///
/// The rules of the sheet hold here too, not only on the screen (ISSUE-019 F5): one or two partners,
/// at least two people, no one twice, and a child in one family of parents (D5, D6).
Future<int> saveFamily(
  GrobingDatabase db,
  FamilyDraft draft, {
  DateTime Function()? clock,
}) => db.transaction(() async {
  if (draft.partners.isEmpty || draft.partners.length > 2) {
    throw ArgumentError('A family has one or two partners');
  }
  if (draft.partners.length + draft.children.length < 2) {
    throw ArgumentError('A family has at least two people');
  }
  final List<int> existing = [
    for (final MemberDraft m in [...draft.partners, ...draft.children])
      if (m case ExistingMember(:final int personId)) personId,
  ];
  if (existing.toSet().length != existing.length) {
    throw ArgumentError('Someone is twice in the family');
  }
  final Set<int> withParents = await peopleWithParents(
    db,
    exceptFamilyId: draft.familyId,
  );
  for (final MemberDraft m in draft.children) {
    if (m case ExistingMember(
      :final int personId,
    ) when withParents.contains(personId)) {
      throw ArgumentError('Person $personId has parents in another family');
    }
  }

  Future<int> idOf(MemberDraft m) async => switch (m) {
    ExistingMember(:final int personId) => personId,
    NewMember(:final String? givenNames, :final String? surname) =>
      await _addPerson(db, givenNames, surname),
  };
  final List<int> partners = [
    for (final MemberDraft m in draft.partners) await idOf(m),
  ];
  final List<int> children = [
    for (final MemberDraft m in draft.children) await idOf(m),
  ];

  final int family;
  if (draft.familyId case final int id) {
    family = id;
    final int? found =
        await (db.selectOnly(db.families)
              ..addColumns([db.families.id])
              ..where(db.families.id.equals(id)))
            .map((r) => r.read(db.families.id))
            .getSingleOrNull();
    if (found == null) throw StateError('No family with id $id');
  } else {
    family = await db.into(db.families).insert(FamiliesCompanion.insert());
  }
  final bool hasClaim =
      await (db.select(db.assertions)
            ..where((a) => a.familyId.equals(family))
            ..limit(1))
          .getSingleOrNull() !=
      null;
  if (!hasClaim) await addFamilyClaim(db, family, clock: clock);

  // Partners: who goes and who comes; those who stay keep their rows.
  final List<int> partnersNow = [
    for (final FamilyPartner p in await (db.select(
      db.familyPartners,
    )..where((p) => p.familyId.equals(family))).get())
      p.personId,
  ];
  await (db.delete(
        db.familyPartners,
      )..where((p) => p.familyId.equals(family) & p.personId.isNotIn(partners)))
      .go();
  for (final int p in partners) {
    if (!partnersNow.contains(p)) {
      await db
          .into(db.familyPartners)
          .insert(
            FamilyPartnersCompanion.insert(familyId: family, personId: p),
          );
    }
  }

  // Children: a link that goes takes its claims; a new one comes with its claim; one from before v6
  // gets its claim now.
  final List<FamilyChildrenData> linksNow = await (db.select(
    db.familyChildren,
  )..where((c) => c.familyId.equals(family))).get();
  for (final FamilyChildrenData link in linksNow) {
    if (!children.contains(link.personId)) {
      await (db.delete(
        db.assertions,
      )..where((a) => a.familyChildId.equals(link.id))).go();
      await (db.delete(
        db.familyChildren,
      )..where((c) => c.id.equals(link.id))).go();
    } else if (await (db.select(db.assertions)
              ..where((a) => a.familyChildId.equals(link.id))
              ..limit(1))
            .getSingleOrNull() ==
        null) {
      await _addLinkClaim(db, link.id, clock);
    }
  }
  for (final int child in children) {
    if (!linksNow.any((l) => l.personId == child)) {
      await addChildLinkWithClaim(
        db,
        familyId: family,
        personId: child,
        clock: clock,
      );
    }
  }

  for (final (EventType type, QualifiedDate? date) in [
    (EventType.marriage, draft.marriage),
    (EventType.end, draft.end),
  ]) {
    if (!(await _familyFact(db, family, type)).correctable) continue;
    final Event? existingEvent = await _firstFamilyEvent(db, family, type);
    if (existingEvent == null) {
      if (date != null) {
        await addEventWithClaim(
          db,
          qualifiedDateValues(
            date,
          ).copyWith(type: Value(type), familyId: Value(family)),
          clock: clock,
        );
      }
    } else if (date == null) {
      await _deleteEvent(db, existingEvent.id);
    } else if (QualifiedDate.ofEvent(existingEvent) != date) {
      await (db.update(db.events)..where((e) => e.id.equals(existingEvent.id)))
          .write(qualifiedDateValues(date));
    }
  }
  return family;
});

/// "Usuń rodzinę" (05_DESIGN/rodzina.md D8): the family, its links, its marriage and end with their
/// claims, and its own claims go, all or nothing. The people stay.
Future<void> deleteFamily(GrobingDatabase db, int familyId) =>
    db.transaction(() async {
      final List<FamilyChildrenData> links = await (db.select(
        db.familyChildren,
      )..where((c) => c.familyId.equals(familyId))).get();
      for (final FamilyChildrenData link in links) {
        await (db.delete(
          db.assertions,
        )..where((a) => a.familyChildId.equals(link.id))).go();
      }
      await (db.delete(
        db.familyChildren,
      )..where((c) => c.familyId.equals(familyId))).go();
      await (db.delete(
        db.familyPartners,
      )..where((p) => p.familyId.equals(familyId))).go();
      for (final Event e in await (db.select(
        db.events,
      )..where((e) => e.familyId.equals(familyId))).get()) {
        await _deleteEvent(db, e.id);
      }
      await (db.delete(
        db.assertions,
      )..where((a) => a.familyId.equals(familyId))).go();
      final int deleted = await (db.delete(
        db.families,
      )..where((f) => f.id.equals(familyId))).go();
      if (deleted != 1) throw StateError('No family with id $familyId');
    });

Future<int> _addPerson(
  GrobingDatabase db,
  String? givenNames,
  String? surname,
) {
  final String? given = blankToNull(givenNames), last = blankToNull(surname);
  if (given == null && last == null) {
    throw ArgumentError('A person needs given names or a surname');
  }
  return db
      .into(db.persons)
      .insert(
        PersonsCompanion.insert(givenNames: Value(given), surname: Value(last)),
      );
}

Future<void> _addLinkClaim(
  GrobingDatabase db,
  int linkId,
  DateTime Function()? clock,
) => db
    .into(db.assertions)
    .insert(
      AssertionsCompanion.insert(
        familyChildId: Value(linkId),
        sourceKind: const ClaimSource().kind,
        status: const ClaimSource().status,
        recordedAt: (clock ?? DateTime.now)(),
      ),
    );

Future<void> _deleteEvent(GrobingDatabase db, int eventId) async {
  await (db.delete(
    db.assertions,
  )..where((a) => a.eventId.equals(eventId))).go();
  await (db.delete(db.events)..where((e) => e.id.equals(eventId))).go();
}

/// The partners of [familyId] in the order written.
Future<List<FamilyMember>> _partners(GrobingDatabase db, int familyId) async {
  final List<int> ids =
      await (db.selectOnly(db.familyPartners)
            ..addColumns([db.familyPartners.personId])
            ..where(db.familyPartners.familyId.equals(familyId))
            ..orderBy([OrderingTerm.asc(const CustomExpression<int>('rowid'))]))
          .map((r) => r.read(db.familyPartners.personId)!)
          .get();
  return [for (final int id in ids) await loadFamilyMember(db, id)];
}

/// The children of [familyId] by birth, those without a date last in the order written.
Future<List<FamilyMember>> _children(GrobingDatabase db, int familyId) async {
  final List<FamilyMember> children = [
    for (final FamilyChildrenData c
        in await (db.select(db.familyChildren)
              ..where((c) => c.familyId.equals(familyId))
              ..orderBy([(c) => OrderingTerm.asc(c.id)]))
            .get())
      await loadFamilyMember(db, c.personId),
  ];
  _stableSortBy(
    children,
    (FamilyMember m) => m.birth == null ? null : _dateKey(m.birth!),
  );
  return children;
}

/// One person as the family screens name them, with their first birth and death (ADR-006 D3).
Future<FamilyMember> loadFamilyMember(GrobingDatabase db, int personId) async {
  final Person p = await (db.select(
    db.persons,
  )..where((p) => p.id.equals(personId))).getSingle();
  Future<QualifiedDate?> date(EventType type) async {
    final Event? e = await firstEvent(db, personId: personId, type: type);
    return e == null ? null : QualifiedDate.ofEvent(e);
  }

  return FamilyMember(
    id: p.id,
    givenNames: p.givenNames,
    surname: p.surname,
    birthSurname: p.birthSurname,
    birth: await date(EventType.birth),
    death: await date(EventType.death),
  );
}

/// The first [type] event of [familyId] written (ADR-006 D3).
Future<Event?> _firstFamilyEvent(
  GrobingDatabase db,
  int familyId,
  EventType type,
) =>
    (db.select(db.events)
          ..where((e) => e.familyId.equals(familyId) & e.type.equalsValue(type))
          ..orderBy([(e) => OrderingTerm.asc(e.id)])
          ..limit(1))
        .getSingleOrNull();

Future<QualifiedDate?> _familyDate(
  GrobingDatabase db,
  int familyId,
  EventType type,
) async {
  final Event? e = await _firstFamilyEvent(db, familyId, type);
  return e == null ? null : QualifiedDate.ofEvent(e);
}

/// The [type] date of [familyId] to show and the number of claims on all its events of that type.
Future<DatedFact> _familyFact(
  GrobingDatabase db,
  int familyId,
  EventType type,
) async {
  final Expression<int> count = db.assertions.id.count();
  final int claims =
      await (db.selectOnly(db.assertions).join([
              innerJoin(
                db.events,
                db.events.id.equalsExp(db.assertions.eventId),
              ),
            ])
            ..addColumns([count])
            ..where(
              db.events.familyId.equals(familyId) &
                  db.events.type.equalsValue(type),
            ))
          .map((r) => r.read(count)!)
          .getSingle();
  return DatedFact(
    date: await _familyDate(db, familyId, type),
    claimCount: claims,
  );
}

/// A date as a number that orders it: the year, then the month and the day where known — the first
/// bound of "między".
int _dateKey(QualifiedDate d) =>
    d.from.year * 10000 + (d.from.month ?? 0) * 100 + (d.from.day ?? 0);

/// Sorts [list] in place by [key], those with a null key last; equal keys keep their order.
void _stableSortBy<T>(List<T> list, int? Function(T) key) {
  final List<(int, T)> indexed = [
    for (final (int i, T e) in list.indexed) (i, e),
  ];
  indexed.sort((a, b) {
    final int? ka = key(a.$2), kb = key(b.$2);
    final int byKey = switch ((ka, kb)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (final int x, final int y) => x.compareTo(y),
    };
    return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
  });
  list
    ..clear()
    ..addAll([for (final (_, T e) in indexed) e]);
}
