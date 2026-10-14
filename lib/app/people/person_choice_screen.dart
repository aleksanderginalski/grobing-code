import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/people.dart';
import '../photo/photos.dart';
import '../theme.dart';
import '../widgets/title_bar.dart';
import 'people_list.dart';

/// A person for a tile of "Połącz dwie osoby" (05_DESIGN/drzewo.md element 7; ISSUE-039): the people as in the
/// Osoby tab — search, A–Z — without [without], the person on the other tile (the same person has no path). A
/// choice mode, so without the bottom bar (style-b.md rule 12), as the choice of "ja"; a tap gives the person's
/// id back and closes.
class PersonChoiceScreen extends StatefulWidget {
  const PersonChoiceScreen({
    super.key,
    required this.database,
    required this.title,
    this.without,
    this.photos,
  });

  final GrobingDatabase database;

  /// "Od kogo?" or "Do kogo?".
  final String title;
  final int? without;
  final Photos? photos;

  @override
  State<PersonChoiceScreen> createState() => _PersonChoiceScreenState();
}

class _PersonChoiceScreenState extends State<PersonChoiceScreen> {
  late final Future<List<PersonListEntry>> _people = loadPeople(widget.database)
      .then(
        (all) => [
          for (final PersonListEntry p in all..sort(comparePeople))
            if (p.id != widget.without) p,
        ],
      );
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackTitleBar(widget.title),
          PeopleSearchField(controller: _query),
          Expanded(
            child: FutureBuilder<List<PersonListEntry>>(
              future: _people,
              builder: (context, people) {
                if (people.hasError) {
                  return const Center(
                    child: Text(
                      'Nie udało się odczytać osób.',
                      style: TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  );
                }
                if (!people.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: peopleListItems(
                    people: people.data!,
                    query: _query.text,
                    card: (p) => PersonListCard(
                      person: p,
                      photos: widget.photos,
                      choosing: true,
                      onTap: () => Navigator.of(context).pop(p.id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
