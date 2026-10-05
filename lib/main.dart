import 'package:flutter/material.dart';

import 'app/grobing_app.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DataLocation location = await DataLocation.appDefault();
  final GrobingDatabase database = GrobingDatabase.atFile(
    location.databaseFile,
  );
  runApp(GrobingApp(database: database, location: location));
}
