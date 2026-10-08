import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/dev/fictional_data.dart';

// ISSUE-021 AC-2, D2 — the made-up people of the debug build carry a surname in the form that fits them,
// as in the tests: "Wymyślona" on the father read as a declension error on the screens. Debug build only;
// the people stay made up (family-data.md).
void main() {
  late Directory tmp;
  late GrobingDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('grobing_fictional_test');
    db = GrobingDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test(
    'father "Wymyślony", mother "Wymyślona" née "Zmyślona", child "Wymyślone"',
    () async {
      await addFictionalData(db, Directory('${tmp.path}/media'));

      Future<Person> named(String givenNames) => (db.select(
        db.persons,
      )..where((p) => p.givenNames.equals(givenNames))).getSingle();

      final Person father = await named('Ojciec 1');
      final Person mother = await named('Matka 1');
      final Person child = await named('Dziecko 1');
      expect(father.surname, 'Wymyślony');
      expect(mother.surname, 'Wymyślona');
      expect(mother.birthSurname, 'Zmyślona');
      expect(child.surname, 'Wymyślone');
    },
  );
}
