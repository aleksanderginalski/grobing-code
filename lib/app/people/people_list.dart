import 'package:flutter/material.dart';

import '../../data/people.dart';
import '../dates.dart';
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../theme.dart';

// The list of people of the Osoby tab (05_DESIGN/osoby.md, elements 2, 4 and 5) — also the choice of
// "ja" (ISSUE-022 D3), which lists the same people the same way.

/// What says "before the choice" under "Ja" (ui review B1, style-b.md rule 9).
const String chooseMeLine = 'Wybierz, która osoba to Ty';

/// The surname a person is ordered and grouped by: theirs, or without one the birth surname — the family
/// it groups them with (osoby.md D1; ui review of ISSUE-022).
String? _sortSurname(PersonListEntry p) => p.surname ?? p.birthSurname;

/// Polish order of the list (osoby.md D1): by surname (or the birth surname), then by given names;
/// people with neither last, under their own heading.
int comparePeople(PersonListEntry a, PersonListEntry b) {
  final String? x = _sortSurname(a), y = _sortSurname(b);
  if ((x == null) != (y == null)) return x == null ? 1 : -1;
  final int bySurname = polishCompare(x ?? '', y ?? '');
  if (bySurname != 0) return bySurname;
  final int byNames = polishCompare(a.givenNames ?? '', b.givenNames ?? '');
  return byNames != 0 ? byNames : a.id.compareTo(b.id);
}

/// The heading a person stands under: the first letter of the surname or birth surname (Ł apart from
/// L, as the Polish alphabet orders them).
String letterOf(PersonListEntry p) => switch (_sortSurname(p)) {
  final String s => s.characters.first.toUpperCase(),
  null => 'Bez nazwiska',
};

/// Whether [p] answers the search (osoby.md, element 2): from the start of a word of the given names,
/// the surname or the birth surname, without Polish letters and case.
bool personMatches(PersonListEntry p, String query) =>
    matchesWordStart(query, [p.givenNames, p.surname, p.birthSurname]);

/// "Imiona Nazwisko z d. Rodowe" (style-b.md rule 6).
String listName(PersonListEntry p) =>
    personName(p.givenNames, p.surname, birthSurname: p.birthSurname);

/// The list's content for [query]: with nothing typed, [people] under their letters; while searching,
/// the matching ones without headings, or "Nie ma osoby „…”." (osoby.md → States). [people] is sorted.
List<Widget> peopleListItems({
  required List<PersonListEntry> people,
  required String query,
  required Widget Function(PersonListEntry person) card,
}) {
  final String q = query.trim();
  if (q.isNotEmpty) {
    final List<PersonListEntry> found = [
      for (final PersonListEntry p in people)
        if (personMatches(p, q)) p,
    ];
    if (found.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 0),
          child: Text(
            'Nie ma osoby „$q”.',
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 14,
            ),
          ),
        ),
      ];
    }
    return [for (final PersonListEntry p in found) card(p)];
  }
  final List<Widget> items = [];
  String? letter;
  for (final PersonListEntry p in people) {
    final String l = letterOf(p);
    if (l != letter) {
      letter = l;
      items.add(_LetterHeading(l));
    }
    items.add(card(p));
  }
  return items;
}

/// A letter over its people (13 sp, muted text).
class _LetterHeading extends StatelessWidget {
  const _LetterHeading(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        letter,
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
      ),
    ),
  );
}

/// Element 2: the pill of the map's search (cmentarze.md, element 2), here a field of its own — this
/// tab searches only people (SPIKE-004 D3). No capital letter; "search" closes the keyboard.
class PeopleSearchField extends StatelessWidget {
  const PeopleSearchField({super.key, required this.controller});

  final TextEditingController controller;

  static final InputBorder _pill = OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: BorderSide.none,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: GrobingColors.text, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: GrobingColors.surface,
        hintText: 'Szukaj osoby',
        hintStyle: const TextStyle(color: GrobingColors.textMuted),
        prefixIcon: const Icon(Icons.search, color: GrobingColors.textMuted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                color: GrobingColors.textMuted,
                tooltip: 'Wyczyść',
                onPressed: controller.clear,
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: _pill,
        enabledBorder: _pill,
        focusedBorder: _pill,
      ),
    ),
  );
}

/// Element 4: a person on the surface with a chevron (style-b.md rule 11) — the profile photo or the
/// initials, "Imiona Nazwisko z d. Rodowe" and the years of life. Kinship under the name comes with
/// ISSUE-025. In the choice of "ja" ([choosing]) a card leads nowhere further, so it has no chevron, and
/// the [selected] one has a tick (rule 11; ui review B2).
class PersonListCard extends StatelessWidget {
  const PersonListCard({
    super.key,
    required this.person,
    required this.onTap,
    this.photos,
    this.choosing = false,
    this.selected = false,
  });

  final PersonListEntry person;
  final VoidCallback onTap;
  final Photos? photos;
  final bool choosing;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      selected: selected ? true : null,
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
                  PersonAvatar(person: person, photos: photos),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          listName(person),
                          style: const TextStyle(
                            color: GrobingColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          lifeYears(birth: person.birth, death: person.death),
                          style: const TextStyle(
                            color: GrobingColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check, color: GrobingColors.amber)
                  else if (!choosing)
                    const Icon(
                      Icons.chevron_right,
                      color: GrobingColors.textMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The person's profile photo in a [size] circle, in its crop (ISSUE-018); without a photo, their
/// initials on the surface with an outline — text, not a stand-in picture (osoby.md → rule 11). Out of
/// the screen reader: the card's text says who it is.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.person,
    this.photos,
    this.size = 40,
  });

  final PersonListEntry person;
  final Photos? photos;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget initials = InitialsCircle(text: _initials(person), size: size);
    return ExcludeSemantics(
      child: switch ((photos, person.profile)) {
        (final Photos photos?, final profile?) => ProfileCircle(
          file: photos.fileOf(profile.relativePath),
          crop: profile.crop,
          size: size,
          unreadable: initials,
        ),
        _ => initials,
      },
    );
  }

  static String _initials(PersonListEntry p) {
    final String letters = [
      for (final String? part in [p.givenNames, p.surname])
        if (part != null && part.trim().isNotEmpty)
          part.trim().characters.first.toUpperCase(),
    ].join();
    return letters.isEmpty ? '?' : letters;
  }
}

/// Letters in a circle on the surface with an outline; "Ja" in amber ([accent]) — the mark of the
/// author (osoby.md, element 3).
class InitialsCircle extends StatelessWidget {
  const InitialsCircle({
    super.key,
    required this.text,
    this.size = 40,
    this.accent = false,
  });

  final String text;
  final double size;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: GrobingColors.surface,
      shape: BoxShape.circle,
      border: Border.all(
        color: accent ? GrobingColors.amber : GrobingColors.outline,
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: accent ? GrobingColors.amber : GrobingColors.text,
        fontSize: accent ? 13 : 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
