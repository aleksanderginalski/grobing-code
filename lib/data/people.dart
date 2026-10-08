import 'package:drift/drift.dart';

import 'database.dart';
import 'graves.dart' show QualifiedDate, watchTables;
import 'photos.dart' show ProfilePhoto, profilePhotos;

/// One person in the list of the Osoby tab (05_DESIGN/osoby.md, element 4) and of the choice of "ja".
class PersonListEntry {
  const PersonListEntry({
    required this.id,
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.birth,
    this.death,
    this.profile,
  });

  final int id;
  final String? givenNames;
  final String? surname;
  final String? birthSurname;
  final QualifiedDate? birth;
  final QualifiedDate? death;

  /// The first photo link (ISSUE-017) with its crop (ISSUE-018); null without a photo.
  final ProfilePhoto? profile;
}

/// Everyone in the app, in no order — Polish ordering is the screen's (`polish.dart`). Birth and death
/// are the first event of each type written, as every screen shows them (ADR-006 D3).
Future<List<PersonListEntry>> loadPeople(GrobingDatabase db) async {
  final List<Person> persons = await db.select(db.persons).get();
  final Map<(int, EventType), QualifiedDate?> first = {};
  for (final Event e
      in await (db.select(db.events)
            ..where(
              (e) =>
                  e.personId.isNotNull() &
                  e.type.isInValues(const [EventType.birth, EventType.death]),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get()) {
    first.putIfAbsent((e.personId!, e.type), () => QualifiedDate.ofEvent(e));
  }
  final Map<int, ProfilePhoto> profiles = await profilePhotos(db, [
    for (final Person p in persons) p.id,
  ]);
  return [
    for (final Person p in persons)
      PersonListEntry(
        id: p.id,
        givenNames: p.givenNames,
        surname: p.surname,
        birthSurname: p.birthSurname,
        birth: first[(p.id, EventType.birth)],
        death: first[(p.id, EventType.death)],
        profile: profiles[p.id],
      ),
  ];
}

/// [loadPeople], again after every write to what it reads.
Stream<List<PersonListEntry>> watchPeople(GrobingDatabase db) => watchTables(
  db,
  'people',
  {db.persons, db.events, db.personMedia, db.media},
  () => loadPeople(db),
);

/// Who "ja" is — the author, the anchor of "how they connect to me" (data-model.md, Setting "ja");
/// null until chosen.
Stream<int?> watchMe(GrobingDatabase db) => (db.select(
  db.settings,
)..where((s) => s.id.equals(1))).watchSingleOrNull().map((s) => s?.mePersonId);

/// Makes [personId] "ja". The settings are one row (`id = 1`), written the first time here.
Future<void> setMe(GrobingDatabase db, int personId) => db
    .into(db.settings)
    .insertOnConflictUpdate(
      SettingsCompanion(id: const Value(1), mePersonId: Value(personId)),
    );
