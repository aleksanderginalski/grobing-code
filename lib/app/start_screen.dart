import 'package:flutter/material.dart';

import 'theme.dart';

/// Empty start screen (ISSUE-002) — the foundation for the first real view.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

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
          ],
        ),
      ),
    );
  }
}
