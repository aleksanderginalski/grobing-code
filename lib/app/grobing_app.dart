import 'package:flutter/material.dart';

import 'start_screen.dart';
import 'theme.dart';

/// Root widget of Grobing (`root_widget` in project-config.example.md).
class GrobingApp extends StatelessWidget {
  const GrobingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grobing',
      debugShowCheckedModeBanner: false,
      theme: GrobingTheme.dark,
      home: const StartScreen(),
    );
  }
}
