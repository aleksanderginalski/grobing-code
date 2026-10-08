import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/graves.dart';

// ISSUE-019 — the data behind the family sheet and the "Rodzina" section (lib/data/families.dart),
// happy path per AC of US-003: AC-1 a family at once, new people on the way · AC-2 a person in two
// unions · AC-3 marriage and end with their qualifier · AC-4 a claim on the family and on each child's
// link (ADR-011) · AC-5 a person from a grave instead of a second one. Plus the rules of the sheet in the
// data layer (F5), all or nothing (F4), children by birth (D4), "Usuń rodzinę" (D8) and the entry of a
// person buried nowhere. Made-up people only (family-data.md).

const QualifiedDate _before1920 = QualifiedDate(
  DateQualifier.before,
  PartialDate(1920),
);
const QualifiedDate _about1948 = QualifiedDate(
  DateQualifier.about,
  PartialDate(1948),
);

DateTime _clock() => DateTime(2026, 10, 7, 12);

void main() {
  late GrobingDatabase db;
  late int cemetery;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
  });

  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  /// A person with no grave, e.g. one added on the family sheet before.
  Future<int> person(String given, {int? birthYear}) async {
    final int id = await db
        .into(db.persons)
        .insert(
          PersonsCompanion.insert(
            givenNames: Value(given),
            surname: const Value('Wymyślony'),
          ),
        );
    if (birthYear != null) {
      await addEventWithClaim(
        db,
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(id),
          qualifier: const Value(DateQualifier.exact),
          year: Value(birthYear),
        ),
      );
    }
    return id;
  }

  Future<List<Assertion>> claimsOf({int? familyId, int? linkId}) =>
      (db.select(db.assertions)..where(
            (a) => familyId != null
                ? a.familyId.equals(familyId)
                : a.familyChildId.equals(linkId!),
          ))
          .get();

  test(
    'AC-1, AC-4, AC-5 — one sheet: a partner from the grave, a new child; the union and the child\'s '
    'link each have a claim from the notes, and no one is entered twice',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Maria', surname: 'Wymyślona'),
      );
      final int maria = (await loadGrave(db, grave))!.people.single.id;
      final int jan = await addPersonToGrave(
        db,
        graveId: grave,
        entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
      );
      final int peopleBefore = await count('persons');

      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(maria), ExistingMember(jan)],
          children: const [NewMember(givenNames: 'Anna', surname: 'Wymyślona')],
          marriage: _about1948,
        ),
        clock: _clock,
      );

      // AC-5: the two from the grave are the same people; AC-1: only the new child was added.
      expect(await count('persons'), peopleBefore + 1);
      final FamilyDetail detail = (await loadFamily(db, family))!;
      expect(detail.partners.map((p) => p.id), [maria, jan]);
      expect(detail.children.single.givenNames, 'Anna');
      expect(detail.marriage.date, _about1948);
      // AC-4.
      final Assertion union = (await claimsOf(familyId: family)).single;
      expect(union.sourceKind, SourceKind.notes);
      expect(union.status, AssertionStatus.claimed);
      expect(union.recordedAt, _clock());
      final FamilyChildrenData link =
          (await db.select(db.familyChildren).get()).single;
      final Assertion childClaim = (await claimsOf(linkId: link.id)).single;
      expect(childClaim.sourceKind, SourceKind.notes);
      expect(childClaim.status, AssertionStatus.claimed);
      // The marriage has its claim like every event.
      expect(
        await (db.select(
          db.assertions,
        )..where((a) => a.eventId.isNotNull())).get(),
        hasLength(1),
      );
    },
  );

  test(
    'AC-2 — a person in two unions, each with its own children; the person\'s section has both, by '
    'marriage date, and the parents of a child',
    () async {
      final int father = await person('Ojciec');
      final int first = await person('Pierwsza');
      final int second = await person('Druga');
      final int older = await person('Starsze', birthYear: 1921);
      final int younger = await person('Młodsze', birthYear: 1950);

      // Written second, married first: the section orders by marriage, not by writing.
      final int later = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(father), ExistingMember(second)],
          children: [ExistingMember(younger)],
          marriage: _about1948,
        ),
      );
      final int earlier = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(father), ExistingMember(first)],
          children: [ExistingMember(older)],
          marriage: _before1920,
          end: const QualifiedDate(DateQualifier.exact, PartialDate(1940)),
        ),
      );

      final PersonRelations relations = await loadRelations(db, father);
      expect(relations.parentsFamilyId, isNull);
      expect(relations.unions.map((u) => u.familyId), [earlier, later]);
      expect(relations.unions.map((u) => u.partner!.id), [first, second]);
      expect(relations.unions.first.children.single.id, older);
      expect(relations.unions.last.children.single.id, younger);
      // AC-3: the end of the first union.
      expect(
        relations.unions.first.end,
        const QualifiedDate(DateQualifier.exact, PartialDate(1940)),
      );

      final PersonRelations child = await loadRelations(db, younger);
      expect(child.parentsFamilyId, later);
      expect(child.parents.map((p) => p.id), [father, second]);
      expect(child.unions, isEmpty);
    },
  );

  test(
    'AC-3 — the dates are corrected in place: changed, cleared with their only claim; a date with '
    'two claims stays whatever the sheet says',
    () async {
      final int a = await person('A');
      final int b = await person('B');
      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(a), ExistingMember(b)],
          children: const [],
          marriage: _before1920,
          end: _about1948,
        ),
      );
      final int eventsBefore = await count('events');

      await saveFamily(
        db,
        FamilyDraft(
          familyId: family,
          partners: [ExistingMember(a), ExistingMember(b)],
          children: const [],
          marriage: const QualifiedDate(
            DateQualifier.between,
            PartialDate(1918),
            PartialDate(1919),
          ),
        ),
      );
      FamilyDetail detail = (await loadFamily(db, family))!;
      expect(
        detail.marriage.date,
        const QualifiedDate(
          DateQualifier.between,
          PartialDate(1918),
          PartialDate(1919),
        ),
      );
      expect(detail.end.date, isNull);
      expect(await count('events'), eventsBefore - 1);

      // Another source speaks for the marriage: the sheet leaves it alone from now on.
      final Event marriage = await (db.select(
        db.events,
      )..where((e) => e.familyId.equals(family))).getSingle();
      await db
          .into(db.assertions)
          .insert(
            AssertionsCompanion.insert(
              eventId: Value(marriage.id),
              sourceKind: SourceKind.grandmother,
              status: AssertionStatus.confirmed,
              recordedAt: _clock(),
            ),
          );
      await saveFamily(
        db,
        FamilyDraft(
          familyId: family,
          partners: [ExistingMember(a), ExistingMember(b)],
          children: const [],
          marriage: _about1948,
        ),
      );
      detail = (await loadFamily(db, family))!;
      expect(detail.marriage.correctable, isFalse);
      expect(detail.marriage.date!.from, const PartialDate(1918));
    },
  );

  test('AC-4 — a child taken off the family takes the claims of its link; a family and links from before '
      'v6 get their claims at the first save (ADR-011, D3)', () async {
    final int a = await person('A');
    final int b = await person('B');
    final int c1 = await person('Dziecko 1');
    final int c2 = await person('Dziecko 2');
    // As v5 left them: rows without claims (only the made-up debug data wrote families then).
    final int family = await db
        .into(db.families)
        .insert(FamiliesCompanion.insert());
    for (final int p in [a, b]) {
      await db
          .into(db.familyPartners)
          .insert(
            FamilyPartnersCompanion.insert(familyId: family, personId: p),
          );
    }
    for (final int c in [c1, c2]) {
      await db
          .into(db.familyChildren)
          .insert(
            FamilyChildrenCompanion.insert(familyId: family, personId: c),
          );
    }
    expect(await count('assertions'), 0);

    await saveFamily(
      db,
      FamilyDraft(
        familyId: family,
        partners: [ExistingMember(a), ExistingMember(b)],
        children: [ExistingMember(c1)],
      ),
    );

    expect(await claimsOf(familyId: family), hasLength(1));
    final FamilyChildrenData kept =
        (await db.select(db.familyChildren).get()).single;
    expect(kept.personId, c1);
    expect(await claimsOf(linkId: kept.id), hasLength(1));
    // The second child's link went, and no claim cites a link that is not there.
    expect(await count('assertions'), 2);
    expect(await count('persons'), 4);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  group(
    'F5 — the rules of the sheet hold in the data layer; a refused save writes nothing',
    () {
      late int a, b, c, d;

      setUp(() async {
        a = await person('A');
        b = await person('B');
        c = await person('C');
        d = await person('D');
      });

      Future<void> refused(FamilyDraft draft) async {
        final List<int> before = [
          for (final String t in [
            'persons',
            'families',
            'family_partners',
            'family_children',
            'assertions',
          ])
            await count(t),
        ];
        await expectLater(saveFamily(db, draft), throwsArgumentError);
        expect([
          for (final String t in [
            'persons',
            'families',
            'family_partners',
            'family_children',
            'assertions',
          ])
            await count(t),
        ], before);
      }

      test('three people in the pair', () async {
        await refused(
          FamilyDraft(
            partners: [ExistingMember(a), ExistingMember(b), ExistingMember(c)],
            children: const [],
          ),
        );
      });

      test('no pair (D6)', () async {
        await refused(
          FamilyDraft(
            partners: const [],
            children: [ExistingMember(a), ExistingMember(b)],
          ),
        );
      });

      test('one person', () async {
        await refused(
          FamilyDraft(partners: [ExistingMember(a)], children: const []),
        );
      });

      test('the same person twice', () async {
        await refused(
          FamilyDraft(
            partners: [ExistingMember(a)],
            children: [ExistingMember(a)],
          ),
        );
      });

      test('a child with parents in another family (D5)', () async {
        await saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(a)],
            children: [ExistingMember(c)],
          ),
        );
        await refused(
          FamilyDraft(
            partners: [ExistingMember(b)],
            children: [ExistingMember(c)],
          ),
        );
        // …but the same child in its own family again is no conflict (a correction).
        expect(await peopleWithParents(db), {c});
        expect(
          await peopleWithParents(
            db,
            exceptFamilyId: (await loadRelations(db, c)).parentsFamilyId,
          ),
          isEmpty,
        );
      });

      test(
        'F4 — all or nothing: a new partner written, then a new child without a name — the partner is '
        'gone too',
        () async {
          await refused(
            FamilyDraft(
              partners: [
                ExistingMember(d),
                const NewMember(givenNames: 'Nowa', surname: 'Wymyślona'),
              ],
              children: const [NewMember(givenNames: '  ')],
            ),
          );
        },
      );
    },
  );

  test(
    'D4 — children by birth, those without a date last in the order written; on the sheet and in the '
    'section',
    () async {
      final int a = await person('A');
      final int b = await person('B');
      final int c1950 = await person('Urodzone 1950', birthYear: 1950);
      final int undated = await person('Bez daty');
      final int c1945 = await person('Urodzone 1945', birthYear: 1945);
      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(a), ExistingMember(b)],
          children: [
            ExistingMember(c1950),
            ExistingMember(undated),
            ExistingMember(c1945),
          ],
        ),
      );

      final List<int> expected = [c1945, c1950, undated];
      expect(
        (await loadFamily(db, family))!.children.map((m) => m.id),
        expected,
      );
      expect(
        (await loadRelations(db, a)).unions.single.children.map((m) => m.id),
        expected,
      );
    },
  );

  test(
    'D8 — "Usuń rodzinę": the family, its links, its marriage and end and every claim on them go; the '
    'people stay',
    () async {
      final int a = await person('A');
      final int b = await person('B');
      final int child = await person('Dziecko');
      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(a), ExistingMember(b)],
          children: [ExistingMember(child)],
          marriage: _before1920,
          end: _about1948,
        ),
      );
      expect(await count('assertions'), 4);

      await deleteFamily(db, family);

      for (final String table in [
        'families',
        'family_partners',
        'family_children',
        'events',
        'assertions',
      ]) {
        expect(await count(table), 0, reason: table);
      }
      expect(await count('persons'), 3);
      expect(await loadRelations(db, a), isA<PersonRelations>());
      expect((await loadRelations(db, a)).unions, isEmpty);
    },
  );

  test(
    'a claim cites exactly one row — never two, never none (ADR-011 CHECK)',
    () async {
      final int a = await person('A');
      final int b = await person('B');
      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(a), ExistingMember(b)],
          children: const [],
        ),
      );
      final int burialGrave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Pochowany'),
      );
      final int burial = (await (db.select(
        db.burials,
      )..where((x) => x.graveId.equals(burialGrave))).getSingle()).id;

      Future<void> insert(AssertionsCompanion c) =>
          db.into(db.assertions).insert(c);
      await expectLater(
        insert(
          AssertionsCompanion.insert(
            familyId: Value(family),
            burialId: Value(burial),
            sourceKind: SourceKind.notes,
            status: AssertionStatus.claimed,
            recordedAt: _clock(),
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        insert(
          AssertionsCompanion.insert(
            sourceKind: SourceKind.notes,
            status: AssertionStatus.claimed,
            recordedAt: _clock(),
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    },
  );

  test(
    'a relative\'s chip: the entry of a person buried nowhere has no grave; one in a grave has its '
    'title and how many lie in it',
    () async {
      final int nowhere = await person('Bez grobu');
      final ({
        BuriedPerson person,
        int? graveId,
        String? graveTitle,
        int peopleCount,
      })?
      found = await loadPersonForCorrection(db, nowhere);
      expect(found!.person.givenNames, 'Bez grobu');
      expect(found.graveId, isNull);
      expect(found.graveTitle, isNull);

      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'W grobie'),
      );
      await addPersonToGrave(
        db,
        graveId: grave,
        entry: const PersonEntry(givenNames: 'Drugi'),
      );
      final int buried = (await loadGrave(db, grave))!.people.first.id;
      final ({
        BuriedPerson person,
        int? graveId,
        String? graveTitle,
        int peopleCount,
      })?
      inGrave = await loadPersonForCorrection(db, buried);
      expect(inGrave!.graveId, grave);
      expect(
        inGrave.graveTitle,
        'Cmentarz Wymyślony',
      ); // no grave name: the cemetery's
      expect(inGrave.peopleCount, 2);
      expect(await loadPersonForCorrection(db, 999), isNull);
    },
  );

  test(
    'Dev deviation 1 — each view hears its own tables: with the cemetery\'s list open, the section '
    'follows a family saved without a new person, and the grave view a date changed alone',
    () async {
      final int grave = await addPersonToNewGrave(
        db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Maria'),
      );
      final int maria = (await loadGrave(db, grave))!.people.single.id;
      final int jan = await person('Jan');

      // The cemetery's list first — it reads neither families nor claims nor events.
      final StreamSubscription<CemeteryGraves?> list = watchCemeteryGraves(
        db,
        cemetery,
      ).listen((_) {});
      final List<PersonRelations> sections = [];
      final StreamSubscription<PersonRelations> section = watchRelations(
        db,
        maria,
      ).listen(sections.add);
      final List<GraveDetail?> views = [];
      final StreamSubscription<GraveDetail?> view = watchGrave(
        db,
        grave,
      ).listen(views.add);
      await pumpEventQueue();

      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(maria), ExistingMember(jan)],
          children: const [],
        ),
      );
      await addEventWithClaim(
        db,
        EventsCompanion.insert(
          type: EventType.death,
          personId: Value(maria),
          qualifier: const Value(DateQualifier.exact),
          year: const Value(1960),
        ),
      );
      await pumpEventQueue();

      expect(sections.last.unions.single.partner!.id, jan);
      expect(
        views.last!.people.single.death.date,
        const QualifiedDate(DateQualifier.exact, PartialDate(1960)),
      );
      await list.cancel();
      await section.cancel();
      await view.cancel();
    },
  );

  // ISSUE-025 — the union as a timeline (together since → wedding → end) and a new person's sex.

  test(
    'ISSUE-025 AC-3 — "Razem od" 1980 and the wedding 1985 are both written, '
    'each with its claim, and read back as the union of each partner',
    () async {
      final int jan = await person('Jan'), maria = await person('Maria');
      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(maria), ExistingMember(jan)],
          children: const [],
          together: const QualifiedDate(DateQualifier.exact, PartialDate(1980)),
          marriage: const QualifiedDate(DateQualifier.exact, PartialDate(1985)),
        ),
        clock: _clock,
      );
      final List<Event> events = await (db.select(
        db.events,
      )..where((e) => e.familyId.equals(family))).get();
      expect(events.map((e) => (e.type, e.year)), [
        (EventType.together, 1980),
        (EventType.marriage, 1985),
      ]);
      for (final Event e in events) {
        expect(
          await (db.select(
            db.assertions,
          )..where((a) => a.eventId.equals(e.id))).get(),
          hasLength(1),
          reason: '${e.type} has its claim',
        );
      }
      final PersonUnion union = (await loadRelations(db, maria)).unions.single;
      expect(union.together?.from.year, 1980);
      expect(union.married, isTrue);
      expect(union.marriage?.from.year, 1985);
      expect(union.ended, isFalse);
      final FamilyDetail detail = (await loadFamily(db, family))!;
      expect(detail.together.date?.from.year, 1980);
      expect(detail.married, isTrue);
    },
  );

  test('ISSUE-025 — a wedding without a date is an event without a date, with '
      'its claim (GEDCOM MARR Y); it survives a later save, and "To nie było '
      'małżeństwo" takes it away with its claim', () async {
    final int jan = await person('Jan'), maria = await person('Maria');
    final int family = await saveFamily(
      db,
      FamilyDraft(
        partners: [ExistingMember(maria), ExistingMember(jan)],
        children: const [],
        married: true,
      ),
    );
    Future<List<Event>> weddings() =>
        (db.select(db.events)
              ..where((e) => e.familyId.equals(family))
              ..where((e) => e.type.equalsValue(EventType.marriage)))
            .get();
    expect((await weddings()).single.year, isNull);
    expect(await count('assertions'), 2, reason: 'the family and the wedding');
    expect((await loadRelations(db, maria)).unions.single.married, isTrue);

    // A later save of another row of the summary keeps the dateless wedding.
    await saveFamily(
      db,
      FamilyDraft(
        familyId: family,
        partners: [ExistingMember(maria), ExistingMember(jan)],
        children: const [],
        together: const QualifiedDate(DateQualifier.about, PartialDate(1946)),
        married: true,
      ),
    );
    expect(await weddings(), hasLength(1));
    expect((await loadFamily(db, family))!.married, isTrue);

    await saveFamily(
      db,
      FamilyDraft(
        familyId: family,
        partners: [ExistingMember(maria), ExistingMember(jan)],
        children: const [],
        together: const QualifiedDate(DateQualifier.about, PartialDate(1946)),
        married: false,
      ),
    );
    expect(await weddings(), isEmpty);
    expect(await count('assertions'), 2, reason: 'the family and "razem od"');
    expect((await loadRelations(db, maria)).unions.single.married, isFalse);
  });

  test(
    'ISSUE-025 — a dated wedding cleared to "Nie znam daty" keeps the event '
    'and loses its date; an end without a date is written the same way',
    () async {
      final int jan = await person('Jan'), maria = await person('Maria');
      final int family = await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(maria), ExistingMember(jan)],
          children: const [],
          marriage: _about1948,
        ),
      );
      await saveFamily(
        db,
        FamilyDraft(
          familyId: family,
          partners: [ExistingMember(maria), ExistingMember(jan)],
          children: const [],
          married: true,
          ended: true,
        ),
      );
      final FamilyDetail f = (await loadFamily(db, family))!;
      expect(f.married, isTrue);
      expect(f.marriage.date, isNull);
      expect(f.ended, isTrue);
      expect(f.end.date, isNull);
      final List<Event> events = await (db.select(
        db.events,
      )..where((e) => e.familyId.equals(family))).get();
      expect(events.map((e) => (e.type, e.year, e.qualifier)), [
        (EventType.marriage, null, null),
        (EventType.end, null, null),
      ]);
    },
  );

  test(
    'ISSUE-025 — a date for a wedding that did not happen is refused',
    () async {
      final int jan = await person('Jan'), maria = await person('Maria');
      await expectLater(
        saveFamily(
          db,
          FamilyDraft(
            partners: [ExistingMember(maria), ExistingMember(jan)],
            children: const [],
            married: false,
            marriage: _about1948,
          ),
        ),
        throwsArgumentError,
      );
      expect(await count('families'), 0, reason: 'all or nothing');
    },
  );

  test('ISSUE-025 — a new person keeps the sex chosen in the wizard; their '
      'relatives read it back', () async {
    final int maria = await person('Maria');
    final int family = await saveFamily(
      db,
      FamilyDraft(
        partners: [
          ExistingMember(maria),
          const NewMember(
            givenNames: 'Kuba',
            surname: 'Testowy',
            sex: Sex.male,
          ),
        ],
        children: const [
          NewMember(givenNames: 'Anna', surname: 'Testowa', sex: Sex.female),
        ],
      ),
    );
    final FamilyDetail f = (await loadFamily(db, family))!;
    expect(
      f.partners.map((p) => (p.givenNames, p.sex)),
      containsAll([('Kuba', Sex.male)]),
    );
    expect(f.children.single.sex, Sex.female);
    final PersonUnion u = (await loadRelations(db, maria)).unions.single;
    expect(u.partner?.sex, Sex.male);
    expect(u.married, isFalse, reason: 'no wedding written — "Partner"');
  });

  test('ISSUE-025 — unions in order of their first date: "Razem od" before the '
      'wedding; the parents\' union comes with its own timeline', () async {
    final int maria = await person('Maria');
    final int jan = await person('Jan'), kuba = await person('Kuba');
    final int mama = await person('Zofia');
    await saveFamily(
      db,
      FamilyDraft(
        partners: [ExistingMember(maria), ExistingMember(kuba)],
        children: const [],
        marriage: const QualifiedDate(DateQualifier.exact, PartialDate(1960)),
      ),
    );
    await saveFamily(
      db,
      FamilyDraft(
        partners: [ExistingMember(maria), ExistingMember(jan)],
        children: const [],
        together: const QualifiedDate(DateQualifier.exact, PartialDate(1946)),
        marriage: const QualifiedDate(DateQualifier.exact, PartialDate(1970)),
      ),
    );
    await saveFamily(
      db,
      FamilyDraft(
        partners: [ExistingMember(mama)],
        children: [ExistingMember(maria)],
        married: true,
      ),
    );
    final PersonRelations r = await loadRelations(db, maria);
    expect(r.unions.map((u) => u.partner?.givenNames), ['Jan', 'Kuba']);
    expect(r.parentsUnion?.married, isTrue);
    expect(r.parentsUnion?.marriage, isNull);
    expect(r.parents.single.givenNames, 'Zofia');
  });
}
