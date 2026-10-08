import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/polish.dart';
import 'package:grobing/data/database.dart' show Sex;

// ISSUE-014: Polish text on the home screen — plural forms (style-b.md rule 6), matching without
// diacritics and endings (05_DESIGN/cmentarze.md D3, AC-3), the Polish alphabet (element 11).
void main() {
  test('plural forms: 1 grób · 2–4 groby (not 12–14) · 0 and 5+ grobów', () {
    expect(
      [0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 24, 25, 112, 122].map(gravesLabel),
      [
        '0 grobów',
        '1 grób',
        '2 groby',
        '4 groby',
        '5 grobów',
        '11 grobów',
        '12 grobów',
        '14 grobów',
        '21 grobów',
        '22 groby',
        '24 groby',
        '25 grobów',
        '112 grobów',
        '122 groby',
      ],
    );
    expect([1, 3, 6].map(peopleLabel), ['1 osoba', '3 osoby', '6 osób']);
    expect([1, 2, 5].map(cemeteriesLabel), [
      '1 cmentarz',
      '2 cmentarze',
      '5 cmentarzy',
    ]);
  });

  test('fold: lower case without Polish diacritics', () {
    expect(fold('Łódź'), 'lodz');
    expect(fold('ZAŻÓŁĆ GĘŚLĄ JAŹŃ'), 'zazolc gesla jazn');
  });

  test(
    'search: words of 5+ letters match without their last two (Polish endings)',
    () {
      expect(searchStems('Powązki krakow  lub'), ['powaz', 'krak', 'lub']);
      expect(
        matchesQuery('powazki', ['Cmentarz Wojskowy na Powązkach']),
        isTrue,
      );
      expect(matchesQuery('lodz', ['Cmentarz Wymyślony', 'Łódź']), isTrue);
      expect(
        matchesQuery('parafialny lodz', ['Cmentarz Parafialny', 'Łódź']),
        isTrue,
      );
      expect(
        matchesQuery('parafialny lodz', ['Cmentarz Parafialny', 'Lublin']),
        isFalse,
      );
      expect(matchesQuery('   ', ['Cmentarz']), isFalse);
    },
  );

  test('alphabetical order of the Polish alphabet', () {
    final List<String> names = [
      'Żabno',
      'Łódź',
      'Lublin',
      'Zamość',
      'Ćmielów',
      'Cieszyn',
      'cmentarz',
    ]..sort(polishCompare);
    expect(names, [
      'Cieszyn',
      'cmentarz',
      'Ćmielów',
      'Lublin',
      'Łódź',
      'Zamość',
      'Żabno',
    ]);
  });

  test(
    'capitalizeWords: what came from the search, as the name field writes it',
    () {
      expect(capitalizeWords('  cmentarz leśny '), 'Cmentarz Leśny');
      expect(capitalizeWords('łąka'), 'Łąka');
    },
  );

  // ISSUE-022 — the Osoby tab's search (05_DESIGN/osoby.md, element 2, AC-2).
  test(
    'matchesWordStart: from the start of a word, without Polish letters and case',
    () {
      final List<String?> anna = ['Anna', 'Wymyślona', 'Zmyślona'];
      expect(matchesWordStart('wymys', anna), isTrue);
      expect(matchesWordStart('WYMYŚ', anna), isTrue);
      expect(
        matchesWordStart('zmys', anna),
        isTrue,
        reason: 'the birth surname too',
      );
      expect(
        matchesWordStart('anna wym', anna),
        isTrue,
        reason: 'every word, any field',
      );
      expect(
        matchesWordStart('myslona', anna),
        isFalse,
        reason: 'not inside a word',
      );
      expect(matchesWordStart('anna x', anna), isFalse);
      expect(matchesWordStart('  ', anna), isFalse);
      expect(matchesWordStart('zmys', ['Ewa', 'Testowa-Zmyślonek']), isTrue);
      expect(matchesWordStart('zmys', ['Ewa', 'Przezmyślonek']), isFalse);
      expect(matchesWordStart('lod', ['Łódź']), isTrue);
      expect(matchesWordStart('test', [null, 'Testowski']), isTrue);
    },
  );

  test(
    'ISSUE-025 AC-1 — suggestSex: the first given name on "-a" is a woman, any other a man, the men on '
    '"-a" from the PESEL measurement are men; no given names, no suggestion',
    () {
      expect(suggestSex('Maria'), Sex.female);
      expect(suggestSex('Anna Zofia'), Sex.female);
      expect(suggestSex('Jan'), Sex.male);
      expect(
        suggestSex('Józef Maria'),
        Sex.male,
        reason: 'the first name counts',
      );
      expect(suggestSex('Kuba'), Sex.male);
      expect(suggestSex('Barnaba'), Sex.male);
      expect(suggestSex('  KUBA '), Sex.male);
      expect(suggestSex(''), isNull);
      expect(suggestSex(null), isNull);
    },
  );
}
