import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_layout.dart';
import 'package:grobing/app/tree/tree_time.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/graves.dart' show PartialDate, QualifiedDate;
import 'package:grobing/dev/fictional_family.dart';

// ISSUE-037 — time on the tree (05_DESIGN/drzewo.md v1.12, element 6; US-010): the windows of a date with a
// qualifier or none (D32 — N3), the slider's start (D34 — T2), a person in a year (AC-1, C1), a pair in a year
// (AC-2, E3 — D35), the lines and the trace of a year (D37). The made-up family of the debug build, with the
// same uncertain dates as ISSUE-037's mockup, whose windows these are (`#test=1`). Made-up people only
// (family-data.md).

void main() {
  late FamilyTreeData family;
  late TreeTime time;
  late Map<String, int> id;

  /// A person by key — the mockup's keys, for names that are not unique in the family.
  int p(String key) => id[key]!;

  TreeUnion union(String a, String b) => family.unions.singleWhere(
    (u) => u.partners.contains(p(a)) && u.partners.contains(p(b)),
  );

  setUpAll(() async {
    final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
    await addFictionalFamily(db);
    family = await loadFamilyTree(db);
    await db.close();
    time = TreeTime(family, now: 2026);
    int named(String given, String surname, {bool Function(TreePerson)? and}) =>
        family.people.values
            .singleWhere(
              (x) =>
                  x.givenNames == given &&
                  x.surname == surname &&
                  (and == null || and(x)),
            )
            .id;
    id = {
      'JA': family.meId!,
      'a1': named('Antoni', 'Wymyślony'),
      'a2': named('Marianna', 'Wymyślona'),
      'td': named('Tadeusz', 'Wymyślewicz'),
      'kz': named('Kazimierz', 'Przykładek'),
      'le': named('Leokadia', 'Testowa'),
      'f3': named('Stanisław', 'Wymyślony', and: (x) => x.birth == null),
      'lh': named('Lech', 'Wymyślak'),
      'L': named('Leon', 'Wymyślony', and: (x) => x.dead),
      'wl': named('Władysław', 'Zmyślony'),
      'zo': named('Zofia', 'Wymyślona', and: (x) => x.dead),
      'mk': named('Marek', 'Wymyślony'),
      'ew': named('Ewa', 'Wymyślona'),
      'adr': named('Andrzej', 'Zmyślony'),
      'bo': named('Bożena', 'Zmyślona'),
      'mi': named('Michał', 'Wymyślony'),
      'nt': named('Natalia', 'Zmyślewicz'),
    };
  });

  test(
    'D34 (T2) — the slider starts at 1860: the full decade before "ok. 1870" '
    '(its window from 1865), at the latest 1880',
    () {
      expect(time.start, 1860);
      // A family born from 1900 on: the slider still starts at 1880.
      final FamilyTreeData late = FamilyTreeData(
        people: {
          1: const TreePerson(
            id: 1,
            birth: QualifiedDate(DateQualifier.exact, PartialDate(1912)),
          ),
        },
        unions: const [],
      );
      expect(TreeTime(late, now: 2026).start, latestSliderStart);
    },
  );

  test('D32 (N3) — the windows of the mockup: "ok.", "między", "przed", "po", none; '
      'deaths "ok.", "po" and without a date', () {
    YearWindow w(int from, int to) => YearWindow(from, to);
    expect(time.birthWindow(p('a2')), w(1865, 1875)); // ok. 1870
    expect(time.birthWindow(p('td')), w(1895, 1900)); // między 1895 a 1900
    // przed 1900: from 20 years before his wife's birth (Gramps), surely by 1900.
    expect(time.birthWindow(p('kz')), w(1882, 1900));
    // po 1905: surely by her wedding, 1930.
    expect(time.birthWindow(p('le')), w(1905, 1930));
    // None: 20 years after his younger parent, surely by his death in 1920.
    expect(time.birthWindow(p('f3')), w(1890, 1920));
    // None, no parents: 20 years before his wife, surely by his wedding.
    expect(time.birthWindow(p('lh')), w(1916, 1958));
    expect(time.deathWindow(p('L')), w(1939, 1949)); // zm. ok. 1944
    // zm. po 1960: at the latest 110 years from his birth (Gramps).
    expect(time.deathWindow(p('kz')), w(1960, 2010));
    // A death without its date: from his last child's birth to 110 years from his own.
    expect(time.deathWindow(p('wl')), w(1930, 2010));
    // Exact dates — no window; the living — no death.
    expect(time.birthWindow(p('JA')), w(1983, 1983));
    expect(time.deathWindow(p('JA')), isNull);
  });

  test(
    'US-010 AC-1, C1 — a person in a year: not yet, maybe born, alive, maybe dead, dead; '
    '"dziś" as without the slider',
    () {
      expect(time.person(p('JA'), 1950), InYear.notYet);
      expect(time.isOn(p('JA'), 1950), isFalse);
      expect(time.person(p('JA'), 1984), InYear.alive);
      expect(time.person(p('zo'), 2009), InYear.alive);
      expect(time.person(p('zo'), 2010), InYear.dead);
      expect(time.person(p('kz'), 1881), InYear.notYet);
      expect(time.person(p('kz'), 1890), InYear.maybeBorn);
      expect(time.isOn(p('kz'), 1890), isTrue);
      expect(time.person(p('kz'), 1950), InYear.alive);
      expect(time.person(p('kz'), 1970), InYear.maybeDead);
      expect(time.person(p('kz'), 2015), InYear.dead);
      expect(time.person(p('wl'), 1929), InYear.alive);
      expect(time.person(p('wl'), 1960), InYear.maybeDead);
      expect(time.person(p('wl'), 2011), InYear.dead);
      // "Dziś" — null or this year: everyone, the dead with the candle (D22), nothing dashed.
      for (final int? today in [null, 2026]) {
        expect(time.person(p('JA'), today), InYear.alive);
        expect(time.person(p('wl'), today), InYear.dead);
        expect(time.person(p('f3'), today), InYear.dead);
      }
    },
  );

  test(
    'US-010 AC-2 — "razem" from 1982, the wedding in 1985; a wedding without a date from '
    'the oldest child; E3 — the end from its year',
    () {
      final TreeUnion parents = union('mk', 'ew');
      expect(time.pair(parents, 1981), isNull);
      expect(time.pair(parents, 1984)!.married, isFalse);
      expect(time.pair(parents, 1986)!.married, isTrue);
      // Antoni and Marianna: married, no date — from Franciszek, 1895 (TimeNets, D31).
      final TreeUnion old = union('a1', 'a2');
      expect(time.pair(old, 1894), isNull);
      expect(time.pair(old, 1895)!.married, isTrue);
      // Andrzej and Bożena parted in 1995.
      final TreeUnion parted = union('adr', 'bo');
      expect(time.pair(parted, 1990)!.ended, isFalse);
      expect(time.pair(parted, 2000)!.ended, isTrue);
      expect(time.pair(parted, null)!.ended, isTrue);
      // "Razem" without a wedding stays dashed.
      expect(time.pair(union('mi', 'nt'), 2015)!.married, isFalse);
    },
  );

  test(
    'D3 — a union without a date orders by its oldest child: the widow\'s first marriage '
    'stays first',
    () {
      final TreeUnion first = family.unions.singleWhere(
        (u) => u.partners.contains(p('wl')),
      );
      expect(first.startKey, isNotNull);
      expect(first.married, isTrue);
      expect(first.marriage, isNull);
      expect(union('adr', 'bo').ended, isTrue);
      expect(union('adr', 'bo').end, isNotNull);
    },
  );

  test(
    'D32 — a person without dates and family: unknown from the slider\'s start to "dziś"; '
    'a death known only from the burial ends there',
    () {
      final FamilyTreeData lone = FamilyTreeData(
        people: {
          1: const TreePerson(id: 1),
          2: const TreePerson(
            id: 2,
            birth: QualifiedDate(DateQualifier.exact, PartialDate(1900)),
            burial: QualifiedDate(DateQualifier.exact, PartialDate(1950)),
            dead: true,
          ),
        },
        unions: const [],
      );
      final TreeTime t = TreeTime(lone, now: 2026);
      expect(t.birthWindow(1), const YearWindow(1880, 2026));
      expect(t.person(1, 1880), InYear.maybeBorn);
      expect(t.person(1, null), InYear.alive);
      expect(t.deathWindow(2), const YearWindow(1900, 1950));
      expect(t.person(2, 1949), InYear.maybeDead);
      expect(t.person(2, 1950), InYear.dead);
    },
  );

  test(
    'D37, E3 — the lines of a year: nobody yet, nothing drawn; "//" from the end; the trace '
    'only to family already born',
    () {
      final TreeGraph graph = TreeGraph(family);
      List<Offset> of(List<TreeLines> lines, TreeLineKind kind) =>
          lines.singleWhere((l) => l.kind == kind).points;

      final TreeLayout fromJa = layoutTree(graph, p('JA'), 2);
      for (final TreeLines l in fromJa.linesAt(time, 1900)) {
        expect(l.points, isEmpty, reason: '${l.kind} in 1900');
      }
      // "Dziś" are the lines without the slider.
      expect(
        of(fromJa.linesAt(time, null), TreeLineKind.parentChild),
        of(fromJa.lines, TreeLineKind.parentChild),
      );

      // The trace sideways only to a partner the union with whom has begun (ui review of ISSUE-037): Teresa
      // married Grzegorz — beyond the view from "Ja" — in 1986.
      final Offset teresa =
          fromJa.positions[family.people.values
              .singleWhere(
                (x) => x.givenNames == 'Teresa' && x.surname == 'Przykładowicz',
              )
              .id]!;
      bool partnerTrace(int year) => of(
        fromJa.linesAt(time, year),
        TreeLineKind.tracePartner,
      ).any((o) => o.dy == teresa.dy + 22 && (o.dx - teresa.dx).abs() == 22);
      expect(partnerTrace(1984), isFalse);
      expect(partnerTrace(1987), isTrue);

      final TreeLayout fromAndrzej = layoutTree(graph, p('adr'), 2);
      expect(of(fromAndrzej.linesAt(time, 1990), TreeLineKind.ended), isEmpty);
      expect(
        of(fromAndrzej.linesAt(time, 2000), TreeLineKind.ended),
        hasLength(4),
      );
      expect(of(fromAndrzej.lines, TreeLineKind.ended), hasLength(4));
    },
  );
}
