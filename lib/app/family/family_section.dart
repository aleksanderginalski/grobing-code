import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../dates.dart';
import '../grave/person_form_screen.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'add_child_sheet.dart';
import 'union_summary_sheet.dart';
import 'union_wizard.dart';

/// Element 9a of the person form, "Rodzina" (05_DESIGN/wpis-osoby.md v5.6, rodzina.md v2): the parents
/// with their union's timeline, and a card for each of the person's unions — the partner, the timeline
/// (together since → the wedding → the end), the children of that pair (C1) — with ✎ to the union's
/// summary and the wizard to add more. Roles come from sex and from the wedding (rodzina.md → Role names);
/// without a sex, the neutral ones. It shows what is written now: the wizard, the summary and a
/// relative's form write at once, and the section follows.
class FamilySection extends StatefulWidget {
  const FamilySection({
    super.key,
    required this.database,
    required this.personId,
    this.graveId,
    this.photos,
  });

  final GrobingDatabase database;
  final int personId;

  /// The grave the form was opened from: its people come first in "Z kim?" (rodzina.md B4).
  final int? graveId;

  /// Passed on to a relative's form (its photos, element 1a).
  final Photos? photos;

  @override
  State<FamilySection> createState() => _FamilySectionState();
}

/// What someone is to the person whose section it is (rodzina.md → Role names).
enum _Role { parent, partner, child }

/// "Matka", "Mąż", "Partnerka", "Syn" — from [sex] and, for a partner, whether there was a wedding; the
/// neutral name without a sex ("Rodzic", "Małżonek", "Partner", "Dziecko").
String _roleName(_Role role, Sex? sex, {bool married = false}) =>
    switch ((role, sex)) {
      (_Role.parent, Sex.female) => 'Matka',
      (_Role.parent, Sex.male) => 'Ojciec',
      (_Role.parent, null) => 'Rodzic',
      (_Role.partner, Sex.female) => married ? 'Żona' : 'Partnerka',
      (_Role.partner, Sex.male) => married ? 'Mąż' : 'Partner',
      (_Role.partner, null) => married ? 'Małżonek' : 'Partner',
      (_Role.child, Sex.female) => 'Córka',
      (_Role.child, Sex.male) => 'Syn',
      (_Role.child, null) => 'Dziecko',
    };

class _FamilySectionState extends State<FamilySection> {
  late final Stream<PersonRelations> _relations = watchRelations(
    widget.database,
    widget.personId,
  );

  static final ButtonStyle _rowButton = secondaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  );

  /// A chip or a card: the relative's entry on top of this form, which stays below with what is typed in
  /// it (wpis-osoby.md D-rodzina-2). Saving or going back returns here.
  Future<void> _openPerson(int personId) => openPersonEntry(
    context,
    widget.database,
    personId,
    photos: widget.photos,
  );

  Future<void> _wizard(
    UnionWizardKind kind, {
    Set<int> partnersAlready = const {},
    bool another = false,
  }) async {
    final FamilyMember self = await loadFamilyMember(
      widget.database,
      widget.personId,
    );
    if (!mounted) return;
    await showUnionWizard(
      context,
      database: widget.database,
      self: self,
      kind: kind,
      partnersAlready: partnersAlready,
      another: another,
      graveId: widget.graveId,
    );
  }

  Future<void> _summary(int familyId, {required bool parents}) =>
      showUnionSummary(
        context,
        database: widget.database,
        familyId: familyId,
        selfId: widget.personId,
        parents: parents,
        graveId: widget.graveId,
      );

  Future<void> _addChild(PersonUnion u) async {
    final FamilyMember self = await loadFamilyMember(
      widget.database,
      widget.personId,
    );
    if (!mounted) return;
    await showAddChild(
      context,
      database: widget.database,
      familyId: u.familyId,
      pairName: [
        shortPersonName(self.givenNames, self.surname),
        if (u.partner case final FamilyMember p)
          shortPersonName(p.givenNames, p.surname),
      ].join(' i '),
      // As the family sheet did (A3'): the surname of the first in the pair.
      suggestedSurname: self.surname,
      graveId: widget.graveId,
    );
  }

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
            // b: the parents and their union's timeline, or the wizard to add them (P1).
            if (r.parentsUnion case final PersonUnion parents) ...[
              _group(
                'Rodzice${_parentsTimeline(parents)}',
                tooltip: 'Popraw związek rodziców',
                onEdit: () => _summary(parents.familyId, parents: true),
              ),
              _chips([
                for (final FamilyMember p in r.parents)
                  (_roleName(_Role.parent, p.sex), p),
              ]),
            ],
            // c, d: a card for each union, by its first date, with its children (C1).
            if (r.unions.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 2),
                child: Text(
                  'Partnerzy',
                  style: TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            for (final PersonUnion u in r.unions) _card(u),
            const SizedBox(height: 12),
            // e, and "Dodaj rodziców" while there are none.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (r.parentsFamilyId == null)
                  OutlinedButton.icon(
                    style: _rowButton,
                    onPressed: () => _wizard(UnionWizardKind.parents),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Dodaj rodziców'),
                  ),
                OutlinedButton.icon(
                  style: _rowButton,
                  onPressed: () => _wizard(
                    UnionWizardKind.partner,
                    another: r.unions.isNotEmpty,
                    partnersAlready: {
                      for (final PersonUnion u in r.unions)
                        if (u.partner case final FamilyMember p) p.id,
                    },
                  ),
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: Text(
                    r.unions.isEmpty
                        ? 'Dodaj partnera'
                        : 'Dodaj kolejnego partnera',
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  /// " · ślub ok. 1920" — nothing when the parents' union has nothing written.
  static String _parentsTimeline(PersonUnion u) {
    if (u.together == null && !u.married && !u.ended) return '';
    return ' · ${unionTimeline(together: u.together, married: u.married, marriage: u.marriage, ended: u.ended, end: u.end)}';
  }

  /// The label of a group and its pencil (grob.md element 3: the same pencil).
  Widget _group(
    String label, {
    required String tooltip,
    required VoidCallback onEdit,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined, color: GrobingColors.amber),
        tooltip: tooltip,
        onPressed: onEdit,
      ),
    ],
  );

  /// c: one union — the partner, "lata · rola", the timeline, ✎; then d, its children and "Dodaj
  /// dziecko". The card leads to the partner's entry (style-b rule 11), ✎ to the summary.
  Widget _card(PersonUnion u) {
    final FamilyMember? p = u.partner;
    final String role = _roleName(_Role.partner, p?.sex, married: u.married);
    final String timeline = unionTimeline(
      together: u.together,
      married: u.married,
      marriage: u.marriage,
      ended: u.ended,
      end: u.end,
    );
    final String name = p == null
        ? 'Drugi rodzic nieznany'
        : personName(p.givenNames, p.surname, birthSurname: p.birthSurname);
    final bool nothingWritten = u.together == null && !u.married && !u.ended;
    final bool showTimeline = p != null || !nothingWritten;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: GrobingColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MergeSemantics(
                      child: Semantics(
                        button: p != null,
                        hint: p == null ? null : 'otwórz wpis',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: p == null ? null : () => _openPerson(p.id),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _initials(p),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            color: GrobingColors.text,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (p != null)
                                          Text(
                                            '${lifeYears(birth: p.birth, death: p.death)} · $role',
                                            style: const TextStyle(
                                              color: GrobingColors.textMuted,
                                              fontSize: 14,
                                            ),
                                          ),
                                        if (showTimeline) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            timeline,
                                            style: const TextStyle(
                                              color: GrobingColors.text,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: GrobingColors.amber,
                    ),
                    tooltip: 'Popraw związek',
                    onPressed: () => _summary(u.familyId, parents: false),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (u.children.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          'Dzieci z tego związku',
                          style: TextStyle(
                            color: GrobingColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _chips([
                        for (final FamilyMember c in u.children)
                          (_roleName(_Role.child, c.sex), c),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: _rowButton,
                      onPressed: () => _addChild(u),
                      icon: const Icon(Icons.person_add_alt_outlined),
                      label: const Text('Dodaj dziecko'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The partner's initials in a circle (wpis-osoby.md 9a c — the profile photo is left for later).
  Widget _initials(FamilyMember? p) {
    final String letters = p == null
        ? '?'
        : [?_first(p.givenNames), ?_first(p.surname)].join().toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: GrobingColors.outline),
        ),
        child: Text(
          letters,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }

  static String? _first(String? s) {
    final String t = (s ?? '').trim();
    return t.isEmpty ? null : t[0];
  }

  /// The chips of one group, wrapping to further lines and growing with the text (SC 1.4.4).
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
            '$role: ${shortPersonName(m.givenNames, m.surname)}',
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
}
