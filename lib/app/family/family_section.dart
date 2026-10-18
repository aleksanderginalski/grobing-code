import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart' show watchTables;
import '../../data/photos.dart' show ProfilePhoto, profilePhotos;
import '../dates.dart';
import '../people/people_list.dart' show InitialsCircle;
import '../person/person_screen.dart';
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'add_child_sheet.dart';
import 'role_names.dart';
import 'union_summary_sheet.dart';
import 'union_wizard.dart';

/// Element 9a of the person form, "Rodzina" (05_DESIGN/wpis-osoby.md v5.6, rodzina.md v2): the parents
/// with their union's timeline, and a card for each of the person's unions — the partner, the timeline
/// (together since → the wedding → the end), the children of that pair (C1) — with ✎ to the union's
/// summary and the wizard to add more. Roles come from sex and from the wedding (rodzina.md → Role names);
/// without a sex, the neutral ones. It shows what is written now: the wizard, the summary and a
/// relative's form write at once, and the section follows. A chip or a partner's card opens that
/// person's view, not their correction (v5.8, osoba.md D14).
class FamilySection extends StatefulWidget {
  const FamilySection({
    super.key,
    required this.database,
    required this.personId,
    this.graveId,
    this.photos,
    this.tab = AppTab.map,
  });

  final GrobingDatabase database;
  final int personId;

  /// The tab of the form's stack, kept active in a relative's view (style-b.md rule 12).
  final AppTab tab;

  /// The grave the form was opened from: its people come first in "Z kim?" (rodzina.md B4).
  final int? graveId;

  /// Passed on to a relative's form (its photos, element 1a).
  final Photos? photos;

  @override
  State<FamilySection> createState() => _FamilySectionState();
}

class _FamilySectionState extends State<FamilySection> {
  /// The relations, and the partners' profile photos for their cards (v5.8) — again after every write to
  /// a table they read, the photo links too.
  late final Stream<(PersonRelations, Map<int, ProfilePhoto>)> _relations =
      watchTables(
        widget.database,
        'family_section',
        {
          widget.database.families,
          widget.database.familyPartners,
          widget.database.familyChildren,
          widget.database.persons,
          widget.database.events,
          widget.database.assertions,
          widget.database.personMedia,
          widget.database.media,
        },
        () async {
          final PersonRelations r = await loadRelations(
            widget.database,
            widget.personId,
          );
          return (
            r,
            await profilePhotos(widget.database, [
              for (final PersonUnion u in r.unions) ?u.partner?.id,
            ]),
          );
        },
      );

  static final ButtonStyle _rowButton = secondaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  );

  /// A chip or a card: the relative's view on top of this form, which stays below with what is typed in
  /// it (wpis-osoby.md v5.8; osoba.md D14). Going back returns here.
  Future<void> _openPerson(int personId) => openPersonView(
    context,
    widget.database,
    personId,
    photos: widget.photos,
    tab: widget.tab,
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
  Widget build(
    BuildContext context,
  ) => StreamBuilder<(PersonRelations, Map<int, ProfilePhoto>)>(
    stream: _relations,
    builder: (context, snapshot) {
      final PersonRelations? r = snapshot.data?.$1;
      final Map<int, ProfilePhoto> profiles = snapshot.data?.$2 ?? const {};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // a: the header with its icon in amber, as R4's sections (style-b.md rule 3).
          const Row(
            children: [
              GrobingIcon(Glyphs.group, size: 20, color: GrobingColors.amber),
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
                  (roleName(FamilyRole.parent, p.sex), p),
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
            for (final PersonUnion u in r.unions)
              _card(u, profiles[u.partner?.id]),
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
                    icon: const GrobingIcon(Glyphs.groupAdd),
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
                  icon: const GrobingIcon(Glyphs.personAddAlt),
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
        icon: const GrobingIcon(
          Glyphs.inkPen,
          color: GrobingColors.amber,
          applyTextScaling: false,
        ),
        tooltip: tooltip,
        onPressed: onEdit,
      ),
    ],
  );

  /// c: one union — the partner, "lata · rola", the timeline, ✎ and the chevron; then d, its children and
  /// "Dodaj dziecko". The card leads to the partner's view (style-b rule 11, v5.8), ✎ to the summary.
  Widget _card(PersonUnion u, ProfilePhoto? profile) {
    final FamilyMember? p = u.partner;
    final String role = roleName(
      FamilyRole.partner,
      p?.sex,
      married: u.married,
    );
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
                        hint: p == null ? null : 'otwórz',
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
                                  _avatar(p, profile),
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
                    icon: const GrobingIcon(
                      Glyphs.inkPen,
                      color: GrobingColors.amber,
                      applyTextScaling: false,
                    ),
                    tooltip: 'Popraw związek',
                    onPressed: () => _summary(u.familyId, parents: false),
                  ),
                  // The card leads further (rule 11): its chevron opens the partner's view too — out of the
                  // screen reader, which has the card (ui review: a dead chevron next to ✎).
                  if (p != null)
                    ExcludeSemantics(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _openPerson(p.id),
                        child: const SizedBox(
                          width: 32,
                          height: 48,
                          child: GrobingIcon(
                            Glyphs.chevronRight,
                            color: GrobingColors.textMuted,
                            applyTextScaling: false,
                          ),
                        ),
                      ),
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
                          (roleName(FamilyRole.child, c.sex), c),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: _rowButton,
                      onPressed: () => _addChild(u),
                      icon: const GrobingIcon(Glyphs.personAddAlt),
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

  /// The partner's profile photo in a 40 dp circle, in its crop (v5.8); without one, their initials.
  Widget _avatar(FamilyMember? p, ProfilePhoto? profile) {
    final String letters = p == null
        ? '?'
        : [?_first(p.givenNames), ?_first(p.surname)].join().toUpperCase();
    final Widget initials = InitialsCircle(text: letters);
    return ExcludeSemantics(
      child: switch ((widget.photos, profile)) {
        (final Photos photos?, final ProfilePhoto pp?) => ProfileCircle(
          file: photos.fileOf(pp.relativePath),
          crop: pp.crop,
          size: 40,
          unreadable: initials,
        ),
        _ => initials,
      },
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
          avatar: const GrobingIcon(
            Glyphs.person,
            size: 18,
            color: GrobingColors.amber,
          ),
          label: Text(
            '$role: ${shortPersonName(m.givenNames, m.surname)}',
            semanticsLabel:
                '$role: ${personName(m.givenNames, m.surname)} — otwórz',
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
