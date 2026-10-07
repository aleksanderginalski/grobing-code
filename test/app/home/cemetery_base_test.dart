import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/external_link.dart';
import 'package:grobing/app/home/cemetery_base.dart';
import 'package:grobing/data/cemeteries.dart';

// ISSUE-015 — the bundled database of cemeteries (05_DESIGN/cmentarze.md, elements 12 and 14):
// AC-1 found offline by name, other name or locality, without Polish letters or endings · AC-2 every
// result has its locality and voivodeship; one name in two voivodeships is two distinguishable results
// · AC-5 the extract carries its ODbL licence and its origin · D7 "Dodany" · D8 order and limit.
// Real-asset tests use public cemeteries only (Powązki, Rakowicki); the rest are made up.

final String _assetJson = File(CemeteryBase.asset).readAsStringSync();
final CemeteryBase _real = CemeteryBase.fromJson(_assetJson);

BaseCemetery _made(
  String name, {
  String locality = 'Wymyślin',
  String voivodeship = 'mazowieckie',
  double lat = 52.0,
  double lon = 20.0,
  List<String> otherNames = const [],
}) => BaseCemetery(
  name: name,
  otherNames: otherNames,
  point: GeoPoint(lat, lon),
  locality: locality,
  voivodeship: voivodeship,
);

void main() {
  group('the real extract', () {
    test(
      'AC-5: the file says its licence (ODbL, OSM attribution) and its origin',
      () {
        final Map<String, Object?> json =
            jsonDecode(_assetJson) as Map<String, Object?>;
        expect(json['license'], contains('ODbL'));
        expect(json['license'], contains('© autorzy OpenStreetMap'));
        expect(json['source'], contains('OpenStreetMap'));
        expect(
          json['source'],
          contains('tool/cemeteries/extract_cemeteries.dart'),
        );
        expect(json['osmBase'], isA<String>());
        expect(json['voivodeships'], hasLength(16));
        expect(_real.cemeteries.length, greaterThan(15000));
      },
    );

    test(
      'it comes sorted the way the results show it — the app does not sort it (D5)',
      () {
        for (int i = 1; i < _real.cemeteries.length; i++) {
          expect(
            byShownName(_real.cemeteries[i - 1], _real.cemeteries[i]),
            lessThanOrEqualTo(0),
            reason: 'row $i',
          );
        }
        // The parsed order is the file's order.
        final List<Object?> rows =
            (jsonDecode(_assetJson) as Map<String, Object?>)['cemeteries']!
                as List<Object?>;
        expect(
          [for (final Object? r in rows.take(50)) (r! as List<Object?>)[0]],
          [for (final BaseCemetery c in _real.cemeteries.take(50)) c.name],
        );
      },
    );

    test(
      'AC-1: "powazki" finds the Powązki cemetery in Warsaw, without Polish letters or endings',
      () {
        final BaseResults r = _real.search('powazki');
        expect(
          r.shown.where(
            (c) =>
                c.name == 'Cmentarz Powązkowski' &&
                c.locality == 'Warszawa' &&
                c.voivodeship == 'mazowieckie',
          ),
          hasLength(1),
        );
      },
    );

    test('AC-1: by its other name — "stare powazki" (loc_name)', () {
      final BaseResults r = _real.search('stare powazki');
      expect(
        r.shown.map((c) => (c.name, c.locality)),
        contains(('Cmentarz Powązkowski', 'Warszawa')),
      );
      final BaseCemetery powazki = r.shown.firstWhere(
        (c) => c.name == 'Cmentarz Powązkowski',
      );
      expect(powazki.otherNames, contains('Stare Powązki'));
    });

    test('AC-1: by locality and name together — "krakow rakowicki"', () {
      final BaseResults r = _real.search('krakow rakowicki');
      expect(
        r.shown.map((c) => (c.name, c.locality, c.voivodeship)),
        contains(('Cmentarz Rakowicki', 'Kraków', 'małopolskie')),
      );
    });

    test('AC-1: by locality alone — "marczow"', () {
      expect(
        _real.search('marczow').shown.map((c) => (c.name, c.locality)),
        contains(('Cmentarz Powązkowski', 'Marczów')),
      );
    });

    test(
      'AC-2: one name in two voivodeships is two results told apart by the voivodeship',
      () {
        final List<BaseCemetery> powazkowski = _real
            .search('powazkowski')
            .shown
            .where((c) => c.name == 'Cmentarz Powązkowski')
            .toList();
        expect(powazkowski.length, greaterThanOrEqualTo(2));
        expect(
          powazkowski.map((c) => c.voivodeship).toSet().length,
          greaterThanOrEqualTo(2),
        );
        for (final BaseCemetery c in _real.cemeteries.take(2000)) {
          expect(c.locality, isNotEmpty);
          expect(c.voivodeship, isNotEmpty);
        }
      },
    );

    test('a city shows its district in brackets: "Warszawa (Żoliborz)"', () {
      final BaseCemetery powazki = _real
          .search('powazki')
          .shown
          .firstWhere(
            (c) => c.name == 'Cmentarz Powązkowski' && c.locality == 'Warszawa',
          );
      expect(powazki.place, 'Warszawa (Żoliborz)');
      expect(powazki.kind, 'rzymskokatolicki');
    });
  });

  group('search on made-up cemeteries', () {
    test('D8: name hits first, then locality hits, each alphabetical', () {
      final CemeteryBase base = CemeteryBase([
        _made('Cmentarz Parafialny'),
        _made('Cmentarz Wymyśliński', locality: 'Testowo'),
        _made('Cmentarz Ewangelicki'),
        _made('Cmentarz Leśny', locality: 'Próbna Wola'),
      ]);
      expect(base.search('wymyslin').shown.map((c) => c.name), [
        'Cmentarz Wymyśliński',
        'Cmentarz Ewangelicki',
        'Cmentarz Parafialny',
      ]);
    });

    test('D8: at most 30 shown, with the number of all hits', () {
      final CemeteryBase base = CemeteryBase([
        for (int i = 0; i < 35; i++) _made('Cmentarz Wymyślony $i'),
      ]);
      final BaseResults r = base.search('wymyslony');
      expect(r.shown, hasLength(30));
      expect(r.total, 35);
    });

    test(
      'an unnamed cemetery sorts as "Cmentarz bez nazwy" and is found by its locality',
      () {
        final CemeteryBase base = CemeteryBase([
          _made('Cmentarz Wymyślony'),
          _made('', locality: 'Wymyślin Mały'),
          _made('Cmentarz Ani Taki'),
        ]);
        expect(base.cemeteries.map(shownName), [
          'Cmentarz Ani Taki',
          'Cmentarz bez nazwy',
          'Cmentarz Wymyślony',
        ]);
        expect(base.search('wymyslin maly').shown.single.name, isEmpty);
      },
    );

    test('fewer than one stem finds nothing', () {
      expect(CemeteryBase([_made('Cmentarz Wymyślony')]).search('  ').total, 0);
    });
  });

  group('"Dodany" (D7)', () {
    CemeterySummary yours(int id, GeoPoint? point) => CemeterySummary(
      id: id,
      name: 'Cmentarz Wymyślony',
      point: point,
      graveCount: 0,
      personCount: 0,
    );

    test(
      'a saved cemetery closer than 100 m is this one; farther, or without a point, is not',
      () {
        final BaseCemetery base = _made('Cmentarz Wymyślony');
        // 0.0005° of latitude ≈ 56 m, 0.0015° ≈ 167 m.
        expect(addedAs(base, [yours(7, const GeoPoint(52.0005, 20.0))]), 7);
        expect(
          addedAs(base, [yours(7, const GeoPoint(52.0015, 20.0))]),
          isNull,
        );
        expect(addedAs(base, [yours(7, null)]), isNull);
      },
    );

    test('distanceMetres is right at the scale of a cemetery', () {
      expect(
        distanceMetres(
          const GeoPoint(52.0, 20.0),
          const GeoPoint(52.001, 20.0),
        ),
        closeTo(111.2, 0.5),
      );
    });
  });

  test(
    'D1: the satellite link is a Google Maps URL with the satellite basemap at the point',
    () {
      final String url = satelliteUrl(const GeoPoint(52.25472, 20.98389));
      expect(
        url,
        startsWith('https://www.google.com/maps/@?api=1&map_action=map'),
      );
      expect(url, contains('center=52.25472,20.98389'));
      expect(url, contains('basemap=satellite'));
      expect(url, contains('zoom=17'));
    },
  );
}
