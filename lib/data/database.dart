import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'database.steps.dart';

part 'database.g.dart';

// Schema v7 — grobing-vault/04_ARCHITECTURE/data-model.md: v1 (ISSUE-007), Assertion (ISSUE-011,
// ADR-006), the grave's name (ISSUE-012), people's photos as links (ISSUE-017), their crop (ISSUE-018),
// claims on families and children's links (ISSUE-019) and a person's sex with the start of a union
// (ISSUE-025), still without the grave fee (S4) and the cemetery offline-map status (SPIKE-001). Enums are
// stored by name, not index: data lives for decades and a reordered enum must not silently change
// meaning. Renaming an enum value is a schema change and needs a migration; a new value at the end is not.

/// A family's events — `marriage`, `end` and `together` — and a person's. `together` is the start of a
/// union before or without a wedding ("Razem od", ISSUE-025): GEDCOM 7 has no tag for it, so an export
/// writes it as `EVEN` with a `TYPE`. A `marriage` with no date says the wedding happened, date unknown
/// (GEDCOM 7's `MARR Y`: "the event is known to have occurred").
enum EventType { birth, death, burial, marriage, end, together }

/// GEDCOM 7's `SEX` at birth: `F` and `M`. None written is `U` — "cannot be determined from available
/// sources" (ISSUE-025; ISSUE-019 D2). `X` has no case in the notes; as a new value at the end it would
/// need no migration.
enum Sex { female, male }

/// FR-004: a date is a value plus a qualifier; `between` uses both bounds.
enum DateQualifier { exact, about, before, after, between }

/// How a grave position was obtained (glossary: pinezka carries its source).
enum PositionSource { satellite, gps }

/// FR-001: where a claim comes from — nagrobek · notatki · babcia · krewny · akt.
enum SourceKind { gravestone, notes, grandmother, relative, record }

/// FR-001: how strong a claim is, not whether it is true. `contradicted` is a result, never deleted.
enum AssertionStatus { claimed, confirmed, contradicted, unknown }

class Persons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get givenNames => text().nullable()();
  TextColumn get surname => text().nullable()();

  /// FR-005: surname at birth, next to the married one.
  TextColumn get birthSurname => text().nullable()();

  /// Null: not known (ISSUE-025). The form suggests it from the given names, never the database.
  TextColumn get sex => textEnum<Sex>().nullable()();

  /// "Kim była" — free text with one source line for the whole text (FR-001 cost decision).
  TextColumn get bio => text().nullable()();
  TextColumn get bioSource => text().nullable()();
  BoolColumn get isLiving => boolean().withDefault(const Constant(false))();
}

/// FR-002: a family is a record of 1-2 partners and children — a union, married or not, with its own
/// start (marriage) and end events. A person in several unions is in several families. The rules of
/// who may be in one (1–2 partners, at least two people, a child in one family of parents) are kept
/// where families are written (`families.dart`, ISSUE-019), not here.
class Families extends Table {
  IntColumn get id => integer().autoIncrement()();
}

/// A partner in a family. The source of the union is a claim on the family itself — GEDCOM 7 cites the
/// `FAM` record, never `HUSB` or `WIFE` (ADR-011): the pair is one fact, not two.
class FamilyPartners extends Table {
  IntColumn get familyId => integer().references(Families, #id)();
  IntColumn get personId => integer().references(Persons, #id)();

  @override
  Set<Column<Object>> get primaryKey => {familyId, personId};
}

/// A child's link to their family of parents. It has an id for its own claims (ISSUE-019, ADR-011):
/// "this was not their child" is about one child, not the whole family — as Gramps cites a `ChildRef`
/// and GEDCOM 7 gives `FAMC` a status. The same child twice in a family means nothing (GEDCOM 7: "should
/// not have multiple CHIL substructures pointing to the same INDI").
class FamilyChildren extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get familyId => integer().references(Families, #id)();
  IntColumn get personId => integer().references(Persons, #id)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {familyId, personId},
  ];
}

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<EventType>()();
  IntColumn get personId => integer().nullable().references(Persons, #id)();
  IntColumn get familyId => integer().nullable().references(Families, #id)();

  /// Null while the date is not known at all.
  TextColumn get qualifier => textEnum<DateQualifier>().nullable()();

  // Year apart from month and day: "ok. 1890" is a year, and the time slider (M10) works in years.
  IntColumn get year => integer().nullable()();
  IntColumn get month => integer().nullable()();
  IntColumn get day => integer().nullable()();
  IntColumn get yearTo => integer().nullable()();
  IntColumn get monthTo => integer().nullable()();
  IntColumn get dayTo => integer().nullable()();
  TextColumn get place => text().nullable()();

  @override
  List<String> get customConstraints => [
    // Person events belong to a person, family events (marriage, end) to a family — never both.
    'CHECK ((person_id IS NULL) <> (family_id IS NULL))',
    "CHECK ((type IN ('birth', 'death', 'burial')) = (person_id IS NOT NULL))",
  ];
}

class Cemeteries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get locality => text().nullable()();
  RealColumn get centerLat => real().nullable()();
  RealColumn get centerLon => real().nullable()();
  TextColumn get grobonetUrl => text().nullable()();
}

/// The manager's address (sector / row / plot) is the truth, the pin is a help. Everything except the
/// cemetery is optional: graves transcribed from the notes have neither (data-model.md → Known
/// consequence; the open question is US-002's, not the schema's).
class Graves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cemeteryId => integer().references(Cemeteries, #id)();

  /// "Grób rodzinny Nowaków" — a title the author gives, optional (ISSUE-012). Never derived from the
  /// surnames of the people buried: a wrong Polish genitive plural on a family grave jars
  /// (05_DESIGN/grob.md D1).
  TextColumn get name => text().nullable()();
  TextColumn get sector => text().nullable()();
  TextColumn get row => text().nullable()();
  TextColumn get plot => text().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  TextColumn get positionSource => textEnum<PositionSource>().nullable()();
  RealColumn get positionAccuracyM => real().nullable()();
}

/// FR-003: many burials per grave. A person is buried in one place, but the sources may disagree on
/// which (FR-001, ADR-006 D2): each grave claimed for a person is its own row, with its own claims.
/// The same person and grave twice is one value — a second source for it is a second claim, not a row.
class Burials extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId => integer().references(Persons, #id)();
  IntColumn get graveId => integer().references(Graves, #id)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {personId, graveId},
  ];
}

/// FR-001 provenance, shaped like a GEDCOM 7 source citation (ADR-006): the value lives in the row it
/// cites, a claim says who stated it and how strong it is. Conflicting values are separate rows, each
/// with its own claims; the one shown is the first row (lowest id). A claim cites exactly one row: an
/// event, a burial, a family (the union) or a child's link (ISSUE-019, ADR-011). Every event, burial,
/// family and child's link written since v6 has at least one claim — `claims.dart` and `families.dart`
/// write them together; families from before v6 have none (ADR-011: a migration adds no rows).
class Assertions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get eventId => integer().nullable().references(Events, #id)();
  IntColumn get burialId => integer().nullable().references(Burials, #id)();
  IntColumn get familyId => integer().nullable().references(Families, #id)();
  IntColumn get familyChildId =>
      integer().nullable().references(FamilyChildren, #id)();
  TextColumn get sourceKind => textEnum<SourceKind>()();

  /// Which relative, which record — "kto je podał" (FR-001). Optional.
  TextColumn get sourceDetail => text().nullable()();
  TextColumn get status => textEnum<AssertionStatus>()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK ((event_id IS NOT NULL) + (burial_id IS NOT NULL) + '
        '(family_id IS NOT NULL) + (family_child_id IS NOT NULL) = 1)',
  ];
}

/// A photo — the record, like GEDCOM 7's MULTIMEDIA_RECORD — and its file in the app's private storage,
/// under [DataLocation.mediaDir]. A grave's photo carries [graveId] (at most one per grave, ISSUE-016);
/// people reach a photo through [PersonMedia] links, so one photo can be on several people (schema v4,
/// ISSUE-017). A row with neither a grave nor a link does not outlive the write that left it so
/// (`photos.dart` → applyPersonPhotoEdits); its file goes with the next sweep (ADR-008).
@DataClassName('MediaFile')
class Media extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get relativePath => text().unique()();
  IntColumn get graveId => integer().nullable().references(Graves, #id)();
}

/// A person's link to a photo — GEDCOM 7's MULTIMEDIA_LINK (`OBJE`). A person's links are ordered by
/// [position], then [mediaId]: *"the first is the most-preferred value"*, so the first is the person's
/// profile photo, and each person has their own (05_DESIGN/zdjecie.md D9).
///
/// The crop of the link (ISSUE-018, ADR-010) is GEDCOM's `CROP`: in pixels of the photo's file — the
/// access copy, upright and never changed in place (ADR-008) — and on the link, so each person on a
/// group photo has their own. All four empty = no crop: the profile circle shows the middle. Whether
/// the crop lies inside the image SQL cannot tell (the image's size is not in the database); one write
/// path keeps it ([applyPersonPhotoEdits] in photos.dart, from the crop screen). A title (`TITL`)
/// would be a column here too, when a screen needs it.
@TableIndex(name: 'person_media_media', columns: {#mediaId})
class PersonMedia extends Table {
  IntColumn get personId => integer().references(Persons, #id)();
  IntColumn get mediaId => integer().references(Media, #id)();
  IntColumn get position => integer()();
  IntColumn get cropLeft => integer().nullable()();
  IntColumn get cropTop => integer().nullable()();
  IntColumn get cropWidth => integer().nullable()();
  IntColumn get cropHeight => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {personId, mediaId};
}

/// Single row: which person is the author ("ja" — the anchor of "how they connect to me").
@DataClassName('Setting')
class Settings extends Table {
  IntColumn get id => integer()();
  IntColumn get mePersonId => integer().nullable().references(Persons, #id)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

/// Run on every connection to the phone's database. The open app and the background backup
/// (ISSUE-010) may hold a connection each: `VACUUM INTO` keeps a read lock while it copies, so without
/// a busy timeout a write in the app would fail at once with `SQLITE_BUSY` instead of waiting. Both
/// connections use the same bundled SQLite library — the one safe way to share a file within a process
/// (https://www.sqlite.org/howtocorrupt.html, 2.3). Top-level: drift runs it in its own isolate.
void configureConnection(Database database) {
  database.execute('PRAGMA busy_timeout = 5000');
}

/// Where the data lives on the phone: the database file and the photo directory next to it.
class DataLocation {
  const DataLocation({required this.databaseFile, required this.mediaDir});

  final File databaseFile;
  final Directory mediaDir;

  /// The layout inside [directory] — on the phone, the app's private support directory
  /// (`main.dart`). No `path_provider` here, so the data layer also runs on a PC (`tool/`).
  factory DataLocation.inDirectory(Directory directory) => DataLocation(
    databaseFile: File('${directory.path}/grobing.db'),
    mediaDir: Directory('${directory.path}/media'),
  );
}

@DriftDatabase(
  tables: [
    Persons,
    Families,
    FamilyPartners,
    FamilyChildren,
    Events,
    Cemeteries,
    Graves,
    Burials,
    Assertions,
    Media,
    PersonMedia,
    Settings,
  ],
)
class GrobingDatabase extends _$GrobingDatabase {
  GrobingDatabase(super.executor);

  factory GrobingDatabase.atFile(File file) => GrobingDatabase(
    NativeDatabase.createInBackground(file, setup: configureConnection),
  );

  /// Stored in `PRAGMA user_version`. Every bump ships with a migration step below, tested from the
  /// previous version (NFR-003), and a new schema export (README → Baza danych).
  static const int currentSchemaVersion = 7;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Never "drop and recreate": the data is irreplaceable. Each step is tested from the version before
    // it (test/drift/grobing/), and a version without a step fails to open instead of losing data.
    // A restore checks that every table of the backup's version is still there with the same row
    // count (restore_service.dart), so a step adds and reshapes, but never drops a table or a row.
    onUpgrade: (m, from, to) async {
      // One transaction for every step, the version number included (drift writes it only after this
      // returns): an upgrade interrupted anywhere leaves the old version whole, and the next start
      // runs it again from the beginning.
      await transaction(() async {
        await m.runMigrationSteps(
          from: from,
          to: to,
          steps: migrationSteps(
            from1To2: _from1To2,
            from2To3: _from2To3,
            from3To4: _from3To4,
            from4To5: _from4To5,
            from5To6: _from5To6,
            from6To7: _from6To7,
          ),
        );
        await customStatement('PRAGMA user_version = $to');
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// ISSUE-011 (ADR-006): claims arrive. Burials lose "one per person" (D2) and get an id for their
  /// claims; the old rowid becomes the id, so every v1 row keeps its place.
  Future<void> _from1To2(Migrator m, Schema2 schema) async {
    await m.alterTable(
      TableMigration(
        schema.burials,
        columnTransformer: {
          schema.burials.id: const CustomExpression<int>('rowid'),
        },
      ),
    );
    await m.createTable(schema.assertions);
    // D5: the only way planned for a v1 date or burial was transcribing the notes, so each gets one
    // claim saying so — and that it was carried over, not entered with its source.
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'INSERT INTO assertions '
      '(event_id, source_kind, source_detail, status, recorded_at) '
      "SELECT id, 'notes', ?, 'claimed', ? FROM events ORDER BY id",
      [carriedOverFromV1, now],
    );
    await customStatement(
      'INSERT INTO assertions '
      '(burial_id, source_kind, source_detail, status, recorded_at) '
      "SELECT id, 'notes', ?, 'claimed', ? FROM burials ORDER BY id",
      [carriedOverFromV1, now],
    );
  }

  /// ISSUE-012: graves get an optional name. A new nullable column: no row changes, nothing dropped.
  Future<void> _from2To3(Migrator m, Schema3 schema) =>
      m.addColumn(schema.graves, schema.graves.name);

  /// ISSUE-017 (ADR-009): a person's photos become links, so one photo can be on several people. Every
  /// `media` row stays — a restore of a v3 backup counts them (README → Baza danych). A v3 person photo
  /// becomes that person's link, in the order of its id, so the first stays the first (the profile).
  /// Foreign keys are off here — `beforeOpen` turns them on after the migration — so the table can be
  /// rebuilt under the new links; the check at the end makes up for it.
  Future<void> _from3To4(Migrator m, Schema4 schema) async {
    await m.createTable(schema.personMedia);
    await m.createIndex(schema.personMediaMedia);
    await customStatement(
      'INSERT INTO person_media (person_id, media_id, position) '
      'SELECT person_id, id, '
      'row_number() OVER (PARTITION BY person_id ORDER BY id) - 1 '
      'FROM media WHERE person_id IS NOT NULL',
    );
    // Without person_id and its "a person or a grave" check: SQLite changes a CHECK only by rebuilding
    // the table. Rows and ids are copied as they are.
    await m.alterTable(TableMigration(schema.media));
    final List<QueryRow> broken = await customSelect(
      'PRAGMA foreign_key_check',
    ).get();
    if (broken.isNotEmpty) {
      throw StateError('Schema v4: ${broken.length} broken references');
    }
  }

  /// ISSUE-018 (ADR-010): a link gets its crop. Four new nullable columns: no row changes, nothing
  /// dropped, and every v4 link has no crop — its profile circle shows the middle, as before.
  Future<void> _from4To5(Migrator m, Schema5 schema) async {
    await m.addColumn(schema.personMedia, schema.personMedia.cropLeft);
    await m.addColumn(schema.personMedia, schema.personMedia.cropTop);
    await m.addColumn(schema.personMedia, schema.personMedia.cropWidth);
    await m.addColumn(schema.personMedia, schema.personMedia.cropHeight);
  }

  /// ISSUE-019 (ADR-011): claims on families and on children's links. A child's link gets an id — its
  /// old rowid, so every link keeps its place — and claims may cite a family or a link: SQLite changes a
  /// CHECK only by rebuilding the table, rows and ids copied as they are. Foreign keys are off here, as in
  /// `_from3To4`; the check at the end makes up for it.
  ///
  /// **No rows are added**: a restore of a v5 backup counts the rows of every table after migrating it
  /// (restore_service.dart), so claims for the families already there would refuse every such backup.
  /// Before v6 only the made-up debug data wrote families (`fictional_data.dart`); a family without a
  /// claim gets one when it is next saved on the family sheet (`families.dart` → saveFamily).
  Future<void> _from5To6(Migrator m, Schema6 schema) async {
    await m.alterTable(
      TableMigration(
        schema.familyChildren,
        columnTransformer: {
          schema.familyChildren.id: const CustomExpression<int>('rowid'),
        },
      ),
    );
    await m.alterTable(
      TableMigration(
        schema.assertions,
        newColumns: [
          schema.assertions.familyId,
          schema.assertions.familyChildId,
        ],
      ),
    );
    final List<QueryRow> broken = await customSelect(
      'PRAGMA foreign_key_check',
    ).get();
    if (broken.isNotEmpty) {
      throw StateError('Schema v6: ${broken.length} broken references');
    }
  }

  /// ISSUE-025: a person's sex. A new nullable column: no row changes, nothing dropped, and every v6
  /// person has none — the form suggests one at the next correction. The new event type `together`
  /// needs no step: the type is stored by name, without a CHECK on its values.
  Future<void> _from6To7(Migrator m, Schema7 schema) =>
      m.addColumn(schema.persons, schema.persons.sex);
}

/// [Assertions.sourceDetail] of the claims the v1→v2 migration gives to existing rows (ADR-006 D5).
const String carriedOverFromV1 = 'przeniesione z v1';
