import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/address_text.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/sectors.dart';

// ISSUE-028 (ADR-016) — the author's sectors and the manager's address, happy path per AC: US-007 AC-4 a
// sector with a zone and one only in the addresses · What to build 3 renaming and removing · D3 the address
// of a grave (05_DESIGN/grob.md v6, 3b). Made-up cemeteries, people and geometry only (family-data.md).

const List<GeoPoint> _zone = [
  GeoPoint(51.4990, 19.4990),
  GeoPoint(51.4990, 19.5000),
  GeoPoint(51.5000, 19.5000),
  GeoPoint(51.5000, 19.4990),
];

void main() {
  late GrobingDatabase db;
  late int cemetery;

  setUp(() async {
    db = GrobingDatabase(NativeDatabase.memory());
    cemetery = await addCemetery(db, name: 'Cmentarz Wymyślony');
  });

  tearDown(() => db.close());

  Future<int> grave(String given) => addPersonToNewGrave(
    db,
    cemeteryId: cemetery,
    entry: PersonEntry(givenNames: given, surname: 'Wymyślony'),
  );

  Future<List<Sector>> sectors([int? of]) =>
      watchSectors(db, of ?? cemetery).first;

  group('the address as typed (address_text.dart)', () {
    test('a part loses its own word in front, inner spaces and blanks', () {
      expect(addressPart('  Kwatera  B ', sectorWord), 'B');
      expect(addressPart('kwatera: 12', sectorWord), '12');
      expect(addressPart('Rząd 4', rowWord), '4');
      expect(addressPart('RZĄD 4', rowWord), '4');
      expect(addressPart('Miejsce 12a', plotWord), '12a');
      expect(addressPart('Kwaterant', sectorWord), 'Kwaterant');
      expect(addressPart('Kwatera', sectorWord), isNull);
      expect(addressPart('   ', rowWord), isNull);
      expect(addressPart(null, plotWord), isNull);
    });

    test(
      '"b", "B" and "Kwatera B" are one sector; Polish letters do not count',
      () {
        expect(sectorKey('b'), sectorKey('B'));
        expect(sectorKey('Kwatera B'), sectorKey('b'));
        expect(sectorKey('Św. Józefa'), sectorKey('sw. jozefa'));
        expect(sectorKey('B1'), isNot(sectorKey('B')));
      },
    );
  });

  test(
    'US-007 AC-4 — a sector with its zone and one only in an address: both listed, with and without a '
    'zone, each with its graves',
    () async {
      final int a = await addSector(db, cemetery, name: 'A', zone: _zone);
      final int g = await grave('Jan');
      await setGraveDetails(db, g, sector: 'B', row: '4', plot: '12');

      final List<Sector> all = await sectors();
      expect(all.map((s) => (s.name, s.zone?.length, s.graveCount)), [
        ('A', 4, 0),
        ('B', null, 1),
      ]);
      expect(all.first.id, a);
      expect(all.first.zone, _zone);
    },
  );

  test(
    'element 19 — a name another sector of the cemetery has is refused with that sector\'s name; another '
    'cemetery may have it; "Kwatera B" is stored as "B"',
    () async {
      await addSector(db, cemetery, name: 'Kwatera B', zone: _zone);
      expect((await sectors()).single.name, 'B');
      await expectLater(
        addSector(db, cemetery, name: 'b', zone: _zone),
        throwsA(isA<SectorNameTaken>().having((e) => e.name, 'name', 'B')),
      );
      final int other = await addCemetery(db, name: 'Cmentarz Zmyślony');
      await addSector(db, other, name: 'B', zone: _zone);
      expect((await sectors(other)).single.name, 'B');
      await expectLater(
        addSector(db, cemetery, name: '  ', zone: _zone),
        throwsArgumentError,
      );
      await expectLater(
        addSector(db, cemetery, name: 'C', zone: _zone.take(2).toList()),
        throwsArgumentError,
      );
    },
  );

  test(
    'What to build 3, ADR-016 — renaming a sector renames every address with it; a name taken by another '
    'sector is refused; the same sector in other letters is not',
    () async {
      final int b = await addSector(db, cemetery, name: 'B', zone: _zone);
      await addSector(db, cemetery, name: 'C', zone: _zone);
      for (final String given in ['Jan', 'Anna']) {
        await setGraveDetails(db, await grave(given), sector: 'B');
      }

      await renameSector(db, b, 'B1');
      final CemeteryGraves? shown = await loadCemeteryGraves(db, cemetery);
      expect(shown!.graves.map((g) => g.sector), ['B1', 'B1']);
      await expectLater(
        renameSector(db, b, 'c'),
        throwsA(isA<SectorNameTaken>().having((e) => e.name, 'name', 'C')),
      );
      await renameSector(db, b, 'b1');
      expect((await sectors()).first.name, 'b1');
    },
  );

  test(
    'What to build 3, D27 — "Usuń z planu" takes only the zone: a sector with graves stays in their '
    'addresses, one without graves goes',
    () async {
      final int kept = await addSector(db, cemetery, name: 'A', zone: _zone);
      final int gone = await addSector(db, cemetery, name: 'D', zone: _zone);
      final int g = await grave('Jan');
      await setGraveDetails(db, g, sector: 'A');

      await removeSectorZone(db, kept);
      await removeSectorZone(db, gone);
      expect((await sectors()).map((s) => (s.id, s.zone, s.graveCount)), [
        (kept, null, 1),
      ]);
      expect((await loadGrave(db, g))!.sector, 'A');
    },
  );

  test('"Narysuj strefę od nowa" replaces the zone', () async {
    final int a = await addSector(db, cemetery, name: 'A', zone: _zone);
    const List<GeoPoint> again = [
      GeoPoint(51.4980, 19.4980),
      GeoPoint(51.4980, 19.4985),
      GeoPoint(51.4985, 19.4985),
    ];
    await setSectorZone(db, a, again);
    expect((await sectors()).single.zone, again);
  });

  test(
    'D3, grob.md 3b — the address of a grave: "b" finds "B"; a new name is a new sector without a zone; a '
    'sector the grave leaves goes when nothing keeps it; the words in front go; blanks are none',
    () async {
      await addSector(db, cemetery, name: 'B', zone: _zone);
      final int g = await grave('Jan');

      await setGraveDetails(
        db,
        g,
        name: '  Grób rodzinny Wymyślonych ',
        sector: 'b',
        row: 'Rząd 4',
        plot: 'Miejsce 12',
      );
      GraveDetail detail = (await loadGrave(db, g))!;
      expect(
        (detail.name, detail.sector, detail.row, detail.plot),
        ('Grób rodzinny Wymyślonych', 'B', '4', '12'),
      );
      expect((await sectors()).length, 1);

      await setGraveDetails(db, g, sector: 'D', row: '4', plot: '12');
      expect(
        (await sectors()).map((s) => (s.name, s.zone == null, s.graveCount)),
        [('B', false, 0), ('D', true, 1)],
      );

      await setGraveDetails(db, g, sector: 'B');
      // "D" had no zone and no other grave: it is nowhere to be seen, so it went. "B" has its zone.
      expect((await sectors()).map((s) => s.name), ['B']);

      await setGraveDetails(db, g, name: ' ', sector: '', row: ' ', plot: '');
      detail = (await loadGrave(db, g))!;
      expect(
        (detail.name, detail.sector, detail.row, detail.plot),
        (null, null, null, null),
      );
      expect((await sectors()).single.graveCount, 0);
    },
  );
}
