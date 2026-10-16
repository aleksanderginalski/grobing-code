import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart' show GeoPoint;
import 'package:grobing/data/places.dart';

import '../support/place_fakes.dart';

// ISSUE-042 — the list of places (lib/data/places.dart; 05_DESIGN/zamieszkanie.md D7, elements 19–21), on a
// made-up list in the tool's layout (test/support/place_fakes.dart), never the real asset: AC-3 the choice
// works from the list in the app — the words from the start, without case, Polish or other Latin letters;
// the name of the list shown, other names found; same names told apart by unit and country; the countries
// apart; a match at a name's start first. Made-up places only (family-data.md).

void main() {
  late Directory tmp;
  late PlaceList list;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grobing_places');
    list = PlaceList.openFile(
      writeFakePlaceList(tmp, countries: fakeCountries, places: fakePlaces),
    );
  });

  tearDown(() {
    list.close();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still open on Windows; the system cleans the temp directory.
    }
  });

  List<String> names(List<ListedPlace> places) => [
    for (final ListedPlace p in places) p.name,
  ];

  test(
    'element 19 — from the start of words, a name\'s start first, then the list\'s order; not inside a word',
    () {
      expect(names(list.search('zmys')), [
        'Zmyślin',
        'Zmyślin',
        'Nowe Zmyślino',
        'Testowo-Zmyślin',
      ]);
      expect(names(list.search('przez')), ['Przezmyślonek']);
      expect(names(list.search('nowe z')), ['Nowe Zmyślino']);
      expect(names(list.search('Testowo-Zm')), ['Testowo-Zmyślin']);
    },
  );

  test(
    'without case, Polish letters or those of other Latin alphabets: the same results as typed plainly',
    () {
      expect(names(list.search('ZMYŚ')), names(list.search('zmys')));
      expect(names(list.search('šimys')), ['Šimyslai']);
      expect(names(list.search('simys')), ['Šimyslai']);
      expect(placeKey('  Testowo-Zmyślin  '), 'testowo zmyslin');
    },
  );

  test(
    'the name of the list is shown, other names are found: a local or a historic one finds the place under '
    'its name',
    () {
      expect(names(list.search('vymy')), ['Wymyślowo']);
      final List<ListedPlace> historic = list.search('zmyslinow');
      expect(historic.map((p) => (p.name, p.geonamesId)), [
        ('Zmyślin', 9000001),
      ]);
    },
  );

  test(
    'same names told apart: the unit and the country in words, the point of the locality, its GeoNames id',
    () {
      final List<ListedPlace> both = list
          .search('zmyslin')
          .where((p) => p.name == 'Zmyślin')
          .toList();
      expect(
        both.map(
          (p) => (p.unit, p.countryCode, p.countryName, p.point, p.geonamesId),
        ),
        [
          (
            'woj. testowe',
            'XB',
            'Kraj Przykładowy',
            const GeoPoint(51.25, 22.5),
            9000001,
          ),
          (
            'obw. przykładowy',
            'XA',
            'Kraj Wymyślony',
            const GeoPoint(50, 20),
            9000002,
          ),
        ],
      );
    },
  );

  test(
    'one or two letters come from the kept first results — the same as the search of a range gives',
    () {
      expect(names(list.search('z')), [
        'Zmyślin',
        'Zmyślin',
        'Nowe Zmyślino',
        'Testowo-Zmyślin',
      ]);
      expect(names(list.search('zm')), names(list.search('zmy')));
      expect(list.search('z', limit: 2), hasLength(2));
      expect(names(list.search('w')), ['Wymyślowo']);
    },
  );

  test('element 21 — nothing found, and nothing for an empty text', () {
    expect(list.search('qqx'), isEmpty);
    expect(list.search('q'), isEmpty);
    expect(list.search(''), isEmpty);
    expect(list.search('  - '), isEmpty);
  });

  test(
    'element 20 (v1.1, D8) — the countries apart, in two groups: the name starting with the text, and a later '
    'word of it; each with its label point',
    () {
      List<String> names(List<ListedCountry> c) => [for (final x in c) x.name];
      final CountryMatches kraj = list.searchCountries('kraj');
      expect(names(kraj.atStart), ['Kraj Przykładowy', 'Kraj Wymyślony']);
      expect(kraj.inside, isEmpty);
      final CountryMatches wym = list.searchCountries('wym');
      expect(names(wym.atStart), ['Wymyślonia']);
      expect(names(wym.inside), ['Kraj Wymyślony']);
      for (final String nothing in ['xyz', '']) {
        final CountryMatches none = list.searchCountries(nothing);
        expect(none.atStart, isEmpty);
        expect(none.inside, isEmpty);
      }
      expect(
        (list.country('XA')?.name, list.country('XA')?.point),
        ('Kraj Wymyślony', const GeoPoint(49.5, 31.5)),
      );
      expect(list.countries, hasLength(3));
    },
  );
}
