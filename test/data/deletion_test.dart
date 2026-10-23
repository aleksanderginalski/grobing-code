import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/cemetery_plans.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/deletion.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/data/sectors.dart';
import 'package:grobing/dev/fictional_data.dart';

// ISSUE-053 — deleting what was added, with "Cofnij" (lib/data/deletion.dart; 05_DESIGN/brand/style-b.md rule 16,
// cmentarze.md 15a, grob.md 3d, wpis-osoby.md 12a/12, cmentarz.md 12b, wieniec.md F7), happy path per AC: AC-1 an
// empty cemetery with its plan, sectors and photo · AC-2 a cemetery with graves — the people stay · AC-3 a grave with
// people — they stay, without it · AC-4 a person with everything theirs · AC-6 a person taken out of a grave, then into
// another · AC-7 a pin · AC-8 a family line. Every deletion is put back by "Cofnij" to the same data fingerprint (the
// measure of NFR-002). AC-5 (a backup after a deletion) is in restore_service_test.dart. Made-up people only
// (family-data.md): the batch of `addFictionalData`.

void main() {
  late Directory tmp;
  late Directory media;
  late GrobingDatabase db;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_deletion_test');
    media = Directory('${tmp.path}/media');
    db = GrobingDatabase(NativeDatabase.memory());
    // One batch: "Cmentarz Wymyślony 1" with "Grób rodzinny Wymyślonych" (father, mother, gravestone photo) and a
    // grave with the address "Kwatera B · Rząd 3 · Miejsce 12" (the child); the father in two unions; the lines
    // "Wymyślscy 1" (at the father) and "Zmyśleńscy 1" (at the mother); the mother's portrait and the wedding photo
    // she shares with the father.
    await addFictionalData(db, media);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<String> fingerprint() async =>
      (await readDataState(db, mediaDir: media)).fingerprint;

  Future<int> count(String table, [String where = '1']) async =>
      (await db
              .customSelect('SELECT COUNT(*) AS c FROM $table WHERE $where')
              .getSingle())
          .read<int>('c');

  Future<int> person(String givenNames) async => (await (db.select(
    db.persons,
  )..where((p) => p.givenNames.equals(givenNames))).getSingle()).id;

  Future<int> cemetery() async =>
      (await db.select(db.cemeteries).getSingle()).id;

  Future<int> familyGrave() async => (await (db.select(
    db.graves,
  )..where((g) => g.name.equals('Grób rodzinny Wymyślonych'))).getSingle()).id;

  Future<int> addressGrave() async => (await (db.select(
    db.graves,
  )..where((g) => g.row.equals('3'))).getSingle()).id;

  group('AC-1 — an empty cemetery', () {
    late int empty;

    setUp(() async {
      empty = await addCemetery(
        db,
        name: 'Cmentarz Próbny',
        locality: 'Miejscowość Testowa',
        point: const GeoPoint(51.0, 20.0),
      );
      await savePlan(
        db,
        empty,
        forPoint: const GeoPoint(51.0, 20.0),
        areas: const [
          PlanArea([
            GeoPoint(51.0, 20.0),
            GeoPoint(51.001, 20.0),
            GeoPoint(51.001, 20.001),
          ]),
        ],
        paths: const [],
        server: 'overpass.example',
        now: DateTime(2026, 10, 23, 12),
      );
      await addSector(
        db,
        empty,
        name: 'A',
        zone: const [
          GeoPoint(51.0, 20.0),
          GeoPoint(51.0005, 20.0),
          GeoPoint(51.0005, 20.0005),
        ],
      );
      await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              relativePath: 'cmentarze/proba.png',
              cemeteryId: Value(empty),
            ),
          );
    });

    test(
      'the window says plan, sectors and photo; they go with the cemetery, the other cemetery stays; '
      '"Cofnij" brings the same plan, sector and photo back — the fingerprint is the one from before',
      () async {
        final CemeteryDeletionPreview preview = await previewCemeteryDeletion(
          db,
          empty,
        );
        expect(preview.graves, 0);
        expect(preview.people, 0);
        expect(
          (preview.hasPlan, preview.hasSectors, preview.hasPhoto),
          (true, true, true),
        );

        final String before = await fingerprint();
        final DeletionSnapshot taken = await deleteCemetery(db, empty);
        expect(await count('cemeteries', 'id = $empty'), 0);
        expect(await count('cemetery_plans', 'cemetery_id = $empty'), 0);
        expect(await count('sectors', 'cemetery_id = $empty'), 0);
        expect(await count('media', 'cemetery_id = $empty'), 0);
        expect(await count('cemeteries'), 1);
        expect(await fingerprint(), isNot(before));

        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
        expect(
          (await watchCemeteryPlan(db, empty).first)!.status,
          PlanStatus.ok,
        );
      },
    );

    test(
      '"W OpenStreetMap nie ma planu" is no plan to lose: the window does not say "planem" (dev pass)',
      () async {
        final int noPlan = await addCemetery(
          db,
          name: 'Cmentarz Bez Planu',
          point: const GeoPoint(50.0, 19.0),
        );
        await saveNotInOsm(
          db,
          noPlan,
          forPoint: const GeoPoint(50.0, 19.0),
          server: 'overpass.example',
        );
        final CemeteryDeletionPreview preview = await previewCemeteryDeletion(
          db,
          noPlan,
        );
        expect(
          (preview.hasPlan, preview.hasSectors, preview.hasPhoto),
          (false, false, false),
        );
        final String before = await fingerprint();
        final DeletionSnapshot taken = await deleteCemetery(db, noPlan);
        expect(await count('cemetery_plans', 'cemetery_id = $noPlan'), 0);
        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
      },
    );
  });

  test(
    'AC-2 — a cemetery with graves (D40): its graves, burials with their claims, the gravestone photo and the '
    'address sector go; the people stay, with their dates, families and photos; "Cofnij" — the same fingerprint',
    () async {
      final int c = await cemetery();
      final CemeteryDeletionPreview preview = await previewCemeteryDeletion(
        db,
        c,
      );
      expect(preview.graves, 2);
      expect(preview.people, 3);
      expect(preview.gravesWithPhoto, 1);
      expect(preview.gravesWithPin, 0);
      expect(preview.gravesWithAddress, 1);
      expect(preview.hasSectors, isTrue);

      final int people = await count('persons');
      final int events = await count('events');
      final int families = await count('families');
      final String before = await fingerprint();
      final DeletionSnapshot taken = await deleteCemetery(db, c);
      expect(await count('cemeteries'), 0);
      expect(await count('graves'), 0);
      expect(await count('burials'), 0);
      expect(await count('assertions', 'burial_id IS NOT NULL'), 0);
      expect(await count('sectors'), 0);
      expect(await count('media', 'grave_id IS NOT NULL'), 0);
      expect(await count('persons'), people);
      expect(await count('events'), events);
      expect(await count('families'), families);
      expect(await count('person_media'), 3);
      // In Osoby they are there, buried nowhere.
      final List<PersonListEntry> list = await loadPeople(db);
      expect(list, hasLength(people));

      await restoreDeletion(db, taken);
      expect(await fingerprint(), before);
    },
  );

  group('AC-3 — a grave', () {
    test(
      'with people (D28): the window names them in the order they were entered; the burials go, the people '
      'stay; "Cofnij" — the same fingerprint',
      () async {
        final int grave = await familyGrave();
        final GraveDeletionPreview preview = await previewGraveDeletion(
          db,
          grave,
        );
        expect(preview.name, 'Grób rodzinny Wymyślonych');
        expect(
          (preview.hasPhoto, preview.hasPin, preview.hasAddress),
          (true, false, false),
        );
        expect(preview.people.map((p) => p.givenNames), [
          'Ojciec 1',
          'Matka 1',
        ]);

        final String before = await fingerprint();
        final DeletionSnapshot taken = await deleteGrave(db, grave);
        expect(await count('graves', 'id = $grave'), 0);
        expect(await count('burials', 'grave_id = $grave'), 0);
        expect(await count('media', 'grave_id = $grave'), 0);
        expect(await count('persons'), 5);
        expect(await count('graves'), 1);
        // Free for "Dodaj osobę" in another grave (grob.md D22) — and taken out of it again before "Cofnij".
        await addExistingPersonToGrave(
          db,
          graveId: await addressGrave(),
          personId: await person('Matka 1'),
        );
        await removeFromGrave(
          db,
          await person('Matka 1'),
          await addressGrave(),
        );

        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
      },
    );

    test(
      'its sector without a zone goes with it, as when an address changes (cmentarz.md D27) — and comes back with '
      'its id, so the address says "Kwatera B" again',
      () async {
        final int grave = await addressGrave();
        final int sector = (await (db.select(
          db.graves,
        )..where((g) => g.id.equals(grave))).getSingle()).sectorId!;
        final String before = await fingerprint();
        final DeletionSnapshot taken = await deleteGrave(db, grave);
        expect(await count('sectors', 'id = $sector'), 0);
        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
        expect((await loadGrave(db, grave))!.sector, 'B');
      },
    );

    test(
      'a gravestone photo someone is also on stays with them, without the grave; "Cofnij" gives it back to the '
      'grave',
      () async {
        final int grave = await familyGrave();
        final int photo = (await (db.select(
          db.media,
        )..where((m) => m.graveId.equals(grave))).getSingle()).id;
        await db
            .into(db.personMedia)
            .insert(
              PersonMediaCompanion.insert(
                personId: await person('Dziecko 1'),
                mediaId: photo,
                position: 0,
              ),
            );
        final String before = await fingerprint();
        final DeletionSnapshot taken = await deleteGrave(db, grave);
        final MediaFile kept = await (db.select(
          db.media,
        )..where((m) => m.id.equals(photo))).getSingle();
        expect(kept.graveId, isNull);
        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
      },
    );
  });

  group('AC-4 — a person', () {
    test(
      'the window lists what is theirs: the burial with its grave, both unions with who stays, the photo shared '
      'with someone (it stays) — not "ja"',
      () async {
        final PersonDeletionPreview preview = await previewPersonDeletion(
          db,
          await person('Ojciec 1'),
        );
        expect(preview.isMe, isFalse);
        expect(preview.burial, (
          graveName: 'Grób rodzinny Wymyślonych',
          cemeteryName: 'Cmentarz Wymyślony 1',
        ));
        expect(preview.unions.map((u) => (u.partner?.givenNames, u.children)), [
          ('Matka 1', 1),
          ('Partnerka 1', 1),
        ]);
        expect(preview.hasParents, isFalse);
        expect(preview.residences, 0);
        expect((preview.ownPhotos, preview.sharedPhotos), (0, 1));

        final PersonDeletionPreview child = await previewPersonDeletion(
          db,
          await person('Dziecko 1'),
        );
        expect(child.hasParents, isTrue);
        expect(child.unions, isEmpty);
      },
    );

    test(
      'the father goes with his dates, burial, claims and places in both unions; the mother and the partner keep '
      'their unions with the children, the wedding photo stays with the mother, his line stays; "Cofnij" — the '
      'same fingerprint',
      () async {
        final int father = await person('Ojciec 1');
        await db.customStatement(
          'INSERT INTO residences (person_id, level, place_name, country_code, country_name, lat, lon, geonames_id) '
          "VALUES (?, 'locality', 'Wymyślin', 'PL', 'Polska', 51.0, 20.0, 1)",
          [father],
        );
        final String before = await fingerprint();
        final DeletionSnapshot taken = await deletePerson(db, father);

        expect(await count('persons', 'id = $father'), 0);
        expect(await count('events', 'person_id = $father'), 0);
        expect(await count('burials', 'person_id = $father'), 0);
        expect(await count('family_partners', 'person_id = $father'), 0);
        expect(await count('residences', 'person_id = $father'), 0);
        expect(await count('person_media', 'person_id = $father'), 0);
        // Both unions keep a partner and a child: neither goes.
        expect(await count('families'), 2);
        final PersonRelations mother = await loadRelations(
          db,
          await person('Matka 1'),
        );
        expect(mother.unions.single.children, hasLength(1));
        expect(await count('media'), 3);
        expect(await count('clans'), 2);
        expect(
          await count(
            'assertions',
            'event_id IS NULL AND burial_id IS NULL AND family_id IS NULL AND family_child_id IS NULL',
          ),
          0,
        );

        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
      },
    );

    test(
      'the mother takes her portrait — nobody else is on it — and leaves the wedding photo with the father; '
      '"Cofnij" brings the portrait row back to its file',
      () async {
        final int mother = await person('Matka 1');
        final PersonDeletionPreview preview = await previewPersonDeletion(
          db,
          mother,
        );
        expect((preview.ownPhotos, preview.sharedPhotos), (1, 1));
        final String before = await fingerprint();
        final DeletionSnapshot taken = await deletePerson(db, mother);
        expect(await count('media'), 2);
        expect(
          await count(
            'person_media',
            'person_id = ${await person('Ojciec 1')}',
          ),
          1,
        );
        await restoreDeletion(db, taken);
        expect(await fingerprint(), before);
      },
    );

    test(
      'a union left without two people goes whole with its dates and claims, as "Usuń związek" (rodzina.md D8) — '
      'a couple without children, and a parent whose only child goes; the other people stay',
      () async {
        final int couple = await saveFamily(
          db,
          const FamilyDraft(
            partners: [
              NewMember(givenNames: 'Testowy', surname: 'Zmyślony'),
              NewMember(givenNames: 'Testowa', surname: 'Zmyślona'),
            ],
            children: [],
            together: QualifiedDate(DateQualifier.about, PartialDate(1950)),
          ),
        );
        final int he = await person('Testowy');
        final int alone = await saveFamily(
          db,
          const FamilyDraft(
            partners: [NewMember(givenNames: 'Rodzic', surname: 'Testowy')],
            children: [NewMember(givenNames: 'Jedynak', surname: 'Testowy')],
          ),
        );
        final String before = await fingerprint();

        final DeletionSnapshot first = await deletePerson(db, he);
        expect(await count('families', 'id = $couple'), 0);
        expect(await count('events', 'family_id = $couple'), 0);
        expect(await count('assertions', 'family_id = $couple'), 0);
        expect(await count('persons', "given_names = 'Testowa'"), 1);

        final DeletionSnapshot second = await deletePerson(
          db,
          await person('Jedynak'),
        );
        expect(await count('families', 'id = $alone'), 0);
        expect(await count('persons', "given_names = 'Rodzic'"), 1);

        await restoreDeletion(db, second);
        await restoreDeletion(db, first);
        expect(await fingerprint(), before);
      },
    );

    test(
      '"ja" cannot be deleted — StateError, nothing changed (wpis-osoby.md 12)',
      () async {
        final int mother = await person('Matka 1');
        await setMe(db, mother);
        expect((await previewPersonDeletion(db, mother)).isMe, isTrue);
        final String before = await fingerprint();
        await expectLater(deletePerson(db, mother), throwsStateError);
        expect(await fingerprint(), before);
      },
    );
  });

  test('AC-6 — "Usuń z grobu": the burial and its claim go, the burial date and everything else stays; the person is '
      'free for another grave; "Cofnij" — the same fingerprint', () async {
    final int father = await person('Ojciec 1');
    final int grave = await familyGrave();
    await addEventWithClaim(
      db,
      EventsCompanion.insert(
        type: EventType.burial,
        personId: Value(father),
        qualifier: const Value(DateQualifier.exact),
        year: const Value(1951),
        month: const Value(3),
        day: const Value(18),
      ),
    );
    expect(await graveLabel(db, grave), (
      graveName: 'Grób rodzinny Wymyślonych',
      cemeteryName: 'Cmentarz Wymyślony 1',
    ));
    final int claims = await count('assertions');
    final String before = await fingerprint();

    final DeletionSnapshot taken = await removeFromGrave(db, father, grave);
    expect(await count('burials', 'person_id = $father'), 0);
    expect(await count('assertions'), claims - 1);
    expect(await count('events', "person_id = $father AND type = 'burial'"), 1);
    expect((await loadPersonForCorrection(db, father))!.graveId, isNull);
    await expectLater(removeFromGrave(db, father, grave), throwsStateError);

    await restoreDeletion(db, taken);
    expect(await fingerprint(), before);

    // The move to another grave (grob.md D29): out of this one, then "Dodaj osobę" in the other.
    final DeletionSnapshot moved = await removeFromGrave(db, father, grave);
    await addExistingPersonToGrave(
      db,
      graveId: await addressGrave(),
      personId: father,
    );
    expect(
      (await loadPersonForCorrection(db, father))!.graveId,
      await addressGrave(),
    );
    // A "Cofnij" still on the screen then cannot lay him in two graves (D23, ui review of ISSUE-053): refused,
    // nothing written.
    final String inOne = await fingerprint();
    await expectLater(
      restoreDeletion(db, moved),
      throwsA(isA<RestoreRefused>()),
    );
    expect(await fingerprint(), inOne);
    expect(await count('burials', 'person_id = $father'), 1);
  });

  test(
    'AC-7 — "Usuń pinezkę": the point, source, accuracy and date go, the address stays; "Cofnij" — the same pin',
    () async {
      final int grave = await addressGrave();
      await setGravePin(
        db,
        grave,
        const GeoPoint(51.0001, 20.0001),
        PositionSource.gps,
        accuracyM: 4,
        clock: () => DateTime(2026, 10, 23, 9, 20),
      );
      final String before = await fingerprint();
      final DeletionSnapshot taken = await deleteGravePin(db, grave);
      final Grave without = await (db.select(
        db.graves,
      )..where((g) => g.id.equals(grave))).getSingle();
      expect(
        (
          without.lat,
          without.lon,
          without.positionSource,
          without.positionAccuracyM,
          without.positionRecordedAt,
        ),
        (null, null, null, null, null),
      );
      expect(without.row, '3');
      expect((await previewGraveDeletion(db, grave)).hasPin, isFalse);

      await restoreDeletion(db, taken);
      expect(await fingerprint(), before);
      final GraveDetail back = (await loadGrave(db, grave))!;
      expect(back.pin?.source, PositionSource.gps);
      expect(back.pin?.accuracyM, 4);
    },
  );

  test(
    'AC-8 — "Usuń ród" (D21): the line and its choice at the father go — he and his child get what the rule gives '
    'without it; "Bez wieńca" at the second child stays; "Cofnij" — the same fingerprint and wreaths',
    () async {
      final int father = await person('Ojciec 1');
      final int child = await person('Dziecko 1');
      final int second = await person('Dziecko z drugiego związku 1');
      final ClanRow line = await (db.select(
        db.clans,
      )..where((c) => c.name.equals('Wymyślscy 1'))).getSingle();
      FamilyTreeData tree = await loadFamilyTree(db);
      expect(tree.wreaths.countWith(line.id), greaterThanOrEqualTo(2));
      expect(tree.wreaths.of(child).own?.name, 'Wymyślscy 1');

      final String before = await fingerprint();
      final DeletionSnapshot taken = await deleteClan(db, line.id);
      expect(await count('clans', 'id = ${line.id}'), 0);
      expect(await count('persons', 'clan_id = ${line.id}'), 0);
      expect(await count('persons', 'no_wreath = 1 AND id = $second'), 1);
      tree = await loadFamilyTree(db);
      expect(tree.wreaths.of(father).own, isNull);
      expect(tree.wreaths.of(child).own, isNull);

      await restoreDeletion(db, taken);
      expect(await fingerprint(), before);
      tree = await loadFamilyTree(db);
      expect(tree.wreaths.of(child).own?.name, 'Wymyślscy 1');
    },
  );

  test(
    'two deletions put back in the reverse order give the data from before — each snapshot holds only its own rows',
    () async {
      final String before = await fingerprint();
      final DeletionSnapshot person1 = await deletePerson(
        db,
        await person('Dziecko 1'),
      );
      final DeletionSnapshot cemetery1 = await deleteCemetery(
        db,
        await cemetery(),
      );
      await restoreDeletion(db, cemetery1);
      await restoreDeletion(db, person1);
      expect(await fingerprint(), before);
    },
  );
}
