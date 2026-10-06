import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/home/pin_groups.dart';

// ISSUE-014 AC-2 + 05_DESIGN/cmentarze.md D8: candles whose 48 dp targets would overlap become one
// candle with a number, so no cemetery hides another.
void main() {
  test('two pins closer than 48 dp: one group of 2 at the first pin', () {
    final List<PinGroup> groups = groupPins([
      (id: 1, at: const Offset(100, 100)),
      (id: 2, at: const Offset(130, 120)),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.ids, [1, 2]);
    expect(groups.single.at, const Offset(100, 100));
  });

  test('two pins 48 dp apart or more: two candles', () {
    final List<PinGroup> groups = groupPins([
      (id: 1, at: const Offset(100, 100)),
      (id: 2, at: const Offset(148, 100)),
    ]);
    expect(groups.map((g) => g.ids), [
      [1],
      [2],
    ]);
  });

  test('greedy, in order: a chain A–B–C splits where C is far from A', () {
    final List<PinGroup> groups = groupPins([
      (id: 1, at: const Offset(0, 0)),
      (id: 2, at: const Offset(40, 0)),
      (id: 3, at: const Offset(80, 0)),
    ]);
    expect(groups.map((g) => g.ids), [
      [1, 2],
      [3],
    ]);
  });

  test('every pin lands in exactly one group', () {
    final List<ScreenPin> pins = [
      for (int i = 0; i < 20; i++)
        (id: i, at: Offset((i * 37) % 200, (i * 53) % 300)),
    ];
    final List<int> all = [for (final g in groupPins(pins)) ...g.ids]..sort();
    expect(all, [for (int i = 0; i < 20; i++) i]);
  });
}
