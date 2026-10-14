import 'package:drift/drift.dart';

import '../data/claims.dart';
import '../data/database.dart';
import '../data/families.dart';
import '../data/graves.dart' show PartialDate, QualifiedDate;
import '../data/people.dart';

// A **made-up** family shaped like the real one, for the tree (ISSUE-033; SPIKE-002 D6 and → Rekomendacja):
// 106 people, 38 unions, 6 generations (born 1868–2019), 31 dead and 75 living, 39 without parents in the
// data, 3 people in two unions (a widower, a widow, a divorce), 2 pairs "razem" (one later married), the
// wife's family over 3 generations with her cousins. The same family as SPIKE-002's mockup and prototype,
// so the tree's numbers can be checked against them. Surnames only from the invented stems (family-data.md,
// retro 3 R7). Debug and profile only, never release (ISSUE-033 D6).
//
// Some dates as the notes will give them, for the time slider (ISSUE-037, drzewo.md D32): "ok.", "między",
// "przed", "po", none at all, a death without its date, three marriages without theirs. The same people and
// dates as ISSUE-037's mockup, whose windows the tests check.

/// One person: key, given name, surname, sex, born, died, born as.
typedef _Person = (String, String, String, Sex, int, int?, String?);

/// One union: partner, partner, together since, married in, children, ended in.
typedef _Union = (String, String, int?, int?, List<String>, int?);

const List<_Person> _people = [
  ('a1', 'Antoni', 'Wymyślony', Sex.male, 1868, 1931, null),
  ('a2', 'Marianna', 'Wymyślona', Sex.female, 1871, 1940, null),
  ('f1', 'Franciszek', 'Wymyślony', Sex.male, 1895, 1958, null),
  ('f2', 'Wiktoria', 'Zmyślicka', Sex.female, 1898, 1975, 'Wymyślona'),
  ('f3', 'Stanisław', 'Wymyślony', Sex.male, 1901, 1920, null),
  ('w1', 'Ignacy', 'Zmyślicki', Sex.male, 1893, 1960, null),
  ('w2', 'Kazimiera', 'Zmyślicka', Sex.female, 1925, 2010, null),
  ('j1', 'Jadwiga', 'Wymyślona', Sex.female, 1899, 1983, 'Zmyślak'),
  ('J', 'Józef', 'Wymyślony', Sex.male, 1925, 2004, null),
  ('L', 'Leon', 'Wymyślony', Sex.male, 1927, 1944, null),
  ('St', 'Stefania', 'Testowiak', Sex.female, 1930, 2015, 'Wymyślona'),
  ('bt', 'Bolesław', 'Testowiak', Sex.male, 1926, 1990, null),
  ('ry', 'Ryszard', 'Testowiak', Sex.male, 1953, null, null),
  ('el', 'Elżbieta', 'Testowiak', Sex.female, 1956, null, null),
  ('gr', 'Grażyna', 'Testowiak', Sex.female, 1955, null, null),
  ('se', 'Sebastian', 'Testowiak', Sex.male, 1980, null, null),
  ('mg1', 'Magdalena', 'Testowiak', Sex.female, 1983, null, null),
  ('he', 'Helena', 'Wymyślona', Sex.female, 1924, 1949, 'Przykładzka'),
  ('jn', 'Jan', 'Wymyślony', Sex.male, 1947, null, null),
  ('ir', 'Irena', 'Wymyślona', Sex.female, 1949, null, null),
  ('tm', 'Tomasz', 'Wymyślony', Sex.male, 1972, null, null),
  ('be', 'Beata', 'Wymyślona', Sex.female, 1975, null, null),
  ('mo', 'Monika', 'Wymyślona', Sex.female, 1974, null, null),
  ('ku', 'Jakub', 'Wymyślony', Sex.male, 2000, null, null),
  ('ol', 'Aleksandra', 'Wymyślona', Sex.female, 2003, null, null),
  ('zo', 'Zofia', 'Wymyślona', Sex.female, 1928, 2010, 'Przykładek'),
  ('sn', 'Stanisław', 'Wymyślony', Sex.male, 1951, null, null),
  ('mk', 'Marek', 'Wymyślony', Sex.male, 1955, null, null),
  ('ha', 'Halina', 'Testowska', Sex.female, 1958, null, 'Wymyślona'),
  ('da', 'Danuta', 'Wymyślona', Sex.female, 1953, null, null),
  ('pa', 'Paweł', 'Wymyślony', Sex.male, 1976, null, null),
  ('mt', 'Marta', 'Zmyślińska', Sex.female, 1979, null, 'Wymyślona'),
  ('kr', 'Krzysztof', 'Wymyślony', Sex.male, 1983, null, null),
  ('an', 'Anna', 'Wymyślona', Sex.female, 1978, null, null),
  ('zu', 'Zuzanna', 'Wymyślona', Sex.female, 2005, null, null),
  ('lu', 'Łukasz', 'Zmyśliński', Sex.male, 1977, null, null),
  ('at', 'Antoni', 'Zmyśliński', Sex.male, 2010, null, null),
  ('hn', 'Hanna', 'Zmyślińska', Sex.female, 2013, null, null),
  ('ew', 'Ewa', 'Wymyślona', Sex.female, 1958, null, 'Zmyślona'),
  ('JA', 'Mateusz', 'Wymyślony', Sex.male, 1983, null, null),
  ('mi', 'Michał', 'Wymyślony', Sex.male, 1987, null, null),
  ('nt', 'Natalia', 'Zmyślewicz', Sex.female, 1989, null, null),
  ('le2', 'Leon', 'Wymyślony', Sex.male, 2018, null, null),
  ('jo', 'Joanna', 'Testowicz', Sex.female, 1990, null, 'Wymyślona'),
  ('bk', 'Bartosz', 'Testowicz', Sex.male, 1988, null, null),
  ('my', 'Maja', 'Testowicz', Sex.female, 2016, null, null),
  ('fp', 'Filip', 'Testowicz', Sex.male, 2019, null, null),
  ('wo', 'Wojciech', 'Testowski', Sex.male, 1955, 2019, null),
  ('agt', 'Agata', 'Zmyślik', Sex.female, 1981, null, 'Testowska'),
  ('dr', 'Dariusz', 'Testowski', Sex.male, 1985, null, null),
  ('rf', 'Rafał', 'Zmyślik', Sex.male, 1979, null, null),
  ('ig', 'Igor', 'Zmyślik', Sex.male, 2009, null, null),
  ('kz', 'Kazimierz', 'Przykładek', Sex.male, 1897, 1966, null),
  ('br', 'Bronisława', 'Przykładek', Sex.female, 1902, 1988, null),
  ('ed', 'Edward', 'Przykładek', Sex.male, 1931, 2001, null),
  ('lc', 'Lucyna', 'Przykładek', Sex.female, 1934, 2012, null),
  ('je', 'Jerzy', 'Przykładek', Sex.male, 1958, null, null),
  // The mother's side.
  ('wl', 'Władysław', 'Zmyślony', Sex.male, 1900, 1944, null),
  ('ge', 'Genowefa', 'Wymyślewicz', Sex.female, 1904, 1979, null),
  ('td', 'Tadeusz', 'Wymyślewicz', Sex.male, 1898, 1970, null),
  ('zd', 'Zdzisław', 'Wymyślewicz', Sex.male, 1950, null, null),
  ('cz', 'Czesław', 'Zmyślony', Sex.male, 1928, 1990, null),
  ('te', 'Teodora', 'Zmyślona', Sex.female, 1931, 2005, null),
  ('rm', 'Roman', 'Zmyślony', Sex.male, 1955, null, null),
  ('iw', 'Iwona', 'Zmyślona', Sex.female, 1958, null, null),
  ('prz', 'Przemysław', 'Zmyślony', Sex.male, 1982, null, null),
  ('hk', 'Henryk', 'Zmyślony', Sex.male, 1930, 1995, null),
  ('kry', 'Krystyna', 'Zmyślona', Sex.female, 1934, null, 'Testowa'),
  ('adr', 'Andrzej', 'Zmyślony', Sex.male, 1960, null, null),
  ('bo', 'Bożena', 'Zmyślona', Sex.female, 1962, null, null),
  ('km', 'Kamil', 'Zmyślony', Sex.male, 1984, null, null),
  ('kg', 'Kinga', 'Zmyślona', Sex.female, 1988, null, null),
  ('pl', 'Paulina', 'Zmyślona', Sex.female, 1986, null, null),
  ('nk', 'Nikola', 'Zmyślona', Sex.female, 2012, null, null),
  ('re', 'Renata', 'Zmyślona', Sex.female, 1970, null, null),
  ('os', 'Oskar', 'Zmyślony', Sex.male, 2002, null, null),
  ('ter', 'Teresa', 'Przykładowicz', Sex.female, 1963, null, 'Zmyślona'),
  ('gz', 'Grzegorz', 'Przykładowicz', Sex.male, 1960, null, null),
  ('kl', 'Karolina', 'Wymyślik', Sex.female, 1988, null, 'Przykładowicz'),
  ('dw', 'Dawid', 'Przykładowicz', Sex.male, 1991, null, null),
  ('mc', 'Marcin', 'Wymyślik', Sex.male, 1986, null, null),
  ('ln', 'Lena', 'Wymyślik', Sex.female, 2017, null, null),
  ('fe', 'Feliks', 'Testowy', Sex.male, 1905, 1975, null),
  ('le', 'Leokadia', 'Testowa', Sex.female, 1908, 1999, null),
  ('bb', 'Barbara', 'Zmyśleńska', Sex.female, 1937, null, 'Testowa'),
  ('zn', 'Zenon', 'Zmyśleński', Sex.male, 1934, 2008, null),
  ('mr', 'Mirosław', 'Zmyśleński', Sex.male, 1962, null, null),
  ('ewl', 'Ewelina', 'Zmyśleńska', Sex.female, 1965, null, null),
  // The wife's side.
  ('ks', 'Kasia', 'Wymyślona', Sex.female, 1985, null, 'Przykładowa'),
  ('c1', 'Zofia', 'Wymyślona', Sex.female, 2012, null, null),
  ('c2', 'Ignacy', 'Wymyślony', Sex.male, 2015, null, null),
  ('pt', 'Piotr', 'Przykładowy', Sex.male, 1957, null, null),
  ('ag', 'Agnieszka', 'Przykładowa', Sex.female, 1960, null, 'Wymyślak'),
  ('ad', 'Adam', 'Przykładowy', Sex.male, 1988, null, null),
  ('we', 'Weronika', 'Przykładowa', Sex.female, 1990, null, null),
  ('jl', 'Julia', 'Przykładowa', Sex.female, 2019, null, null),
  ('em', 'Edmund', 'Przykładowy', Sex.male, 1930, 2008, null),
  ('wa', 'Wanda', 'Przykładowa', Sex.female, 1934, null, 'Testowicz'),
  ('jl2', 'Jolanta', 'Zmyślewska', Sex.female, 1961, null, 'Przykładowa'),
  ('sl', 'Sławomir', 'Zmyślewski', Sex.male, 1958, null, null),
  ('emi', 'Emilia', 'Zmyślewska', Sex.female, 1990, null, null),
  ('lh', 'Lech', 'Wymyślak', Sex.male, 1932, 2000, null),
  ('ce', 'Cecylia', 'Wymyślak', Sex.female, 1936, 2016, null),
  ('rk', 'Radosław', 'Wymyślak', Sex.male, 1963, null, null),
  ('mg2', 'Małgorzata', 'Wymyślak', Sex.female, 1965, null, null),
  ('sz', 'Szymon', 'Wymyślak', Sex.male, 1992, null, null),
];

/// The births written otherwise than as an exact year (ISSUE-037): with a qualifier, or null — none written.
/// The year in [_people] then stands for nothing.
const Map<String, QualifiedDate?> _birthAs = {
  'a2': QualifiedDate(DateQualifier.about, PartialDate(1870)),
  'td': QualifiedDate(
    DateQualifier.between,
    PartialDate(1895),
    PartialDate(1900),
  ),
  'kz': QualifiedDate(DateQualifier.before, PartialDate(1900)),
  'le': QualifiedDate(DateQualifier.after, PartialDate(1905)),
  'f3': null,
  'lh': null,
};

/// The deaths written otherwise: with a qualifier, or null — a death without its date.
const Map<String, QualifiedDate?> _deathAs = {
  'L': QualifiedDate(DateQualifier.about, PartialDate(1944)),
  'kz': QualifiedDate(DateQualifier.after, PartialDate(1960)),
  'wl': null,
};

/// Marriages without a date, as most are on the notes (ISSUE-037): the first partner's key.
const Set<String> _marriedWhenUnknown = {'a1', 'kz', 'wl'};

const List<_Union> _unions = [
  ('a1', 'a2', null, null, ['f1', 'f2', 'f3'], null),
  ('w1', 'f2', null, 1922, ['w2'], null),
  ('f1', 'j1', null, 1921, ['J', 'L', 'St'], null),
  ('bt', 'St', null, 1951, ['ry', 'el'], null),
  ('ry', 'gr', null, 1978, ['se', 'mg1'], null),
  ('J', 'he', null, 1946, ['jn'], null),
  ('jn', 'ir', null, 1970, ['tm', 'be'], null),
  ('tm', 'mo', null, 1998, ['ku', 'ol'], null),
  ('J', 'zo', null, 1950, ['sn', 'mk', 'ha'], null),
  ('sn', 'da', null, 1975, ['pa', 'mt', 'kr'], null),
  ('pa', 'an', null, 2003, ['zu'], null),
  ('lu', 'mt', null, 2008, ['at', 'hn'], null),
  ('mk', 'ew', 1982, 1985, ['JA', 'mi', 'jo'], null),
  ('mi', 'nt', 2014, null, ['le2'], null),
  ('bk', 'jo', null, 2014, ['my', 'fp'], null),
  ('wo', 'ha', null, 1980, ['agt', 'dr'], null),
  ('rf', 'agt', null, 2007, ['ig'], null),
  ('kz', 'br', null, null, ['zo', 'ed'], null),
  ('ed', 'lc', null, 1956, ['je'], null),
  ('wl', 'ge', null, null, ['cz', 'hk'], null),
  ('ge', 'td', null, 1948, ['zd'], null),
  ('cz', 'te', null, 1953, ['rm'], null),
  ('rm', 'iw', null, 1980, ['prz'], null),
  ('hk', 'kry', null, 1955, ['ew', 'adr', 'ter'], null),
  ('adr', 'bo', null, 1983, ['km', 'kg'], 1995),
  ('km', 'pl', null, 2010, ['nk'], null),
  ('adr', 're', null, 2000, ['os'], null),
  ('gz', 'ter', null, 1986, ['kl', 'dw'], null),
  ('mc', 'kl', null, 2015, ['ln'], null),
  ('fe', 'le', null, 1930, ['kry', 'bb'], null),
  ('zn', 'bb', null, 1960, ['mr', 'ewl'], null),
  ('JA', 'ks', null, 2010, ['c1', 'c2'], null),
  ('pt', 'ag', null, 1983, ['ks', 'ad'], null),
  ('ad', 'we', null, 2015, ['jl'], null),
  ('em', 'wa', null, 1955, ['pt', 'jl2'], null),
  ('sl', 'jl2', null, 1987, ['emi'], null),
  ('lh', 'ce', null, 1958, ['ag', 'rk'], null),
  ('rk', 'mg2', null, 1990, ['sz'], null),
];

/// The marker of this family's people — a second call adds nothing.
const String _bio = 'Osoba wymyślona do drzewa (ISSUE-033).';

/// Adds the made-up family, once; "ja" becomes its "Ja" unless someone already is. False when it is
/// already there.
Future<bool> addFictionalFamily(GrobingDatabase db) async {
  final bool present =
      await (db.select(db.persons)
            ..where((p) => p.bio.equals(_bio))
            ..limit(1))
          .getSingleOrNull() !=
      null;
  if (present) return false;
  QualifiedDate? year(int? y) =>
      y == null ? null : QualifiedDate(DateQualifier.exact, PartialDate(y));

  await db.transaction(() async {
    final Map<String, int> ids = {};
    for (final (
          String key,
          String given,
          String surname,
          Sex sex,
          int born,
          int? died,
          String? bornAs,
        )
        in _people) {
      final int id = await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              givenNames: Value(given),
              surname: Value(surname),
              birthSurname: Value(bornAs),
              sex: Value(sex),
              bio: const Value(_bio),
              bioSource: const Value('dane testowe'),
            ),
          );
      ids[key] = id;
      final QualifiedDate? birth = _birthAs.containsKey(key)
          ? _birthAs[key]
          : year(born);
      if (birth != null) {
        await addEventWithClaim(db, _event(EventType.birth, id, birth));
      }
      if (_deathAs.containsKey(key) || died != null) {
        await addEventWithClaim(
          db,
          _event(
            EventType.death,
            id,
            _deathAs.containsKey(key) ? _deathAs[key] : year(died),
          ),
        );
      }
    }
    for (final (
          String a,
          String b,
          int? together,
          int? married,
          List<String> children,
          int? ended,
        )
        in _unions) {
      await saveFamily(
        db,
        FamilyDraft(
          partners: [ExistingMember(ids[a]!), ExistingMember(ids[b]!)],
          children: [for (final String c in children) ExistingMember(ids[c]!)],
          together: year(together),
          married: married != null || _marriedWhenUnknown.contains(a),
          marriage: year(married),
          end: year(ended),
        ),
      );
    }
    final Setting? settings = await (db.select(
      db.settings,
    )..where((s) => s.id.equals(1))).getSingleOrNull();
    if (settings?.mePersonId == null) await setMe(db, ids['JA']!);
  });
  return true;
}

/// A person's event with [date] — none: the event is known, its date not.
EventsCompanion _event(EventType type, int person, QualifiedDate? date) =>
    EventsCompanion.insert(
      type: type,
      personId: Value(person),
      qualifier: Value(date?.qualifier),
      year: Value(date?.from.year),
      yearTo: Value(date?.to?.year),
    );
