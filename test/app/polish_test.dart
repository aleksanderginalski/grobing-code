import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/polish.dart';

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
}
