import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/person/kinship_names.dart';
import 'package:grobing/data/database.dart' show Sex;
import 'package:grobing/data/kinship.dart';

// ISSUE-024 AC-3 (osoba.md v2.1 element 7, D13') — the chain after "Ja": each row the step to the person
// above and the first name, as R3's path card; "jej"/"jego" by the word in the row above, not the person's
// sex. Made-up names only (family-data.md).

ChainPerson _p(KinEdge edge, String name, {Sex? sex, bool married = false}) =>
    ChainPerson(edge: edge, sex: sex, married: married, name: name);

void main() {
  test('a grandmother: "Mama Anna", "Jej mama Maria" (AC-3)', () {
    expect(
      chainLabels([
        _p(KinEdge.parent, 'Anna', sex: Sex.female),
        _p(KinEdge.parent, 'Maria', sex: Sex.female),
      ]),
      ['Mama Anna', 'Jej mama Maria'],
    );
  });

  test(
    'through a wife, as R3: "Żona Kasia", "Jej tata Marek", "Jego siostra Ewa", "Jej mąż Józef"',
    () {
      expect(
        chainLabels([
          _p(KinEdge.partner, 'Kasia', sex: Sex.female, married: true),
          _p(KinEdge.parent, 'Marek', sex: Sex.male),
          _p(KinEdge.sibling, 'Ewa', sex: Sex.female),
          _p(KinEdge.partner, 'Józef', sex: Sex.male, married: true),
        ]),
        ['Żona Kasia', 'Jej tata Marek', 'Jego siostra Ewa', 'Jej mąż Józef'],
      );
    },
  );

  test(
    'a pair "razem": partnerka / partner; a mother\'s brother: "Jej brat Zenon"',
    () {
      expect(
        chainLabels([
          _p(KinEdge.partner, 'Ola', sex: Sex.female),
          _p(KinEdge.child, 'Piotr', sex: Sex.male),
        ]),
        ['Partnerka Ola', 'Jej syn Piotr'],
      );
      expect(
        chainLabels([
          _p(KinEdge.parent, 'Anna', sex: Sex.female),
          _p(KinEdge.sibling, 'Zenon', sex: Sex.male),
        ]),
        ['Mama Anna', 'Jej brat Zenon'],
      );
    },
  );

  test(
    'without a sex the neutral word, and the next row says "jego" — the word\'s gender',
    () {
      expect(
        chainLabels([
          _p(KinEdge.parent, 'Piotr', sex: Sex.male),
          _p(KinEdge.parent, 'Aleksander'),
          _p(KinEdge.child, 'Zofia', sex: Sex.female),
        ]),
        ['Tata Piotr', 'Jego rodzic Aleksander', 'Jego córka Zofia'],
      );
      expect(stepWord(KinEdge.child, null), 'dziecko');
      expect(stepWord(KinEdge.sibling, null), 'rodzeństwo');
      expect(stepWord(KinEdge.partner, null), 'partner');
      // As the mini tree's "Małżonek" (rodzina.md Role names) — ui review of ISSUE-024.
      expect(stepWord(KinEdge.partner, null, married: true), 'małżonek');
    },
  );

  test('no steps — no rows', () => expect(chainLabels(const []), isEmpty));
}
