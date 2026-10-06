import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/claims.dart';
import 'package:grobing/data/database.dart';

// ISSUE-014: the cemeteries of the home screen — add, correct, and the counts on the sheet (AC-4,
// 05_DESIGN/cmentarze.md D13). Made-up cemeteries and people only.
void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<CemeterySummary>> current() => watchCemeteries(db).first;

  test(
    'add: name and locality trimmed, a blank locality stored as none, the point kept',
    () async {
      final int a = await addCemetery(
        db,
        name: '  Cmentarz Wymyślony ',
        locality: ' Wieś Przykładowa ',
        point: const GeoPoint(51.0, 20.0),
      );
      final int b = await addCemetery(
        db,
        name: 'Cmentarz Próbny',
        locality: '  ',
      );

      final List<CemeterySummary> all = await current();
      expect(all.map((c) => c.id), [a, b]);
      expect(all[0].name, 'Cmentarz Wymyślony');
      expect(all[0].locality, 'Wieś Przykładowa');
      expect(all[0].point, const GeoPoint(51.0, 20.0));
      expect(all[1].locality, isNull);
      expect(all[1].point, isNull);
    },
  );

  test('a blank name is refused', () {
    expect(() => addCemetery(db, name: '   '), throwsArgumentError);
  });

  test(
    'counts: graves, and distinct people — one person with burials in two graves counts once',
    () async {
      final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
      final int other = await addCemetery(db, name: 'Cmentarz Drugi');
      final int grave1 = await db
          .into(db.graves)
          .insert(GravesCompanion.insert(cemeteryId: cemetery));
      final int grave2 = await db
          .into(db.graves)
          .insert(GravesCompanion.insert(cemeteryId: cemetery));
      Future<int> person(String name) => db
          .into(db.persons)
          .insert(PersonsCompanion.insert(givenNames: Value(name)));
      final int anna = await person('Anna Wymyślona');
      final int jan = await person('Jan Wymyślony');
      final int ewa = await person('Ewa Wymyślona');
      await addBurialWithClaim(db, personId: anna, graveId: grave1);
      await addBurialWithClaim(db, personId: jan, graveId: grave1);
      await addBurialWithClaim(db, personId: ewa, graveId: grave2);
      // Sources disagree on Ewa's grave (ADR-006 D2): a second burial row, still one person.
      await addBurialWithClaim(
        db,
        personId: ewa,
        graveId: grave1,
        source: const ClaimSource(kind: SourceKind.grandmother),
      );

      final List<CemeterySummary> all = await current();
      final CemeterySummary c = all.firstWhere((s) => s.id == cemetery);
      expect((c.graveCount, c.personCount), (2, 3));
      final CemeterySummary o = all.firstWhere((s) => s.id == other);
      expect((o.graveCount, o.personCount), (0, 0));
    },
  );

  test(
    'correct: name, locality and point change; without a point it leaves the map',
    () async {
      final int id = await addCemetery(
        db,
        name: 'Cmentarz Wymyślny',
        point: const GeoPoint(50.5, 19.5),
      );
      await updateCemetery(
        db,
        id,
        name: 'Cmentarz Wymyślony',
        locality: 'Miejscowość Testowa',
        point: const GeoPoint(51.0, 20.0),
      );
      CemeterySummary c = (await current()).single;
      expect(c.name, 'Cmentarz Wymyślony');
      expect(c.locality, 'Miejscowość Testowa');
      expect(c.point, const GeoPoint(51.0, 20.0));

      await updateCemetery(db, id, name: 'Cmentarz Wymyślony', point: null);
      c = (await current()).single;
      expect(c.point, isNull);
      expect(c.locality, isNull);
    },
  );

  test('correcting a cemetery that does not exist fails loudly', () {
    expect(
      updateCemetery(db, 999, name: 'Cmentarz Wymyślony'),
      throwsStateError,
    );
  });

  test('the stream gives a new value after every write', () async {
    final List<int> sizes = [];
    final sub = watchCemeteries(db).listen((l) => sizes.add(l.length));
    await pumpEventQueue();
    await addCemetery(db, name: 'Cmentarz Pierwszy');
    await pumpEventQueue();
    await addCemetery(db, name: 'Cmentarz Drugi');
    await pumpEventQueue();
    await sub.cancel();
    expect(sizes, [0, 1, 2]);
  });
}
