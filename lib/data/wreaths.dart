import 'clans.dart';
import 'database.dart' show Sex;

// Whose wreath is which (ISSUE-044, ADR-021; 05_DESIGN/wieniec.md B1–B7): worked out from the tree when it
// is read, never stored — only the choice at a person is (`clans.dart`). Pure: the tree (`family_tree.dart`)
// gives it the people and the unions it has read anyway, and the tests give it a family.

/// Where a person's own line comes from (wieniec.md E1 — the row's states).
enum WreathOrigin {
  /// A line chosen at this person: the top of a line, or an exception to the father's.
  chosenHere,

  /// "Bez wieńca" chosen at this person.
  noneHere,

  /// The father's line, with nothing chosen here.
  fromFather,

  /// The father is in the tree, but has no line.
  fatherWithout,

  /// No father in the tree and nothing chosen (O1).
  noFather,
}

/// A person's wreath: their own line (B2) on the left, a married woman's husband's on the right (B4), each
/// half filling the whole when the other is missing (B5).
class PersonWreath {
  const PersonWreath({
    this.own,
    required this.origin,
    this.fatherId,
    this.fatherClan,
    this.husbandId,
    this.husbandClan,
  });

  static const PersonWreath empty = PersonWreath(origin: WreathOrigin.noFather);

  /// The person's own line — the one their children get from them (B6).
  final Clan? own;
  final WreathOrigin origin;

  /// The father (B1), when the tree has one.
  final int? fatherId;

  /// The father's own line — what the wreath would be without a choice here ("Po ojcu byłoby: …").
  final Clan? fatherClan;

  /// A married woman's husband of the last marriage (B4), and his own line.
  final int? husbandId;
  final Clan? husbandClan;

  Clan? get left => own ?? husbandClan;
  Clan? get right => husbandClan ?? own;

  bool get isEmpty => left == null;

  /// Two lines in two halves (Ś3) — not when both halves are the same line.
  bool get isHalved => own != null && husbandClan != null && own != husbandClan;

  /// A choice here that differs from what the father would give (E1a: "Wróć do wieńca po ojcu").
  bool get overridesFather =>
      fatherClan != null &&
      (origin == WreathOrigin.noneHere ||
          (origin == WreathOrigin.chosenHere && own?.id != fatherClan!.id));
}

/// One union, as much of it as the wreaths need.
class WreathUnion {
  const WreathUnion({
    required this.familyId,
    required this.partners,
    required this.children,
    this.married = false,
    this.startKey,
  });

  final int familyId;
  final List<int> partners;
  final List<int> children;

  /// A wedding is written — only a marriage gives a woman her husband's half (B4: not "razem").
  final bool married;

  /// The union's start as a number that orders it (`TreeUnion.startKey`); null: no date.
  final int? startKey;
}

/// The wreaths of a whole family.
class WreathGraph {
  WreathGraph._({
    required Map<int, Sex?> sex,
    required Map<int, WreathChoice> choices,
    required Map<int, Clan> clans,
    required Map<int, int> fathers,
    required Map<int, List<int>> fatherOf,
    required Map<int, int> husbands,
  }) : _sex = sex,
       _choices = choices,
       _clans = clans,
       _fathers = fathers,
       _children = fatherOf,
       _husbands = husbands;

  /// [unions] in the order of their rows (the oldest family first): a child in several families of
  /// parents takes the first (B1).
  factory WreathGraph.of({
    required Map<int, Sex?> sex,
    required Map<int, WreathChoice> choices,
    required List<WreathUnion> unions,
    required Map<int, Clan> clans,
  }) {
    final Map<int, int> fathers = {};
    final Map<int, List<int>> fatherOf = {};
    for (final WreathUnion u in unions) {
      final int? father = u.partners
          .where((p) => sex[p] == Sex.male)
          .firstOrNull;
      if (father == null) continue;
      for (final int child in u.children) {
        if (fathers.containsKey(child) || child == father) continue;
        fathers[child] = father;
        (fatherOf[father] ??= []).add(child);
      }
    }

    // B4: the last marriage — the latest start, those without a date after them in the order written
    // (as the mini tree orders a person's unions).
    final List<WreathUnion> marriages = [
      for (final WreathUnion u in unions)
        if (u.married && u.partners.length == 2) u,
    ];
    int compare(WreathUnion a, WreathUnion b) {
      final int? ka = a.startKey, kb = b.startKey;
      if (ka != kb) {
        if (ka == null) return 1;
        if (kb == null) return -1;
        return ka.compareTo(kb);
      }
      return a.familyId.compareTo(b.familyId);
    }

    marriages.sort(compare);
    final Map<int, int> husbands = {};
    for (final WreathUnion u in marriages) {
      final int a = u.partners[0], b = u.partners[1];
      if (sex[a] == Sex.female && sex[b] == Sex.male) husbands[a] = b;
      if (sex[b] == Sex.female && sex[a] == Sex.male) husbands[b] = a;
    }
    return WreathGraph._(
      sex: sex,
      choices: choices,
      clans: clans,
      fathers: fathers,
      fatherOf: fatherOf,
      husbands: husbands,
    );
  }

  final Map<int, Sex?> _sex;
  final Map<int, WreathChoice> _choices;
  final Map<int, Clan> _clans;
  final Map<int, int> _fathers;
  final Map<int, List<int>> _children;
  final Map<int, int> _husbands;
  final Map<int, Clan?> _ownMemo = {};
  final Map<int, PersonWreath> _memo = {};

  Iterable<Clan> get clans => _clans.values;

  /// [personId]'s wreath (B1–B7).
  PersonWreath of(int personId) => _memo.putIfAbsent(personId, () {
    if (!_sex.containsKey(personId)) return PersonWreath.empty;
    final WreathChoice choice =
        _choices[personId] ?? const WreathChoice.inherit();
    final int? father = _fathers[personId];
    final Clan? fatherClan = father == null ? null : _own(father);
    final WreathOrigin origin;
    if (choice.clanId != null && _clans.containsKey(choice.clanId)) {
      origin = WreathOrigin.chosenHere;
    } else if (choice.none) {
      origin = WreathOrigin.noneHere;
    } else if (father == null) {
      origin = WreathOrigin.noFather;
    } else {
      origin = fatherClan == null
          ? WreathOrigin.fatherWithout
          : WreathOrigin.fromFather;
    }
    final int? husband = _sex[personId] == Sex.female
        ? _husbands[personId]
        : null;
    return PersonWreath(
      own: _own(personId),
      origin: origin,
      fatherId: father,
      fatherClan: fatherClan,
      husbandId: husband,
      husbandClan: husband == null ? null : _own(husband),
    );
  });

  /// Who gets [personId]'s line after them, along the fathers (wieniec.md E1, F5): their children with
  /// nothing chosen, theirs, and so on — a generation at a time.
  List<int> heirs(int personId) {
    final List<int> out = [];
    final Set<int> seen = {personId};
    List<int> level = [personId];
    while (level.isNotEmpty) {
      final List<int> next = [];
      for (final int p in level) {
        for (final int c in _children[p] ?? const <int>[]) {
          if (!seen.add(c)) continue;
          if (!(_choices[c] ?? const WreathChoice.inherit()).inherits) continue;
          out.add(c);
          next.add(c);
        }
      }
      level = next;
    }
    return out;
  }

  /// How many people have [clanId] in their wreath, in either half (wieniec.md E2, F5).
  int countWith(int clanId) {
    int n = 0;
    for (final int p in _sex.keys) {
      final PersonWreath w = of(p);
      if (w.left?.id == clanId || w.right?.id == clanId) n++;
    }
    return n;
  }

  /// B2: the line chosen here, none, or the father's — a loop in the tree (which the app does not block)
  /// gives none instead of hanging.
  Clan? _own(int personId) {
    if (_ownMemo.containsKey(personId)) return _ownMemo[personId];
    final List<int> chain = [];
    final Set<int> seen = {};
    Clan? found;
    int? p = personId;
    while (p != null) {
      if (_ownMemo.containsKey(p)) {
        found = _ownMemo[p];
        break;
      }
      if (!seen.add(p)) break; // a loop: none
      chain.add(p);
      final WreathChoice choice = _choices[p] ?? const WreathChoice.inherit();
      if (choice.clanId != null && _clans.containsKey(choice.clanId)) {
        found = _clans[choice.clanId];
        break;
      }
      if (choice.none) break;
      p = _fathers[p];
    }
    for (final int q in chain) {
      _ownMemo[q] = found;
    }
    return found;
  }
}
