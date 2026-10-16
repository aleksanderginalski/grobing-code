import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/residences.dart';

// ISSUE-042 — places of residence in the data (lib/data/residences.dart): AC-1 a country with "około" years,
// AC-2 one residence made more exact (locality, then address) stays one row, D5 written in the person's
// transaction — a failed "Zapisz" leaves none, D4 the order of the years, D6 the places chosen lately, D3 a
// period's dates exact or about and the end not before the start. Made-up people and places only
// (family-data.md).

const ResidencePlace _country = ResidencePlace.country(
  countryCode: 'XA',
  countryName: 'Kraj Wymyślony',
  point: GeoPoint(49.5, 31.5),
);

ResidencePlace _locality(int id, String name) => ResidencePlace.locality(
  name: name,
  unit: 'woj. testowe',
  countryCode: 'XB',
  countryName: 'Kraj Przykładowy',
  point: GeoPoint(51 + id / 100, 22 + id / 100),
  geonamesId: id,
);

QualifiedDate _about(int year) =>
    QualifiedDate(DateQualifier.about, PartialDate(year));
QualifiedDate _exact(int year, [int? month, int? day]) =>
    QualifiedDate(DateQualifier.exact, PartialDate(year, month, day));

void main() {
  late GrobingDatabase db;
  late int grave;
  late int jan;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    final int cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
    grave = await addPersonToNewGrave(
      db,
      cemeteryId: cemetery,
      entry: const PersonEntry(givenNames: 'Anna', surname: 'Testowa'),
    );
    jan = await addPersonToGrave(
      db,
      graveId: grave,
      entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
    );
  });

  tearDown(() => db.close());

  Future<List<ResidenceRow>> rows() => (db.select(
    db.residences,
  )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();

  test(
    'AC-1 — only a country and "ok. 1930 – ok. 1945": one row at the level "country", the country\'s point, '
    'both years about, no GeoNames id and no address',
    () async {
      await writeResidences(db, jan, [
        Residence(from: _about(1930), to: _about(1945), place: _country),
      ]);

      final List<ResidenceRow> stored = await rows();
      expect(stored, hasLength(1));
      final ResidenceRow r = stored.single;
      expect(
        (
          r.personId,
          r.level,
          r.placeName,
          r.countryCode,
          r.countryName,
          r.lat,
          r.lon,
          r.geonamesId,
          r.address,
        ),
        (
          jan,
          PlaceLevel.country,
          'Kraj Wymyślony',
          'XA',
          'Kraj Wymyślony',
          49.5,
          31.5,
          null,
          null,
        ),
      );
      expect(
        (r.fromQualifier, r.fromYear, r.toQualifier, r.toYear),
        (DateQualifier.about, 1930, DateQualifier.about, 1945),
      );
      final Residence back = (await residencesOf(db, jan)).single;
      expect(
        (back.from, back.to, back.level),
        (_about(1930), _about(1945), PlaceLevel.country),
      );
    },
  );

  test(
    'AC-2 — the same residence made more exact, a locality and then an address: still one row (its id kept), '
    'the level and the point follow',
    () async {
      await writeResidences(db, jan, [
        Residence(from: _about(1930), to: _about(1945), place: _country),
      ]);
      final Residence first = (await residencesOf(db, jan)).single;

      await writeResidences(db, jan, [
        Residence(
          id: first.id,
          from: first.from,
          to: first.to,
          place: _locality(7, 'Zmyślin'),
        ),
      ]);
      final Residence second = (await residencesOf(db, jan)).single;
      expect(
        (second.id, second.level, second.place.point),
        (first.id, PlaceLevel.locality, const GeoPoint(51.07, 22.07)),
      );

      await writeResidences(db, jan, [
        Residence(
          id: second.id,
          from: second.from,
          to: second.to,
          place: second.place,
          address: 'ul. Przykładowa 3',
        ),
      ]);
      final List<ResidenceRow> stored = await rows();
      expect(stored, hasLength(1));
      expect(
        (
          stored.single.id,
          stored.single.level,
          stored.single.geonamesId,
          stored.single.lat,
          stored.single.address,
        ),
        (first.id, PlaceLevel.address, 7, 51.07, 'ul. Przykładowa 3'),
      );
    },
  );

  test(
    'D5 — written in the person\'s transaction: a write that fails after the residences leaves neither the '
    'person nor the residences',
    () async {
      final int peopleBefore = (await db.select(db.persons).get()).length;

      await expectLater(
        addPersonToGrave(
          db,
          graveId: grave,
          entry: const PersonEntry(givenNames: 'Ewa', surname: 'Zmyślona'),
          alsoWrite: (person) async {
            await writeResidences(db, person, [
              Residence(place: _locality(3, 'Wymyślowo')),
            ]);
            throw StateError('the photos failed');
          },
        ),
        throwsStateError,
      );

      expect(await db.select(db.persons).get(), hasLength(peopleBefore));
      expect(await rows(), isEmpty);
    },
  );

  test(
    'D5 — the form\'s list becomes the stored one: a residence left out goes, a changed one is updated, an '
    'unchanged one keeps its row, a new one is added; another person\'s rows stay',
    () async {
      await writeResidences(db, jan, [
        Residence(from: _exact(1920), place: _locality(1, 'Wymyślowo')),
        Residence(from: _exact(1930), place: _locality(2, 'Zmyślin')),
        Residence(from: _exact(1940), place: _country),
      ]);
      final int anna = jan - 1;
      await writeResidences(db, anna, [
        Residence(place: _locality(9, 'Przykładów')),
      ]);
      final List<Residence> stored = await residencesOf(db, jan);

      await writeResidences(db, jan, [
        stored[0],
        Residence(id: stored[2].id, from: _exact(1941), place: stored[2].place),
        Residence(from: _exact(1950), place: _locality(4, 'Testowo')),
      ]);

      final List<Residence> after = await residencesOf(db, jan);
      expect(after.map((r) => (r.from?.from.year, r.place.name)), [
        (1920, 'Wymyślowo'),
        (1941, 'Kraj Wymyślony'),
        (1950, 'Testowo'),
      ]);
      expect(after[0].id, stored[0].id);
      expect(after[1].id, stored[2].id);
      expect(stored.map((r) => r.id), isNot(contains(after[2].id)));
      expect(await residencesOf(db, anna), hasLength(1));
    },
  );

  test(
    'D4 — in the order of the years: by the start, without one by the end, without either at the end in the '
    'order entered; the same years as entered',
    () {
      final List<Residence> entered = [
        Residence(place: _locality(1, 'Bez lat 1')),
        Residence(from: _exact(1946), place: _locality(2, 'Od 1946')),
        Residence(to: _about(1925), place: _locality(3, 'Do ok. 1925')),
        Residence(place: _locality(4, 'Bez lat 2')),
        Residence(
          from: _exact(1930, 5),
          to: _exact(1945),
          place: _locality(5, 'Od 05.1930'),
        ),
        Residence(from: _exact(1930), place: _locality(6, 'Od 1930')),
        Residence(from: _exact(1946), place: _locality(7, 'Też od 1946')),
      ];

      expect(inStayOrder(entered).map((r) => r.place.name), [
        'Do ok. 1925',
        'Od 1930',
        'Od 05.1930',
        'Od 1946',
        'Też od 1946',
        'Bez lat 1',
        'Bez lat 2',
      ]);
    },
  );

  test(
    'D6 — "Ostatnio wybrane": up to 5 different places of the residences written, the newest first; one '
    'place written twice is one',
    () async {
      await writeResidences(db, jan, [
        for (int i = 1; i <= 4; i++)
          Residence(place: _locality(i, 'Miejsce $i')),
        Residence(place: _locality(2, 'Miejsce 2')),
        const Residence(place: _country),
        Residence(place: _locality(5, 'Miejsce 5')),
      ]);

      final List<ResidencePlace> recent = await recentPlaces(db);
      expect(recent.map((p) => p.name), [
        'Miejsce 5',
        'Kraj Wymyślony',
        'Miejsce 2',
        'Miejsce 4',
        'Miejsce 3',
      ]);
      expect(await recentPlaces(db, limit: 2), hasLength(2));
    },
  );

  test(
    'D3 — refused: a date other than exact or about, an end before the start, an address without a locality; '
    'nothing written. The same year at both ends is fine',
    () async {
      for (final Residence wrong in [
        const Residence(
          from: QualifiedDate(DateQualifier.before, PartialDate(1930)),
          place: _country,
        ),
        const Residence(
          from: QualifiedDate(
            DateQualifier.between,
            PartialDate(1930),
            PartialDate(1932),
          ),
          place: _country,
        ),
        Residence(from: _exact(1950), to: _exact(1940), place: _country),
        Residence(from: _exact(1945, 6), to: _exact(1945, 5), place: _country),
        const Residence(place: _country, address: 'ul. Przykładowa 3'),
      ]) {
        await expectLater(
          writeResidences(db, jan, [wrong]),
          throwsArgumentError,
        );
      }
      expect(await rows(), isEmpty);

      await writeResidences(db, jan, [
        Residence(from: _exact(1945), to: _exact(1945), place: _country),
        Residence(from: _exact(1945, 5), to: _exact(1945), place: _country),
      ]);
      expect(await rows(), hasLength(2));
    },
  );

  test('notBefore — a month or a day decides only when both have it', () {
    expect(notBefore(const PartialDate(1945), const PartialDate(1945)), isTrue);
    expect(
      notBefore(const PartialDate(1945, 6), const PartialDate(1945)),
      isTrue,
    );
    expect(
      notBefore(const PartialDate(1945, 6), const PartialDate(1945, 5)),
      isFalse,
    );
    expect(
      notBefore(const PartialDate(1945, 6, 10), const PartialDate(1945, 6, 9)),
      isFalse,
    );
    expect(
      notBefore(const PartialDate(1945, 6, 10), const PartialDate(1945, 6)),
      isTrue,
    );
    expect(
      notBefore(const PartialDate(1946), const PartialDate(1945)),
      isFalse,
    );
  });

  test(
    'v1.2 D12 — a residence without an end ends where the next later start begins, with its qualifier; a typed '
    'end wins; the last, the same start and one without a start get none; nothing is written',
    () async {
      final List<Residence> entered = [
        Residence(from: _exact(2024), place: _country),
        Residence(from: _exact(2026), place: _locality(1, 'Zmyślin')),
      ];
      expect(impliedEnds(inStayOrder(entered)), [_exact(2026), null]);

      final List<Residence> mixed = inStayOrder([
        Residence(to: _about(1920), place: _locality(1, 'Tylko do')),
        Residence(from: _exact(1925), place: _locality(2, 'Od 1925')),
        Residence(
          from: _exact(1930),
          to: _exact(1933),
          place: _locality(3, 'Wpisany koniec'),
        ),
        Residence(from: _about(1935), place: _locality(4, 'Od ok. 1935')),
        Residence(from: _exact(1935), place: _locality(5, 'Też od 1935')),
        Residence(from: _exact(1950, 3), place: _locality(6, 'Od 03.1950')),
        Residence(place: _locality(7, 'Bez lat')),
      ]);
      expect(mixed.map((r) => r.place.name), [
        'Tylko do',
        'Od 1925',
        'Wpisany koniec',
        'Od ok. 1935',
        'Też od 1935',
        'Od 03.1950',
        'Bez lat',
      ]);
      expect(impliedEnds(mixed), [
        null, // no start: it ends no one and takes no end
        _exact(1930), // the next later start
        null, // a typed end wins
        _exact(1950, 3), // the same start (1935) is not later — the next one is
        _exact(1950, 3),
        null, // the last with a start
        null, // no years
      ]);

      await writeResidences(db, jan, entered);
      expect((await rows()).map((r) => (r.fromYear, r.toYear)), [
        (2024, null),
        (2026, null),
      ]); // worked out when read, never written
    },
  );
}
