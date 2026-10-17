import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/migration_year.dart';
import 'package:grobing/app/tree/tree_time.dart';
import 'package:grobing/data/cemeteries.dart' show GeoPoint;
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/graves.dart' show PartialDate, QualifiedDate;
import 'package:grobing/data/residences.dart';

// ISSUE-045 — the migration map's time (lib/app/tree/migration_year.dart; 05_DESIGN/mapa-migracji.md v1.1): who lives
// where in a year of the tree's slider (element 4, D4 — each rule alone), the groups of a stack (D3), the pill (3, D7),
// the card's line (12, D8, D16), the first frame's points (10 — R4). Made-up people and
// places only, from the invented stems (family-data.md, retro 3 R7).

QualifiedDate _y(int year) =>
    QualifiedDate(DateQualifier.exact, PartialDate(year));
QualifiedDate _ok(int year) =>
    QualifiedDate(DateQualifier.about, PartialDate(year));

ResidencePlace _town(int id, String name, {String country = 'Polska'}) =>
    ResidencePlace.locality(
      name: name,
      unit: 'woj. testowe',
      countryCode: country == 'Polska' ? 'PL' : 'UA',
      countryName: country,
      point: GeoPoint(50 + id / 10, 20 + id / 10),
      geonamesId: 990000000 + id,
    );

const ResidencePlace _lithuania = ResidencePlace.country(
  countryCode: 'LT',
  countryName: 'Litwa',
  point: GeoPoint(55.104, 24.09),
);

final ResidencePlace _zmyslin = _town(1, 'Zmyślin', country: 'Ukraina');
final ResidencePlace _wymyslowo = _town(2, 'Wymyślowo');
final ResidencePlace _testowo = _town(3, 'Testowo');

TreePerson _person(
  int id, {
  QualifiedDate? born,
  QualifiedDate? died,
  bool dead = false,
}) => TreePerson(
  id: id,
  givenNames: 'Osoba$id',
  surname: 'Wymyślona',
  birth: born,
  death: died,
  dead: dead || died != null,
);

MigrationYear _map(
  List<TreePerson> people,
  Map<int, List<Residence>> residences,
) {
  final FamilyTreeData family = FamilyTreeData(
    people: {for (final TreePerson p in people) p.id: p},
    unions: const [],
  );
  return MigrationYear(
    time: TreeTime(family, now: 2026),
    residences: residences,
    people: family.people.keys,
  );
}

void main() {
  group('D4 — who lives where in a year', () {
    test(
      'a typed "Do" counts its own year: "do 1945" and "od 1946" leave no gap; the first year is the birth\'s',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _y(1925))],
          {
            1: [
              Residence(to: _y(1945), place: _zmyslin),
              Residence(from: _y(1946), place: _wymyslowo),
            ],
          },
        );
        expect(m.person(1, 1924).presence, MapPresence.notYet);
        // A stay with only "Do" begins at birth.
        expect(m.person(1, 1925).place, _zmyslin);
        expect(m.person(1, 1945).place, _zmyslin);
        expect(m.person(1, 1946).place, _wymyslowo);
        // The last stay, without an end, lasts while the person lives — to "dziś".
        expect(m.person(1, null).place, _wymyslowo);
      },
    );

    test(
      'an empty "Do" ends where the next start begins (zamieszkanie.md D12) — the same end as the person\'s view',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _y(1900))],
          {
            1: [
              Residence(from: _y(1920), place: _zmyslin),
              Residence(from: _y(1930), place: _testowo),
            ],
          },
        );
        expect(m.person(1, 1919).presence, MapPresence.nowhere);
        expect(m.person(1, 1929).place, _zmyslin);
        expect(m.person(1, 1930).place, _testowo);
      },
    );

    test(
      'of two stays in one year the later start wins — the move of that year ("1923–1929" and "od 1929")',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _y(1890))],
          {
            1: [
              Residence(from: _y(1923), to: _y(1929), place: _lithuania),
              Residence(from: _y(1929), place: _zmyslin),
            ],
          },
        );
        expect(m.person(1, 1928).place, _lithuania);
        expect(m.person(1, 1929).place, _zmyslin);
      },
    );

    test(
      'the last stay ends at death; from the death on the person is off the map (K2 — D16)',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _y(1900), died: _y(1958))],
          {
            1: [Residence(from: _y(1946), place: _wymyslowo)],
          },
        );
        expect(m.person(1, 1957).place, _wymyslowo);
        expect(m.person(1, 1958).presence, MapPresence.gone);
        expect(m.person(1, null).presence, MapPresence.gone);
      },
    );

    test(
      'a residence without years has no place on the time axis — never on the map, not in the first frame',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _y(1900))],
          {
            1: [const Residence(place: _lithuania)],
          },
        );
        expect(m.person(1, 1950).presence, MapPresence.nowhere);
        expect(m.hasPlaces, isFalse);
        expect(m.allPoints(), isEmpty);
      },
    );

    test(
      '"ok." as on the tree (N3): from 5 years before, with the dashed outline in the window',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _ok(1900))],
          {
            1: [Residence(to: _y(1950), place: _testowo)],
          },
        );
        expect(m.person(1, 1894).presence, MapPresence.notYet);
        final MapPersonYear early = m.person(1, 1895);
        expect(early.place, _testowo);
        expect(early.unsure, isTrue);
        expect(m.person(1, 1906).unsure, isFalse);
      },
    );

    test(
      'a stay that ended before "dziś" leaves the person without a place today',
      () {
        final MigrationYear m = _map(
          [_person(1, born: _y(1958))],
          {
            1: [Residence(from: _y(1958), to: _y(1986), place: _testowo)],
          },
        );
        expect(m.person(1, 1986).place, _testowo);
        expect(m.person(1, null).presence, MapPresence.nowhere);
      },
    );
  });

  test(
    'D3 — a place\'s stack: the person in the middle first, then by the year of birth; the pill counts the people '
    'with a place and those alive without one (element 3)',
    () {
      final MigrationYear m = _map(
        [
          _person(1, born: _y(1930)),
          _person(2, born: _y(1920)),
          _person(3, born: _y(1925)),
          _person(4, born: _y(1910)), // alive, no residence
          _person(5, born: _y(1990)), // not born in 1950
        ],
        {
          for (final int id in [1, 2, 3])
            id: [Residence(from: _y(1946), place: _testowo)],
        },
      );
      expect(m.groups(1950), {
        _testowo: [2, 3, 1],
      });
      expect(m.groups(1950, first: 1), {
        _testowo: [1, 2, 3],
      });
      expect(m.counts(1950), (here: 3, nowhere: 1));
      expect(m.counts(1940), (here: 0, nowhere: 4));
    },
  );

  test('the first frame: every residence with years (element 10)', () {
    final MigrationYear m = _map(
      [_person(1, born: _y(1900))],
      {
        1: [
          Residence(to: _y(1923), place: _zmyslin),
          Residence(from: _y(1923), to: _y(1929), place: _lithuania),
        ],
      },
    );
    expect(m.hasPlaces, isTrue);
    expect(m.allPoints(), [_zmyslin.point, _lithuania.point]);
  });

  group(
    'words (element 12, 3, 4) — the hard space after one-letter words and before "·" (style-b.md rule 6)',
    () {
      test('the card\'s line in each state; after death none (D16)', () {
        final Residence then = Residence(
          to: _y(1945),
          place: _zmyslin,
          nameThen: 'Zmyślin, Polska',
        );
        expect(
          mapWhereLine(MapPersonYear(MapPresence.here, residence: then), 1930),
          'W\u00A01930: Zmyślin, Polska ·\u00A0dziś\u00A0Ukraina',
        );
        expect(
          mapWhereLine(
            MapPersonYear(
              MapPresence.here,
              residence: Residence(from: _y(1923), place: _lithuania),
            ),
            1925,
          ),
          'W\u00A01925: Litwa ·\u00A0cały kraj',
        );
        expect(
          mapWhereLine(
            MapPersonYear(
              MapPresence.here,
              residence: Residence(from: _y(2012), place: _testowo),
            ),
            null,
          ),
          'Dziś: Testowo, Polska',
        );
        expect(
          mapWhereLine(const MapPersonYear(MapPresence.nowhere), 1950),
          'W\u00A01950: nie wiadomo, gdzie mieszka',
        );
        expect(
          mapWhereLine(const MapPersonYear(MapPresence.notYet), 1900),
          'W\u00A01900: przed narodzinami',
        );
        expect(
          mapWhereLine(const MapPersonYear(MapPresence.gone), 1990),
          isNull,
        );
      });

      test(
        'the pill: the plural, and "bez miejsca" only when there are some',
        () {
          expect(
            mapPill((here: 9, nowhere: 3), 1950),
            'W\u00A01950 na mapie: 9 osób ·\u00A03 bez miejsca',
          );
          expect(
            mapPill((here: 1, nowhere: 0), null),
            'Dziś na mapie: 1 osoba',
          );
          expect(
            mapPill((here: 2, nowhere: 0), null),
            'Dziś na mapie: 2 osoby',
          );
        },
      );

      test(
        'the label under a place: today\'s name; a country alone with "cały kraj" (O3)',
        () {
          expect(mapPlaceLabel(_zmyslin), 'Zmyślin');
          expect(mapPlaceLabel(_lithuania), 'Litwa ·\u00A0cały kraj');
        },
      );
    },
  );
}
