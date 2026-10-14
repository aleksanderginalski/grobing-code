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

  // ISSUE-033, US-009 AC-5 (05_DESIGN/drzewo.md v1.9 element 5, D12, D13, D28) — the tree's card: who the person
  // is to "ja", from the dictionary of ISSUE-025 D2 with its bracket, farther ones told in segments counted
  // from the other person, in the genitive. In the author's voice (ISSUE-035, G2): "Mój / Moja / Moje" by the
  // word at the start, "mojego / mojej" in lower case inside. A made-up family (family-data.md).
  group('kinshipName — the tree\'s card', () {
    // Ids of the made-up family; sexes below.
    const int ja = 1, tata = 2, mama = 3, dziadek = 4, babcia = 5;
    const int ciotka = 6, stryj = 7, wujek = 8, mazCiotki = 9, kuzynka = 10;
    const int zona = 11, tesc = 12, tesciowa = 13, szwagier = 14;
    const int babciaZony = 15, dziadekZony = 16, prababkaZony = 17;
    const int pradziadekZony = 18, siostraPrababki = 19, jejMaz = 20;
    const int kuzynkaBabci = 21, praprababka = 22, prapradziadek = 23;
    const int brat = 24, partnerkaBrata = 25, dziecko = 26, rodzicMamy = 27;
    const int dziadekMamy = 28;
    final Map<int, Sex?> sex = {
      ja: Sex.male,
      tata: Sex.male,
      mama: Sex.female,
      dziadek: Sex.male,
      babcia: Sex.female,
      ciotka: Sex.female,
      stryj: Sex.male,
      wujek: Sex.male,
      mazCiotki: Sex.male,
      kuzynka: Sex.female,
      zona: Sex.female,
      tesc: Sex.male,
      tesciowa: Sex.female,
      szwagier: Sex.male,
      babciaZony: Sex.female,
      dziadekZony: Sex.male,
      prababkaZony: Sex.female,
      pradziadekZony: Sex.male,
      siostraPrababki: Sex.female,
      jejMaz: Sex.male,
      kuzynkaBabci: Sex.female,
      praprababka: Sex.female,
      prapradziadek: Sex.male,
      brat: Sex.male,
      partnerkaBrata: Sex.female,
      dziecko: null,
      rodzicMamy: null,
      dziadekMamy: Sex.male,
    };
    // family → partners, family → children; the married ones below.
    final KinGraph kin = KinGraph.of(
      partners: {
        1: [dziadek, babcia],
        2: [tata, mama],
        3: [ciotka, mazCiotki],
        4: [ja, zona],
        5: [tesc, tesciowa],
        6: [dziadekZony, babciaZony],
        7: [pradziadekZony, prababkaZony],
        8: [prapradziadek, praprababka],
        9: [jejMaz, siostraPrababki],
        10: [brat, partnerkaBrata],
        11: [rodzicMamy, dziadekMamy],
      },
      children: {
        1: [tata, ciotka, stryj],
        2: [ja, brat],
        3: [kuzynka],
        4: [dziecko],
        5: [zona, szwagier],
        6: [tesciowa],
        7: [babciaZony],
        8: [prababkaZony, siostraPrababki],
        9: [kuzynkaBabci],
        11: [mama, wujek],
      },
      married: {1, 2, 3, 4, 5, 6, 7, 8, 9, 11},
    );
    String? name(int to) => kinshipName(kin.path(ja, to)!, (id) => sex[id]);

    test('the dictionary with its brackets (AC-5)', () {
      expect(name(ciotka), 'Moja ciotka (siostra taty)');
      expect(name(stryj), 'Mój stryj (brat taty)');
      expect(name(wujek), 'Mój wuj (brat mamy)');
      expect(name(kuzynka), 'Moja siostra cioteczna (córka siostry taty)');
      expect(name(mazCiotki), 'Mój wuj (mąż siostry taty)');
      expect(name(tesc), 'Mój teść (tata żony)');
      expect(name(szwagier), 'Mój szwagier (brat żony)');
      expect(name(babcia), 'Moja babcia');
      expect(name(zona), 'Moja żona');
    });

    test(
      'farther — segments from the other person: "Siostra cioteczna babci mojej żony" (AC-5, D12)',
      () {
        expect(name(kuzynkaBabci), 'Siostra cioteczna babci mojej żony');
        // Counted from "ja", "teściowa" would take the first two steps (ISSUE-025 D2 before D12).
        expect(name(kuzynkaBabci), isNot('Siostrzenica babci mojej teściowej'));
        expect(name(babciaZony), 'Babcia mojej żony');
        expect(name(siostraPrababki), 'Ciotka babci mojej żony');
      },
    );

    test('"razem" and no sex: partnerka; the neutral words', () {
      expect(name(partnerkaBrata), 'Partnerka mojego brata');
      expect(name(dziecko), 'Moje dziecko');
      // The mother's parent without a sex: no "dziadek" or "babcia" — one step at a time (ISSUE-025 D2).
      expect(name(rodzicMamy), 'Rodzic mojej mamy');
      expect(name(dziadekMamy), 'Mój dziadek');
    });

    test('"ja" themselves has no name', () {
      expect(kinshipName(const [], (id) => sex[id]), isNull);
    });
  });
}
