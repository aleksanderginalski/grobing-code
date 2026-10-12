import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/person/mini_tree.dart';
import 'package:grobing/data/database.dart' show Sex;
import 'package:grobing/data/families.dart';

// ISSUE-024 AC-2 (osoba.md element 6, D12) — the mini tree's layout: the parents above the person, one
// partner on the right, two on both sides with the earlier on the left, each union's children under it
// and never sharing a bus, wider than the screen → scrolls with the person in the middle. Made-up people
// only (family-data.md).

FamilyMember _m(int id, String name, {Sex? sex}) =>
    FamilyMember(id: id, givenNames: name, surname: 'Wymyślony', sex: sex);

MiniTreeNode _node(MiniTreeLayout l, int id) =>
    l.nodes.firstWhere((n) => n.member.id == id);

void main() {
  const double label = 38;

  test(
    'one union: parents over the person, the husband on the right, the children under the pair',
    () {
      final MiniTreeLayout l = layoutMiniTree(
        person: _m(1, 'Maria', sex: Sex.female),
        parents: [
          _m(2, 'Józef', sex: Sex.male),
          _m(3, 'Zofia', sex: Sex.female),
        ],
        parentsMarried: true,
        unions: [
          PersonUnion(
            familyId: 1,
            partner: _m(4, 'Jan', sex: Sex.male),
            married: true,
            children: [_m(5, 'Anna'), _m(6, 'Stanisław'), _m(7, 'Zenon')],
          ),
        ],
        labelHeight: label,
        viewport: 360,
      );
      final MiniTreeNode maria = _node(l, 1);
      final MiniTreeNode jan = _node(l, 4);
      expect(maria.role, MiniRole.self);
      expect(jan.role, MiniRole.partner);
      expect(jan.married, isTrue);
      expect(miniRoleName(jan), 'Mąż');
      expect(miniRoleName(_node(l, 2)), 'Ojciec');
      expect(miniRoleName(_node(l, 3)), 'Matka');
      expect(jan.x, greaterThan(maria.x));
      expect(_node(l, 2).y, lessThan(maria.y));
      final double pairMiddle = (maria.x + jan.x) / 2;
      final List<double> kids = [
        for (final int id in [5, 6, 7]) _node(l, id).x,
      ];
      expect(kids, orderedEquals([...kids]..sort()));
      expect((kids.first + kids.last) / 2, closeTo(pairMiddle, 0.01));
      expect(_node(l, 5).y, greaterThan(maria.y));
      expect(l.width, 360); // fits — centred, no scrolling
      // Lines: the parents' pair solid, the person's pair solid, parent–child stepped.
      expect(
        l.lines.where((x) => x.kind == MiniLineKind.married),
        hasLength(2),
      );
      expect(l.lines.where((x) => x.kind == MiniLineKind.together), isEmpty);
    },
  );

  test(
    'two unions: the earlier on the left ("razem" — dashed), the later on the right; each group of '
    'children under its union, the left ending before the person and the right starting after',
    () {
      final MiniTreeLayout l = layoutMiniTree(
        person: _m(1, 'Stefan', sex: Sex.male),
        parents: const [],
        unions: [
          PersonUnion(
            familyId: 1,
            partner: _m(2, 'Helena', sex: Sex.female),
            children: [_m(3, 'Kazimierz'), _m(4, 'Teresa'), _m(5, 'Henryk')],
          ),
          PersonUnion(
            familyId: 2,
            partner: _m(6, 'Irena', sex: Sex.female),
            married: true,
            children: [
              _m(7, 'Barbara'),
              _m(8, 'Leszek'),
              _m(9, 'Danuta'),
              _m(10, 'Marek'),
            ],
          ),
        ],
        labelHeight: label,
        viewport: 360,
      );
      final double stefan = _node(l, 1).x;
      expect(_node(l, 2).x, lessThan(stefan));
      expect(_node(l, 6).x, greaterThan(stefan));
      expect(miniRoleName(_node(l, 2)), 'Partnerka');
      expect(miniRoleName(_node(l, 6)), 'Żona');
      expect(_node(l, 5).x, lessThan(stefan)); // the left group's last
      expect(_node(l, 7).x, greaterThan(stefan)); // the right group's first
      expect(
        l.lines.where((x) => x.kind == MiniLineKind.together),
        hasLength(1),
      );
      // Seven children don't fit in 360 dp: the tree scrolls, and starts with Stefan in the middle.
      expect(l.width, greaterThan(360));
      expect(l.focusX, stefan);
    },
  );

  test(
    'a family of one parent: the children under the person; nobody — just the person',
    () {
      final MiniTreeLayout one = layoutMiniTree(
        person: _m(1, 'Ewa'),
        parents: [_m(2, 'Anna')],
        unions: [
          PersonUnion(familyId: 1, children: [_m(3, 'Robin')]),
        ],
        labelHeight: label,
        viewport: 360,
      );
      expect(_node(one, 3).x, closeTo(_node(one, 1).x, 0.01));
      expect(_node(one, 2).x, closeTo(_node(one, 1).x, 0.01));
      expect(miniRoleName(_node(one, 2)), 'Rodzic');
      expect(miniRoleName(_node(one, 3)), 'Dziecko');

      final MiniTreeLayout alone = layoutMiniTree(
        person: _m(1, 'Ewa'),
        parents: const [],
        unions: const [],
        labelHeight: label,
        viewport: 360,
      );
      expect(alone.nodes, hasLength(1));
      expect(alone.lines, isEmpty);
    },
  );
}
