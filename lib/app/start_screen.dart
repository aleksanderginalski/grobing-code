import 'package:flutter/material.dart';

import '../backup/backup_service.dart';
import '../data/database.dart';
import 'data_state_screen.dart';
import 'theme.dart';

/// Start screen (ISSUE-002) — the foundation for the first real view; leads to "Stan danych"
/// (ISSUE-007).
class StartScreen extends StatelessWidget {
  const StartScreen({
    super.key,
    required this.database,
    required this.location,
    required this.backup,
  });

  final GrobingDatabase database;
  final DataLocation location;
  final BackupService backup;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Grobing',
              style: textTheme.headlineMedium?.copyWith(
                color: GrobingColors.text,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 32,
              height: 2,
              child: ColoredBox(color: GrobingColors.amber),
            ),
            const SizedBox(height: 48),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DataStateScreen(
                    database: database,
                    location: location,
                    backup: backup,
                  ),
                ),
              ),
              child: const Text('Stan danych'),
            ),
          ],
        ),
      ),
    );
  }
}
