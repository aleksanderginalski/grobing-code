import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/data/database.dart';

import 'generated/schema.dart';

// ISSUE-007 AC-4: schema v1 is the reference for every later migration test (NFR-003). With a single
// version `make-migrations` generates no test, so these two pin the reference by hand. The file is
// not called migration_test.dart, so `make-migrations` can still create that one at schema v2.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    'the saved v1 schema (drift_schemas/grobing) is what the current code expects',
    () async {
      final GrobingDatabase db = GrobingDatabase(await verifier.startAt(1));
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 1);
    },
  );

  test(
    'a database created by the app matches the code\'s own schema',
    () async {
      final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.validateDatabaseSchema();
    },
  );
}
