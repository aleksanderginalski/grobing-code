import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'database.steps.dart';

part 'database.g.dart';

// Schema v4 — grobing-vault/04_ARCHITECTURE/data-model.md: v1 (ISSUE-007), Assertion (ISSUE-011,
// ADR-006), the grave's name (ISSUE-012) and people's photos as links (ISSUE-017), still without the
// grave fee (S4) and the cemetery offline-map status (SPIKE-001). Enums are
// stored by name, not index: data lives for decades and a reordered enum must not silently change
// meaning. Renaming an enum value is a schema change and needs a migration.

enum EventType { birth, death, burial, marriage, end }

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

  /// "Kim była" — free text with one source line for the whole text (FR-001 cost decision).
  TextColumn get bio => text().nullable()();
  TextColumn get bioSource => text().nullable()();
  BoolColumn get isLiving => boolean().withDefault(const Constant(false))();
}

/// FR-002: a family is a record of 1-2 partners and children. The "at most two partners" rule is
/// enforced where families are entered (US-003), not here.
class Families extends Table {
  IntColumn get id => integer().autoIncrement()();
}

class FamilyPartners extends Table {
  IntColumn get familyId => integer().references(Families, #id)();
  IntColumn get personId => integer().references(Persons, #id)();

  @override
  Set<Column<Object>> get primaryKey => {familyId, personId};
}

class FamilyChildren extends Table {
  IntColumn get familyId => integer().references(Families, #id)();
  IntColumn get personId => integer().references(Persons, #id)();

  @override
  Set<Column<Object>> get primaryKey => {familyId, personId};
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

/// FR-001 provenance, shaped like a GEDCOM 7 source citation (ADR-006): the value lives in the event
/// or burial row, a claim says who stated it and how strong it is. Conflicting values are separate
/// rows, each with its own claims; the one shown is the first row (lowest id). Every event and burial
/// row has at least one claim — `claims.dart` writes them together.
class Assertions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get eventId => integer().nullable().references(Events, #id)();
  IntColumn get burialId => integer().nullable().references(Burials, #id)();
  TextColumn get sourceKind => textEnum<SourceKind>()();

  /// Which relative, which record — "kto je podał" (FR-001). Optional.
  TextColumn get sourceDetail => text().nullable()();
  TextColumn get status => textEnum<AssertionStatus>()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK ((event_id IS NULL) <> (burial_id IS NULL))',
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
/// profile photo, and each person has their own (05_DESIGN/zdjecie.md D9). What GEDCOM puts on the
/// link — a face's crop, a title — would be columns here, added when a screen needs them.
@TableIndex(name: 'person_media_media', columns: {#mediaId})
class PersonMedia extends Table {
  IntColumn get personId => integer().references(Persons, #id)();
  IntColumn get mediaId => integer().references(Media, #id)();
  IntColumn get position => integer()();

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
  static const int currentSchemaVersion = 4;

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
}

/// [Assertions.sourceDetail] of the claims the v1→v2 migration gives to existing rows (ADR-006 D5).
const String carriedOverFromV1 = 'przeniesione z v1';
