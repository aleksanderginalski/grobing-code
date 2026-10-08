import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/people.dart';
import '../photo/photos.dart';
import '../theme.dart';
import '../widgets/title_bar.dart';
import 'people_list.dart';

/// The choice of "ja" (ISSUE-022 D3; 05_DESIGN/ustawienia.md, element 1): the people as in the Osoby tab
/// — search, A–Z — and the one now chosen ticked. A choice mode, so without the bottom bar (style-b.md
/// rule 12). Choosing writes at once and closes; what was chosen shows where it was opened from (rule 10).
class MePickerScreen extends StatefulWidget {
  const MePickerScreen({super.key, required this.database, this.photos});

  final GrobingDatabase database;
  final Photos? photos;

  @override
  State<MePickerScreen> createState() => _MePickerScreenState();
}

class _MePickerScreenState extends State<MePickerScreen> {
  late final Future<List<PersonListEntry>> _people = loadPeople(
    widget.database,
  ).then((all) => all..sort(comparePeople));
  late final Stream<int?> _me = watchMe(widget.database);
  final TextEditingController _query = TextEditingController();
  bool _saving = false;

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

  Future<void> _choose(int personId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await setMe(widget.database, personId);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nie udało się zapisać. Spróbuj jeszcze raz.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackTitleBar('Która osoba to Ty?'),
          PeopleSearchField(controller: _query),
          Expanded(
            child: FutureBuilder<List<PersonListEntry>>(
              future: _people,
              builder: (context, people) => StreamBuilder<int?>(
                stream: _me,
                builder: (context, me) {
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
                  if (people.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        'Tu pojawią się osoby z grobów i rodzin.',
                        style: TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    );
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
                        selected: p.id == me.data,
                        onTap: () => _choose(p.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
