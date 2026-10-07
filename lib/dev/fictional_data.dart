import 'dart:io';

import 'package:drift/drift.dart';

import '../data/claims.dart';
import '../data/database.dart';
import 'fictional_photo.dart';

/// Adds one batch of **made-up** people, families and graves (family-data.md: never real data in the
/// repo). Called only behind `kDebugMode` (ISSUE-007 D3), so the release build that one day runs on
/// the phone with the family's data does not contain it. Every call adds a new numbered batch.
Future<void> addFictionalData(GrobingDatabase db, Directory mediaDir) async {
  final int batch =
      (await db.select(db.cemeteries).get()).length + 1; // numbers the names

  // A made-up point in Poland for the map of ISSUE-014 (05_DESIGN/cmentarze.md D15): batches 1 and 2
  // a few hundred metres apart, so they share one candle with a number; every third batch without a
  // point, so only the search finds it. Round, invented coordinates — no real cemetery is meant.
  final ({double lat, double lon})? point = switch (batch) {
    _ when batch % 3 == 0 => null,
    1 => (lat: 51.0, lon: 20.0),
    2 => (lat: 51.002, lon: 20.003),
    _ => (lat: 50.0 + (batch % 5) * 0.5, lon: 17.0 + (batch % 7) * 0.8),
  };

  // Made-up pictures drawn in code — a gravestone (ISSUE-016), a portrait and a "wedding photo"
  // (ISSUE-017). Drawn and written before the transaction, so it stays as short as a real write: the
  // claim helpers' nested transactions report their tables at once, and a long transaction after them
  // spreads one batch into more backup requests (background_backup_test). A file before its row is the
  // order photos.dart keeps too (D3); the sweep takes only files older than an hour.
  Future<String> picture(String name, Uint8List png) async {
    final String path = 'wymyslone/$name-$batch.png';
    final File file = File('${mediaDir.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png, flush: true);
    return path;
  }

  final String gravestone = await picture(
    'nagrobek',
    fictionalGravestonePng(batch),
  );
  final String portraitPath = await picture(
    'portret',
    fictionalPeoplePng(batch, heads: 1),
  );
  final String weddingPath = await picture(
    'slub',
    fictionalPeoplePng(batch, heads: 2),
  );

  await db.transaction(() async {
    final int cemetery = await db
        .into(db.cemeteries)
        .insert(
          CemeteriesCompanion.insert(
            name: 'Cmentarz Wymyślony $batch',
            locality: const Value('Miejscowość Testowa'),
            centerLat: Value(point?.lat),
            centerLon: Value(point?.lon),
          ),
        );
    // One grave with a name and one without, so the grave screens show both (ISSUE-012).
    final int grave = await db
        .into(db.graves)
        .insert(
          GravesCompanion.insert(
            cemeteryId: cemetery,
            name: const Value('Grób rodzinny Wymyślonych'),
          ),
        );
    final int graveWithAddress = await db
        .into(db.graves)
        .insert(
          GravesCompanion.insert(
            cemeteryId: cemetery,
            sector: const Value('B'),
            row: const Value('3'),
            plot: const Value('12'),
          ),
        );

    Future<int> person(String given, {String? birthSurname}) => db
        .into(db.persons)
        .insert(
          PersonsCompanion.insert(
            givenNames: Value('$given $batch'),
            surname: const Value('Wymyślona'),
            birthSurname: Value(birthSurname),
            bio: const Value('Osoba wymyślona do testów.'),
            bioSource: const Value('dane testowe'),
          ),
        );

    final int father = await person('Ojciec');
    final int mother = await person('Matka', birthSurname: 'Zmyślona');
    final int child = await person('Dziecko');

    final int family = await db
        .into(db.families)
        .insert(FamiliesCompanion.insert());
    for (final int partner in [father, mother]) {
      await db
          .into(db.familyPartners)
          .insert(
            FamilyPartnersCompanion.insert(familyId: family, personId: partner),
          );
    }
    await db
        .into(db.familyChildren)
        .insert(
          FamilyChildrenCompanion.insert(familyId: family, personId: child),
        );

    // A made-up dispute (US-004 AC-1): the notes and the grandmother give the father different birth
    // years. Both claims stay, both contradicted; the notes' row, written first, is the one shown.
    const ClaimSource notesDisputed = ClaimSource(
      status: AssertionStatus.contradicted,
    );
    const ClaimSource grandmotherDisputed = ClaimSource(
      kind: SourceKind.grandmother,
      status: AssertionStatus.contradicted,
    );
    final List<(EventsCompanion, ClaimSource)> events = [
      (
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(father),
          qualifier: const Value(DateQualifier.about),
          year: const Value(1890),
        ),
        notesDisputed,
      ),
      (
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(father),
          qualifier: const Value(DateQualifier.exact),
          year: const Value(1892),
        ),
        grandmotherDisputed,
      ),
      (
        EventsCompanion.insert(
          type: EventType.death,
          personId: Value(father),
          qualifier: const Value(DateQualifier.exact),
          year: const Value(1951),
          month: const Value(3),
          day: const Value(14),
        ),
        const ClaimSource(),
      ),
      (
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(mother),
          qualifier: const Value(DateQualifier.between),
          year: const Value(1893),
          yearTo: const Value(1895),
        ),
        const ClaimSource(),
      ),
      (
        EventsCompanion.insert(
          type: EventType.marriage,
          familyId: Value(family),
          qualifier: const Value(DateQualifier.before),
          year: const Value(1920),
        ),
        const ClaimSource(),
      ),
    ];
    for (final (EventsCompanion event, ClaimSource source) in events) {
      await addEventWithClaim(db, event, source: source);
    }
    for (final (int person, int inGrave) in [
      (father, grave),
      (mother, grave),
      (child, graveWithAddress),
    ]) {
      await addBurialWithClaim(db, personId: person, graveId: inGrave);
    }

    // The grave view shows the gravestone, and the media part of the fingerprint is exercised.
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            relativePath: gravestone,
            graveId: Value(grave),
          ),
        );

    // The mother has a portrait (her profile photo) and a "wedding photo" she shares with the father —
    // one file, two links, his first and only one (ISSUE-017).
    final int portrait = await db
        .into(db.media)
        .insert(MediaCompanion.insert(relativePath: portraitPath));
    final int wedding = await db
        .into(db.media)
        .insert(MediaCompanion.insert(relativePath: weddingPath));
    for (final (int person, int media, int position) in [
      (mother, portrait, 0),
      (mother, wedding, 1),
      (father, wedding, 0),
    ]) {
      await db
          .into(db.personMedia)
          .insert(
            PersonMediaCompanion.insert(
              personId: person,
              mediaId: media,
              position: position,
            ),
          );
    }
  });
}
