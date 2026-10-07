import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'person_form_screen.dart';

/// One grave and everyone buried in it (ISSUE-012; 05_DESIGN/grob.md v2): R4 without the photos,
/// which come with US-005. The grave's name is set from the pencil next to the title.
class GraveScreen extends StatefulWidget {
  const GraveScreen({super.key, required this.database, required this.graveId});

  final GrobingDatabase database;
  final int graveId;

  @override
  State<GraveScreen> createState() => _GraveScreenState();
}

class _GraveScreenState extends State<GraveScreen> {
  late Stream<GraveDetail?> _grave = _watch();

  Stream<GraveDetail?> _watch() => watchGrave(widget.database, widget.graveId);

  /// The title the person form shows below its own: the grave's name, or its cemetery's.
  String _graveTitle(GraveDetail g) => g.name ?? g.cemeteryName;

  Future<void> _addPerson(GraveDetail g) => _openForm(
    NextPerson(
      graveId: g.id,
      graveTitle: _graveTitle(g),
      peopleCount: g.people.length,
      suggestedSurname: g.people.isEmpty ? null : g.people.last.surname,
    ),
  );

  Future<void> _correct(GraveDetail g, BuriedPerson person) => _openForm(
    Correction(
      person: person,
      graveTitle: _graveTitle(g),
      peopleCount: g.people.length,
    ),
  );

  Future<void> _openForm(PersonFormMode mode) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonFormScreen(database: widget.database, mode: mode),
    ),
  );

  Future<void> _editName(GraveDetail g) => showDialog<void>(
    context: context,
    builder: (_) => GraveNameDialog(
      name: g.name,
      save: (name) => setGraveName(widget.database, g.id, name),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<GraveDetail?>(
    stream: _grave,
    builder: (context, snapshot) {
      final GraveDetail? grave = snapshot.data;
      final bool failed =
          snapshot.hasError || (snapshot.hasData && grave == null);
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(grave),
              Expanded(
                child: failed
                    ? _readError()
                    : grave == null
                    ? const Center(child: CircularProgressIndicator())
                    : _content(grave),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Element 1: back, and the cemetery · locality as the bar's subtitle.
  Widget _bar(GraveDetail? grave) => Row(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: BackButton(color: GrobingColors.text),
      ),
      Expanded(
        child: Text(
          grave == null
              ? ''
              : [grave.cemeteryName, ?grave.cemeteryLocality].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ),
      const SizedBox(width: 16),
    ],
  );

  Widget _content(GraveDetail grave) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      _title(grave),
      const SizedBox(height: 6),
      _address(grave),
      // 24 dp between the heading and the list (style-b.md rule 5; ui review).
      const SizedBox(height: 24),
      if (grave.people.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'W tym grobie nie ma jeszcze wpisanych osób.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
          ),
        ),
      for (final BuriedPerson p in grave.people)
        _PersonCard(person: p, onTap: () => _correct(grave, p)),
      const SizedBox(height: 8),
      // Element 6: the row of actions; "Dodaj zdjęcie" joins it with US-005.
      Row(
        children: [
          OutlinedButton.icon(
            style: secondaryButtonStyle.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
            ),
            onPressed: () => _addPerson(grave),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Dodaj osobę'),
          ),
        ],
      ),
    ],
  );

  /// Elements 2 and 3: the name — "Grób" without one — centred, and the pencil to set it. The same
  /// room on the left keeps the title in the middle.
  Widget _title(GraveDetail grave) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(width: 48),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            grave.name ?? 'Grób',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GrobingColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined),
        color: GrobingColors.amber,
        tooltip: 'Popraw grób',
        onPressed: () => _editName(grave),
      ),
    ],
  );

  /// Element 4: the address in full words, or what is missing and when it gets filled in.
  Widget _address(GraveDetail grave) {
    const TextStyle muted = TextStyle(
      color: GrobingColors.textMuted,
      fontSize: 14,
    );
    final String? address = graveAddress(grave.sector, grave.row, grave.plot);
    if (address != null) {
      return Text(
        addressLine(address, hasPin: grave.hasPin),
        textAlign: TextAlign.center,
        style: muted,
      );
    }
    return Column(
      children: [
        Text.rich(
          TextSpan(
            children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: GrobingColors.textMuted,
                  ),
                ),
              ),
              TextSpan(text: addressLine(null, hasPin: grave.hasPin)),
            ],
          ),
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 2),
        const Text(
          'Uzupełnisz przy wizycie.',
          textAlign: TextAlign.center,
          style: muted,
        ),
      ],
    );
  }

  Widget _readError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Nie udało się odczytać grobu.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          style: secondaryButtonStyle,
          onPressed: () => setState(() => _grave = _watch()),
          child: const Text('Spróbuj ponownie'),
        ),
      ],
    ),
  );
}

/// Element 5: one person — "Imiona Nazwisko z d. Rodowe" and the dates as entered — leading to the
/// correction of the entry (ISSUE-012 D1).
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final BuriedPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: GrobingColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        personName(
                          person.givenNames,
                          person.surname,
                          birthSurname: person.birthSurname,
                        ),
                        style: const TextStyle(
                          color: GrobingColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lifeLine(
                          birth: person.birth.date,
                          death: person.death.date,
                          burial: person.burial.date,
                        ),
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

/// The window "Popraw grób" (05_DESIGN/grob.md, element 3a): the grave's name, optional. It saves
/// itself, so a failed save keeps it open with the message.
class GraveNameDialog extends StatefulWidget {
  const GraveNameDialog({super.key, this.name, required this.save});

  final String? name;
  final Future<void> Function(String? name) save;

  @override
  State<GraveNameDialog> createState() => _GraveNameDialogState();
}

class _GraveNameDialogState extends State<GraveNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name ?? '',
  )..selection = TextSelection.collapsed(offset: (widget.name ?? '').length);
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.save(_name.text.trim().isEmpty ? null : _name.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(inputDecorationTheme: GrobingTheme.fields),
    child: AlertDialog(
      backgroundColor: GrobingColors.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Popraw grób',
        style: TextStyle(
          color: GrobingColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Nazwa grobu',
              // The text of R4 (05_DESIGN/brand/references.md).
              hintText: 'np. Grób rodzinny Nowaków',
              helperText: _failed
                  ? null
                  : 'Zostaw puste, jeśli grób nie ma nazwy.',
              helperStyle: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 13,
              ),
              helperMaxLines: 2,
              // Never colour alone (SC 1.4.1): the message comes with an icon.
              error: _failed
                  ? const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: GrobingColors.error,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Nie udało się zapisać. Spróbuj jeszcze raz.',
                            style: TextStyle(color: GrobingColors.error),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Zapisz'),
        ),
      ],
    ),
  );
}
