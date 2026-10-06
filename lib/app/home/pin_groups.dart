import 'dart:ui';

/// A pin to place, at its position on the screen.
typedef ScreenPin = ({int id, Offset at});

/// One candle on the map: a cemetery, or several whose pins would cover each other.
class PinGroup {
  const PinGroup(this.ids, this.at);

  /// The cemeteries in the group, the first one is where the candle stands.
  final List<int> ids;
  final Offset at;
}

/// Groups [pins] whose tap targets would overlap: two pins closer than [distance] (the 48 dp target,
/// style-b.md) become one candle with a number (05_DESIGN/cmentarze.md D8). Greedy, in the order given:
/// each pin not yet in a group starts one and takes every free pin closer than [distance] to it. The
/// whole of Poland is ~700 km on ~330 dp, so at the start a target covers ~100 km.
List<PinGroup> groupPins(List<ScreenPin> pins, {double distance = 48}) {
  final List<PinGroup> groups = [];
  final Set<int> taken = {};
  for (final ScreenPin seed in pins) {
    if (taken.contains(seed.id)) continue;
    final List<int> ids = [seed.id];
    taken.add(seed.id);
    for (final ScreenPin other in pins) {
      if (taken.contains(other.id)) continue;
      if ((other.at - seed.at).distance < distance) {
        ids.add(other.id);
        taken.add(other.id);
      }
    }
    groups.add(PinGroup(ids, seed.at));
  }
  return groups;
}
