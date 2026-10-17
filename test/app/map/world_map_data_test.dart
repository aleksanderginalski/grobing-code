import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/map/world_map_data.dart';
import 'package:latlong2/latlong.dart';

// ISSUE-045 AC-4 — the world of the migration map is in the app (assets/map/world.json, Natural Earth 1:10m, rebuilt by
// tool/map/extract_world.dart; 05_DESIGN/mapa-migracji.md element 2, D1): it reads without the network, the countries
// have the codes the list of places keeps (`ISO_A2_EH` — France and Norway are `-99` in `ISO_A2`), Polish names and the
// point of the name — where a residence known only to its country stands (element 6, O3).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorldMapData world;

  setUpAll(() async {
    world = WorldMapData.fromJson(
      await rootBundle.loadString(WorldMapData.asset),
    );
  });

  test(
    'the whole world, simplified: about 180 countries, each with land; no Antarctica (Mercator has no pole)',
    () {
      expect(world.countries.length, inInclusiveRange(170, 200));
      expect(world.countries.every((c) => c.rings.isNotEmpty), isTrue);
      expect(
        world.countries.every((c) => c.rings.every((r) => r.length >= 4)),
        isTrue,
      );
      expect(world.byCode.containsKey('AQ'), isFalse);
      final int points = world.countries.fold(
        0,
        (n, c) => n + c.rings.fold(0, (m, r) => m + r.length),
      );
      // The measure of the plan (0.06°): about 35–38 thousand points — more would weigh on every frame of a gesture.
      expect(points, inInclusiveRange(30000, 40000));
    },
  );

  test(
    'the countries of the family\'s migrations: their codes and Polish names, France and Norway too (ISO_A2_EH)',
    () {
      for (final (String code, String name) in const [
        ('PL', 'Polska'),
        ('UA', 'Ukraina'),
        ('LT', 'Litwa'),
        ('DE', 'Niemcy'),
        ('FR', 'Francja'),
        ('NO', 'Norwegia'),
        ('GB', 'Wielka Brytania'),
        ('US', 'Stany Zjednoczone'),
      ]) {
        expect(world.byCode[code]?.name, name, reason: code);
      }
    },
  );

  test(
    'the point of the name: Natural Earth\'s label point, the one the list of places gives a country — inside its land',
    () {
      final LatLng lithuania = world.byCode['LT']!.label;
      expect(lithuania.latitude, closeTo(55.104, 0.001));
      expect(lithuania.longitude, closeTo(24.09, 0.001));
      final LatLng france = world.byCode['FR']!.label;
      // Europe, not an overseas department.
      expect(france.latitude, inInclusiveRange(42, 51));
      expect(france.longitude, inInclusiveRange(-5, 8));
    },
  );
}
