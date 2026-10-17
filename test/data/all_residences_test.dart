import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/residences.dart';

// ISSUE-045 — everyone's residences for the migration map (lib/data/residences.dart: allResidences, watchAllResidences):
// each person's in the order of the years (zamieszkanie.md D4), a person without residences not in it, and a new value
// after a write. Read only — the map writes nothing. Made-up people and places only (family-data.md).

ResidencePlace _town(int id, String name) => ResidencePlace.locality(
  name: name,
  unit: 'woj. testowe',
  countryCode: 'PL',
  countryName: 'Polska',
  point: GeoPoint(50 + id / 10, 20 + id / 10),
  geonamesId: 990000000 + id,
);

QualifiedDate _y(int year) =>
    QualifiedDate(DateQualifier.exact, PartialDate(year));

void main() {
  late GrobingDatabase db;
  late int anna;
  late int jan;
  late int ewa;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    final int grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Anna', surname: 'Testowa'),
    );
    anna = (await db.select(db.persons).get()).single.id;
    jan = await addPersonToGrave(
      db,
      graveId: grave,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
    ewa = await addPersonToGrave(
      db,
      graveId: grave,
      entry: const PersonEntry(givenNames: 'Ewa', surname: 'Zmyślona'),
    );
  });

  tearDown(() => db.close());

  test(
    'everyone\'s residences by person, each person\'s in the order of the years; a person without any is not there',
    () async {
      // Entered out of order: the later stay first.
      await writeResidences(db, jan, [
        Residence(from: _y(1946), place: _town(2, 'Wymyślowo')),
        Residence(to: _y(1945), place: _town(1, 'Zmyślin')),
      ]);
      await writeResidences(db, anna, [
        Residence(from: _y(1950), place: _town(3, 'Testowo')),
      ]);

      final Map<int, List<Residence>> all = await allResidences(db);
      expect(all.keys.toSet(), {jan, anna});
      expect(all.containsKey(ewa), isFalse);
      expect(all[jan]!.map((r) => r.place.name), ['Zmyślin', 'Wymyślowo']);
      expect(all[anna]!.single.place.name, 'Testowo');
      expect(all[anna]!.single.from, _y(1950));
    },
  );

  test(
    'a new value after every write to the residences — the map follows a change at once',
    () async {
      final List<Map<int, List<Residence>>> seen = [];
      final sub = watchAllResidences(db).listen(seen.add);
      await pumpEventQueue();
      expect(seen.last, isEmpty);

      await writeResidences(db, ewa, [
        Residence(from: _y(1958), place: _town(3, 'Testowo')),
      ]);
      await pumpEventQueue();
      expect(seen.last.keys, [ewa]);

      await writeResidences(db, ewa, const []);
      await pumpEventQueue();
      expect(seen.last, isEmpty);
      await sub.cancel();
    },
  );
}
