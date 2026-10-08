import 'package:flutter/material.dart';

import '../theme.dart';

/// Back and the screen's title (20 sp, semibold) — the bar of the screens under the gear and of the
/// choice of "ja" (05_DESIGN/ustawienia.md → Sketch).
class BackTitleBar extends StatelessWidget {
  const BackTitleBar(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
    child: Row(
      children: [
        const BackButton(color: GrobingColors.text),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                color: GrobingColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
