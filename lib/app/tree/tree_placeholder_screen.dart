import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../photo/photos.dart';
import '../tabs.dart';
import '../theme.dart';

/// The Drzewo tab before the tree is built (ISSUE-022 D1 = A, the author's decision at stop #1): the bar
/// has its final three tabs, and this one says plainly when the tree comes. Goes away with the tree
/// (SPIKE-002, 05_DESIGN/drzewo.md).
class TreePlaceholderScreen extends StatelessWidget {
  const TreePlaceholderScreen({super.key, required this.database, this.photos});

  final GrobingDatabase database;
  final Photos? photos;

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: GrobingTabBar(
      active: AppTab.tree,
      database: database,
      photos: photos,
    ),
    body: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  header: true,
                  child: const Text(
                    'Drzewo',
                    style: TextStyle(
                      color: GrobingColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 48,
                      color: GrobingColors.outline,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Drzewo powstanie po SPIKE-002.\n'
                      'Na razie rodzinę widać przy osobie.',
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
