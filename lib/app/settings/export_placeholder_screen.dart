import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/title_bar.dart';

/// "Eksport dla rodziny" before the export is built (ISSUE-022 D1 = A, the author's decision at stop #1):
/// the row stands where it will stay, and this says when it comes. Goes away with US-006
/// (05_DESIGN/ustawienia.md, elements 8–11).
class ExportPlaceholderScreen extends StatelessWidget {
  const ExportPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackTitleBar('Eksport dla rodziny'),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ios_share,
                      size: 48,
                      color: GrobingColors.outline,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Eksport powstanie z US-006: jeden plik HTML i jeden PDF, '
                      'które otworzą się bez Grobing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
