import 'package:flutter/material.dart';

import '../data/database.dart';
import 'start_screen.dart';
import 'theme.dart';

/// Root widget of Grobing (`root_widget` in project-config.example.md).
class GrobingApp extends StatelessWidget {
  const GrobingApp({super.key, required this.database, required this.location});

  final GrobingDatabase database;
  final DataLocation location;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grobing',
      debugShowCheckedModeBanner: false,
      theme: GrobingTheme.dark,
      home: StartScreen(database: database, location: location),
    );
  }
}
