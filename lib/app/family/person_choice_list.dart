import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../photo/photo_people_screen.dart' show PeopleSectionHeader;
import '../polish.dart';
import '../theme.dart';

/// What the person list gives back: someone already in the app, or a new person to type.
sealed class PickedMember {
  const PickedMember();
}

class PickedPerson extends PickedMember {
  const PickedPerson(this.choice);

  final PersonChoice choice;
}

class PickedNew extends PickedMember {
  const PickedNew(this.text);

  /// What was typed in the search — the new person's given names to start from (rodzina.md B3).
  final String text;
}

/// B of 05_DESIGN/rodzina.md — the "Z kim?" step of the family wizard and the list of "Dodaj dziecko"
/// (rodzina.md v2, C1 and E): search first, then create (D3) — the field takes the keyboard at once,
/// "Nowa osoba" stands over the list, and this grave's people come first. Someone who cannot be chosen
/// says why in words, never in the colour alone (SC 1.4.1).
class PersonChoiceList extends StatefulWidget {
  const PersonChoiceList({
    super.key,
    required this.database,
    required this.onPicked,
    this.unavailable = const {},
    this.graveId,
    this.forChild = false,
    this.familyId,
  });

  final GrobingDatabase database;
  final ValueChanged<PickedMember> onPicked;

  /// Who cannot be chosen here, and why — "ta osoba", "już partner tej osoby", "już w tej rodzinie".
  final Map<int, String> unavailable;

  /// The grave of the person the wizard was opened from: "W tym grobie" (B4).
  final int? graveId;

  /// A child has one family of parents (D5): someone with parents elsewhere is "ma już rodziców".
  final bool forChild;

  /// The family the child joins — its own children do not count as "ma już rodziców".
  final int? familyId;

  @override
  State<PersonChoiceList> createState() => _PersonChoiceListState();
}

class _PersonChoiceListState extends State<PersonChoiceList> {
  final TextEditingController _filter = TextEditingController();

  late final Future<
    ({List<PersonChoice> all, List<int> inGrave, Set<int> withParents})
  >
  _choices = _load();

  Future<({List<PersonChoice> all, List<int> inGrave, Set<int> withParents})>
  _load() async {
    final ({List<PersonChoice> all, List<int> inGrave}) choices =
        await loadPersonChoices(widget.database, graveId: widget.graveId);
    return (
      all: choices.all,
      inGrave: choices.inGrave,
      withParents: widget.forChild
          ? await peopleWithParents(
              widget.database,
              exceptFamilyId: widget.familyId,
            )
          : const <int>{},
    );
  }

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  static int _compare(PersonChoice a, PersonChoice b) {
    final int bySurname = polishCompare(a.surname ?? '', b.surname ?? '');
    return bySurname != 0
        ? bySurname
        : polishCompare(a.givenNames ?? '', b.givenNames ?? '');
  }

  bool _matches(PersonChoice c) =>
      _filter.text.trim().isEmpty ||
      matchesQuery(_filter.text, [c.givenNames, c.surname, c.birthSurname]);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // B2: the keyboard at once — searching is the way in (D3).
      TextField(
        controller: _filter,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        style: const TextStyle(color: GrobingColors.text, fontSize: 16),
        decoration: const InputDecoration(
          hintText: 'Szukaj osoby albo wpisz nową',
          prefixIcon: Icon(Icons.search, color: GrobingColors.textMuted),
        ),
      ),
      Expanded(
        child: FutureBuilder(
          future: _choices,
          builder: (context, snapshot) {
            // B — wczytywanie: the background only, the read takes a moment.
            final data = snapshot.data;
            if (data == null) return const SizedBox.shrink();
            return _list(data);
          },
        ),
      ),
    ],
  );

  Widget _list(
    ({List<PersonChoice> all, List<int> inGrave, Set<int> withParents}) data,
  ) {
    final Map<int, PersonChoice> byId = {
      for (final PersonChoice c in data.all) c.id: c,
    };
    final List<PersonChoice> inGrave = [
      for (final int id in data.inGrave)
        if (byId[id] case final PersonChoice c when _matches(c)) c,
    ];
    final List<PersonChoice> others = [
      for (final PersonChoice c in data.all)
        if (!data.inGrave.contains(c.id) && _matches(c)) c,
    ]..sort(_compare);
    final String typed = _filter.text.trim();
    String? reason(PersonChoice c) {
      if (widget.unavailable[c.id] case final String why) return why;
      if (data.withParents.contains(c.id)) return 'ma już rodziców';
      return null;
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      children: [
        // B3: always there, first.
        _NewRow(typed: typed, onTap: () => widget.onPicked(PickedNew(typed))),
        if (inGrave.isNotEmpty) ...[
          const PeopleSectionHeader('W tym grobie'),
          for (final PersonChoice c in inGrave) _row(c, reason(c)),
        ],
        if (others.isNotEmpty) ...[
          const PeopleSectionHeader('Inne osoby'),
          for (final PersonChoice c in others)
            _row(c, reason(c), withPlace: true),
        ],
        if (inGrave.isEmpty && others.isEmpty && typed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Nie ma osoby pasującej do „$typed”.',
              style: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }

  /// B4–B5: a person; [withPlace] adds where they lie, so two of the same name differ (zdjecie.md D5).
  /// With a [reason] the row cannot be chosen and says why in place of the years.
  Widget _row(PersonChoice c, String? reason, {bool withPlace = false}) {
    final String life = lifeLine(birth: c.birth, death: c.death);
    final String? place = withPlace ? (c.graveName ?? c.cemeteryName) : null;
    final bool enabled = reason == null;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? () => widget.onPicked(PickedPerson(c)) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    personName(
                      c.givenNames,
                      c.surname,
                      birthSurname: c.birthSurname,
                    ),
                    style: TextStyle(
                      color: enabled
                          ? GrobingColors.text
                          : GrobingColors.textMuted,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    reason ?? (place == null ? life : '$life · $place'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// B3: "Nowa osoba", with what is typed — „Nowa osoba: „Anna”” — so the new person starts from it.
class _NewRow extends StatelessWidget {
  const _NewRow({required this.typed, required this.onTap});

  final String typed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            const Icon(
              Icons.person_add_alt_outlined,
              color: GrobingColors.amber,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                typed.isEmpty ? 'Nowa osoba' : 'Nowa osoba: „$typed”',
                style: const TextStyle(color: GrobingColors.text, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
