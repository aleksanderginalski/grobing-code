import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

// ISSUE-011 AC-2 (a date and a burial are written with their claim), the dispute of US-004 AC-1 on the
// v2 schema (ADR-006 D1, D2, D3), AC-5 (the fingerprint covers the claims) and the invariant of D5: no
// event or burial row without a claim. Made-up people only (family-data.md).

final DateTime _at = DateTime.utc(2026, 10, 6, 12);
DateTime _clock() => _at;

/// Event and burial rows that have no claim — the invariant says there are none.
Future<List<String>> _unclaimed(GrobingDatabase db) async => [
  for (final QueryRow r
      in await db
          .customSelect(
            "SELECT 'event ' || id AS row FROM events WHERE id NOT IN "
            '(SELECT event_id FROM assertions WHERE event_id IS NOT NULL) '
            "UNION ALL SELECT 'burial ' || id FROM burials WHERE id NOT IN "
            '(SELECT burial_id FROM assertions WHERE burial_id IS NOT NULL)',
          )
          .get())
    r.read<String>('row'),
];

void main() {
  late GrobingDatabase db;
  late int person;
  late int grave;
  late int otherGrave;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    final int cemetery = await db
        .into(db.cemeteries)
        .insert(CemeteriesCompanion.insert(name: 'Cmentarz Wymyślony'));
    grave = await db
        .into(db.graves)
        .insert(GravesCompanion.insert(cemeteryId: cemetery));
    otherGrave = await db
        .into(db.graves)
        .insert(GravesCompanion.insert(cemeteryId: cemetery));
    person = await db
        .into(db.persons)
        .insert(PersonsCompanion.insert(givenNames: const Value('Ktoś')));
  });

  tearDown(() => db.close());

  group('AC-2 — a fact is written with its claim', () {
    test(
      'a date "około 1890": the event and one claim — notes, claimed, when',
      () async {
        final int id = await addEventWithClaim(
          db,
          EventsCompanion.insert(
            type: EventType.birth,
            personId: Value(person),
            qualifier: const Value(DateQualifier.about),
            year: const Value(1890),
          ),
          clock: _clock,
        );

        final Event event = await db.select(db.events).getSingle();
        expect(
          (event.id, event.qualifier, event.year),
          (id, DateQualifier.about, 1890),
        );
        final Assertion claim = await db.select(db.assertions).getSingle();
        expect(
          (
            claim.eventId,
            claim.burialId,
            claim.sourceKind,
            claim.sourceDetail,
            claim.status,
          ),
          (id, null, SourceKind.notes, null, AssertionStatus.claimed),
        );
        expect(claim.recordedAt.isAtSameMomentAs(_at), isTrue);
      },
    );

    test('a burial: the row and one claim on it', () async {
      final int id = await addBurialWithClaim(
        db,
        personId: person,
        graveId: grave,
        source: const ClaimSource(
          kind: SourceKind.relative,
          detail: 'wymyślony kuzyn',
        ),
        clock: _clock,
      );

      final Assertion claim = await db.select(db.assertions).getSingle();
      expect(
        (claim.eventId, claim.burialId, claim.sourceKind, claim.sourceDetail),
        (null, id, SourceKind.relative, 'wymyślony kuzyn'),
      );
      expect(await _unclaimed(db), isEmpty);
    });

    test(
      'a write that fails leaves neither the row nor the claim (one transaction)',
      () async {
        await expectLater(
          addBurialWithClaim(db, personId: 999, graveId: grave),
          throwsA(isA<SqliteException>()),
        );
        expect(await db.select(db.burials).get(), isEmpty);
        expect(await db.select(db.assertions).get(), isEmpty);
      },
    );

    test(
      'a claim is on an event or on a burial — never both, never neither',
      () async {
        final int event = await addEventWithClaim(
          db,
          EventsCompanion.insert(
            type: EventType.death,
            personId: Value(person),
          ),
        );
        final int burial = await addBurialWithClaim(
          db,
          personId: person,
          graveId: grave,
        );
        for (final (int?, int?) target in [(event, burial), (null, null)]) {
          await expectLater(
            db
                .into(db.assertions)
                .insert(
                  AssertionsCompanion.insert(
                    eventId: Value(target.$1),
                    burialId: Value(target.$2),
                    sourceKind: SourceKind.notes,
                    status: AssertionStatus.claimed,
                    recordedAt: _at,
                  ),
                ),
            throwsA(isA<SqliteException>()),
          );
        }
      },
    );
  });

  test(
    'US-004 AC-1 on v2 — the grandmother contradicts a date and a grave: both rows stay with their '
    'claims, nothing is replaced, the first row written is the one shown',
    () async {
      const ClaimSource notes = ClaimSource(
        status: AssertionStatus.contradicted,
      );
      const ClaimSource grandmother = ClaimSource(
        kind: SourceKind.grandmother,
        status: AssertionStatus.contradicted,
      );
      EventsCompanion birth(DateQualifier q, int year) =>
          EventsCompanion.insert(
            type: EventType.birth,
            personId: Value(person),
            qualifier: Value(q),
            year: Value(year),
          );

      await addEventWithClaim(
        db,
        birth(DateQualifier.about, 1890),
        source: notes,
      );
      await addEventWithClaim(
        db,
        birth(DateQualifier.exact, 1892),
        source: grandmother,
      );
      await addBurialWithClaim(
        db,
        personId: person,
        graveId: grave,
        source: notes,
      );
      await addBurialWithClaim(
        db,
        personId: person,
        graveId: otherGrave,
        source: grandmother,
      );

      expect((await db.select(db.events).get()).map((e) => e.year), [
        1890,
        1892,
      ]);
      expect((await db.select(db.burials).get()).map((b) => b.graveId), [
        grave,
        otherGrave,
      ]);
      expect(
        (await db.select(db.assertions).get()).map(
          (c) => (c.sourceKind, c.status),
        ),
        [
          for (int i = 0; i < 2; i++) ...[
            (SourceKind.notes, AssertionStatus.contradicted),
            (SourceKind.grandmother, AssertionStatus.contradicted),
          ],
        ],
      );
      expect(
        (await firstEvent(db, personId: person, type: EventType.birth))!.year,
        1890,
      );
      expect((await firstBurial(db, person))!.graveId, grave);
      // The same grave again is the same value: a second source is a claim on the row, not a row.
      await expectLater(
        addBurialWithClaim(db, personId: person, graveId: grave),
        throwsA(isA<SqliteException>()),
      );
      expect(await _unclaimed(db), isEmpty);
    },
  );

  test(
    'AC-5 — the fingerprint covers the claims: one changed status changes it',
    () async {
      final Directory media = Directory('${Directory.systemTemp.path}/none');
      await addEventWithClaim(
        db,
        EventsCompanion.insert(type: EventType.birth, personId: Value(person)),
        clock: _clock,
      );
      final DataState before = await readDataState(db, mediaDir: media);
      expect(before.rowCounts['assertions'], 1);

      await db
          .update(db.assertions)
          .write(
            const AssertionsCompanion(status: Value(AssertionStatus.unknown)),
          );
      final DataState after = await readDataState(db, mediaDir: media);
      expect(after.rowCounts, before.rowCounts);
      expect(after.fingerprint, isNot(before.fingerprint));
    },
  );

  test(
    'D5 — the made-up data keeps the invariant and carries one dispute',
    () async {
      final Directory tmp = Directory.systemTemp.createTempSync(
        'grobing_claims',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      await addFictionalData(db, Directory('${tmp.path}/media'));

      expect(await _unclaimed(db), isEmpty);
      final List<Assertion> disputed =
          await (db.select(db.assertions)..where(
                (c) => c.status.equalsValue(AssertionStatus.contradicted),
              ))
              .get();
      expect(disputed.map((c) => c.sourceKind), [
        SourceKind.notes,
        SourceKind.grandmother,
      ]);
    },
  );
}
