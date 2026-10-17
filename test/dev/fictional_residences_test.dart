import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/cemeteries.dart' show GeoPoint;
import 'package:grobing/data/database.dart';
import 'package:grobing/data/photos.dart' show ProfilePhoto, profilePhotos;
import 'package:grobing/data/residences.dart';
import 'package:grobing/dev/fictional_family.dart';
import 'package:grobing/dev/fictional_residences.dart';

// ISSUE-045 — the made-up residences of the debug and profile builds (lib/dev/fictional_residences.dart): 30 people of the
// made-up family get them; a second press gives the same, not twice; what was entered by hand on a made-up person stays.
// Towns only from the invented stems (family-data.md, retro 3 R7).

const List<String> _stems = ['Wymyśl', 'Zmyśl', 'Testow', 'Przykład'];

void main() {
  late GrobingDatabase db;

  setUp(() => db = GrobingDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('without the made-up family nothing is added', () async {
    expect(await addFictionalResidences(db), 0);
    expect(await allResidences(db), isEmpty);
  });

  test(
    '30 people get residences — towns from the invented stems, countries alone, "ok.", stays without years; a second '
    'press gives the same rows, and a residence entered by hand stays',
    () async {
      await addFictionalFamily(db);
      expect(await addFictionalResidences(db), 30);
      final Map<int, List<Residence>> first = await allResidences(db);
      expect(first, hasLength(30));
      final List<Residence> all = [for (final l in first.values) ...l];
      for (final Residence r in all.where((r) => !r.place.isCountry)) {
        expect(
          _stems.any((s) => r.place.name.startsWith(s)),
          isTrue,
          reason: r.place.name,
        );
      }
      expect(all.where((r) => r.place.isCountry), isNotEmpty);
      expect(all.where((r) => r.from == null && r.to == null), hasLength(2));
      expect(
        all.where((r) => r.from?.qualifier == DateQualifier.about),
        isNotEmpty,
      );

      // A residence entered by hand on a made-up person, then the button again.
      final int person = first.keys.first;
      const ResidencePlace hand = ResidencePlace.locality(
        name: 'Przykładówek',
        countryCode: 'PL',
        countryName: 'Polska',
        point: GeoPoint(52, 21),
        geonamesId: 123,
      );
      await writeResidences(db, person, [
        ...first[person]!,
        const Residence(place: hand),
      ]);
      expect(await addFictionalResidences(db), 30);
      final Map<int, List<Residence>> again = await allResidences(db);
      expect(
        [for (final l in again.values) ...l].length,
        all.length + 1,
        reason: 'the same rows, not twice, and the hand-entered one',
      );
      expect(again[person]!.where((r) => r.place == hand), hasLength(1));
    },
  );

  test(
    'portraits (D26): seven of the made-up family, "ja" among them, get a drawn portrait as their profile photo — the '
    'file under media/, nothing twice, and a person who has a photo keeps it',
    () async {
      final Directory tmp = Directory.systemTemp.createTempSync('portraits');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final Directory media = Directory('${tmp.path}/media');
      expect(await addFictionalPortraits(db, media), 0, reason: 'no family');

      await addFictionalFamily(db);
      final List<int> people = [
        for (final p in await db.select(db.persons).get()) p.id,
      ];
      expect(await addFictionalPortraits(db, media), 7);
      final Map<int, ProfilePhoto> profiles = await profilePhotos(db, people);
      expect(profiles, hasLength(7));
      final int me = (await db.select(db.settings).getSingle()).mePersonId!;
      expect(profiles.containsKey(me), isTrue, reason: '"ja" has a portrait');
      for (final ProfilePhoto p in profiles.values) {
        expect(
          File('${media.path}/${p.relativePath}').existsSync(),
          isTrue,
          reason: p.relativePath,
        );
      }

      expect(await addFictionalPortraits(db, media), 0, reason: 'not twice');
      expect(await db.select(db.personMedia).get(), hasLength(7));
    },
  );
}
