import 'package:drift/drift.dart';

import 'claims.dart';
import 'database.dart';
import 'photos.dart';

// Graves and the people buried in them, as the transcription screens show and write them
// (ISSUE-012; 05_DESIGN/cmentarz.md, grob.md, wpis-osoby.md). Writes go through drift's own API, so
// they notify `tableUpdates` and ask for a background backup (ISSUE-010).

/// A year, optionally with a month and a day: "1890", "03.1951", "14.03.1951" (FR-004).
class PartialDate {
  const PartialDate(this.year, [this.month, this.day])
    : assert(day == null || month != null);

  final int year;
  final int? month;
  final int? day;

  @override
  bool operator ==(Object other) =>
      other is PartialDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'PartialDate($year, $month, $day)';
}

/// A date with its qualifier (FR-004): exact, about, before, after — or between [from] and [to].
class QualifiedDate {
  const QualifiedDate(this.qualifier, this.from, [this.to]);

  final DateQualifier qualifier;
  final PartialDate from;

  /// The second bound, only for [DateQualifier.between].
  final PartialDate? to;

  /// The date an event row holds; null when it has none.
  static QualifiedDate? ofEvent(Event e) {
    if (e.year == null) return null;
    return QualifiedDate(
      e.qualifier ?? DateQualifier.exact,
      PartialDate(e.year!, e.month, e.day),
      e.yearTo == null ? null : PartialDate(e.yearTo!, e.monthTo, e.dayTo),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QualifiedDate &&
      other.qualifier == qualifier &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(qualifier, from, to);
}

/// One person as the form writes them (05_DESIGN/wpis-osoby.md). Blank texts are stored as none.
class PersonEntry {
  const PersonEntry({
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.bio,
    this.bioSource,
    this.birth,
    this.death,
    this.burial,
  });

  final String? givenNames;
  final String? surname;

  /// FR-005: the surname at birth.
  final String? birthSurname;

  /// "Kim była" — a short biography, with one source line for the whole text (FR-001).
  final String? bio;
  final String? bioSource;
  final QualifiedDate? birth;
  final QualifiedDate? death;

  /// The date of the burial — an event, not a property of the burial row (FR-003).
  final QualifiedDate? burial;
}

/// The source line "kim była" gets unless the user changes it (05_DESIGN/wpis-osoby.md, element 9).
const String defaultBioSource = 'notatki';

/// One grave on the cemetery screen (05_DESIGN/cmentarz.md, element 3).
class GraveSummary {
  const GraveSummary({
    required this.id,
    this.name,
    this.sector,
    this.row,
    this.plot,
    required this.hasPin,
    required this.people,
    this.photoPath,
  });

  final int id;
  final String? name;
  final String? sector;
  final String? row;
  final String? plot;
  final bool hasPin;

  /// The grave's photo, relative to the media directory (05_DESIGN/cmentarz.md, element 3 (d)).
  final String? photoPath;

  /// The people buried here, in the order they were entered.
  final List<({int id, String? givenNames, String? surname})> people;
}

/// The cemetery screen: the cemetery and its graves in the order they were entered.
class CemeteryGraves {
  const CemeteryGraves({
    required this.id,
    required this.name,
    this.locality,
    required this.graves,
  });

  final int id;
  final String name;
  final String? locality;
  final List<GraveSummary> graves;

  /// Distinct people with a burial here: someone whose sources disagree on the grave counts once
  /// (05_DESIGN/cmentarze.md D13).
  int get personCount => {
    for (final GraveSummary g in graves)
      for (final p in g.people) p.id,
  }.length;
}

/// The date of one kind (birth, death, burial) shown for a person, and how many claims back that kind
/// of fact in all — more than one means another source spoke too (a dispute or a confirmation), and
/// the correction form leaves it alone (ISSUE-012 D1).
class DatedFact {
  const DatedFact({required this.date, required this.claimCount});

  final QualifiedDate? date;
  final int claimCount;

  bool get correctable => claimCount <= 1;
}

/// One person in the grave view (05_DESIGN/grob.md, element 5).
class BuriedPerson {
  const BuriedPerson({
    required this.id,
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.bio,
    this.bioSource,
    required this.birth,
    required this.death,
    required this.burial,
  });

  final int id;
  final String? givenNames;
  final String? surname;
  final String? birthSurname;
  final String? bio;
  final String? bioSource;
  final DatedFact birth;
  final DatedFact death;
  final DatedFact burial;

  /// What the correction form starts from.
  PersonEntry get entry => PersonEntry(
    givenNames: givenNames,
    surname: surname,
    birthSurname: birthSurname,
    bio: bio,
    bioSource: bioSource,
    birth: birth.date,
    death: death.date,
    burial: burial.date,
  );
}

/// The grave view: the grave, its cemetery and everyone buried in it, in the order entered.
class GraveDetail {
  const GraveDetail({
    required this.id,
    required this.cemeteryId,
    required this.cemeteryName,
    this.cemeteryLocality,
    this.name,
    this.sector,
    this.row,
    this.plot,
    required this.hasPin,
    required this.people,
    this.photoPath,
  });

  final int id;
  final int cemeteryId;
  final String cemeteryName;
  final String? cemeteryLocality;
  final String? name;
  final String? sector;
  final String? row;
  final String? plot;
  final bool hasPin;
  final List<BuriedPerson> people;

  /// The grave's only photo, relative to the media directory (05_DESIGN/grob.md, element 1a).
  final String? photoPath;
}

/// A new value after every write to a table the view reads. drift re-runs a watched query when any
/// table in its `readsFrom` changes; the view itself is loaded with typed queries.
Stream<T> _watch<T>(
  GrobingDatabase db,
  Set<ResultSetImplementation<dynamic, dynamic>> tables,
  Future<T> Function() load,
) => db
    .customSelect('SELECT 1', readsFrom: tables)
    .watch()
    .asyncMap((_) => load());

/// The cemetery and its graves; null when there is no such cemetery.
Stream<CemeteryGraves?> watchCemeteryGraves(
  GrobingDatabase db,
  int cemeteryId,
) => _watch(db, {
  db.cemeteries,
  db.graves,
  db.burials,
  db.persons,
  db.media,
}, () => loadCemeteryGraves(db, cemeteryId));

Future<CemeteryGraves?> loadCemeteryGraves(
  GrobingDatabase db,
  int cemeteryId,
) async {
  final Cemetery? cemetery = await (db.select(
    db.cemeteries,
  )..where((c) => c.id.equals(cemeteryId))).getSingleOrNull();
  if (cemetery == null) return null;
  final List<Grave> graves =
      await (db.select(db.graves)
            ..where((g) => g.cemeteryId.equals(cemeteryId))
            ..orderBy([(g) => OrderingTerm.asc(g.id)]))
          .get();
  final List<TypedResult> buried =
      await (db.select(db.burials).join([
              innerJoin(
                db.persons,
                db.persons.id.equalsExp(db.burials.personId),
              ),
              innerJoin(db.graves, db.graves.id.equalsExp(db.burials.graveId)),
            ])
            ..where(db.graves.cemeteryId.equals(cemeteryId))
            ..orderBy([OrderingTerm.asc(db.burials.id)]))
          .get();
  // The first photo of each grave — the lowest id (photos.dart → gravePhotoPath).
  final Map<int, String> photos = {};
  for (final MediaFile m
      in await (db.select(db.media)
            ..where(
              (m) => m.graveId.isInQuery(
                db.selectOnly(db.graves)
                  ..addColumns([db.graves.id])
                  ..where(db.graves.cemeteryId.equals(cemeteryId)),
              ),
            )
            ..orderBy([(m) => OrderingTerm.asc(m.id)]))
          .get()) {
    photos.putIfAbsent(m.graveId!, () => m.relativePath);
  }
  final Map<int, List<({int id, String? givenNames, String? surname})>> people =
      {};
  for (final TypedResult r in buried) {
    final Person p = r.readTable(db.persons);
    people.putIfAbsent(r.readTable(db.burials).graveId, () => []).add((
      id: p.id,
      givenNames: p.givenNames,
      surname: p.surname,
    ));
  }
  return CemeteryGraves(
    id: cemetery.id,
    name: cemetery.name,
    locality: cemetery.locality,
    graves: [
      for (final Grave g in graves)
        GraveSummary(
          id: g.id,
          name: g.name,
          sector: g.sector,
          row: g.row,
          plot: g.plot,
          hasPin: g.lat != null && g.lon != null,
          people: people[g.id] ?? const [],
          photoPath: photos[g.id],
        ),
    ],
  );
}

/// The grave with its cemetery and people; null when there is no such grave.
Stream<GraveDetail?> watchGrave(GrobingDatabase db, int graveId) => _watch(db, {
  db.cemeteries,
  db.graves,
  db.burials,
  db.persons,
  db.events,
  db.assertions,
  db.media,
}, () => loadGrave(db, graveId));

Future<GraveDetail?> loadGrave(GrobingDatabase db, int graveId) async {
  final TypedResult? row = await (db.select(db.graves).join([
    innerJoin(db.cemeteries, db.cemeteries.id.equalsExp(db.graves.cemeteryId)),
  ])..where(db.graves.id.equals(graveId))).getSingleOrNull();
  if (row == null) return null;
  final Grave grave = row.readTable(db.graves);
  final Cemetery cemetery = row.readTable(db.cemeteries);
  final List<Person> persons =
      await (db.select(db.burials).join([
              innerJoin(
                db.persons,
                db.persons.id.equalsExp(db.burials.personId),
              ),
            ])
            ..where(db.burials.graveId.equals(graveId))
            ..orderBy([OrderingTerm.asc(db.burials.id)]))
          .map((r) => r.readTable(db.persons))
          .get();
  return GraveDetail(
    id: grave.id,
    cemeteryId: cemetery.id,
    cemeteryName: cemetery.name,
    cemeteryLocality: cemetery.locality,
    name: grave.name,
    sector: grave.sector,
    row: grave.row,
    plot: grave.plot,
    hasPin: grave.lat != null && grave.lon != null,
    people: [
      for (final Person p in persons)
        BuriedPerson(
          id: p.id,
          givenNames: p.givenNames,
          surname: p.surname,
          birthSurname: p.birthSurname,
          bio: p.bio,
          bioSource: p.bioSource,
          birth: await _fact(db, p.id, EventType.birth),
          death: await _fact(db, p.id, EventType.death),
          burial: await _fact(db, p.id, EventType.burial),
        ),
    ],
    photoPath: await gravePhotoPath(db, graveId),
  );
}

/// The [type] date of [personId] to show — the first event written (ADR-006 D3) — and the number of
/// claims on all its events of that type.
Future<DatedFact> _fact(
  GrobingDatabase db,
  int personId,
  EventType type,
) async {
  final Event? first = await firstEvent(db, personId: personId, type: type);
  final Expression<int> count = db.assertions.id.count();
  final int claims =
      await (db.selectOnly(db.assertions).join([
              innerJoin(
                db.events,
                db.events.id.equalsExp(db.assertions.eventId),
              ),
            ])
            ..addColumns([count])
            ..where(
              db.events.personId.equals(personId) &
                  db.events.type.equalsValue(type),
            ))
          .map((r) => r.read(count)!)
          .getSingle();
  return DatedFact(
    date: first == null ? null : QualifiedDate.ofEvent(first),
    claimCount: claims,
  );
}

/// Writes [entry] as the first person of a new grave on [cemeteryId]; returns the grave's id. The
/// grave, the person, the burial and the dates — each fact with its claim from the notes — are written
/// together or not at all (05_DESIGN/wpis-osoby.md: no "half a person").
Future<int> addPersonToNewGrave(
  GrobingDatabase db, {
  required int cemeteryId,
  required PersonEntry entry,
  DateTime Function()? clock,
}) => db.transaction(() async {
  final int grave = await db
      .into(db.graves)
      .insert(GravesCompanion.insert(cemeteryId: cemeteryId));
  await _addPerson(db, grave, entry, clock);
  return grave;
});

/// Writes [entry] as one more person in [graveId]; returns the person's id. All or nothing, as
/// [addPersonToNewGrave].
Future<int> addPersonToGrave(
  GrobingDatabase db, {
  required int graveId,
  required PersonEntry entry,
  DateTime Function()? clock,
}) => db.transaction(() => _addPerson(db, graveId, entry, clock));

Future<int> _addPerson(
  GrobingDatabase db,
  int graveId,
  PersonEntry entry,
  DateTime Function()? clock,
) async {
  _requireName(entry);
  final int person = await db
      .into(db.persons)
      .insert(
        PersonsCompanion.insert(
          givenNames: Value(_text(entry.givenNames)),
          surname: Value(_text(entry.surname)),
          birthSurname: Value(_text(entry.birthSurname)),
          bio: Value(_text(entry.bio)),
          bioSource: Value(_bioSource(entry)),
        ),
      );
  // Nested transactions on NativeDatabase (drift ≥ 2.0): the claim helpers' own transactions commit
  // only with this one.
  await addBurialWithClaim(
    db,
    personId: person,
    graveId: graveId,
    clock: clock,
  );
  for (final (EventType type, QualifiedDate? date) in _dates(entry)) {
    if (date != null) {
      await addEventWithClaim(db, _event(type, person, date), clock: clock);
    }
  }
  return person;
}

/// Corrects [personId] in place (ISSUE-012 D1): a typo made while transcribing is an error of the same
/// source, not a second source, so the values change in their rows and the claims stay. A date backed
/// by more than one claim (another source spoke too) never changes here, whatever [entry] says. A
/// cleared date goes, with its only claim.
Future<void> updatePersonEntry(
  GrobingDatabase db,
  int personId,
  PersonEntry entry,
) => db.transaction(() async {
  _requireName(entry);
  final int updated =
      await (db.update(db.persons)..where((p) => p.id.equals(personId))).write(
        PersonsCompanion(
          givenNames: Value(_text(entry.givenNames)),
          surname: Value(_text(entry.surname)),
          birthSurname: Value(_text(entry.birthSurname)),
          bio: Value(_text(entry.bio)),
          bioSource: Value(_bioSource(entry)),
        ),
      );
  if (updated != 1) throw StateError('No person with id $personId');
  for (final (EventType type, QualifiedDate? date) in _dates(entry)) {
    if (!(await _fact(db, personId, type)).correctable) continue;
    final Event? existing = await firstEvent(
      db,
      personId: personId,
      type: type,
    );
    if (existing == null) {
      if (date != null) {
        await addEventWithClaim(db, _event(type, personId, date));
      }
    } else if (date == null) {
      await (db.delete(
        db.assertions,
      )..where((a) => a.eventId.equals(existing.id))).go();
      await (db.delete(db.events)..where((e) => e.id.equals(existing.id))).go();
    } else if (QualifiedDate.ofEvent(existing) != date) {
      await (db.update(
        db.events,
      )..where((e) => e.id.equals(existing.id))).write(_dateValues(date));
    }
  }
});

/// Names the grave, or — for a blank [name] — takes its name away (05_DESIGN/grob.md, element 3a).
Future<void> setGraveName(GrobingDatabase db, int graveId, String? name) async {
  final int updated =
      await (db.update(db.graves)..where((g) => g.id.equals(graveId))).write(
        GravesCompanion(name: Value(_text(name))),
      );
  if (updated != 1) throw StateError('No grave with id $graveId');
}

List<(EventType, QualifiedDate?)> _dates(PersonEntry entry) => [
  (EventType.birth, entry.birth),
  (EventType.death, entry.death),
  (EventType.burial, entry.burial),
];

EventsCompanion _event(EventType type, int personId, QualifiedDate date) =>
    _dateValues(date).copyWith(type: Value(type), personId: Value(personId));

EventsCompanion _dateValues(QualifiedDate date) {
  final bool between = date.qualifier == DateQualifier.between;
  if (between != (date.to != null)) {
    throw ArgumentError.value(
      date.qualifier,
      'date',
      'a second bound goes with "between" and only with it',
    );
  }
  return EventsCompanion(
    qualifier: Value(date.qualifier),
    year: Value(date.from.year),
    month: Value(date.from.month),
    day: Value(date.from.day),
    yearTo: Value(date.to?.year),
    monthTo: Value(date.to?.month),
    dayTo: Value(date.to?.day),
  );
}

void _requireName(PersonEntry entry) {
  if (_text(entry.givenNames) == null && _text(entry.surname) == null) {
    throw ArgumentError('A person needs given names or a surname');
  }
}

/// The source line of "kim była": none without a text, the notes unless said otherwise (FR-001).
String? _bioSource(PersonEntry entry) {
  if (_text(entry.bio) == null) return null;
  return _text(entry.bioSource) ?? defaultBioSource;
}

String? _text(String? s) {
  final String? trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
