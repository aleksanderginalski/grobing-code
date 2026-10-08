import 'package:flutter/material.dart';

import '../data/database.dart';
import 'people/people_screen.dart';
import 'photo/photos.dart';
import 'theme.dart';
import 'tree/tree_placeholder_screen.dart';

/// The destinations of the bottom bar (style-b.md rule 12; 05_DESIGN/cmentarze.md, element 18).
enum AppTab {
  map('Mapa', Icons.map_outlined),
  people('Osoby', Icons.group_outlined),
  tree('Drzewo', Icons.account_tree_outlined);

  const AppTab(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The name of the tab's main screen on the navigator's stack. The map's is the first route.
  String get routeName => '/$name';
}

/// Opens [tab]'s main screen, its stack from the start (cmentarze.md, element 18). The map is always the
/// first route — Android's fixed start destination, the last screen before back leaves the app
/// (developer.android.com → Principles of navigation) — so back from another tab's main screen returns
/// to the map. On a tab's main screen its tab does nothing; deeper in its stack it returns there.
void openTab(
  BuildContext context,
  AppTab tab, {
  required GrobingDatabase database,
  Photos? photos,
}) {
  final NavigatorState navigator = Navigator.of(context);
  bool atMain = false;
  navigator.popUntil((route) {
    if (route.isFirst) return true;
    if (route.settings.name == tab.routeName) atMain = true;
    return atMain;
  });
  if (tab == AppTab.map || atMain) return;
  // A tab is not a step deeper: its screen stands at once, without sliding in (and leaves the same way).
  navigator.push(
    PageRouteBuilder<void>(
      settings: RouteSettings(name: tab.routeName),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => switch (tab) {
        AppTab.people => PeopleScreen(database: database, photos: photos),
        AppTab.tree => TreePlaceholderScreen(
          database: database,
          photos: photos,
        ),
        AppTab.map => throw StateError('The map is the first route'),
      },
    ),
  );
}

/// Element 18 of cmentarze.md: the bottom bar on the viewing screens — hidden in forms, windows, choice
/// modes and on a photo over the whole screen (style-b.md rule 12). [active] is the tab the screen was
/// opened from; it stays active over its whole stack (SPIKE-004 D2).
class GrobingTabBar extends StatelessWidget {
  const GrobingTabBar({
    super.key,
    required this.active,
    required this.database,
    this.photos,
  });

  final AppTab active;
  final GrobingDatabase database;
  final Photos? photos;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: GrobingColors.surface,
      border: Border(top: BorderSide(color: GrobingColors.outline)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            for (final AppTab tab in AppTab.values)
              Expanded(
                child: _Tab(
                  tab: tab,
                  active: tab == active,
                  onTap: () =>
                      openTab(context, tab, database: database, photos: photos),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One tab: the icon over its label; the active one in amber, its label underlined 2 dp.
class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.active, required this.onTap});

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? GrobingColors.amber : GrobingColors.textMuted;
    return Semantics(
      container: true,
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, color: color),
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? GrobingColors.amber : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  tab.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
