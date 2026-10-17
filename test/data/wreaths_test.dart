import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/clans.dart';
import 'package:grobing/data/database.dart' show Sex;
import 'package:grobing/data/wreaths.dart';

// ISSUE-044 — whose wreath is which (lib/data/wreaths.dart; 05_DESIGN/wieniec.md B1–B7), as a pure function
// over a made-up family: B1 the father, B2 the own line (chosen, "bez wieńca", from the father, O1), B3–B5 a
// married woman's halves, B6 children take the father's own line, B7 an ended marriage still counts; the
// heirs and the counts of the rows E1, E2 and F5; a loop in the tree does not hang. AC-1, AC-2, AC-4 in
// the data. Made-up people only (family-data.md).

const Clan _w = Clan(
  id: 1,
  name: 'Wymyślscy',
  motif: WreathMotif.dab,
  colour: ClanColour.stareZloto,
);
const Clan _z = Clan(
  id: 2,
  name: 'Zmyśleńscy',
  motif: WreathMotif.laur,
  colour: ClanColour.patyna,
);
const Clan _p = Clan(
  id: 3,
  name: 'Przykładowscy',
  motif: WreathMotif.jarzebina,
  colour: ClanColour.lawenda,
);
const Map<int, Clan> _clans = {1: _w, 2: _z, 3: _p};

// The people: 1 Józef ♂ (top of his line) and 2 Anna ♀ (top of hers), married; their children 3 Jan ♂ and
// 4 Maria ♀; 5 Piotr ♂, Maria's husband (top of his line); 6 Kasia ♀ and 7 Tomek ♂, Jan's children with
// 8 Ewa ♀ (no line); 9 Zosia ♀, Maria's daughter.
const Map<int, Sex?> _sex = {
  1: Sex.male,
  2: Sex.female,
  3: Sex.male,
  4: Sex.female,
  5: Sex.male,
  6: Sex.female,
  7: Sex.male,
  8: Sex.female,
  9: Sex.female,
};

const List<WreathUnion> _unions = [
  WreathUnion(
    familyId: 1,
    partners: [1, 2],
    children: [3, 4],
    married: true,
    startKey: 19200000,
  ),
  WreathUnion(
    familyId: 2,
    partners: [3, 8],
    children: [6, 7],
    married: true,
    startKey: 19500000,
  ),
  WreathUnion(
    familyId: 3,
    partners: [4, 5],
    children: [9],
    married: true,
    startKey: 19520000,
  ),
];

WreathGraph _graph({
  Map<int, WreathChoice> choices = const {
    1: WreathChoice.clan(1),
    2: WreathChoice.clan(2),
    5: WreathChoice.clan(3),
  },
  List<WreathUnion> unions = _unions,
  Map<int, Sex?> sex = _sex,
}) => WreathGraph.of(sex: sex, choices: choices, unions: unions, clans: _clans);

void main() {
  test(
    'B2, AC-1 — the line chosen at the top goes to the children and grandchildren after the father, with '
    'nothing chosen at them',
    () {
      final WreathGraph g = _graph();
      expect((g.of(1).own, g.of(1).origin), (_w, WreathOrigin.chosenHere));
      expect((g.of(3).own, g.of(3).origin), (_w, WreathOrigin.fromFather));
      expect(g.of(3).fatherId, 1);
      expect(g.of(3).fatherClan, _w);
      expect(g.of(6).own, _w); // the granddaughter, after Jan
      expect(g.of(7).own, _w);
      expect(g.of(4).own, _w); // the daughter has her father's line as her own
    },
  );

  test(
    'B6 — a married daughter\'s children take their father\'s line, not hers',
    () {
      final WreathGraph g = _graph();
      expect(g.of(9).own, _p);
      expect(g.of(9).isHalved, isFalse);
    },
  );

  test(
    'B3–B5, AC-4 — a married woman: her own line on the left, her husband\'s on the right; the husband '
    'whole',
    () {
      final WreathGraph g = _graph();
      final PersonWreath anna = g.of(2);
      expect((anna.left, anna.right, anna.isHalved), (_z, _w, true));
      expect(anna.husbandId, 1);
      final PersonWreath maria = g.of(4);
      expect((maria.left, maria.right), (_w, _p));
      final PersonWreath jozef = g.of(1);
      expect((jozef.left, jozef.right, jozef.isHalved), (_w, _w, false));
      expect(jozef.husbandId, isNull);
    },
  );

  test(
    'B5 — a missing half fills the whole: a wife with no line wears her husband\'s, a husband with none '
    'leaves her own whole; with neither — no wreath',
    () {
      final WreathGraph g = _graph();
      final PersonWreath ewa = g.of(
        8,
      ); // no father, nothing chosen, married to Jan
      expect(ewa.own, isNull);
      expect(ewa.origin, WreathOrigin.noFather);
      expect((ewa.left, ewa.right, ewa.isEmpty), (_w, _w, false));

      final WreathGraph noHusbandLine = _graph(
        choices: const {2: WreathChoice.clan(2)},
      );
      final PersonWreath anna = noHusbandLine.of(2);
      expect((anna.left, anna.right, anna.isHalved), (_z, _z, false));

      final WreathGraph none = _graph(choices: const {});
      expect(none.of(2).isEmpty, isTrue);
      expect(none.of(9).isEmpty, isTrue);
    },
  );

  test(
    'B4 — "razem" without a wedding gives no half; the last marriage does — by its start, the ones without '
    'a date after them, in the order written',
    () {
      // Anna (2): a union "razem" with Piotr (5), not married.
      final WreathGraph together = _graph(
        unions: const [
          WreathUnion(familyId: 1, children: [], partners: [1, 3]),
          WreathUnion(
            familyId: 7,
            children: [],
            partners: [2, 5],
            startKey: 19300000,
          ),
        ],
        sex: const {1: Sex.male, 2: Sex.female, 3: Sex.male, 5: Sex.male},
      );
      expect(together.of(2).husbandClan, isNull);

      // Anna marries Józef (1925) and later Piotr (1931): Piotr's line on the right.
      final WreathGraph twice = _graph(
        unions: const [
          WreathUnion(
            familyId: 8,
            children: [],
            partners: [5, 2],
            married: true,
            startKey: 19310000,
          ),
          WreathUnion(
            familyId: 9,
            children: [],
            partners: [1, 2],
            married: true,
            startKey: 19250000,
          ),
        ],
      );
      expect((twice.of(2).husbandId, twice.of(2).right), (5, _p));

      // A marriage without a date comes after the dated one: it is the last.
      final WreathGraph undated = _graph(
        unions: const [
          WreathUnion(
            familyId: 8,
            children: [],
            partners: [5, 2],
            married: true,
          ),
          WreathUnion(
            familyId: 9,
            children: [],
            partners: [1, 2],
            married: true,
            startKey: 19250000,
          ),
        ],
      );
      expect(undated.of(2).husbandId, 5);
    },
  );

  test(
    'B1 — a parent without a sex is no father; a child in two families of parents takes the first',
    () {
      final WreathGraph noSex = _graph(sex: {..._sex, 1: null});
      expect(noSex.of(3).fatherId, isNull);
      expect(noSex.of(3).origin, WreathOrigin.noFather);

      final WreathGraph twoFamilies = _graph(
        unions: const [
          ..._unions,
          WreathUnion(familyId: 10, partners: [5], children: [3]),
        ],
      );
      expect(twoFamilies.of(3).fatherId, 1);
    },
  );

  test(
    'B2, AC-2, E1a — an exception at a son: he and his children take it, his father and sister keep theirs; '
    '"bez wieńca" the same; back to the father\'s clears it',
    () {
      final WreathGraph exception = _graph(
        choices: const {
          1: WreathChoice.clan(1),
          2: WreathChoice.clan(2),
          3: WreathChoice.clan(3),
          5: WreathChoice.clan(3),
        },
      );
      expect(
        (exception.of(3).own, exception.of(3).origin),
        (_p, WreathOrigin.chosenHere),
      );
      expect(exception.of(3).overridesFather, isTrue);
      expect(exception.of(6).own, _p);
      expect(exception.of(1).own, _w);
      expect(exception.of(4).own, _w);

      final WreathGraph none = _graph(
        choices: const {1: WreathChoice.clan(1), 3: WreathChoice.none()},
      );
      expect(
        (none.of(3).own, none.of(3).origin),
        (null, WreathOrigin.noneHere),
      );
      expect(none.of(3).overridesFather, isTrue);
      expect(none.of(7).own, isNull);

      // The father's own line chosen at the son is no exception.
      final WreathGraph same = _graph(
        choices: const {1: WreathChoice.clan(1), 3: WreathChoice.clan(1)},
      );
      expect(same.of(3).overridesFather, isFalse);
    },
  );

  test(
    'O1 — no father in the tree and nothing chosen: no wreath; a father without a line: none either',
    () {
      final WreathGraph g = _graph(choices: const {});
      expect(g.of(1).origin, WreathOrigin.noFather);
      expect(g.of(3).origin, WreathOrigin.fatherWithout);
      expect(g.of(3).isEmpty, isTrue);
    },
  );

  test('B7 — an ended marriage still gives her husband\'s half', () {
    // WreathUnion has no end: the graph never reads it, so an ended union is a married one like any other.
    final WreathGraph g = _graph();
    expect(g.of(2).husbandClan, _w);
  });

  test(
    'a loop in the tree (the app does not block one) gives no line, and does not hang',
    () {
      final WreathGraph loop = WreathGraph.of(
        sex: const {1: Sex.male, 2: Sex.male},
        choices: const {},
        unions: const [
          WreathUnion(familyId: 1, partners: [1], children: [2]),
          WreathUnion(familyId: 2, partners: [2], children: [1]),
        ],
        clans: _clans,
      );
      expect(loop.of(1).own, isNull);
      expect(loop.of(2).own, isNull);
      expect(loop.heirs(1), [2]);
    },
  );

  test(
    'heirs (E1, F5) — a generation at a time, along the fathers, without those with a choice of their own; '
    'countWith (E2, F5) — everyone with the line in either half',
    () {
      final WreathGraph g = _graph();
      expect(g.heirs(1), [3, 4, 6, 7]);
      expect(g.heirs(5), [9]);
      // Józef, Jan, Maria (left), Kasia, Tomek, Anna (right), Ewa (whole, B5).
      expect(g.countWith(1), 7);
      expect(g.countWith(2), 1);
      // Piotr, Zosia, Maria (right).
      expect(g.countWith(3), 3);

      final WreathGraph exception = _graph(
        choices: const {1: WreathChoice.clan(1), 3: WreathChoice.none()},
      );
      expect(exception.heirs(1), [4]);
    },
  );

  test(
    'a person not in the graph, and a choice of a line that is gone: no wreath, no error',
    () {
      final WreathGraph g = _graph(choices: const {1: WreathChoice.clan(99)});
      expect(g.of(42).isEmpty, isTrue);
      expect(g.of(1).own, isNull);
      expect(g.of(1).origin, WreathOrigin.noFather);
    },
  );
}
