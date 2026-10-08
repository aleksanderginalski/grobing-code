import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/people.dart';
import '../grave/person_form_screen.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'me_picker_screen.dart';
import 'people_list.dart';

/// The Osoby tab (ISSUE-022; 05_DESIGN/osoby.md v1): everyone in the app, found by name without knowing
/// the cemetery — "Ja" on top, then A–Z by surname. A card opens the person's entry until the person
/// view exists (ISSUE-022 D2). Back returns here with the same text and the same place in the list.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.database, this.photos});

  final GrobingDatabase database;
  final Photos? photos;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  late Stream<List<PersonListEntry>> _people = watchPeople(widget.database);
  late final Stream<int?> _me = watchMe(widget.database);
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The search gives up the keyboard first: a field still focused takes it back when the person's
  /// screen closes, and the keyboard would cover the list just returned to (found on the emulator).
  /// The field itself, not the route's scope: the scope remembers its last field and refocuses it.
  Future<void> _open(int personId) {
    FocusManager.instance.primaryFocus?.unfocus();
    return openPersonEntry(
      context,
      widget.database,
      personId,
      photos: widget.photos,
    );
  }

  /// "Ja" not chosen yet: the card asks who it is (ISSUE-022 D3).
  Future<void> _chooseMe() {
    FocusManager.instance.primaryFocus?.unfocus();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MePickerScreen(database: widget.database, photos: widget.photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: GrobingTabBar(
      active: AppTab.people,
      database: widget.database,
      photos: widget.photos,
    ),
    body: SafeArea(
      bottom: false,
      child: StreamBuilder<List<PersonListEntry>>(
        stream: _people,
        builder: (context, people) => StreamBuilder<int?>(
          stream: _me,
          builder: (context, me) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(people.data?.length),
              PeopleSearchField(controller: _query),
              Expanded(
                child: people.hasError
                    ? _readError()
                    : !people.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : _list(people.data!, me.data),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// Element 1: "Osoby" and how many there are.
  Widget _bar(int? count) => SizedBox(
    height: 64,
    child: Row(
      children: [
        const SizedBox(width: 16),
        Semantics(
          header: true,
          child: const Text(
            'Osoby',
            style: TextStyle(
              color: GrobingColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        if (count != null && count > 0)
          Text(
            peopleLabel(count),
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 14,
            ),
          ),
        const SizedBox(width: 16),
      ],
    ),
  );

  /// Elements 3–5 and the empty base (osoby.md → States). "Ja" stands on top and not again in A–Z; the
  /// search finds them like anyone else.
  Widget _list(List<PersonListEntry> all, int? meId) {
    if (all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Text(
          'Tu pojawią się osoby z grobów i rodzin.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      );
    }
    final List<PersonListEntry> sorted = [...all]..sort(comparePeople);
    PersonListEntry? me;
    for (final PersonListEntry p in sorted) {
      if (p.id == meId) me = p;
    }
    final bool searching = _query.text.trim().isNotEmpty;
    return ListView(
      // Scrolling the list puts the keyboard away: what is found is below it.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (!searching)
          _MeCard(me: me, onTap: me == null ? _chooseMe : () => _open(me!.id)),
        ...peopleListItems(
          people: searching
              ? sorted
              : [
                  for (final PersonListEntry p in sorted)
                    if (p.id != meId) p,
                ],
          query: _query.text,
          card: (p) => PersonListCard(
            person: p,
            photos: widget.photos,
            onTap: () => _open(p.id),
          ),
        ),
      ],
    );
  }

  Widget _readError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Nie udało się odczytać osób.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          style: secondaryButtonStyle,
          onPressed: () =>
              setState(() => _people = watchPeople(widget.database)),
          child: const Text('Spróbuj ponownie'),
        ),
      ],
    ),
  );
}

/// Element 3: "Ja" — the first card, with an outline: the author, from whom the chains are counted. Under
/// "Ja" the chosen person's name, or before the choice what to do (ISSUE-022 D3; ui review B1).
class _MeCard extends StatelessWidget {
  const _MeCard({required this.me, required this.onTap});

  final PersonListEntry? me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: GrobingColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GrobingColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: InitialsCircle(text: 'Ja', accent: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Ja',
                        style: TextStyle(
                          color: GrobingColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        me == null ? chooseMeLine : listName(me!),
                        style: const TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: GrobingColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
