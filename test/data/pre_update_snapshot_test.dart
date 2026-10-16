import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/pre_update_snapshot.dart';
import 'package:sqlite3/sqlite3.dart';

import '../drift/grobing/generated/schema.dart';
import '../drift/grobing/generated/schema_v11.dart' as v11;

// ISSUE-041 (K3, AC-2): before a new version migrates the database, the start keeps a copy of it at the
// old version. Made-up cemeteries and graves only (family-data.md).

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  late Directory tmp;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));
  setUp(() => tmp = Directory.systemTemp.createTempSync('grobing_snapshot_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A database file at schema v11 with a made-up cemetery, sector and three graves.
  Future<File> writeV11(String name) async {
    final File file = File('${tmp.path}/$name');
    final InitializedSchema schema = await verifier.schemaAt(11);
    final v11.DatabaseAtV11 old = v11.DatabaseAtV11(schema.newConnection());
    await old.batch((b) {
      b.insertAll(old.cemeteries, const [
        v11.CemeteriesData(id: 1, name: 'Cmentarz Wymyślony'),
      ]);
      b.insertAll(old.sectors, const [
        v11.SectorsData(id: 1, cemeteryId: 1, name: 'B', nameKey: 'b'),
      ]);
      b.insertAll(old.graves, const [
        v11.GravesData(
          id: 1,
          cemeteryId: 1,
          name: 'Grób Wymyślonych',
          sectorId: 1,
          lat: 52.5001,
          lon: 19.5001,
          positionSource: 'gps',
          positionAccuracyM: 4,
        ),
        v11.GravesData(id: 2, cemeteryId: 1, name: 'Grób Zmyślonych'),
        v11.GravesData(id: 3, cemeteryId: 1),
      ]);
    });
    await old.customStatement('VACUUM INTO ?', [file.path]);
    await old.close();
    return file;
  }

  /// The grave names joined with `|` (a record compares a list by identity, a string by value).
  ({int version, int graves, int cemeteries, String names, String ok}) read(
    File file,
  ) {
    final Database raw = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      return (
        version: raw.userVersion,
        graves:
            raw.select('SELECT count(*) AS n FROM graves').first['n'] as int,
        cemeteries:
            raw.select('SELECT count(*) AS n FROM cemeteries').first['n']
                as int,
        names: [
          for (final Row r in raw.select('SELECT name FROM graves ORDER BY id'))
            r['name'] as String?,
        ].join('|'),
        ok: raw.select('PRAGMA integrity_check').first.values.first.toString(),
      );
    } finally {
      raw.close();
    }
  }

  Future<int> gravesAfterMigration(File file) async {
    final GrobingDatabase db = GrobingDatabase.atFile(file);
    try {
      final int n = (await db.select(db.graves).get()).length;
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        GrobingDatabase.currentSchemaVersion,
      );
      return n;
    } finally {
      await db.close();
    }
  }

  test(
    'AC-2 — a v11 database: the snapshot is at v11 with every row, the database itself is left as it was, '
    'and both migrate to the current version with the same graves',
    () async {
      final File database = await writeV11('grobing.db');
      final Directory dir = preUpdateSnapshotDir(tmp);

      final File? snapshot = takePreUpdateSnapshot(
        database: database,
        dir: dir,
      );

      expect(snapshot?.path, preUpdateSnapshotFile(dir, 11).path);
      const String names = 'Grób Wymyślonych|Grób Zmyślonych|null';
      expect(read(snapshot!), (
        version: 11,
        graves: 3,
        cemeteries: 1,
        names: names,
        ok: 'ok',
      ));
      expect(read(database), (
        version: 11,
        graves: 3,
        cemeteries: 1,
        names: names,
        ok: 'ok',
      ));
      expect(await gravesAfterMigration(database), 3);
      final File copy = snapshot.copySync('${tmp.path}/from-snapshot.db');
      expect(await gravesAfterMigration(copy), 3);
    },
  );

  test(
    'no snapshot when there is nothing to keep: no database yet (first install), a database already at the '
    'current version (also every database a restore brings — it migrates in its own staging), a file drift '
    'never created (user_version 0)',
    () async {
      final Directory dir = preUpdateSnapshotDir(tmp);

      expect(
        takePreUpdateSnapshot(database: File('${tmp.path}/none.db'), dir: dir),
        isNull,
      );

      final File current = File('${tmp.path}/current.db');
      final GrobingDatabase db = GrobingDatabase.atFile(current);
      await db.select(db.cemeteries).get();
      await db.close();
      expect(takePreUpdateSnapshot(database: current, dir: dir), isNull);

      final File blank = File('${tmp.path}/blank.db');
      sqlite3.open(blank.path)
        ..execute('CREATE TABLE t (x)')
        ..close();
      expect(takePreUpdateSnapshot(database: blank, dir: dir), isNull);

      expect(dir.existsSync(), isFalse);
    },
  );

  test(
    'keeps the three newest snapshots, removes a partial file of an interrupted run, and a second start at '
    'the same old version replaces its snapshot',
    () async {
      final File database = await writeV11('grobing.db');
      final Directory dir = preUpdateSnapshotDir(tmp)..createSync();
      for (final int v in [8, 9, 10]) {
        preUpdateSnapshotFile(dir, v).writeAsStringSync('v$v');
      }
      File('${dir.path}/grobing-v7.db.partial').writeAsStringSync('half');

      takePreUpdateSnapshot(database: database, dir: dir);
      final File? again = takePreUpdateSnapshot(database: database, dir: dir);

      expect(again, isNotNull);
      expect(read(again!).graves, 3);
      expect(
        dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort(),
        ['grobing-v10.db', 'grobing-v11.db', 'grobing-v9.db'],
      );
    },
  );

  test('an interrupted write (hot journal) is rolled back before the copy: the snapshot has the committed rows '
      'at the committed version, not the half-written ones', () async {
    final File source = await writeV11('source.db');
    // A write that changes every grave, spills pages to the file (cache of one page) and sets the next
    // version — like a migration cut off before its commit. The file and its journal are copied while the
    // transaction is open: the copy is a database with a hot journal and no process holding it.
    final Database writer = sqlite3.open(source.path);
    writer
      ..execute('PRAGMA cache_size = 1')
      ..execute('BEGIN')
      ..execute("UPDATE graves SET name = 'zmienione'")
      ..execute(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3000) '
        "INSERT INTO cemeteries (name) SELECT 'Cmentarz Testowy ' || i FROM n",
      )
      ..execute('PRAGMA user_version = 12');
    final File database = File('${tmp.path}/grobing.db')
      ..writeAsBytesSync(source.readAsBytesSync());
    final File journal = File('${database.path}-journal')
      ..writeAsBytesSync(File('${source.path}-journal').readAsBytesSync());
    writer
      ..execute('ROLLBACK')
      ..close();
    expect(journal.lengthSync(), greaterThan(0));
    const committed = (
      version: 11,
      graves: 3,
      cemeteries: 1,
      names: 'Grób Wymyślonych|Grób Zmyślonych|null',
      ok: 'ok',
    );
    // The file without its journal is not the committed database — pages of the cut-off write are in it,
    // so the test fails if the snapshot copied the file as it lies.
    final File torn = File('${tmp.path}/torn.db')
      ..writeAsBytesSync(database.readAsBytesSync());
    Object tornState;
    try {
      tornState = read(torn);
    } on SqliteException catch (e) {
      tornState = e;
    }
    expect(tornState, isNot(committed));

    final File? snapshot = takePreUpdateSnapshot(
      database: database,
      dir: preUpdateSnapshotDir(tmp),
    );

    expect(journal.existsSync(), isFalse);
    expect(
      snapshot?.path,
      preUpdateSnapshotFile(preUpdateSnapshotDir(tmp), 11).path,
    );
    expect(read(snapshot!), committed);
    expect(read(database), committed);
  });
}
