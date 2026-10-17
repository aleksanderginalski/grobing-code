import 'package:drift/drift.dart';

import 'database.dart';
import 'folding.dart';
import 'graves.dart' show watchTables;

// Family lines — "rody" (ISSUE-044, ADR-021; 05_DESIGN/wieniec.md): a line's name and its wreath, and the
// choice of a line at a person. Only the choice is stored; the wreath of everyone else is worked out from
// the tree (`wreaths.dart`). Writes save at once, like the family in the same form (wieniec.md D16), and
// go through drift's API, so they notify `tableUpdates` and ask for a background backup (ISSUE-010).

/// The motifs drawn for the app — the author's images, one file each in `assets/wreaths/` (wieniec.md A1,
/// D12: 19 of the 20 prompts, no poppy). [key] is what the database keeps; a key it does not know (a
/// backup from a newer app) draws no wreath rather than a wrong one.
enum WreathMotif {
  laur('laur', 'Laur'),
  dab('dab', 'Dąb'),
  klosy('klosy', 'Kłosy'),
  jarzebina('jarzebina', 'Jarzębina'),
  lipa('lipa', 'Lipa'),
  brzoza('brzoza', 'Brzoza'),
  klon('klon', 'Klon'),
  kasztanowiec('kasztanowiec', 'Kasztanowiec'),
  bluszcz('bluszcz', 'Bluszcz'),
  dzikaRoza('dzika_roza', 'Dzika róża'),
  chaber('chaber', 'Chaber'),
  rumianek('rumianek', 'Rumianek'),
  konwalia('konwalia', 'Konwalia'),
  wrzos('wrzos', 'Wrzos'),
  paproc('paproc', 'Paproć'),
  kalina('kalina', 'Kalina'),
  leszczyna('leszczyna', 'Leszczyna'),
  chmiel('chmiel', 'Chmiel'),
  jablon('jablon', 'Jabłoń');

  const WreathMotif(this.key, this.label);

  final String key;
  final String label;

  /// The motif's image: its shape, the C3 shading and the halo (wieniec.md A4, A5; `tool/wreaths/`).
  String get asset => 'assets/wreaths/wieniec-$key.png';

  static WreathMotif? byKey(String key) {
    for (final WreathMotif m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// The twelve colours of a line (wieniec.md D6) — their values live in `theme.dart`, the database keeps
/// the [key].
enum ClanColour {
  stareZloto('stare_zloto', 'Stare złoto'),
  braz('braz', 'Brąz'),
  miedz('miedz', 'Miedź'),
  srebro('srebro', 'Srebro'),
  koscSloniowa('kosc_sloniowa', 'Kość słoniowa'),
  grafit('grafit', 'Grafit'),
  patyna('patyna', 'Patyna'),
  oliwka('oliwka', 'Oliwka'),
  blekit('blekit', 'Błękit'),
  lawenda('lawenda', 'Lawenda'),
  wrzos('wrzos', 'Wrzos'),
  rubin('rubin', 'Rubin');

  const ClanColour(this.key, this.label);

  final String key;
  final String label;

  /// An unknown key falls back to the first colour: the line keeps its wreath, in a colour that is safe.
  static ClanColour byKey(String key) {
    for (final ClanColour c in values) {
      if (c.key == key) return c;
    }
    return values.first;
  }
}

/// A family line as the screens read it.
class Clan {
  const Clan({
    required this.id,
    required this.name,
    required this.motif,
    required this.colour,
  });

  factory Clan.ofRow(ClanRow r) => Clan(
    id: r.id,
    name: r.name,
    motif: WreathMotif.byKey(r.motif),
    colour: ClanColour.byKey(r.colour),
  );

  final int id;
  final String name;

  /// Null: a key this app does not know — no wreath is drawn.
  final WreathMotif? motif;
  final ClanColour colour;

  @override
  bool operator ==(Object other) =>
      other is Clan &&
      other.id == id &&
      other.name == name &&
      other.motif == motif &&
      other.colour == colour;

  @override
  int get hashCode => Object.hash(id, name, motif, colour);
}

/// What is chosen at a person: nothing (the wreath comes from the father), a line, or "bez wieńca".
class WreathChoice {
  const WreathChoice.inherit() : clanId = null, none = false;
  const WreathChoice.clan(int this.clanId) : none = false;
  const WreathChoice.none() : clanId = null, none = true;

  final int? clanId;
  final bool none;

  bool get inherits => clanId == null && !none;
}

/// Why a line's name was refused (wieniec.md F2).
enum ClanNameProblem { empty, taken }

class ClanNameException implements Exception {
  const ClanNameException(this.problem);

  final ClanNameProblem problem;

  @override
  String toString() => 'ClanNameException($problem)';
}

/// A new line's colour (wieniec.md F3): the first of the palette no other line has; all taken — the first.
ClanColour firstFreeColour(Iterable<Clan> others) =>
    ClanColour.values.firstWhere(
      (c) => others.every((o) => o.colour != c),
      orElse: () => ClanColour.values.first,
    );

/// A new line's motif (wieniec.md F4, D20): the first no other line has; every motif used — the first no
/// other line has in [colour], since a line is told by its motif and colour together; every pair used — the
/// first.
WreathMotif firstFreeMotif(Iterable<Clan> others, ClanColour colour) =>
    WreathMotif.values.firstWhere(
      (m) => others.every((o) => o.motif != m),
      orElse: () => WreathMotif.values.firstWhere(
        (m) => others.every((o) => o.motif != m || o.colour != colour),
        orElse: () => WreathMotif.values.first,
      ),
    );

/// Every line, by name without case and Polish letters (wieniec.md E2: A–Z).
Future<List<Clan>> loadClans(GrobingDatabase db) async {
  final List<Clan> clans = [
    for (final ClanRow r in await db.select(db.clans).get()) Clan.ofRow(r),
  ];
  clans.sort((a, b) {
    final int byName = fold(a.name).compareTo(fold(b.name));
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return clans;
}

/// [loadClans], again after every write to the lines.
Stream<List<Clan>> watchClans(GrobingDatabase db) =>
    watchTables(db, 'clans', {db.clans}, () => loadClans(db));

/// A new line, and — when [forPerson] is given — chosen at that person, in one transaction (wieniec.md F6:
/// "Zapisz ród" gives the line to the person whose entry is open). Throws [ClanNameException].
Future<int> createClan(
  GrobingDatabase db, {
  required String name,
  required WreathMotif motif,
  required ClanColour colour,
  int? forPerson,
}) => db.transaction(() async {
  final String trimmed = await _checkedName(db, name);
  final int id = await db
      .into(db.clans)
      .insert(
        ClansCompanion.insert(
          name: trimmed,
          motif: motif.key,
          colour: colour.key,
        ),
      );
  if (forPerson != null) {
    await _writeChoice(db, forPerson, WreathChoice.clan(id));
  }
  return id;
});

/// A line's name, motif and colour (wieniec.md F, poprawa — AC-6). Everyone with the line sees the change,
/// because no wreath is stored. Throws [ClanNameException].
Future<void> updateClan(
  GrobingDatabase db,
  int id, {
  required String name,
  required WreathMotif motif,
  required ClanColour colour,
}) => db.transaction(() async {
  final String trimmed = await _checkedName(db, name, except: id);
  await (db.update(db.clans)..where((c) => c.id.equals(id))).write(
    ClansCompanion(
      name: Value(trimmed),
      motif: Value(motif.key),
      colour: Value(colour.key),
    ),
  );
});

/// The choice at [personId] (wieniec.md E1, E1a, E2): a line, "bez wieńca", or back to the father's.
Future<void> setWreathChoice(
  GrobingDatabase db,
  int personId,
  WreathChoice choice,
) => _writeChoice(db, personId, choice);

Future<void> _writeChoice(
  GrobingDatabase db,
  int personId,
  WreathChoice choice,
) async {
  await (db.update(db.persons)..where((p) => p.id.equals(personId))).write(
    PersonsCompanion(
      clanId: Value(choice.clanId),
      noWreath: Value(choice.none),
    ),
  );
}

/// [name] trimmed, or [ClanNameException] when it is empty or another line has it already — the same
/// name without case and Polish letters ("Wymyślscy" = "wymyslscy"), as the search compares names.
Future<String> _checkedName(
  GrobingDatabase db,
  String name, {
  int? except,
}) async {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) throw const ClanNameException(ClanNameProblem.empty);
  final String folded = fold(trimmed);
  for (final ClanRow r in await db.select(db.clans).get()) {
    if (r.id != except && fold(r.name.trim()) == folded) {
      throw const ClanNameException(ClanNameProblem.taken);
    }
  }
  return trimmed;
}
