import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../grave/person_form_screen.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'family_sheet_screen.dart';

/// Element 9a of the person form, "Rodzina" (05_DESIGN/wpis-osoby.md v5.1): the person's parents and
/// unions as chips — like R4's right screen — that open the relative's entry, the pencil of each family
/// and the ways to add one. The names are neutral, without sex ("Rodzic", "Partner", "Dziecko" — the
/// author's decision at stop #1 of ISSUE-019; rodzina.md → Role names). It shows what is written now:
/// the family sheet and a relative's form write at once, and the section follows.
class FamilySection extends StatefulWidget {
  const FamilySection({
    super.key,
    required this.database,
    required this.personId,
    required this.personName,
    this.graveId,
    this.photos,
  });

  final GrobingDatabase database;
  final int personId;

  /// The person as the form has them now — the subtitle of the family sheet.
  final String Function() personName;

  /// The grave the form was opened from: its people come first on the person picker (rodzina.md B4).
  final int? graveId;

  /// Passed on to a relative's form (its photos, element 1a).
  final Photos? photos;

  @override
  State<FamilySection> createState() => _FamilySectionState();
}

class _FamilySectionState extends State<FamilySection> {
  late final Stream<PersonRelations> _relations = watchRelations(
    widget.database,
    widget.personId,
  );

  static final ButtonStyle _rowButton = secondaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  );

  /// A chip: the relative's entry on top of this form, which stays below with what is typed in it
  /// (wpis-osoby.md D-rodzina-2). Saving or going back returns here.
  Future<void> _openPerson(int personId) async {
    final ({
      BuriedPerson person,
      int? graveId,
      String? graveTitle,
      int peopleCount,
    })?
    found = await loadPersonForCorrection(widget.database, personId);
    if (found == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonFormScreen(
          database: widget.database,
          mode: Correction(
            person: found.person,
            graveTitle: found.graveTitle,
            peopleCount: found.peopleCount,
            graveId: found.graveId,
          ),
          photos: widget.photos,
        ),
      ),
    );
  }

  Future<void> _openSheet({int? familyId, FamilyStart? start}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FamilySheetScreen(
            database: widget.database,
            personId: widget.personId,
            personName: widget.personName(),
            familyId: familyId,
            start: start ?? FamilyStart.asPartner,
            graveId: widget.graveId,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<PersonRelations>(
    stream: _relations,
    builder: (context, snapshot) {
      final PersonRelations? r = snapshot.data;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // a: the header with its icon in amber, as R4's sections (style-b.md rule 3).
          const Row(
            children: [
              Icon(Icons.people_outline, size: 20, color: GrobingColors.amber),
              SizedBox(width: 8),
              Text(
                'Rodzina',
                style: TextStyle(
                  color: GrobingColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (r != null) ...[
            // b: the parents.
            if (r.parentsFamilyId case final int family) ...[
              _group('Rodzice', family),
              _chips([for (final FamilyMember p in r.parents) ('Rodzic', p)]),
            ],
            // d: each union by marriage date, then its children by birth.
            for (final PersonUnion u in r.unions) ...[
              _group(_unionLabel(u), u.familyId),
              _chips([
                if (u.partner case final FamilyMember partner)
                  ('Partner', partner),
                for (final FamilyMember c in u.children) ('Dziecko', c),
              ]),
            ],
            const SizedBox(height: 12),
            // f: "Dodaj rodziców" while there are none; "Dodaj związek" always — another union, after
            // a parting or a death, is another family with its own children (AC-2).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (r.parentsFamilyId == null)
                  OutlinedButton.icon(
                    style: _rowButton,
                    onPressed: () => _openSheet(start: FamilyStart.asChild),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Dodaj rodziców'),
                  ),
                OutlinedButton.icon(
                  style: _rowButton,
                  onPressed: () => _openSheet(start: FamilyStart.asPartner),
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: const Text('Dodaj związek'),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  /// "Związek · ślub ok. 1948 · koniec 1960" (style-b.md rule 6 for the dates).
  static String _unionLabel(PersonUnion u) => [
    'Związek',
    if (u.marriage case final QualifiedDate m) 'ślub ${formatDate(m)}',
    if (u.end case final QualifiedDate e) 'koniec ${formatDate(e)}',
  ].join(' · ');

  /// The label of a family and its pencil to the family sheet (grob.md element 3: the same pencil).
  Widget _group(String label, int familyId) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined, color: GrobingColors.amber),
        tooltip: 'Popraw rodzinę',
        onPressed: () => _openSheet(familyId: familyId),
      ),
    ],
  );

  /// e: the chips of one family, wrapping to further lines and growing with the text (SC 1.4.4).
  Widget _chips(List<(String, FamilyMember)> people) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final (String role, FamilyMember m) in people)
        ActionChip(
          avatar: const Icon(
            Icons.person_outline,
            size: 18,
            color: GrobingColors.amber,
          ),
          label: Text(
            '$role: ${_shortName(m)}',
            semanticsLabel:
                '$role: ${personName(m.givenNames, m.surname)} — otwórz wpis',
          ),
          labelStyle: const TextStyle(color: GrobingColors.text, fontSize: 14),
          backgroundColor: GrobingColors.surface,
          side: const BorderSide(color: GrobingColors.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onPressed: () => _openPerson(m.id),
        ),
    ],
  );

  /// The first given name, as R4's chips ("Partner: Jan"); without given names, the surname.
  static String _shortName(FamilyMember m) {
    final String? given = m.givenNames?.trim();
    if (given == null || given.isEmpty) return m.surname ?? '';
    return given.split(RegExp(r'\s+')).first;
  }
}
