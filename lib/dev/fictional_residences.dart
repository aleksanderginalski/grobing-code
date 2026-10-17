import 'dart:io';

import 'package:drift/drift.dart';

import '../data/cemeteries.dart' show GeoPoint;
import '../data/database.dart';
import '../data/graves.dart' show PartialDate, QualifiedDate;
import '../data/residences.dart';
import 'fictional_photo.dart';

// **Made-up** residences for the made-up family of fictional_family.dart (ISSUE-045; 05_DESIGN/mapa-migracji.md): the
// migration map needs people who moved — after 1945 from the east to the west and the north, abroad to a country
// alone or to a town, back again, "ok." dates, an empty "Do", a stay without years. The towns are invented, from the
// invented stems (family-data.md, retro 3 R7), set at example points; the countries stand at Natural Earth's label
// points, as the list of places gives them. Debug and profile only, as the family (ISSUE-033 D6).

/// A locality of this file: an invented name in a real country, at an example point. The ids are past every
/// GeoNames id (about 13 million), so they never meet a place of the list.
ResidencePlace _town(
  int id,
  String name,
  String unit,
  String code,
  String country,
  double lat,
  double lon,
) => ResidencePlace.locality(
  name: name,
  unit: unit,
  countryCode: code,
  countryName: country,
  point: GeoPoint(lat, lon),
  geonamesId: 990000000 + id,
);

final ResidencePlace _zmyslin = _town(
  1,
  'Zmyślin',
  'obw. przykładowy',
  'UA',
  'Ukraina',
  49.55,
  25.59,
);
final ResidencePlace _testowice = _town(
  2,
  'Testowice',
  'woj. testowe',
  'PL',
  'Polska',
  51.25,
  22.57,
);
final ResidencePlace _wymyslowo = _town(
  3,
  'Wymyślowo',
  'woj. przykładowe',
  'PL',
  'Polska',
  51.05,
  16.58,
);
final ResidencePlace _testowo = _town(
  4,
  'Testowo',
  'woj. wymyślone',
  'PL',
  'Polska',
  54.35,
  18.60,
);
final ResidencePlace _zmyslice = _town(
  5,
  'Zmyślice',
  'woj. zmyślone',
  'PL',
  'Polska',
  50.06,
  19.94,
);
final ResidencePlace _przykladowo = _town(
  6,
  'Przykładowo',
  'stan przykładowy',
  'US',
  'Stany Zjednoczone',
  41.88,
  -87.63,
);

/// A country alone, at Natural Earth's label point (tool/map/extract_world.dart).
ResidencePlace _country(String code, String name, double lat, double lon) =>
    ResidencePlace.country(
      countryCode: code,
      countryName: name,
      point: GeoPoint(lat, lon),
    );

final ResidencePlace _france = _country('FR', 'Francja', 46.696, 2.552);
final ResidencePlace _lithuania = _country('LT', 'Litwa', 55.104, 24.09);
final ResidencePlace _germany = _country('DE', 'Niemcy', 50.962, 9.678);
final ResidencePlace _britain = _country(
  'GB',
  'Wielka Brytania',
  54.403,
  -2.116,
);
final ResidencePlace _usa = _country(
  'US',
  'Stany Zjednoczone',
  39.538,
  -97.483,
);

/// Before 1945 the town was in Poland: the name of the time (N2).
const String _then = 'Zmyślin, Polska';

QualifiedDate _y(int year) =>
    QualifiedDate(DateQualifier.exact, PartialDate(year));
QualifiedDate _ok(int year) =>
    QualifiedDate(DateQualifier.about, PartialDate(year));

Residence _r(
  QualifiedDate? from,
  QualifiedDate? to,
  ResidencePlace place, {
  String? then,
}) => Residence(from: from, to: to, place: place, nameThen: then);

/// "given surname born" → the person's residences; born — the year of the birth as written ("ok. 1870" → 1870,
/// "przed 1900" → 1900, "po 1905" → 1905).
Map<String, List<Residence>> _residences() => {
  'Antoni Wymyślony 1868': [
    _r(null, _y(1920), _zmyslin, then: _then),
    _r(_y(1920), null, _testowice),
  ],
  'Marianna Wymyślona 1870': [
    _r(null, _y(1920), _zmyslin, then: _then),
    _r(_y(1920), null, _testowice),
  ],
  'Franciszek Wymyślony 1895': [
    _r(null, _ok(1914), _zmyslin, then: _then),
    _r(_ok(1914), _y(1921), _france),
    _r(_y(1921), _y(1945), _testowice),
    _r(_y(1946), null, _wymyslowo),
  ],
  'Wiktoria Zmyślicka 1898': [
    _r(null, _y(1920), _zmyslin, then: _then),
    _r(_y(1920), _y(1945), _testowice),
    _r(_y(1946), null, _wymyslowo),
  ],
  'Józef Wymyślony 1925': [
    _r(null, _y(1945), _testowice),
    _r(_y(1946), _y(1952), _wymyslowo),
    _r(_y(1952), null, _testowo),
  ],
  'Leon Wymyślony 1927': [_r(_y(1927), null, _testowice)],
  'Stefania Testowiak 1930': [
    _r(null, _y(1945), _testowice),
    _r(_y(1946), null, _wymyslowo),
    _r(_y(1970), null, _zmyslice),
  ],
  'Zofia Wymyślona 1928': [
    _r(null, _ok(1945), _lithuania),
    _r(_ok(1946), null, _testowo),
  ],
  'Stanisław Wymyślony 1951': [
    _r(_y(1951), null, _testowo),
    _r(_y(1975), _y(1990), _germany),
    _r(_y(1990), null, _testowo),
  ],
  'Marek Wymyślony 1955': [_r(_y(1955), null, _testowo)],
  'Jan Wymyślony 1947': [
    _r(_y(1947), null, _testowo),
    _r(_y(1972), null, _przykladowo),
  ],
  'Ewa Wymyślona 1958': [_r(_y(1958), null, _testowo)],
  'Mateusz Wymyślony 1983': [
    _r(null, _y(2002), _testowo),
    _r(_y(2002), _y(2008), _zmyslice),
    _r(_y(2008), _y(2012), _britain),
    _r(_y(2012), null, _zmyslice),
  ],
  'Michał Wymyślony 1987': [
    _r(_y(1987), null, _testowo),
    _r(_y(2011), null, _germany),
  ],
  'Kasia Wymyślona 1985': [_r(_y(1985), null, _zmyslice)],
  'Zofia Wymyślona 2012': [_r(_y(2012), null, _zmyslice)],
  'Ignacy Wymyślony 2015': [_r(_y(2015), null, _zmyslice)],
  'Kazimierz Przykładek 1900': [
    _r(null, _ok(1945), _lithuania),
    _r(_ok(1946), null, _testowo),
  ],
  'Bronisława Przykładek 1902': [
    _r(null, _ok(1945), _lithuania),
    _r(_ok(1946), null, _testowo),
  ],
  'Władysław Zmyślony 1900': [_r(_y(1900), null, _testowice)],
  'Czesław Zmyślony 1928': [
    _r(null, _y(1950), _testowice),
    _r(_y(1950), null, _testowo),
  ],
  'Henryk Zmyślony 1930': [
    _r(null, _y(1950), _testowice),
    _r(_y(1950), null, _testowo),
  ],
  'Krystyna Zmyślona 1934': [
    _r(null, _y(1952), _wymyslowo),
    _r(_y(1952), null, _testowo),
  ],
  // Without years: no place on the time axis (mapa-migracji.md D4) — seen only in the person's view.
  'Feliks Testowy 1905': [_r(null, null, _wymyslowo)],
  'Leokadia Testowa 1905': [_r(null, null, _wymyslowo)],
  'Piotr Przykładowy 1957': [_r(_y(1957), null, _zmyslice)],
  'Agnieszka Przykładowa 1960': [_r(_y(1960), null, _zmyslice)],
  'Edmund Przykładowy 1930': [
    _r(null, _y(1945), _zmyslin, then: _then),
    _r(_y(1946), null, _zmyslice),
  ],
  'Wanda Przykładowa 1934': [
    _r(null, _y(1945), _zmyslin, then: _then),
    _r(_y(1946), null, _zmyslice),
  ],
  // Alone, abroad for good.
  'Teofil Przykładowski 1910': [_r(_y(1930), null, _usa)],
};

/// A residence this file wrote: one of its towns, or one of its countries alone.
bool _madeUp(Residence r) =>
    (r.place.geonamesId ?? 0) >= 990000000 ||
    [_france, _lithuania, _germany, _britain, _usa].contains(r.place);

/// Gives the made-up family its residences — again on a second call, in place of this file's earlier ones; what was
/// entered by hand stays. The number of people who got them: none when the family is not there.
Future<int> addFictionalResidences(GrobingDatabase db) async {
  final Map<String, List<Residence>> wanted = _residences();
  // The family's people — the marker of fictional_family.dart — with their year of birth.
  final List<Person> people =
      await (db.select(db.persons)..where(
            (p) => p.bio.equals('Osoba wymyślona do drzewa (ISSUE-033).'),
          ))
          .get();
  if (people.isEmpty) return 0;
  final Map<int, int> born = {
    for (final Event e
        in await (db.select(db.events)..where(
              (e) =>
                  e.type.equalsValue(EventType.birth) &
                  e.personId.isIn(people.map((p) => p.id)),
            ))
            .get())
      if (e.personId != null && e.year != null) e.personId!: e.year!,
  };
  int added = 0;
  await db.transaction(() async {
    for (final Person p in people) {
      final List<Residence>? mine =
          wanted['${p.givenNames} ${p.surname} ${born[p.id]}'];
      if (mine == null) continue;
      // Again and again the same: this file's residences are replaced, those entered by hand stay.
      final List<Residence> kept = [
        for (final Residence r in await residencesOf(db, p.id))
          if (!_madeUp(r)) r,
      ];
      await writeResidences(db, p.id, [...kept, ...mine]);
      added++;
    }
  });
  return added;
}

/// The made-up people who get a made-up portrait as their profile photo (ISSUE-045, the author at stop #2: "avatary
/// zamiast inicjałów") — "ja" among them, so the map shows a photo there too; the others stay with their initials.
const List<String> _portrayed = [
  'Mateusz Wymyślony 1983',
  'Marek Wymyślony 1955',
  'Ewa Wymyślona 1958',
  'Józef Wymyślony 1925',
  'Zofia Wymyślona 1928',
  'Kazimierz Przykładek 1900',
  'Kasia Wymyślona 1985',
];

/// Gives [_portrayed] a portrait drawn in code (`fictionalPeoplePng` — a sepia ground, a head and shoulders; nobody is
/// meant, and no image file in the repo) as their profile photo, under [mediaDir]. Only to a person without any photo:
/// a second press, or a photo entered by hand, changes nothing. The number of people who got one.
Future<int> addFictionalPortraits(
  GrobingDatabase db,
  Directory mediaDir,
) async {
  final List<Person> people =
      await (db.select(db.persons)..where(
            (p) => p.bio.equals('Osoba wymyślona do drzewa (ISSUE-033).'),
          ))
          .get();
  final Map<int, int> born = {
    for (final Event e
        in await (db.select(db.events)..where(
              (e) =>
                  e.type.equalsValue(EventType.birth) &
                  e.personId.isIn(people.map((p) => p.id)),
            ))
            .get())
      if (e.personId != null && e.year != null) e.personId!: e.year!,
  };
  final Set<int> withPhoto = {
    for (final PersonMediaData l in await db.select(db.personMedia).get())
      l.personId,
  };
  int added = 0;
  for (final Person p in people) {
    final int index = _portrayed.indexOf(
      '${p.givenNames} ${p.surname} ${born[p.id]}',
    );
    if (index < 0 || withPhoto.contains(p.id)) continue;
    // The file before its row, as photos.dart keeps it (D3).
    final String path = 'wymyslone/portret-mapa-${p.id}.png';
    final File file = File('${mediaDir.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      fictionalPeoplePng(index * 3 + 1, heads: 1),
      flush: true,
    );
    await db.transaction(() async {
      final int media = await db
          .into(db.media)
          .insert(MediaCompanion.insert(relativePath: path));
      await db
          .into(db.personMedia)
          .insert(
            PersonMediaCompanion.insert(
              personId: p.id,
              mediaId: media,
              position: 0,
            ),
          );
    });
    added++;
  }
  return added;
}
