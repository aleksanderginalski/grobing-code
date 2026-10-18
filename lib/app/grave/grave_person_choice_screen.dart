import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../family/person_choice_list.dart';
import '../photo/photos.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/title_bar.dart';
import 'person_form_screen.dart';

/// "Kto leży w tym grobie?" (05_DESIGN/grob.md v9, elements 8–12; ISSUE-047): "Dodaj osobę" searches first
/// (D22). Someone in the app buried nowhere — added in the tree, say — joins [grave] at once and the grave
/// shows them; "Nowa osoba" opens the form with what was typed. Everyone with a grave is in sight, greyed,
/// with where they lie (D23). A choice mode, so without the bottom bar (style-b.md rule 12).
class GravePersonChoiceScreen extends StatefulWidget {
  const GravePersonChoiceScreen({
    super.key,
    required this.database,
    required this.grave,
    this.photos,
    this.tab = AppTab.map,
  });

  final GrobingDatabase database;
  final GraveDetail grave;

  /// For the form of a new person, as the grave view would pass it.
  final Photos? photos;
  final AppTab tab;

  @override
  State<GravePersonChoiceScreen> createState() =>
      _GravePersonChoiceScreenState();
}

class _GravePersonChoiceScreenState extends State<GravePersonChoiceScreen> {
  bool _saving = false;

  Future<void> _picked(PickedMember picked) async {
    switch (picked) {
      case PickedPerson(:final PersonChoice choice):
        await _bury(choice.id);
      case PickedNew(:final String text):
        // The form takes this screen's place: its "Zapisz" goes back to the grave, as before (wpis-osoby.md v6).
        final GraveDetail g = widget.grave;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PersonFormScreen(
              database: widget.database,
              mode: NextPerson(
                graveId: g.id,
                graveTitle: g.name ?? g.cemeteryName,
                peopleCount: g.people.length,
                suggestedSurname: g.people.isEmpty
                    ? null
                    : g.people.last.surname,
                givenNames: text,
              ),
              photos: widget.photos,
              tab: widget.tab,
            ),
          ),
        );
    }
  }

  /// Element 11: the burial is written at once — a choice, not an entry to correct (D22) — and the grave
  /// shows the person; no "Zapisano" (style-b.md rule 10).
  Future<void> _bury(int personId) async {
    if (_saving) return;
    _saving = true;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await addExistingPersonToGrave(
        widget.database,
        graveId: widget.grave.id,
        personId: personId,
      );
      navigator.pop();
    } on Object {
      _saving = false;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
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
          const BackTitleBar('Kto leży w tym grobie?'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // The field with its frame in the outline colour, as in the family sheet (grob.md 9, rodzina.md B2).
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(inputDecorationTheme: GrobingTheme.fields),
                child: PersonChoiceList(
                  database: widget.database,
                  graveId: widget.grave.id,
                  forGrave: true,
                  onPicked: _picked,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
