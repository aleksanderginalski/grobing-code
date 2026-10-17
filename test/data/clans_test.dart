import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/clans.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/wreaths.dart';

// ISSUE-044 — family lines in the data (lib/data/clans.dart; 05_DESIGN/wieniec.md E, F, D16): a new line
// chosen at a person in one transaction, the name unique without case and Polish letters, a line corrected
// for everyone (AC-6), the choice written and cleared; read back through the tree (AC-1, AC-2). Made-up
// people only (family-data.md).

void main() {
  late GrobingDatabase db;

  setUp(() {
    db = GrobingDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> person(String given, Sex sex) => db
      .into(db.persons)
      .insert(
        PersonsCompanion.insert(
          givenNames: Value(given),
          surname: const Value('Wymyślony'),
          sex: Value(sex),
        ),
      );

  Future<Person> read(int id) =>
      (db.select(db.persons)..where((p) => p.id.equals(id))).getSingle();

  test(
    'F6 — a new line is chosen at the person whose entry is open, in the same transaction; its keys are '
    'the motif\'s and the colour\'s',
    () async {
      final int jozef = await person('Józef', Sex.male);
      final int id = await createClan(
        db,
        name: '  Wymyślscy ',
        motif: WreathMotif.dzikaRoza,
        colour: ClanColour.koscSloniowa,
        forPerson: jozef,
      );

      final ClanRow row = await db.select(db.clans).getSingle();
      expect(
        (row.id, row.name, row.motif, row.colour),
        (id, 'Wymyślscy', 'dzika_roza', 'kosc_sloniowa'),
      );
      expect((await read(jozef)).clanId, id);
      expect((await read(jozef)).noWreath, isFalse);
      final List<Clan> clans = await loadClans(db);
      expect(
        (clans.single.motif, clans.single.colour),
        (WreathMotif.dzikaRoza, ClanColour.koscSloniowa),
      );
    },
  );

  test(
    'F2 — the name is refused empty, and when another line has it without case and Polish letters; nothing '
    'is written then, the person keeps the choice they had',
    () async {
      final int jozef = await person('Józef', Sex.male);
      final int jan = await person('Jan', Sex.male);
      await createClan(
        db,
        name: 'Wymyślscy',
        motif: WreathMotif.dab,
        colour: ClanColour.stareZloto,
        forPerson: jozef,
      );

      Future<ClanNameProblem?> problemOf(Future<void> write) async {
        try {
          await write;
          return null;
        } on ClanNameException catch (e) {
          return e.problem;
        }
      }

      expect(
        await problemOf(
          createClan(
            db,
            name: 'wymyslscy',
            motif: WreathMotif.laur,
            colour: ClanColour.patyna,
            forPerson: jan,
          ),
        ),
        ClanNameProblem.taken,
      );
      expect(
        await problemOf(
          createClan(
            db,
            name: '   ',
            motif: WreathMotif.laur,
            colour: ClanColour.patyna,
            forPerson: jan,
          ),
        ),
        ClanNameProblem.empty,
      );
      expect(await db.select(db.clans).get(), hasLength(1));
      expect((await read(jan)).clanId, isNull);
    },
  );

  test(
    'AC-6, F poprawa — a line\'s name, motif and colour change for everyone with it; its own name is no '
    'clash, another line\'s is',
    () async {
      final int jozef = await person('Józef', Sex.male);
      final int w = await createClan(
        db,
        name: 'Wymyślscy',
        motif: WreathMotif.dab,
        colour: ClanColour.stareZloto,
        forPerson: jozef,
      );
      await createClan(
        db,
        name: 'Zmyśleńscy',
        motif: WreathMotif.laur,
        colour: ClanColour.patyna,
      );

      await updateClan(
        db,
        w,
        name: 'Wymyślscy',
        motif: WreathMotif.dab,
        colour: ClanColour.miedz,
      );
      final FamilyTreeData tree = await loadFamilyTree(db);
      expect(tree.wreaths.of(jozef).own?.colour, ClanColour.miedz);

      await expectLater(
        updateClan(
          db,
          w,
          name: 'ZMYŚLEŃSCY',
          motif: WreathMotif.dab,
          colour: ClanColour.miedz,
        ),
        throwsA(
          isA<ClanNameException>().having(
            (e) => e.problem,
            'problem',
            ClanNameProblem.taken,
          ),
        ),
      );
      expect(
        (await (db.select(
          db.clans,
        )..where((c) => c.id.equals(w))).getSingle()).name,
        'Wymyślscy',
      );
    },
  );

  test(
    'E1, E1a, E2 — the choice: a line, "bez wieńca", back to the father\'s — one of the two columns, never '
    'both',
    () async {
      final int jan = await person('Jan', Sex.male);
      final int w = await createClan(
        db,
        name: 'Wymyślscy',
        motif: WreathMotif.dab,
        colour: ClanColour.stareZloto,
      );

      await setWreathChoice(db, jan, WreathChoice.clan(w));
      expect(
        ((await read(jan)).clanId, (await read(jan)).noWreath),
        (w, false),
      );
      await setWreathChoice(db, jan, const WreathChoice.none());
      expect(
        ((await read(jan)).clanId, (await read(jan)).noWreath),
        (null, true),
      );
      await setWreathChoice(db, jan, const WreathChoice.inherit());
      expect(
        ((await read(jan)).clanId, (await read(jan)).noWreath),
        (null, false),
      );
    },
  );

  test(
    'AC-1, AC-2 through the tree — a father with a line gives it to the child added to him; an exception at '
    'the child stays with the child',
    () async {
      final int jozef = await person('Józef', Sex.male);
      final int w = await createClan(
        db,
        name: 'Wymyślscy',
        motif: WreathMotif.dab,
        colour: ClanColour.stareZloto,
        forPerson: jozef,
      );
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(jozef)],
          children: [
            const NewMember(
              givenNames: 'Jan',
              surname: 'Wymyślony',
              sex: Sex.male,
            ),
            const NewMember(
              givenNames: 'Maria',
              surname: 'Wymyślona',
              sex: Sex.female,
            ),
          ],
        ),
      );
      FamilyTreeData tree = await loadFamilyTree(db);
      final int jan = tree.people.values
          .firstWhere((p) => p.givenNames == 'Jan')
          .id;
      final int maria = tree.people.values
          .firstWhere((p) => p.givenNames == 'Maria')
          .id;
      expect(
        (tree.wreaths.of(jan).own?.id, tree.wreaths.of(jan).origin),
        (w, WreathOrigin.fromFather),
      );

      final int p = await createClan(
        db,
        name: 'Przykładowscy',
        motif: WreathMotif.jarzebina,
        colour: ClanColour.lawenda,
        forPerson: jan,
      );
      tree = await loadFamilyTree(db);
      expect(tree.wreaths.of(jan).own?.id, p);
      expect(tree.wreaths.of(jan).overridesFather, isTrue);
      expect(tree.wreaths.of(jozef).own?.id, w);
      expect(tree.wreaths.of(maria).own?.id, w);
    },
  );

  test('E2 — lines A–Z without case and Polish letters', () async {
    for (final String name in [
      'Zmyśleńscy',
      'testowi',
      'Wymyślscy',
      'Przykładowi',
    ]) {
      await createClan(
        db,
        name: name,
        motif: WreathMotif.laur,
        colour: ClanColour.stareZloto,
      );
    }
    expect((await loadClans(db)).map((c) => c.name), [
      'Przykładowi',
      'testowi',
      'Wymyślscy',
      'Zmyśleńscy',
    ]);
  });

  test(
    'F3, F4, D20 — a new line starts with the colour and the motif nobody has; with every motif used, the first '
    'motif nobody has in that colour, since a line is told by its motif and colour together',
    () {
      Clan line(int id, WreathMotif motif, ClanColour colour) =>
          Clan(id: id, name: 'Wymyślscy $id', motif: motif, colour: colour);

      expect(
        (
          firstFreeColour(const []),
          firstFreeMotif(const [], ClanColour.values.first),
        ),
        (ClanColour.values.first, WreathMotif.values.first),
      );
      final List<Clan> two = [
        line(1, WreathMotif.values[0], ClanColour.values[0]),
        line(2, WreathMotif.values[1], ClanColour.values[1]),
      ];
      expect(
        (firstFreeColour(two), firstFreeMotif(two, ClanColour.values[2])),
        (ClanColour.values[2], WreathMotif.values[2]),
      );

      // Every motif has a line, all in the first colour but the third motif, which is in the second.
      final List<Clan> every = [
        for (final WreathMotif m in WreathMotif.values)
          line(
            m.index + 1,
            m,
            m == WreathMotif.values[2]
                ? ClanColour.values[1]
                : ClanColour.values[0],
          ),
      ];
      expect(
        firstFreeMotif(every, ClanColour.values[0]),
        WreathMotif.values[2],
      );
      expect(
        firstFreeMotif(every, ClanColour.values[1]),
        WreathMotif.values[0],
      );
      expect(
        firstFreeMotif(every, ClanColour.values[3]),
        WreathMotif.values[0],
      );

      // Every pair used: the first motif.
      final List<Clan> all = [
        for (final ClanColour c in ClanColour.values)
          for (final WreathMotif m in WreathMotif.values)
            line(c.index * 100 + m.index, m, c),
      ];
      expect(firstFreeColour(all), ClanColour.values.first);
      expect(
        firstFreeMotif(all, ClanColour.values[5]),
        WreathMotif.values.first,
      );
    },
  );

  test(
    'a key the app does not know (a backup from a newer app): no motif — no wreath; an unknown colour falls '
    'back to the first',
    () async {
      await db
          .into(db.clans)
          .insert(
            ClansCompanion.insert(
              name: 'Testowi',
              motif: 'mak',
              colour: 'zielen',
            ),
          );
      final Clan clan = (await loadClans(db)).single;
      expect(clan.motif, isNull);
      expect(clan.colour, ClanColour.values.first);
    },
  );
}
