import 'dart:math' as math;

import '../../data/database.dart' show DateQualifier;
import '../../data/family_tree.dart';
import '../../data/graves.dart' show QualifiedDate;

// Time on the tree (05_DESIGN/drzewo.md v1.12, element 6; US-010, ISSUE-037): who is there in a year, who is
// maybe there, who is dead, and how each pair is joined. Pure Dart, worked out once for the family: the
// slider then only asks.
//
// A date with a qualifier — or none — is a window (D32): from the year the event may have happened to the year
// it surely has. Missing ends come from the family, as TimeNets estimates missing dates (D31: "We use a
// rule-based method to estimate missing dates"), with Gramps' numbers: 20 years between generations, siblings
// and spouses, 110 years of life at most. The windows only say when it is not known — the app still never
// guesses a death from age (D22): the candle needs a written death or burial.

/// 20 years: Gramps' `AVG_GENERATION_GAP` and `MAX_SIB_AGE_DIFF` (drzewo.md D31).
const int _generation = 20;

/// Gramps' `MAX_AGE_PROB_ALIVE` (D31).
const int _maxAge = 110;

/// "ok. Y" is Y − 5 … Y + 5 (D32 — a design decision: "ok." on the notes is mostly a rounded year).
const int _about = 5;

/// The slider never starts later than this (US-010 AC-3, D34).
const int latestSliderStart = 1880;

/// The tempo of ▶ (drzewo.md element 6, D41 — V2; ISSUE-038): years a second, in the order the button goes
/// through them. "Szybko" is ISSUE-037's tempo, which was too fast for the author; "Średnio" is the default.
enum TreeTempo {
  slow('Wolno', 'wolno', 5),
  medium('Średnio', 'średnio', 10),
  fast('Szybko', 'szybko', 20);

  const TreeTempo(this.label, this.spoken, this.yearsPerSecond);

  /// On the button.
  final String label;

  /// For the reader: "Tempo historii: średnio".
  final String spoken;
  final int yearsPerSecond;

  /// The time to the next year while ▶ runs.
  Duration get yearStep => Duration(microseconds: 1000000 ~/ yearsPerSecond);

  /// With the system's animations off ▶ jumps a decade at once (R2, D36), as often as the tempo gives:
  /// every 2 · 1 · 0.5 s.
  Duration get decadeStep =>
      Duration(microseconds: 10 * 1000000 ~/ yearsPerSecond);

  /// The button's next tempo: "Wolno" → "Średnio" → "Szybko" → "Wolno".
  TreeTempo get next => values[(index + 1) % values.length];
}

/// The tempo chosen — the same in the card and in presentation, kept while the app runs (D41): after it is
/// closed, "Średnio" again. Not in the database: one button is not worth a change of the schema.
TreeTempo treeTempo = TreeTempo.medium;

/// What the tree shows of a person in one year (D32 — N3, D33).
enum InYear {
  /// Not born yet: off the tree, the place kept (AC-1).
  notYet,

  /// Maybe born already: on the tree with the dashed outline.
  maybeBorn,
  alive,

  /// Maybe dead already: the dashed outline, no candle yet.
  maybeDead,

  /// Surely dead: the candle.
  dead,
}

/// The years an event is not known in: it may have happened from [from], it surely has from [to].
class YearWindow {
  const YearWindow(this.from, this.to);

  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is YearWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from–$to';
}

/// A pair's line in one year (AC-2, D35): married — solid, else "razem" — dashed; [ended] — "//" across it.
class PairInYear {
  const PairInYear({required this.married, required this.ended});

  final bool married;
  final bool ended;
}

/// The family's time, worked out once.
class TreeTime {
  TreeTime._(this.now, this.start, this._births, this._deaths, this._pairs);

  /// [now] is this year: from it on — "dziś" — the tree is as without the slider.
  factory TreeTime(FamilyTreeData data, {required int now}) {
    final Map<int, TreePerson> people = data.people;
    final Map<int, List<TreeUnion>> unionsOf = {};
    final Map<int, TreeUnion> parentUnion = {};
    for (final TreeUnion u in data.unions) {
      for (final int p in u.partners) {
        (unionsOf[p] ??= []).add(u);
      }
      for (final int c in u.children) {
        parentUnion.putIfAbsent(c, () => u);
      }
    }
    List<TreeUnion> unions(int n) => unionsOf[n] ?? const [];
    List<int> parents(int n) => parentUnion[n]?.partners ?? const [];
    List<int> children(int n) => [
      for (final TreeUnion u in unions(n)) ...u.children,
    ];
    List<int> partners(int n) => [
      for (final TreeUnion u in unions(n))
        for (final int p in u.partners)
          if (p != n) p,
    ];
    List<int> siblings(int n) => {
      for (final int p in parents(n))
        for (final int c in children(p))
          if (c != n) c,
    }.toList();
    int? born(int n) => people[n]?.birth?.from.year;
    List<int> known(Iterable<int> ids) => [
      for (final int x in ids)
        if (born(x) case final int y) y,
    ];

    // D34: the full decade before the earliest birth — before the window of an "ok." one — at the latest 1880.
    int start = latestSliderStart;
    for (final TreePerson p in people.values) {
      final QualifiedDate? b = p.birth;
      if (b == null) continue;
      final int y = b.qualifier == DateQualifier.about
          ? b.from.year - _about
          : b.from.year;
      start = math.min(start, (y / 10).floor() * 10);
    }

    // A pair's start: its own date, else its oldest child's birth (TimeNets), else the younger partner at 20.
    int? pairStart(TreeUnion u) {
      if ((u.together ?? u.marriage) case final QualifiedDate d) {
        return d.from.year;
      }
      final List<int> kids = known(u.children);
      if (kids.isNotEmpty) return kids.reduce(math.min);
      final List<int> ps = known(u.partners);
      return ps.isEmpty ? null : ps.reduce(math.max) + _generation;
    }

    // The earliest a person may have been born, and the year they surely were.
    int earliest(int n) {
      final List<int> ps = known(parents(n));
      if (ps.isNotEmpty) return ps.reduce(math.max) + _generation;
      final List<int> near = known([...partners(n), ...siblings(n)]);
      if (near.isNotEmpty) return near.reduce(math.min) - _generation;
      return start;
    }

    int surely(int n) {
      final TreePerson? p = people[n];
      final List<int> own = [
        for (final TreeUnion u in unions(n))
          if ((u.together ?? u.marriage) case final QualifiedDate d)
            d.from.year,
        ...known(children(n)),
        ?p?.death?.from.year,
        ?p?.burial?.from.year,
      ];
      if (own.isNotEmpty) return own.reduce(math.min);
      final List<int> near = known([...partners(n), ...siblings(n)]);
      if (near.isNotEmpty) return near.reduce(math.max) + _generation;
      return now;
    }

    final Map<int, YearWindow> births = {};
    for (final TreePerson p in people.values) {
      final QualifiedDate? b = p.birth;
      final int? y = b?.from.year;
      births[p.id] = switch (b?.qualifier) {
        null => () {
          final int to = surely(p.id);
          return YearWindow(math.min(earliest(p.id), to), to);
        }(),
        DateQualifier.exact => YearWindow(y!, y),
        DateQualifier.about => YearWindow(y! - _about, y + _about),
        DateQualifier.between => YearWindow(y!, b!.to?.year ?? y),
        DateQualifier.before => YearWindow(math.min(earliest(p.id), y!), y),
        DateQualifier.after => YearWindow(y!, math.max(surely(p.id), y)),
      };
    }

    // The last year a person surely lived: born, a union of theirs began, a child of theirs was born.
    int lastFact(int n) => [
      births[n]!.to,
      for (final TreeUnion u in unions(n)) ?pairStart(u),
      ...known(children(n)),
    ].reduce(math.max);

    final Map<int, YearWindow> deaths = {};
    for (final TreePerson p in people.values) {
      if (!p.dead) continue;
      final int last = lastFact(p.id);
      // The latest a death can be: the burial's date, else 110 years from birth (never after this year).
      final int cap =
          p.burial?.from.year ?? math.min(births[p.id]!.to + _maxAge, now);
      final QualifiedDate? d = p.death;
      final int? y = d?.from.year;
      deaths[p.id] = switch (d?.qualifier) {
        null => YearWindow(last, math.max(last, cap)),
        DateQualifier.exact => YearWindow(y!, y),
        DateQualifier.about => YearWindow(y! - _about, y + _about),
        DateQualifier.between => YearWindow(y!, d!.to?.year ?? y),
        DateQualifier.before => YearWindow(math.min(last, y!), y),
        DateQualifier.after => YearWindow(y!, math.max(y, cap)),
      };
    }

    final Map<int, ({int? from, int? married, int? ended})> pairs = {};
    for (final TreeUnion u in data.unions) {
      final int? from = pairStart(u);
      final List<int> kids = known(u.children);
      pairs[u.familyId] = (
        from: from,
        // A wedding without its date: from the oldest child (TimeNets), else from the pair's start.
        married: !u.married
            ? null
            : u.marriage?.from.year ??
                  (kids.isEmpty ? from : kids.reduce(math.min)),
        // An end without its date shows only today — it is known, its year is not.
        ended: !u.ended ? null : u.end?.from.year ?? now,
      );
    }
    return TreeTime._(now, start, births, deaths, pairs);
  }

  final int now;

  /// The slider's first year (D34).
  final int start;
  final Map<int, YearWindow> _births;
  final Map<int, YearWindow> _deaths;
  final Map<int, ({int? from, int? married, int? ended})> _pairs;

  YearWindow? birthWindow(int person) => _births[person];

  /// Null for the living (D22).
  YearWindow? deathWindow(int person) => _deaths[person];

  /// [year] null or from [now] on is today: everyone is on the tree, the dead with the candle.
  InYear person(int id, int? year) {
    final YearWindow? death = _deaths[id];
    if (year == null || year >= now) {
      return death == null ? InYear.alive : InYear.dead;
    }
    final YearWindow? birth = _births[id];
    if (birth != null) {
      if (year < birth.from) return InYear.notYet;
      if (year < birth.to) return InYear.maybeBorn;
    }
    if (death != null) {
      if (year >= death.to) return InYear.dead;
      if (year >= death.from) return InYear.maybeDead;
    }
    return InYear.alive;
  }

  /// On the tree in [year]: born, or maybe born.
  bool isOn(int id, int? year) => person(id, year) != InYear.notYet;

  /// The pair's line in [year], or null — not together yet (AC-2). The partners being born is the caller's.
  PairInYear? pair(TreeUnion union, int? year) {
    final ({int? from, int? married, int? ended})? p = _pairs[union.familyId];
    if (year == null || year >= now || p == null) {
      return PairInYear(married: union.married, ended: union.ended);
    }
    final int? from = p.from;
    if (from == null || year < from) return null;
    return PairInYear(
      married: p.married != null && year >= p.married!,
      ended: p.ended != null && year >= p.ended!,
    );
  }
}
