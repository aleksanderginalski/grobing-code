import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_labels.dart';

// ISSUE-033 D1 = I2 (05_DESIGN/drzewo.md v1.6 element 4; style-b.md rule 13 v1.25) — names that would overlap:
// the one nearer the person in the middle stays, first by level, then by the distance across.

LabelBox _box(int id, double x, {int level = 1, double? distance}) => LabelBox(
  id: id,
  centerX: x,
  top: 0,
  width: 60,
  height: 17,
  level: level,
  distance: distance ?? x.abs(),
);

void main() {
  test('names apart all stay', () {
    expect(visibleLabels([_box(1, 0), _box(2, 100), _box(3, 200)]), {1, 2, 3});
  });

  test(
    'of two overlapping, the lower level stays — the middle (−1) before everyone',
    () {
      expect(visibleLabels([_box(1, 0, level: 2), _box(2, 30, level: 1)]), {2});
      expect(visibleLabels([_box(1, 0, level: 1), _box(2, 30, level: -1)]), {
        2,
      });
    },
  );

  test('of the same level, the nearer across stays', () {
    expect(
      visibleLabels([
        _box(1, 100, distance: 100),
        _box(2, 130, distance: 130),
        _box(3, 160, distance: 160),
      ]),
      {1, 3},
    );
  });

  test('the gap counts: names that only touch with the gap hide too', () {
    expect(visibleLabels([_box(1, 0), _box(2, 62)]), {1, 2});
    expect(visibleLabels([_box(1, 0), _box(2, 62)], gap: 4), {1});
  });

  test('names in different rows never hide each other', () {
    const LabelBox below = LabelBox(
      id: 2,
      centerX: 0,
      top: 40,
      width: 60,
      height: 17,
      level: 2,
      distance: 0,
    );
    expect(visibleLabels([_box(1, 0), below]), {1, 2});
  });
}
