import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show MigrationStrategy, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/home/cemetery_base.dart';
import 'package:grobing/backup/age/age.dart';
import 'package:grobing/backup/backup_archive.dart';
import 'package:grobing/backup/backup_service.dart';
import 'package:grobing/backup/backup_settings.dart';
import 'package:grobing/backup/restore_service.dart';
import 'package:grobing/backup/tar_writer.dart';
import 'package:grobing/data/cemeteries.dart';
import 'package:grobing/data/data_state.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/families.dart';
import 'package:grobing/data/graves.dart';
import 'package:grobing/data/people.dart';
import 'package:grobing/data/photos.dart';
import 'package:grobing/dev/fictional_data.dart';
import 'package:grobing/dev/fictional_photo.dart';

import '../drift/grobing/generated/schema_v1.dart' as v1;
import '../drift/grobing/generated/schema_v2.dart' as v2;
import '../drift/grobing/generated/schema_v3.dart' as v3;
import '../drift/grobing/generated/schema_v4.dart' as v4;
import '../drift/grobing/generated/schema_v5.dart' as v5;
import '../drift/grobing/generated/schema_v6.dart' as v6;
import '../support/backup_fakes.dart';

// ISSUE-009: restore from the backup file — key file + passphrase + backup file.
// AC-1: the restored data has the source's fingerprint (NFR-002 → Method).
// AC-2: a wrong passphrase, a damaged file, an unsafe tar, a manifest that does not match and a
//       backup from a newer schema are refused with a readable message, the phone's data untouched.
// AC-3: a backup from an older schema goes through the app's own migrations (synthetic next version);
//       ISSUE-011 AC-4: a real v1 backup into the v2 app.
// AC-5: too large for the phone → refused before unpacking.
// D3: what the backup does afterwards. Data: made-up people only (`fictional_data.dart`).

const String _passphrase = 'hasło-testowe Żółć';
final DateTime _createdAt = DateTime.utc(2026, 10, 6, 12);

/// A key file as setup writes it, but with a cheap scrypt so that the many refusal tests stay fast;
/// the real work factor runs in the end-to-end test through `BackupService`.
Future<({Uint8List keyFile, X25519Identity identity})> _cheapKey(
  String passphrase, {
  int workFactor = 10,
}) async {
  final X25519Identity identity = X25519Identity.generate();
  final BytesBuilder out = BytesBuilder();
  await for (final List<int> c in ageEncrypt(
    Stream.value(utf8.encode(encodeIdentityFile(identity, _createdAt))),
    [ScryptRecipient(passphrase, workFactor: workFactor)],
  )) {
    out.add(c);
  }
  return (keyFile: out.takeBytes(), identity: identity);
}

Future<Uint8List> _decrypt(List<int> file, AgeIdentity identity) async {
  final BytesBuilder out = BytesBuilder();
  await for (final List<int> c in ageDecrypt(Stream.value(file), [identity])) {
    out.add(c);
  }
  return out.takeBytes();
}

Future<Uint8List> _encrypt(List<int> plain, AgeRecipient to) async {
  final BytesBuilder out = BytesBuilder();
  await for (final List<int> c in ageEncrypt(Stream.value(plain), [to])) {
    out.add(c);
  }
  return out.takeBytes();
}

typedef _Entry = ({String path, List<int> data});

/// The files of a tar written by `tar_writer.dart`.
List<_Entry> _untar(Uint8List tar) {
  final List<_Entry> entries = [];
  int offset = 0;
  while (!tar.sublist(offset, offset + 512).every((b) => b == 0)) {
    String field(int at, int length) {
      final Uint8List b = tar.sublist(offset + at, offset + at + length);
      final int end = b.indexOf(0);
      return ascii.decode(end < 0 ? b : b.sublist(0, end));
    }

    final String prefix = field(345, 155);
    final String name = field(0, 100);
    final int size = int.parse(field(124, 12), radix: 8);
    entries.add((
      path: prefix.isEmpty ? name : '$prefix/$name',
      data: tar.sublist(offset + 512, offset + 512 + size),
    ));
    offset += 512 + (size + 511) ~/ 512 * 512;
  }
  return entries;
}

/// A ustar header for any path and type — including ones the writer refuses.
Uint8List _rawHeader(String path, int size, {String type = '0'}) {
  final Uint8List h = Uint8List(512);
  void put(int at, String s) => h.setRange(at, at + s.length, ascii.encode(s));
  put(0, path);
  put(100, '0000644');
  put(108, '0000000');
  put(116, '0000000');
  put(124, size.toRadixString(8).padLeft(11, '0'));
  put(136, '00000000000');
  put(156, type);
  put(257, 'ustar');
  put(263, '00');
  h.fillRange(148, 156, 0x20);
  put(148, h.fold(0, (s, b) => s + b).toRadixString(8).padLeft(6, '0'));
  h[154] = 0;
  h[155] = 0x20;
  return h;
}

List<int> _tar(List<_Entry> entries, {Set<String> raw = const {}}) => [
  for (final _Entry e in entries) ...[
    ...(raw.contains(e.path)
        ? _rawHeader(e.path, e.data.length)
        : tarFileHeader(e.path, e.data.length, _createdAt)),
    ...e.data,
    ...tarPadding(e.data.length),
  ],
  ...tarEnd(),
];

Map<String, Object?> _manifestOf(List<_Entry> entries) =>
    jsonDecode(utf8.decode(entries.last.data)) as Map<String, Object?>;

_Entry _manifestEntry(Map<String, Object?> manifest) =>
    (path: backupManifestName, data: utf8.encode(jsonEncode(manifest)));

/// The manifest's `files` recomputed from [files], as the writer would have written them.
Map<String, Object?> _withFiles(
  Map<String, Object?> manifest,
  List<_Entry> files,
) => {
  ...manifest,
  'files': [
    for (final _Entry f in files)
      {
        'path': f.path,
        'size': f.data.length,
        'sha256': sha256.convert(f.data).toString(),
      },
  ],
};

/// An app one schema version newer than this one: tests the mechanism "an older backup goes through
/// the app's migrations" apart from any real migration step (ISSUE-009 AC-3; v3 since ISSUE-011).
class _SchemaNext extends GrobingDatabase {
  _SchemaNext(super.executor);

  static const int version = GrobingDatabase.currentSchemaVersion + 1;

  @override
  int get schemaVersion => version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from == GrobingDatabase.currentSchemaVersion) {
        await customStatement('ALTER TABLE persons ADD COLUMN nickname TEXT');
      }
    },
  );
}

/// Made-up rows of a phone at schema v2 (ISSUE-012): a date and two burials, each with its claim.
const List<String> _v2Rows = [
  'INSERT INTO persons (id, given_names, surname) VALUES '
      "(1, 'Jan', 'Wymyślony'), (2, 'Anna', 'Wymyślona')",
  "INSERT INTO cemeteries (id, name) VALUES (1, 'Cmentarz Wymyślony')",
  'INSERT INTO graves (id, cemetery_id) VALUES (1, 1)',
  "INSERT INTO graves (id, cemetery_id, sector) VALUES (2, 1, 'B')",
  "INSERT INTO events (id, type, person_id, qualifier, year) VALUES (1, 'birth', 1, 'about', 1890)",
  'INSERT INTO burials (id, person_id, grave_id) VALUES (1, 1, 1), (2, 2, 2)',
  'INSERT INTO assertions (event_id, burial_id, source_kind, status, recorded_at) VALUES '
      "(1, NULL, 'notes', 'claimed', 1791273600), "
      "(NULL, 1, 'notes', 'claimed', 1791273600), "
      "(NULL, 2, 'notes', 'claimed', 1791273600)",
];

/// Made-up rows of a phone at schema v3 (ISSUE-017 F3): a grave's photo and three people's photos, still
/// with one owner each — Anna has two, Jan one.
/// Made-up rows of a phone at schema v5 (ISSUE-019 F2): a father in two unions, each with a child and the
/// first with its marriage — families without claims, as v5 kept them.
const List<String> _v5Rows = [
  'INSERT INTO persons (id, given_names, surname) VALUES '
      "(1, 'Ojciec', 'Wymyślony'), (2, 'Matka', 'Wymyślona'), (3, 'Dziecko', 'Wymyślone'), "
      "(4, 'Partnerka', 'Zmyślona'), (5, 'Drugie dziecko', 'Wymyślone')",
  'INSERT INTO families (id) VALUES (1), (2)',
  'INSERT INTO family_partners (family_id, person_id) VALUES (1, 1), (1, 2), (2, 1), (2, 4)',
  'INSERT INTO family_children (family_id, person_id) VALUES (1, 3), (2, 5)',
  'INSERT INTO events (id, type, family_id, qualifier, year) VALUES '
      "(1, 'marriage', 1, 'before', 1920)",
  'INSERT INTO assertions (event_id, burial_id, source_kind, status, recorded_at) VALUES '
      "(1, NULL, 'notes', 'claimed', 1791273600)",
];

/// Made-up rows of a phone at schema v6 (ISSUE-025 AC-4): the father's two unions with their claims, the
/// first with its wedding — no sex and no "Razem od", as v6 kept them.
const List<String> _v6Rows = [
  'INSERT INTO persons (id, given_names, surname) VALUES '
      "(1, 'Ojciec', 'Wymyślony'), (2, 'Matka', 'Wymyślona'), (3, 'Dziecko', 'Wymyślone'), "
      "(4, 'Partnerka', 'Zmyślona'), (5, 'Drugie dziecko', 'Wymyślone')",
  'INSERT INTO families (id) VALUES (1), (2)',
  'INSERT INTO family_partners (family_id, person_id) VALUES (1, 1), (1, 2), (2, 1), (2, 4)',
  'INSERT INTO family_children (id, family_id, person_id) VALUES (1, 1, 3), (2, 2, 5)',
  'INSERT INTO events (id, type, family_id, qualifier, year) VALUES '
      "(1, 'marriage', 1, 'before', 1920)",
  'INSERT INTO assertions (event_id, family_id, family_child_id, source_kind, status, recorded_at) VALUES '
      "(1, NULL, NULL, 'notes', 'claimed', 1791273600), "
      "(NULL, 1, NULL, 'notes', 'claimed', 1791273600), "
      "(NULL, 2, NULL, 'notes', 'claimed', 1791273600), "
      "(NULL, NULL, 1, 'notes', 'claimed', 1791273600), "
      "(NULL, NULL, 2, 'notes', 'claimed', 1791273600)",
];

/// Made-up rows of a phone at schema v4 (ISSUE-018 F3): a gravestone, a photo Jan and Anna share (Jan's
/// profile, Anna's second) and Anna's own profile — links without crops, as every v4 link is.
const List<String> _v4Rows = [
  'INSERT INTO persons (id, given_names, surname) VALUES '
      "(1, 'Jan', 'Wymyślony'), (2, 'Anna', 'Wymyślona')",
  "INSERT INTO cemeteries (id, name) VALUES (1, 'Cmentarz Wymyślony')",
  "INSERT INTO graves (id, cemetery_id, name) VALUES (1, 1, 'Grób Wymyślonych')",
  'INSERT INTO burials (id, person_id, grave_id) VALUES (1, 1, 1), (2, 2, 1)',
  'INSERT INTO assertions (event_id, burial_id, source_kind, status, recorded_at) VALUES '
      "(NULL, 1, 'notes', 'claimed', 1791273600), "
      "(NULL, 2, 'notes', 'claimed', 1791273600)",
  'INSERT INTO media (id, relative_path, grave_id) VALUES '
      "(1, 'groby/1/nagrobek.png', 1), "
      "(2, 'zdjecia/slub.png', NULL), "
      "(3, 'zdjecia/anna.png', NULL)",
  'INSERT INTO person_media (person_id, media_id, position) VALUES '
      '(1, 2, 0), (2, 3, 0), (2, 2, 1)',
];

const List<String> _v3Rows = [
  'INSERT INTO persons (id, given_names, surname) VALUES '
      "(1, 'Jan', 'Wymyślony'), (2, 'Anna', 'Wymyślona')",
  "INSERT INTO cemeteries (id, name) VALUES (1, 'Cmentarz Wymyślony')",
  "INSERT INTO graves (id, cemetery_id, name) VALUES (1, 1, 'Grób Wymyślonych')",
  'INSERT INTO burials (id, person_id, grave_id) VALUES (1, 1, 1), (2, 2, 1)',
  'INSERT INTO assertions (event_id, burial_id, source_kind, status, recorded_at) VALUES '
      "(NULL, 1, 'notes', 'claimed', 1791273600), "
      "(NULL, 2, 'notes', 'claimed', 1791273600)",
  'INSERT INTO media (id, relative_path, person_id, grave_id) VALUES '
      "(1, 'groby/1/nagrobek.png', NULL, 1), "
      "(2, 'osoby/anna-1.png', 2, NULL), "
      "(3, 'osoby/anna-2.png', 2, NULL), "
      "(4, 'osoby/jan-1.png', 1, NULL)",
];

/// Made-up rows of a phone still at schema v1 (ISSUE-011 AC-4): two dates, two burials.
const List<String> _v1Rows = [
  'INSERT INTO persons (id, given_names, surname) VALUES '
      "(1, 'Ojciec 1', 'Wymyślona'), (2, 'Matka 1', 'Wymyślona')",
  "INSERT INTO cemeteries (id, name) VALUES (1, 'Cmentarz Wymyślony 1')",
  'INSERT INTO graves (id, cemetery_id) VALUES (1, 1)',
  'INSERT INTO events (type, person_id, qualifier, year) VALUES '
      "('birth', 1, 'about', 1890), ('death', 2, 'before', 1960)",
  'INSERT INTO burials (person_id, grave_id) VALUES (1, 1), (2, 1)',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tmp;
  late FakeDocumentStore drive;

  /// The source phone's data — made-up people; a gravestone, a portrait and a "wedding photo" the
  /// mother shares with the father (ISSUE-017) — and its fingerprint.
  late Directory source;
  late String sourceFingerprint;
  late Map<String, int> sourceCounts;

  /// A valid backup of [source], its tar, and the key that opens it (cheap scrypt).
  late X25519Identity identity;
  late Uint8List backupTar;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('grobing_restore_test');
    drive = FakeDocumentStore(Directory('${tmp.path}/drive'));
    source = Directory('${tmp.path}/source')..createSync();
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(File('${source.path}/grobing.db')),
    );
    await addFictionalData(db, Directory('${source.path}/media'));
    // ISSUE-022: the source phone has chosen "ja" — a setting in the database, so it travels with it.
    await setMe(
      db,
      (await (db.select(
        db.persons,
      )..where((p) => p.givenNames.equals('Matka 1'))).getSingle()).id,
    );
    final DataState state = await readDataState(
      db,
      mediaDir: Directory('${source.path}/media'),
    );
    sourceFingerprint = state.fingerprint;
    sourceCounts = state.rowCounts;
    await db.customStatement('VACUUM INTO ?', ['${tmp.path}/snapshot.db']);
    await db.close();

    final ({Uint8List keyFile, X25519Identity identity}) key = await _cheapKey(
      _passphrase,
    );
    identity = key.identity;
    drive.fileFor(FakeDocumentStore.uriOf('klucz.age'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(key.keyFile);
    final File backup = drive.fileFor(FakeDocumentStore.uriOf('kopia.age'));
    await writeEncryptedBackup(
      snapshot: File('${tmp.path}/snapshot.db'),
      mediaDir: Directory('${source.path}/media'),
      recipient: identity.recipient,
      output: backup,
      createdAt: _createdAt,
    );
    backupTar = await _decrypt(backup.readAsBytesSync(), identity);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// A phone: its data directory and the open live database, optionally with made-up data.
  Future<({Directory dir, GrobingDatabase db})> phone(
    String name, {
    bool withData = false,
  }) async {
    final Directory dir = Directory('${tmp.path}/$name')..createSync();
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(File('${dir.path}/grobing.db')),
    );
    if (withData) {
      await addFictionalData(db, Directory('${dir.path}/media'));
      await addFictionalData(db, Directory('${dir.path}/media'));
    } else {
      await db.customSelect('SELECT 1').get();
    }
    return (dir: dir, db: db);
  }

  /// The phone's data as it is on disk now (after a restore closed the live database).
  Future<DataState> stateOnDisk(Directory dir) async {
    final GrobingDatabase db = GrobingDatabase(
      NativeDatabase(File('${dir.path}/grobing.db')),
    );
    try {
      return await readDataState(db, mediaDir: Directory('${dir.path}/media'));
    } finally {
      await db.close();
    }
  }

  /// Puts [bytes] in "Drive" as a backup file and returns its uri.
  String upload(String name, List<int> bytes) {
    final String uri = FakeDocumentStore.uriOf(name);
    drive.fileFor(uri)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return uri;
  }

  Future<String> uploadTar(String name, List<int> tar) async =>
      upload(name, await _encrypt(tar, identity.recipient));

  group('AC-1 — the restored data is the source data', () {
    test(
      'end to end with the real setup: BackupService writes key and backup, a fresh phone '
      'restores them with the fingerprint of the source; nothing is left behind',
      () async {
        // The source phone sets up its backup exactly as the app does (scrypt work factor 18).
        final GrobingDatabase sourceDb = GrobingDatabase(
          NativeDatabase(File('${source.path}/grobing.db')),
        );
        final FakeDocumentStore realDrive = FakeDocumentStore(
          Directory('${tmp.path}/real-drive'),
        );
        final BackupService backup = BackupService(
          database: sourceDb,
          location: DataLocation.inDirectory(source),
          workDir: Directory('${tmp.path}/cache'),
          settings: BackupSettingsStore(File('${source.path}/backup.json')),
          documents: realDrive,
          lock: FakeDataLock(),
        );
        final BackupSettings settings = (await backup.setUp(_passphrase))!;
        await sourceDb.close();

        final ({Directory dir, GrobingDatabase db}) fresh = await phone(
          'fresh',
        );
        final List<RestoreStep> steps = [];
        final RestoreResult result =
            await restoreServiceIn(fresh.dir, fresh.db, realDrive).restore(
              backupUri: settings.documentUri,
              keyUri: FakeDocumentStore.uriOf(backupKeyFileName),
              passphrase: _passphrase,
              onStep: steps.add,
            );

        final DataState restored = await stateOnDisk(fresh.dir);
        expect(restored.fingerprint, sourceFingerprint);
        expect(restored.rowCounts, sourceCounts);
        expect(result.dataFingerprint, sourceFingerprint);
        // US-005 AC-3 for people, read directly (US-005 review): the mother's two photos in their order
        // (the portrait is her profile), and the father's only photo is the same row and file as her
        // second — one shared photo, two links.
        expect(sourceCounts['person_media'], 3);
        final GrobingDatabase back = GrobingDatabase(
          NativeDatabase(File('${fresh.dir.path}/grobing.db')),
        );
        final List<Person> people = await back.select(back.persons).get();
        int idOf(String given) =>
            people.firstWhere((p) => p.givenNames == given).id;
        final List<PersonPhoto> mother = await personPhotos(
          back,
          idOf('Matka 1'),
        );
        final List<PersonPhoto> father = await personPhotos(
          back,
          idOf('Ojciec 1'),
        );
        // ISSUE-019 F3: the father's two unions come back, each with its child and its claims (ADR-011).
        final PersonRelations fatherFamilies = await loadRelations(
          back,
          idOf('Ojciec 1'),
        );
        final int familyClaims =
            (await back
                    .customSelect(
                      'SELECT count(*) AS c FROM assertions '
                      'WHERE family_id IS NOT NULL OR family_child_id IS NOT NULL',
                    )
                    .getSingle())
                .read<int>('c');
        final int? me = await watchMe(back).first;
        await back.close();
        expect(me, idOf('Matka 1'), reason: 'ISSUE-022: "ja" comes back');
        expect(fatherFamilies.unions.map((u) => u.partner!.givenNames), [
          'Matka 1',
          'Partnerka 1',
        ]);
        expect(fatherFamilies.unions.map((u) => u.children.single.givenNames), [
          'Dziecko 1',
          'Dziecko z drugiego związku 1',
        ]);
        expect(familyClaims, 4); // two unions and two children's links
        // ISSUE-025: the sex written and the second union's "Razem od" before its wedding come back.
        expect(
          people.firstWhere((p) => p.givenNames == 'Ojciec 1').sex,
          Sex.male,
        );
        expect(
          people.firstWhere((p) => p.givenNames == 'Dziecko 1').sex,
          isNull,
        );
        expect(fatherFamilies.unions.last.together?.from.year, 1922);
        expect(fatherFamilies.unions.last.married, isTrue);
        expect(mother.map((p) => p.relativePath), [
          'wymyslone/portret-1.png',
          'wymyslone/slub-1.png',
        ]);
        expect(father.single.mediaId, mother[1].mediaId);
        // ISSUE-018 F4: each link to the shared photo comes back with its own crop; the portrait has none.
        expect(mother[0].crop, isNull);
        expect(
          mother[1].crop,
          const PhotoCrop(left: 80, top: 50, width: 160, height: 160),
        );
        expect(
          father.single.crop,
          const PhotoCrop(left: 240, top: 50, width: 160, height: 160),
        );
        for (final PersonPhoto p in mother) {
          expect(
            File('${fresh.dir.path}/media/${p.relativePath}').existsSync(),
            isTrue,
          );
        }
        expect(
          (result.schemaFrom, result.schemaTo),
          (
            GrobingDatabase.currentSchemaVersion,
            GrobingDatabase.currentSchemaVersion,
          ),
        );
        expect(steps, [
          RestoreStep.checkingSpace,
          RestoreStep.unlockingKey,
          RestoreStep.copying,
          RestoreStep.decrypting,
          RestoreStep.verifying,
          RestoreStep.replacing,
        ]);
        // Only the data is left: no staging, no old data, no marker, no secret.
        expect(
          fresh.dir
              .listSync()
              .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
              .toSet(),
          {'grobing.db', 'media', 'backup.json'},
        );
        final String stored = File(
          '${fresh.dir.path}/backup.json',
        ).readAsStringSync();
        expect(stored, isNot(contains('AGE-SECRET-KEY')));
        expect(stored, isNot(contains(_passphrase)));
      },
    );

    test(
      'a phone with other data: replaced entirely — also photos the backup does not have',
      () async {
        // A backup without photos onto a phone with photos: old photos must not survive.
        final List<_Entry> entries = _untar(backupTar);
        final List<_Entry> noPhotos = [
          entries.firstWhere((e) => e.path == backupDatabaseName),
        ];
        final Map<String, Object?> manifest = _withFiles(
          _manifestOf(entries),
          noPhotos,
        );
        // The fingerprint covers the photos too: recompute it from the database alone.
        final Directory check = Directory('${tmp.path}/check')..createSync();
        File('${check.path}/grobing.db').writeAsBytesSync(noPhotos.single.data);
        final GrobingDatabase checkDb = GrobingDatabase(
          NativeDatabase(File('${check.path}/grobing.db')),
        );
        final DataState withoutPhotos = await readDataState(
          checkDb,
          mediaDir: Directory('${check.path}/media'),
        );
        await checkDb.close();
        manifest['data_fingerprint'] = withoutPhotos.fingerprint;
        final String uri = await uploadTar(
          'bez-zdjec.age',
          _tar([...noPhotos, _manifestEntry(manifest)]),
        );

        final ({Directory dir, GrobingDatabase db}) used = await phone(
          'used',
          withData: true,
        );
        await restoreServiceIn(used.dir, used.db, drive).restore(
          backupUri: uri,
          keyUri: FakeDocumentStore.uriOf('klucz.age'),
          passphrase: _passphrase,
        );

        final DataState after = await stateOnDisk(used.dir);
        expect(after.fingerprint, withoutPhotos.fingerprint);
        expect(after.mediaFileCount, 0);
      },
    );
  });

  test(
    'ISSUE-014 DoD — cemeteries added and corrected on the home screen come back from a backup '
    'with their points',
    () async {
      final Directory from = Directory('${tmp.path}/home-screen')..createSync();
      final GrobingDatabase db = GrobingDatabase(
        NativeDatabase(File('${from.path}/grobing.db')),
      );
      final int moved = await addCemetery(
        db,
        name: 'Cmentarz Wymyślny',
        locality: 'Miejscowość Testowa',
        point: const GeoPoint(50.5, 19.5),
      );
      await updateCemetery(
        db,
        moved,
        name: 'Cmentarz Wymyślony',
        locality: 'Miejscowość Testowa',
        point: const GeoPoint(51.0, 20.0),
      );
      await addCemetery(db, name: 'Cmentarz Próbny');
      final DataState before = await readDataState(
        db,
        mediaDir: Directory('${from.path}/media'),
      );
      await db.customStatement('VACUUM INTO ?', ['${tmp.path}/home.db']);
      await db.close();
      final File backup = File('${tmp.path}/home.age');
      await writeEncryptedBackup(
        snapshot: File('${tmp.path}/home.db'),
        mediaDir: Directory('${from.path}/media'),
        recipient: identity.recipient,
        output: backup,
        createdAt: _createdAt,
      );
      final String uri = upload('home.age', backup.readAsBytesSync());

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('fresh');
      await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
        backupUri: uri,
        keyUri: FakeDocumentStore.uriOf('klucz.age'),
        passphrase: _passphrase,
      );

      expect((await stateOnDisk(fresh.dir)).fingerprint, before.fingerprint);
      final GrobingDatabase restored = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      try {
        final List<CemeterySummary> all = await watchCemeteries(restored).first;
        expect(all.map((c) => (c.name, c.point)), [
          ('Cmentarz Wymyślony', const GeoPoint(51.0, 20.0)),
          ('Cmentarz Próbny', null),
        ]);
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'ISSUE-015 DoD — a cemetery added from the bundled database comes back from a backup with the '
    "database's point and the corrected name",
    () async {
      final BaseCemetery powazki = CemeteryBase.fromJson(
        File(CemeteryBase.asset).readAsStringSync(),
      ).search('powazki').shown.firstWhere((c) => c.locality == 'Warszawa');
      final Directory from = Directory('${tmp.path}/from-base')..createSync();
      final GrobingDatabase db = GrobingDatabase(
        NativeDatabase(File('${from.path}/grobing.db')),
      );
      await addCemetery(
        db,
        name: 'Stare Powązki',
        locality: powazki.locality,
        point: powazki.point,
      );
      await db.customStatement('VACUUM INTO ?', ['${tmp.path}/from-base.db']);
      await db.close();
      final File backup = File('${tmp.path}/from-base.age');
      await writeEncryptedBackup(
        snapshot: File('${tmp.path}/from-base.db'),
        mediaDir: Directory('${from.path}/media'),
        recipient: identity.recipient,
        output: backup,
        createdAt: _createdAt,
      );
      final String uri = upload('from-base.age', backup.readAsBytesSync());

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('fresh');
      await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
        backupUri: uri,
        keyUri: FakeDocumentStore.uriOf('klucz.age'),
        passphrase: _passphrase,
      );

      final GrobingDatabase restored = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      try {
        final CemeterySummary c = (await watchCemeteries(
          restored,
        ).first).single;
        expect(
          (c.name, c.locality, c.point),
          ('Stare Powązki', 'Warszawa', powazki.point),
        );
      } finally {
        await restored.close();
      }
    },
  );

  group('D3 — the backup after a restore', () {
    test(
      'fresh phone: goes on with the restored key, to the restored file',
      () async {
        final ({Directory dir, GrobingDatabase db}) fresh = await phone(
          'fresh',
        );
        final RestoreResult result =
            await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
              backupUri: FakeDocumentStore.uriOf('kopia.age'),
              keyUri: FakeDocumentStore.uriOf('klucz.age'),
              passphrase: _passphrase,
            );

        expect(result.backup, RestoredBackup.continued);
        final BackupSettings settings = (await BackupSettingsStore(
          File('${fresh.dir.path}/backup.json'),
        ).read())!;
        expect(settings.recipient, identity.recipient.encode());
        expect(settings.documentUri, FakeDocumentStore.uriOf('kopia.age'));
        expect(drive.kept, {FakeDocumentStore.uriOf('kopia.age')});
      },
    );

    test(
      'fresh phone, provider refuses writing: not configured, no settings',
      () async {
        drive.writable = false;
        final ({Directory dir, GrobingDatabase db}) fresh = await phone(
          'fresh',
        );
        final RestoreResult result =
            await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
              backupUri: FakeDocumentStore.uriOf('kopia.age'),
              keyUri: FakeDocumentStore.uriOf('klucz.age'),
              passphrase: _passphrase,
            );

        expect(result.backup, RestoredBackup.notConfigured);
        expect(File('${fresh.dir.path}/backup.json').existsSync(), isFalse);
        expect((await stateOnDisk(fresh.dir)).fingerprint, sourceFingerprint);
      },
    );

    test('phone with a backup set up: keeps its own key and file', () async {
      final ({Directory dir, GrobingDatabase db}) used = await phone(
        'used',
        withData: true,
      );
      const BackupSettings own = BackupSettings(
        recipient: 'age1ownkey',
        documentUri: 'content://fake/own.age',
      );
      await BackupSettingsStore(
        File('${used.dir.path}/backup.json'),
      ).write(own);

      final RestoreResult result =
          await restoreServiceIn(used.dir, used.db, drive).restore(
            backupUri: FakeDocumentStore.uriOf('kopia.age'),
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(result.backup, RestoredBackup.kept);
      final BackupSettings after = (await BackupSettingsStore(
        File('${used.dir.path}/backup.json'),
      ).read())!;
      expect(
        (after.recipient, after.documentUri),
        (own.recipient, own.documentUri),
      );
      expect((await stateOnDisk(used.dir)).fingerprint, sourceFingerprint);
    });
  });

  group('AC-2 — refused with a readable message, the phone untouched', () {
    late ({Directory dir, GrobingDatabase db}) used;
    late String before;

    setUp(() async {
      used = await phone('used', withData: true);
      before = (await readDataState(
        used.db,
        mediaDir: Directory('${used.dir.path}/media'),
      )).fingerprint;
    });

    tearDown(() => used.db.close());

    /// Restores and expects a refusal whose message contains [message]; then checks that nothing
    /// changed: same fingerprint, database still open, no staging, no marker, no path in the message.
    Future<void> refused(
      String message, {
      String? backupUri,
      String? keyUri,
      String passphrase = _passphrase,
    }) async {
      final RestoreService restore = restoreServiceIn(used.dir, used.db, drive);
      await expectLater(
        restore.restore(
          backupUri: backupUri ?? FakeDocumentStore.uriOf('kopia.age'),
          keyUri: keyUri ?? FakeDocumentStore.uriOf('klucz.age'),
          passphrase: passphrase,
        ),
        throwsA(
          isA<BackupException>()
              .having((e) => e.message, 'message', contains(message))
              .having((e) => e.message, 'message', isNot(contains(tmp.path)))
              .having((e) => e.message, 'message', isNot(contains(passphrase))),
        ),
      );
      expect(restore.databaseClosed, isFalse);
      final DataState after = await readDataState(
        used.db,
        mediaDir: Directory('${used.dir.path}/media'),
      );
      expect(after.fingerprint, before);
      expect(
        Directory('${used.dir.path}/restore-staging').existsSync(),
        isFalse,
      );
      expect(File('${used.dir.path}/restore.json').existsSync(), isFalse);
    }

    test(
      'wrong passphrase',
      () => refused('Złe hasło', passphrase: 'inne hasło'),
    );

    test('a key file from another setup', () async {
      final ({Uint8List keyFile, X25519Identity identity}) other =
          await _cheapKey(_passphrase);
      upload('inny-klucz.age', other.keyFile);
      await refused(
        'Ten plik klucza nie otwiera tej kopii',
        keyUri: FakeDocumentStore.uriOf('inny-klucz.age'),
      );
    });

    test('a "key file" too large to be one (e.g. the backup picked twice)', () {
      upload('duzy.age', Uint8List(RestoreService.keyFileMaxBytes + 1));
      return refused(
        'To nie jest plik klucza',
        keyUri: FakeDocumentStore.uriOf('duzy.age'),
      );
    });

    test(
      'a key file whose scrypt would need more memory than a phone has',
      () async {
        final ({Uint8List keyFile, X25519Identity identity}) heavy =
            await _cheapKey(_passphrase);
        // Same stanza, work factor 21 written in: refused before anything is computed.
        final String text = latin1.decode(heavy.keyFile);
        final String heavier = text.replaceFirstMapped(
          RegExp(r'(-> scrypt \S+) 10\n'),
          (m) => '${m[1]} 21\n',
        );
        expect(heavier, isNot(text));
        upload('ciezki-klucz.age', latin1.encode(heavier));
        await refused(
          'Nie da się otworzyć pliku klucza',
          keyUri: FakeDocumentStore.uriOf('ciezki-klucz.age'),
        );
      },
    );

    test('not an age file at all', () {
      upload('notatka.age', utf8.encode('to jest zwykły tekst, nie kopia'));
      return refused(
        'To nie jest plik kopii Grobing',
        backupUri: FakeDocumentStore.uriOf('notatka.age'),
      );
    });

    test('one changed bit in the backup file', () {
      final Uint8List bytes = drive
          .fileFor(FakeDocumentStore.uriOf('kopia.age'))
          .readAsBytesSync();
      bytes[bytes.length - 100] ^= 0x01;
      upload('zmieniona.age', bytes);
      return refused(
        'uszkodzony',
        backupUri: FakeDocumentStore.uriOf('zmieniona.age'),
      );
    });

    test('a backup file cut short', () {
      final Uint8List bytes = drive
          .fileFor(FakeDocumentStore.uriOf('kopia.age'))
          .readAsBytesSync();
      upload('ucieta.age', bytes.sublist(0, bytes.length - 3000));
      return refused(
        'niepełny',
        backupUri: FakeDocumentStore.uriOf('ucieta.age'),
      );
    });

    for (final (String what, String path, String type) in [
      ('a path that climbs out with ..', 'media/../../evil', '0'),
      ('an absolute path', '/evil', '0'),
      ('a symbolic link', 'media/link', '2'),
      ('a file Grobing does not write', 'other.txt', '0'),
    ]) {
      test('a correctly encrypted tar with $what', () async {
        final List<_Entry> entries = _untar(backupTar);
        final List<int> tar = [
          ..._rawHeader(path, 1, type: type),
          0x41,
          ...Uint8List(511),
          ..._tar(entries),
        ];
        final String uri = await uploadTar('zla.age', tar);
        await refused('której Grobing nie zapisuje', backupUri: uri);
        expect(File('${tmp.path}/evil').existsSync(), isFalse);
        expect(File('${used.dir.path}/other.txt').existsSync(), isFalse);
      });
    }

    test('the database twice in the archive', () async {
      final List<_Entry> entries = _untar(backupTar);
      final String uri = await uploadTar(
        'podwojna.age',
        _tar([entries.first, ...entries]),
      );
      await refused('której Grobing nie zapisuje', backupUri: uri);
    });

    test('a photo whose SHA-256 does not match the manifest', () async {
      final List<_Entry> entries = _untar(backupTar);
      final int photo = entries.indexWhere(
        (e) => e.path.startsWith(backupMediaPrefix),
      );
      final List<int> changed = [...entries[photo].data]..[0] ^= 0xff;
      entries[photo] = (path: entries[photo].path, data: changed);
      final String uri = await uploadTar('suma.age', _tar(entries));
      await refused('nie zgadza się z jej opisem', backupUri: uri);
    });

    test('a manifest listing a file the archive does not have', () async {
      final List<_Entry> entries = _untar(backupTar);
      final Map<String, Object?> manifest = _manifestOf(entries);
      (manifest['files']! as List<Object?>).add({
        'path': 'media/brak.jpg',
        'size': 1,
        'sha256': '0' * 64,
      });
      final String uri = await uploadTar(
        'brak.age',
        _tar([...entries.take(entries.length - 1), _manifestEntry(manifest)]),
      );
      await refused('nie zgadza się z jej opisem', backupUri: uri);
    });

    test('a data fingerprint that does not match the database', () async {
      final List<_Entry> entries = _untar(backupTar);
      final Map<String, Object?> manifest = _manifestOf(entries)
        ..['data_fingerprint'] = '0' * 64;
      final String uri = await uploadTar(
        'odcisk.age',
        _tar([...entries.take(entries.length - 1), _manifestEntry(manifest)]),
      );
      await refused('nie zgadza się z jej opisem', backupUri: uri);
    });

    test('record counts that do not match the database', () async {
      final List<_Entry> entries = _untar(backupTar);
      final Map<String, Object?> manifest = _manifestOf(entries);
      (manifest['record_counts']! as Map<String, Object?>)['persons'] = 999;
      final String uri = await uploadTar(
        'liczby.age',
        _tar([...entries.take(entries.length - 1), _manifestEntry(manifest)]),
      );
      await refused('nie zgadza się z jej opisem', backupUri: uri);
    });

    test('the manifest not last in the archive', () async {
      final List<_Entry> entries = _untar(backupTar);
      final String uri = await uploadTar(
        'kolejnosc.age',
        _tar([entries.last, ...entries.take(entries.length - 1)]),
      );
      await refused('nie zgadza się z jej opisem', backupUri: uri);
    });

    test('a damaged database whose checksums match its manifest', () async {
      final List<_Entry> entries = _untar(backupTar);
      final List<int> db = [...entries.first.data];
      // Overwrite the second page (the first table's b-tree) with noise; the header stays valid.
      for (int i = 4096 + 8; i < 4096 + 400; i++) {
        db[i] = (i * 31) & 0xff;
      }
      final List<_Entry> files = [
        (path: backupDatabaseName, data: db),
        ...entries.skip(1).take(entries.length - 2),
      ];
      final String uri = await uploadTar(
        'baza.age',
        _tar([
          ...files,
          _manifestEntry(_withFiles(_manifestOf(entries), files)),
        ]),
      );
      await refused('uszkodzona', backupUri: uri);
    });

    test('a backup from a newer schema asks for an update', () async {
      final List<_Entry> entries = _untar(backupTar);
      final Map<String, Object?> manifest = _manifestOf(entries)
        ..['schema_version'] = GrobingDatabase.currentSchemaVersion + 1;
      final String uri = await uploadTar(
        'nowsza.age',
        _tar([...entries.take(entries.length - 1), _manifestEntry(manifest)]),
      );
      await refused('Zaktualizuj aplikację', backupUri: uri);
    });

    test('a backup in a newer format asks for an update', () async {
      final List<_Entry> entries = _untar(backupTar);
      final Map<String, Object?> manifest = _manifestOf(entries)
        ..['format_version'] = 2;
      final String uri = await uploadTar(
        'format2.age',
        _tar([...entries.take(entries.length - 1), _manifestEntry(manifest)]),
      );
      await refused('Zaktualizuj aplikację', backupUri: uri);
    });
  });

  group('AC-5 — too large for the phone: refused before unpacking', () {
    late ({Directory dir, GrobingDatabase db}) used;

    setUp(() async => used = await phone('used', withData: true));
    tearDown(() => used.db.close());

    test(
      'known size: free space under 2 × size + 200 MB → refused before copying',
      () async {
        final int size = drive
            .fileFor(FakeDocumentStore.uriOf('kopia.age'))
            .lengthSync();
        drive.free = 2 * size + RestoreService.spaceMargin - 1;
        final RestoreService restore = restoreServiceIn(
          used.dir,
          used.db,
          drive,
        );
        await expectLater(
          restore.restore(
            backupUri: FakeDocumentStore.uriOf('kopia.age'),
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          ),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'm',
              contains('Za mało miejsca'),
            ),
          ),
        );
        // Not even the key file was read: the check comes first.
        expect(drive.readBudgets, isEmpty);
        expect(
          Directory('${used.dir.path}/restore-staging').existsSync(),
          isFalse,
        );
      },
    );

    test('known size and just enough space → restored', () async {
      final int size = drive
          .fileFor(FakeDocumentStore.uriOf('kopia.age'))
          .lengthSync();
      drive.free = 2 * size + RestoreService.spaceMargin;
      await restoreServiceIn(used.dir, used.db, drive).restore(
        backupUri: FakeDocumentStore.uriOf('kopia.age'),
        keyUri: FakeDocumentStore.uriOf('klucz.age'),
        passphrase: _passphrase,
      );
      expect((await stateOnDisk(used.dir)).fingerprint, sourceFingerprint);
    });

    test(
      'unknown size: reading stops at what fits twice → refused, nothing left',
      () async {
        drive.sizeUnknown = true;
        final int size = drive
            .fileFor(FakeDocumentStore.uriOf('kopia.age'))
            .lengthSync();
        // Budget = (free - margin) / 2, one byte short of the file.
        drive.free = RestoreService.spaceMargin + 2 * (size - 1);
        final RestoreService restore = restoreServiceIn(
          used.dir,
          used.db,
          drive,
        );
        await expectLater(
          restore.restore(
            backupUri: FakeDocumentStore.uriOf('kopia.age'),
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          ),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'm',
              contains('Za mało miejsca'),
            ),
          ),
        );
        expect(drive.readBudgets.last, size - 1);
        expect(
          Directory('${used.dir.path}/restore-staging').existsSync(),
          isFalse,
        );
      },
    );
  });

  test('ISSUE-011 AC-4 — a real v1 backup restores into the current app: v1 tables and counts kept, every '
      'date and burial carried over with one claim', () async {
    // The v1 phone's snapshot, made by the v1 schema itself (drift's export of v1). The backup
    // writer reads snapshots at the app's own version, so the v1 archive is assembled here.
    final File v1File = File('${tmp.path}/v1.db');
    final v1.DatabaseAtV1 old = v1.DatabaseAtV1(NativeDatabase(v1File));
    for (final String row in _v1Rows) {
      await old.customStatement(row);
    }
    final DataState v1State = await readDataState(
      old,
      mediaDir: Directory('${tmp.path}/v1-media'),
    );
    expect(v1State.schemaVersion, 1);
    await old.customStatement('VACUUM INTO ?', ['${tmp.path}/v1-snapshot.db']);
    await old.close();
    final List<_Entry> files = [
      (
        path: backupDatabaseName,
        data: File('${tmp.path}/v1-snapshot.db').readAsBytesSync(),
      ),
    ];
    final String uri = await uploadTar(
      'kopia-v1.age',
      _tar([
        ...files,
        _manifestEntry(
          _withFiles({
            ..._manifestOf(_untar(backupTar)),
            'schema_version': 1,
            'record_counts': v1State.rowCounts,
            'data_fingerprint': v1State.fingerprint,
          }, files),
        ),
      ]),
    );

    final ({Directory dir, GrobingDatabase db}) fresh = await phone('fresh');
    final RestoreResult result =
        await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
          backupUri: uri,
          keyUri: FakeDocumentStore.uriOf('klucz.age'),
          passphrase: _passphrase,
        );

    expect(
      (result.schemaFrom, result.schemaTo),
      (1, GrobingDatabase.currentSchemaVersion),
    );
    final DataState after = await stateOnDisk(fresh.dir);
    expect(after.schemaVersion, GrobingDatabase.currentSchemaVersion);
    for (final MapEntry<String, int> table in v1State.rowCounts.entries) {
      expect(after.rowCounts[table.key], table.value, reason: table.key);
    }
    expect(after.rowCounts['assertions'], 4);

    final GrobingDatabase reopened = GrobingDatabase(
      NativeDatabase(File('${fresh.dir.path}/grobing.db')),
    );
    final List<Assertion> claims = await reopened
        .select(reopened.assertions)
        .get();
    await reopened.close();
    expect(
      claims.map((c) => (c.sourceKind, c.sourceDetail, c.status)).toSet(),
      {(SourceKind.notes, carriedOverFromV1, AssertionStatus.claimed)},
    );
  });

  test(
    'ISSUE-012 DoD — a grave entered through the transcription screens comes back from the backup: '
    'the same fingerprint, its name, both people with their dates',
    () async {
      final ({Directory dir, GrobingDatabase db}) entered = await phone(
        'entered',
      );
      final int cemetery = await addCemetery(
        entered.db,
        name: 'Cmentarz Wymyślony',
      );
      final int grave = await addPersonToNewGrave(
        entered.db,
        cemeteryId: cemetery,
        entry: const PersonEntry(
          givenNames: 'Jan',
          surname: 'Wymyślony',
          bio: 'Kowal, wymyślony do testów.',
          birth: QualifiedDate(DateQualifier.about, PartialDate(1890)),
        ),
      );
      await addPersonToGrave(
        entered.db,
        graveId: grave,
        entry: const PersonEntry(
          givenNames: 'Anna',
          surname: 'Wymyślona',
          birthSurname: 'Zmyślona',
          birth: QualifiedDate(
            DateQualifier.between,
            PartialDate(1893),
            PartialDate(1895),
          ),
        ),
      );
      await setGraveName(entered.db, grave, 'Grób rodzinny Wymyślonych');
      final DataState before = await readDataState(
        entered.db,
        mediaDir: Directory('${entered.dir.path}/media'),
      );
      await entered.db.customStatement('VACUUM INTO ?', [
        '${tmp.path}/entered.db',
      ]);
      await entered.db.close();
      final String uri = FakeDocumentStore.uriOf('kopia-wpisy.age');
      await writeEncryptedBackup(
        snapshot: File('${tmp.path}/entered.db'),
        mediaDir: Directory('${entered.dir.path}/media'),
        recipient: identity.recipient,
        output: drive.fileFor(uri)..createSync(recursive: true),
        createdAt: _createdAt,
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('fresh');
      await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
        backupUri: uri,
        keyUri: FakeDocumentStore.uriOf('klucz.age'),
        passphrase: _passphrase,
      );

      expect((await stateOnDisk(fresh.dir)).fingerprint, before.fingerprint);
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final GraveDetail restored = (await loadGrave(reopened, grave))!;
      await reopened.close();
      expect(restored.name, 'Grób rodzinny Wymyślonych');
      expect(restored.people.map((p) => p.givenNames), ['Jan', 'Anna']);
      expect(restored.people.last.birth.date!.qualifier, DateQualifier.between);
      expect(restored.people.first.bioSource, defaultBioSource);
    },
  );

  test(
    'ISSUE-016 AC-3 — a gravestone photo comes back from the backup: the same file, the same row, the '
    'same fingerprint',
    () async {
      final ({Directory dir, GrobingDatabase db}) entered = await phone(
        'zdjecie',
      );
      final Directory media = Directory('${entered.dir.path}/media');
      final int cemetery = await addCemetery(
        entered.db,
        name: 'Cmentarz Wymyślony',
      );
      final int grave = await addPersonToNewGrave(
        entered.db,
        cemeteryId: cemetery,
        entry: const PersonEntry(givenNames: 'Jan', surname: 'Wymyślony'),
      );
      final File prepared = File('${tmp.path}/photo-work/gotowe.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(fictionalGravestonePng(5));
      final List<int> bytes = prepared.readAsBytesSync();
      final String path = await setGravePhoto(
        entered.db,
        media,
        grave,
        prepared,
      );
      final DataState before = await readDataState(entered.db, mediaDir: media);
      expect(before.mediaFileCount, 1);
      await entered.db.customStatement('VACUUM INTO ?', [
        '${tmp.path}/zdjecie.db',
      ]);
      await entered.db.close();
      final String uri = FakeDocumentStore.uriOf('kopia-zdjecie.age');
      await writeEncryptedBackup(
        snapshot: File('${tmp.path}/zdjecie.db'),
        mediaDir: media,
        recipient: identity.recipient,
        output: drive.fileFor(uri)..createSync(recursive: true),
        createdAt: _createdAt,
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('nowy');
      await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
        backupUri: uri,
        keyUri: FakeDocumentStore.uriOf('klucz.age'),
        passphrase: _passphrase,
      );

      expect((await stateOnDisk(fresh.dir)).fingerprint, before.fingerprint);
      expect(File('${fresh.dir.path}/media/$path').readAsBytesSync(), bytes);
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final String? restored = await gravePhotoPath(reopened, grave);
      await reopened.close();
      expect(restored, path);
    },
  );

  test(
    'ISSUE-012 — a v2 backup restores into the current app: every v2 table and count kept, graves '
    'without a name',
    () async {
      final File v2File = File('${tmp.path}/v2.db');
      final v2.DatabaseAtV2 old = v2.DatabaseAtV2(NativeDatabase(v2File));
      for (final String row in _v2Rows) {
        await old.customStatement(row);
      }
      await old.customStatement('PRAGMA user_version = 2');
      final DataState v2State = await readDataState(
        old,
        mediaDir: Directory('${tmp.path}/v2-media'),
      );
      expect(v2State.schemaVersion, 2);
      await old.customStatement('VACUUM INTO ?', [
        '${tmp.path}/v2-snapshot.db',
      ]);
      await old.close();
      final List<_Entry> files = [
        (
          path: backupDatabaseName,
          data: File('${tmp.path}/v2-snapshot.db').readAsBytesSync(),
        ),
      ];
      final String uri = await uploadTar(
        'kopia-v2.age',
        _tar([
          ...files,
          _manifestEntry(
            _withFiles({
              ..._manifestOf(_untar(backupTar)),
              'schema_version': 2,
              'record_counts': v2State.rowCounts,
              'data_fingerprint': v2State.fingerprint,
            }, files),
          ),
        ]),
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('fresh');
      final RestoreResult result =
          await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
            backupUri: uri,
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(
        (result.schemaFrom, result.schemaTo),
        (2, GrobingDatabase.currentSchemaVersion),
      );
      final DataState after = await stateOnDisk(fresh.dir);
      expect(after.schemaVersion, GrobingDatabase.currentSchemaVersion);
      // Every v2 table with its count; a table added later (person_media, v4) is there and empty.
      for (final MapEntry<String, int> t in v2State.rowCounts.entries) {
        expect(after.rowCounts[t.key], t.value, reason: t.key);
      }
      expect(after.rowCounts['person_media'], 0);
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final List<Grave> graves = await reopened.select(reopened.graves).get();
      await reopened.close();
      expect(graves.map((g) => (g.id, g.name, g.sector)), [
        (1, null, null),
        (2, null, 'B'),
      ]);
    },
  );

  test(
    'ISSUE-017 F3 — a v3 backup with people\'s photos restores into the v4 app: every v3 table and '
    'count kept, each person photo becomes that person\'s link in the order of its id, the grave keeps '
    'its photo, every file is there',
    () async {
      final File v3File = File('${tmp.path}/v3.db');
      final Directory v3Media = Directory('${tmp.path}/v3-media');
      final v3.DatabaseAtV3 old = v3.DatabaseAtV3(NativeDatabase(v3File));
      for (final String row in _v3Rows) {
        await old.customStatement(row);
      }
      await old.customStatement('PRAGMA user_version = 3');
      const List<String> photoPaths = [
        'groby/1/nagrobek.png',
        'osoby/anna-1.png',
        'osoby/anna-2.png',
        'osoby/jan-1.png',
      ];
      for (final (int i, String path) in photoPaths.indexed) {
        File('${v3Media.path}/$path')
          ..createSync(recursive: true)
          ..writeAsBytesSync(fictionalGravestonePng(i + 1));
      }
      final DataState v3State = await readDataState(old, mediaDir: v3Media);
      expect(v3State.schemaVersion, 3);
      expect(v3State.mediaFileCount, 4);
      await old.customStatement('VACUUM INTO ?', [
        '${tmp.path}/v3-snapshot.db',
      ]);
      await old.close();
      final List<_Entry> files = [
        (
          path: backupDatabaseName,
          data: File('${tmp.path}/v3-snapshot.db').readAsBytesSync(),
        ),
        for (final String path in photoPaths)
          (
            path: 'media/$path',
            data: File('${v3Media.path}/$path').readAsBytesSync(),
          ),
      ];
      final String uri = await uploadTar(
        'kopia-v3.age',
        _tar([
          ...files,
          _manifestEntry(
            _withFiles({
              ..._manifestOf(_untar(backupTar)),
              'schema_version': 3,
              'record_counts': v3State.rowCounts,
              'data_fingerprint': v3State.fingerprint,
            }, files),
          ),
        ]),
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('v4');
      final RestoreResult result =
          await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
            backupUri: uri,
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(
        (result.schemaFrom, result.schemaTo),
        (3, GrobingDatabase.currentSchemaVersion),
      );
      final DataState after = await stateOnDisk(fresh.dir);
      expect(after.schemaVersion, GrobingDatabase.currentSchemaVersion);
      for (final MapEntry<String, int> t in v3State.rowCounts.entries) {
        expect(after.rowCounts[t.key], t.value, reason: t.key);
      }
      expect(after.rowCounts['person_media'], 3);
      expect(after.mediaFileCount, 4);
      for (final String path in photoPaths) {
        expect(
          File('${fresh.dir.path}/media/$path').existsSync(),
          isTrue,
          reason: path,
        );
      }
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final List<String> anna = [
        for (final PersonPhoto p in await personPhotos(reopened, 2))
          p.relativePath,
      ];
      final List<String> jan = [
        for (final PersonPhoto p in await personPhotos(reopened, 1))
          p.relativePath,
      ];
      final String? gravestone = await gravePhotoPath(reopened, 1);
      final List<Object?> broken = [
        for (final r
            in await reopened.customSelect('PRAGMA foreign_key_check').get())
          r.data,
      ];
      await reopened.close();
      expect(anna, ['osoby/anna-1.png', 'osoby/anna-2.png']);
      expect(jan, ['osoby/jan-1.png']);
      expect(gravestone, 'groby/1/nagrobek.png');
      expect(broken, isEmpty);
    },
  );

  test(
    'ISSUE-019 F2 — a v5 backup with families restores into the v6 app: every v5 table and count kept '
    '(the migration adds no claims — D3), each child link gets an id, the families read as before',
    () async {
      final File v5File = File('${tmp.path}/v5.db');
      final v5.DatabaseAtV5 old = v5.DatabaseAtV5(NativeDatabase(v5File));
      for (final String row in _v5Rows) {
        await old.customStatement(row);
      }
      await old.customStatement('PRAGMA user_version = 5');
      final DataState v5State = await readDataState(
        old,
        mediaDir: Directory('${tmp.path}/v5-media'),
      );
      expect(v5State.schemaVersion, 5);
      expect(v5State.rowCounts['family_children'], 2);
      await old.customStatement('VACUUM INTO ?', [
        '${tmp.path}/v5-snapshot.db',
      ]);
      await old.close();
      final List<_Entry> files = [
        (
          path: backupDatabaseName,
          data: File('${tmp.path}/v5-snapshot.db').readAsBytesSync(),
        ),
      ];
      final String uri = await uploadTar(
        'kopia-v5.age',
        _tar([
          ...files,
          _manifestEntry(
            _withFiles({
              ..._manifestOf(_untar(backupTar)),
              'schema_version': 5,
              'record_counts': v5State.rowCounts,
              'data_fingerprint': v5State.fingerprint,
            }, files),
          ),
        ]),
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('v6');
      final RestoreResult result =
          await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
            backupUri: uri,
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(
        (result.schemaFrom, result.schemaTo),
        (5, GrobingDatabase.currentSchemaVersion),
      );
      final DataState after = await stateOnDisk(fresh.dir);
      expect(after.schemaVersion, GrobingDatabase.currentSchemaVersion);
      expect(after.rowCounts, v5State.rowCounts);
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final PersonRelations father = await loadRelations(reopened, 1);
      final List<FamilyChildrenData> links = await reopened
          .select(reopened.familyChildren)
          .get();
      final List<Object?> broken = [
        for (final r
            in await reopened.customSelect('PRAGMA foreign_key_check').get())
          r.data,
      ];
      await reopened.close();
      expect(father.unions.map((u) => u.partner!.id), [2, 4]);
      expect(father.unions.map((u) => u.children.single.id), [3, 5]);
      expect(links.map((l) => l.id), [1, 2]);
      expect(broken, isEmpty);
    },
  );

  test(
    'ISSUE-025 AC-4 — a v6 backup restores into the v7 app: every v6 table and count kept, the people come '
    'without a sex, the unions without "Razem od", the one with a wedding married and the other not',
    () async {
      final File v6File = File('${tmp.path}/v6.db');
      final v6.DatabaseAtV6 old = v6.DatabaseAtV6(NativeDatabase(v6File));
      for (final String row in _v6Rows) {
        await old.customStatement(row);
      }
      await old.customStatement('PRAGMA user_version = 6');
      final DataState v6State = await readDataState(
        old,
        mediaDir: Directory('${tmp.path}/v6-media'),
      );
      expect(v6State.schemaVersion, 6);
      await old.customStatement('VACUUM INTO ?', [
        '${tmp.path}/v6-snapshot.db',
      ]);
      await old.close();
      final List<_Entry> files = [
        (
          path: backupDatabaseName,
          data: File('${tmp.path}/v6-snapshot.db').readAsBytesSync(),
        ),
      ];
      final String uri = await uploadTar(
        'kopia-v6.age',
        _tar([
          ...files,
          _manifestEntry(
            _withFiles({
              ..._manifestOf(_untar(backupTar)),
              'schema_version': 6,
              'record_counts': v6State.rowCounts,
              'data_fingerprint': v6State.fingerprint,
            }, files),
          ),
        ]),
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('v7');
      final RestoreResult result =
          await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
            backupUri: uri,
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(
        (result.schemaFrom, result.schemaTo),
        (6, GrobingDatabase.currentSchemaVersion),
      );
      final DataState after = await stateOnDisk(fresh.dir);
      expect(after.schemaVersion, GrobingDatabase.currentSchemaVersion);
      expect(after.rowCounts, v6State.rowCounts);
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final List<Person> persons = await reopened
          .select(reopened.persons)
          .get();
      final PersonRelations father = await loadRelations(reopened, 1);
      await reopened.close();
      expect(persons.map((p) => p.sex), everyElement(isNull));
      expect(father.unions.map((u) => u.partner!.id), [2, 4]);
      expect(father.unions.map((u) => u.together), [null, null]);
      expect(father.unions.map((u) => u.married), [true, false]);
      expect(father.unions.first.marriage?.from.year, 1920);
    },
  );

  test(
    'ISSUE-018 F3 — a v4 backup restores into the v5 app: every v4 table and count kept, every link and '
    'its position kept, no link has a crop (the circles show the middle), every file is there',
    () async {
      final File v4File = File('${tmp.path}/v4.db');
      final Directory v4Media = Directory('${tmp.path}/v4-media');
      final v4.DatabaseAtV4 old = v4.DatabaseAtV4(NativeDatabase(v4File));
      for (final String row in _v4Rows) {
        await old.customStatement(row);
      }
      await old.customStatement('PRAGMA user_version = 4');
      const List<String> photoPaths = [
        'groby/1/nagrobek.png',
        'zdjecia/anna.png',
        'zdjecia/slub.png',
      ];
      for (final (int i, String path) in photoPaths.indexed) {
        File('${v4Media.path}/$path')
          ..createSync(recursive: true)
          ..writeAsBytesSync(fictionalPeoplePng(i + 1, heads: 2));
      }
      final DataState v4State = await readDataState(old, mediaDir: v4Media);
      expect(v4State.schemaVersion, 4);
      expect(v4State.rowCounts['person_media'], 3);
      await old.customStatement('VACUUM INTO ?', [
        '${tmp.path}/v4-snapshot.db',
      ]);
      await old.close();
      final List<_Entry> files = [
        (
          path: backupDatabaseName,
          data: File('${tmp.path}/v4-snapshot.db').readAsBytesSync(),
        ),
        for (final String path in photoPaths)
          (
            path: 'media/$path',
            data: File('${v4Media.path}/$path').readAsBytesSync(),
          ),
      ];
      final String uri = await uploadTar(
        'kopia-v4.age',
        _tar([
          ...files,
          _manifestEntry(
            _withFiles({
              ..._manifestOf(_untar(backupTar)),
              'schema_version': 4,
              'record_counts': v4State.rowCounts,
              'data_fingerprint': v4State.fingerprint,
            }, files),
          ),
        ]),
      );

      final ({Directory dir, GrobingDatabase db}) fresh = await phone('v5');
      final RestoreResult result =
          await restoreServiceIn(fresh.dir, fresh.db, drive).restore(
            backupUri: uri,
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(
        (result.schemaFrom, result.schemaTo),
        (4, GrobingDatabase.currentSchemaVersion),
      );
      final DataState after = await stateOnDisk(fresh.dir);
      expect(after.schemaVersion, GrobingDatabase.currentSchemaVersion);
      expect(after.rowCounts, v4State.rowCounts);
      expect(after.mediaFileCount, 3);
      final GrobingDatabase reopened = GrobingDatabase(
        NativeDatabase(File('${fresh.dir.path}/grobing.db')),
      );
      final List<PersonPhoto> jan = await personPhotos(reopened, 1);
      final List<PersonPhoto> anna = await personPhotos(reopened, 2);
      final List<Object?> broken = [
        for (final r
            in await reopened.customSelect('PRAGMA foreign_key_check').get())
          r.data,
      ];
      await reopened.close();
      expect(jan.map((p) => (p.relativePath, p.crop)), [
        ('zdjecia/slub.png', null),
      ]);
      expect(anna.map((p) => (p.relativePath, p.crop)), [
        ('zdjecia/anna.png', null),
        ('zdjecia/slub.png', null),
      ]);
      for (final String path in photoPaths) {
        expect(
          File('${fresh.dir.path}/media/$path').existsSync(),
          isTrue,
          reason: path,
        );
      }
      expect(broken, isEmpty);
    },
  );

  test(
    'AC-3 — a backup from the previous schema restores into a newer app through its own migration',
    () async {
      final Directory dir = Directory('${tmp.path}/next')..createSync();
      final _SchemaNext live = _SchemaNext(
        NativeDatabase(File('${dir.path}/grobing.db')),
      );
      await live.customSelect('SELECT 1').get();

      final RestoreResult result =
          await restoreServiceIn(
            dir,
            live,
            drive,
            schemaVersion: _SchemaNext.version,
            openDatabase: (file) => _SchemaNext(NativeDatabase(file)),
          ).restore(
            backupUri: FakeDocumentStore.uriOf('kopia.age'),
            keyUri: FakeDocumentStore.uriOf('klucz.age'),
            passphrase: _passphrase,
          );

      expect(
        (result.schemaFrom, result.schemaTo),
        (GrobingDatabase.currentSchemaVersion, _SchemaNext.version),
      );
      final _SchemaNext reopened = _SchemaNext(
        NativeDatabase(File('${dir.path}/grobing.db')),
      );
      final DataState state = await readDataState(
        reopened,
        mediaDir: Directory('${dir.path}/media'),
      );
      expect(state.schemaVersion, _SchemaNext.version);
      expect(state.rowCounts, sourceCounts);
      final List<String> columns =
          (await reopened.customSelect('PRAGMA table_info(persons)').get())
              .map((r) => r.read<String>('name'))
              .toList();
      expect(columns, contains('nickname'));
      await reopened.close();
    },
  );

  test(
    'a failed migration refuses the restore and leaves the phone untouched',
    () async {
      final ({Directory dir, GrobingDatabase db}) used = await phone(
        'used',
        withData: true,
      );
      final String before = (await readDataState(
        used.db,
        mediaDir: Directory('${used.dir.path}/media'),
      )).fingerprint;
      // An app that says "one version newer" but opens the file without reaching it: the migration
      // did not happen.
      await expectLater(
        restoreServiceIn(
          used.dir,
          used.db,
          drive,
          schemaVersion: _SchemaNext.version,
          openDatabase: (file) => GrobingDatabase(NativeDatabase(file)),
        ).restore(
          backupUri: FakeDocumentStore.uriOf('kopia.age'),
          keyUri: FakeDocumentStore.uriOf('klucz.age'),
          passphrase: _passphrase,
        ),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'm',
            contains('przenieść'),
          ),
        ),
      );
      expect(
        (await readDataState(
          used.db,
          mediaDir: Directory('${used.dir.path}/media'),
        )).fingerprint,
        before,
      );
      await used.db.close();
    },
  );
}
