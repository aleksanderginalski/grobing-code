import 'dart:io';

import 'package:drift/drift.dart';

import '../data/claims.dart';
import '../data/database.dart';
import '../data/families.dart';
import '../data/graves.dart';
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

    // The surname in the form that fits the made-up name, as in the tests — "Wymyślona" on the father read
    // as a declension error on the screens (ISSUE-021, D2). The model has no sex; a surname is just text.
    Future<int> person(String given, String surname, {String? birthSurname}) =>
        db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(
                givenNames: Value('$given $batch'),
                surname: Value(surname),
                birthSurname: Value(birthSurname),
                bio: const Value('Osoba wymyślona do testów.'),
                bioSource: const Value('dane testowe'),
              ),
            );

    final int father = await person('Ojciec', 'Wymyślony');
    final int mother = await person(
      'Matka',
      'Wymyślona',
      birthSurname: 'Zmyślona',
    );
    final int child = await person('Dziecko', 'Wymyślone');

    // Two unions of the father, each a family with its claims (ISSUE-019, ADR-011): the first with the
    // mother, ended by a parting; the second with a partner and a child buried nowhere — the author's
    // case at stop #1 ("rozstali się lub owdowieli i mieli nowe związki i dzieci").
    await saveFamily(
      db,
      FamilyDraft(
        partners: [ExistingMember(father), ExistingMember(mother)],
        children: [ExistingMember(child)],
        marriage: const QualifiedDate(DateQualifier.before, PartialDate(1920)),
        end: const QualifiedDate(DateQualifier.before, PartialDate(1924)),
      ),
    );
    final int second = await saveFamily(
      db,
      FamilyDraft(
        partners: [
          ExistingMember(father),
          NewMember(givenNames: 'Partnerka $batch', surname: 'Zmyślona'),
        ],
        children: [NewMember(givenNames: 'Dziecko z drugiego związku $batch')],
        marriage: const QualifiedDate(DateQualifier.exact, PartialDate(1925)),
      ),
    );
    final FamilyDetail secondFamily = (await loadFamily(db, second))!;

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
      // The second union's child has a birth year, so the children sort by birth (ISSUE-019 D4).
      (
        EventsCompanion.insert(
          type: EventType.birth,
          personId: Value(secondFamily.children.single.id),
          qualifier: const Value(DateQualifier.exact),
          year: const Value(1927),
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
    // one file, two links, his first and only one (ISSUE-017). Each link to the wedding photo has its own
    // crop on its own drawn head (ISSUE-018): the father's profile shows him, not the middle between
    // them, and the mother's crop shows if she makes it her profile.
    final int portrait = await db
        .into(db.media)
        .insert(MediaCompanion.insert(relativePath: portraitPath));
    final int wedding = await db
        .into(db.media)
        .insert(MediaCompanion.insert(relativePath: weddingPath));
    for (final (int person, int media, int position, int? cropLeft) in [
      (mother, portrait, 0, null),
      (mother, wedding, 1, _headCropLeft(0)),
      (father, wedding, 0, _headCropLeft(1)),
    ]) {
      await db
          .into(db.personMedia)
          .insert(
            PersonMediaCompanion.insert(
              personId: person,
              mediaId: media,
              position: position,
              cropLeft: Value(cropLeft),
              cropTop: Value(cropLeft == null ? null : _headCropTop),
              cropWidth: Value(cropLeft == null ? null : _headCropSide),
              cropHeight: Value(cropLeft == null ? null : _headCropSide),
            ),
          );
    }
  });
}

// A square around head [index] of the two on the drawn wedding photo (`fictionalPeoplePng`, 480 × 360,
// heads at a third and two thirds of the width, at 36 % of the height).
const int _headCropSide = 160;
const int _headCropTop = 50;
int _headCropLeft(int index) =>
    (480 * (index + 1) / 3).round() - _headCropSide ~/ 2;
