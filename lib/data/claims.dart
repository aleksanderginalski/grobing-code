import 'package:drift/drift.dart';

import 'database.dart';

/// Who stated a fact and how strong it is (FR-001): what a claim adds to the value in its row. The
/// default is US-002's — transcribed from the notes, one source.
class ClaimSource {
  const ClaimSource({
    this.kind = SourceKind.notes,
    this.detail,
    this.status = AssertionStatus.claimed,
  });

  final SourceKind kind;

  /// Which relative, which record (FR-001: "kto je podał"). Optional.
  final String? detail;
  final AssertionStatus status;
}

// Facts written together with their claims (ISSUE-011, ADR-006; families and children's links:
// ISSUE-019, ADR-011). Every event and burial row has at least one claim, so they are written here, in
// one transaction with it — through drift's own API, so
// the write notifies `tableUpdates` and asks for a background backup (ISSUE-010). A value that
// contradicts an existing one is a new row with its own claim, never an update of the old row.

/// Adds [event] with one claim from [source]; returns the event's id.
Future<int> addEventWithClaim(
  GrobingDatabase db,
  EventsCompanion event, {
  ClaimSource source = const ClaimSource(),
  DateTime Function()? clock,
}) => db.transaction(() async {
  final int id = await db.into(db.events).insert(event);
  await _addClaim(db, source, clock, eventId: id);
  return id;
});

/// Adds the burial of [personId] in [graveId] with one claim from [source]; returns the burial's id.
Future<int> addBurialWithClaim(
  GrobingDatabase db, {
  required int personId,
  required int graveId,
  ClaimSource source = const ClaimSource(),
  DateTime Function()? clock,
}) => db.transaction(() async {
  final int id = await db
      .into(db.burials)
      .insert(BurialsCompanion.insert(personId: personId, graveId: graveId));
  await _addClaim(db, source, clock, burialId: id);
  return id;
});

/// Adds one claim from [source] that [familyId] — the union — is as written (ISSUE-019, ADR-011: the
/// pair is cited on the family, as GEDCOM 7 cites `FAM`). Returns the claim's id.
Future<int> addFamilyClaim(
  GrobingDatabase db,
  int familyId, {
  ClaimSource source = const ClaimSource(),
  DateTime Function()? clock,
}) => _addClaim(db, source, clock, familyId: familyId);

/// Adds [personId] as a child of [familyId] with one claim from [source] on the link (ADR-011: one
/// child's parentage can be disputed alone); returns the link's id.
Future<int> addChildLinkWithClaim(
  GrobingDatabase db, {
  required int familyId,
  required int personId,
  ClaimSource source = const ClaimSource(),
  DateTime Function()? clock,
}) => db.transaction(() async {
  final int id = await db
      .into(db.familyChildren)
      .insert(
        FamilyChildrenCompanion.insert(familyId: familyId, personId: personId),
      );
  await _addClaim(db, source, clock, familyChildId: id);
  return id;
});

/// The [type] event of [personId] to show when the sources disagree: the first one written (lowest
/// id), as GEDCOM 7 §3.1 shows the first of several (ADR-006 D3). Null when there is none.
Future<Event?> firstEvent(
  GrobingDatabase db, {
  required int personId,
  required EventType type,
}) =>
    (db.select(db.events)
          ..where((e) => e.personId.equals(personId) & e.type.equalsValue(type))
          ..orderBy([(e) => OrderingTerm.asc(e.id)])
          ..limit(1))
        .getSingleOrNull();

/// The burial of [personId] to show when the sources disagree on the grave — the first one written,
/// as [firstEvent]. Null when there is none.
Future<Burial?> firstBurial(GrobingDatabase db, int personId) =>
    (db.select(db.burials)
          ..where((b) => b.personId.equals(personId))
          ..orderBy([(b) => OrderingTerm.asc(b.id)])
          ..limit(1))
        .getSingleOrNull();

Future<int> _addClaim(
  GrobingDatabase db,
  ClaimSource source,
  DateTime Function()? clock, {
  int? eventId,
  int? burialId,
  int? familyId,
  int? familyChildId,
}) => db
    .into(db.assertions)
    .insert(
      AssertionsCompanion.insert(
        eventId: Value(eventId),
        burialId: Value(burialId),
        familyId: Value(familyId),
        familyChildId: Value(familyChildId),
        sourceKind: source.kind,
        sourceDetail: Value(source.detail),
        status: source.status,
        recordedAt: (clock ?? DateTime.now)(),
      ),
    );
