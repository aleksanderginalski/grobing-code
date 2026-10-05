import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// Schema v1 — grobing-vault/04_ARCHITECTURE/data-model.md, without Assertion (ISSUE-007 D2: its shape
// arrives with US-002 as v2), without the grave fee (S4) and the cemetery offline-map status
// (SPIKE-001). Enums are stored by name, not index: data lives for decades and a reordered enum must
// not silently change meaning. Renaming an enum value is a schema change and needs a migration.

enum EventType { birth, death, burial, marriage, end }

/// FR-004: a date is a value plus a qualifier; `between` uses both bounds.
enum DateQualifier { exact, about, before, after, between }

/// How a grave position was obtained (glossary: pinezka carries its source).
enum PositionSource { satellite, gps }

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
  TextColumn get sector => text().nullable()();
  TextColumn get row => text().nullable()();
  TextColumn get plot => text().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  TextColumn get positionSource => textEnum<PositionSource>().nullable()();
  RealColumn get positionAccuracyM => real().nullable()();
}

/// FR-003: many burials per grave, at most one per person.
class Burials extends Table {
  // Unique rather than the primary key: a lone INTEGER PRIMARY KEY would become SQLite's rowid and
  // could be generated when omitted, instead of always naming a person.
  IntColumn get personId => integer().unique().references(Persons, #id)();
  IntColumn get graveId => integer().references(Graves, #id)();
}

/// A photo file in the app's private storage, under [DataLocation.mediaDir].
@DataClassName('MediaFile')
class Media extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get relativePath => text().unique()();
  IntColumn get personId => integer().nullable().references(Persons, #id)();
  IntColumn get graveId => integer().nullable().references(Graves, #id)();

  @override
  List<String> get customConstraints => [
    'CHECK ((person_id IS NULL) <> (grave_id IS NULL))',
  ];
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

/// Where the data lives on the phone: the database file and the photo directory next to it.
class DataLocation {
  const DataLocation({required this.databaseFile, required this.mediaDir});

  final File databaseFile;
  final Directory mediaDir;

  static Future<DataLocation> appDefault() async {
    final Directory support = await getApplicationSupportDirectory();
    return DataLocation(
      databaseFile: File('${support.path}/grobing.db'),
      mediaDir: Directory('${support.path}/media'),
    );
  }
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
    Media,
    Settings,
  ],
)
class GrobingDatabase extends _$GrobingDatabase {
  GrobingDatabase(super.executor);

  factory GrobingDatabase.atFile(File file) =>
      GrobingDatabase(NativeDatabase.createInBackground(file));

  /// Stored in `PRAGMA user_version`. Every bump ships with a migration step below, tested from the
  /// previous version (NFR-003), and a new schema export (README → Baza danych).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Never "drop and recreate": the data is irreplaceable. A version without a step is a bug.
      throw StateError('No migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
