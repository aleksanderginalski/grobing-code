import 'package:flutter/material.dart';

import '../../data/clans.dart';
import '../../data/database.dart';
import '../../data/family_tree.dart';
import '../../data/wreaths.dart';
import '../family/union_wizard.dart' show shortPersonName;
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/date_block.dart' show ErrorLine;
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import '../widgets/title_bar.dart';
import '../widgets/wreath.dart';

// The wreath of a family line in a person's correction (ISSUE-044; 05_DESIGN/wieniec.md E, F; wpis-osoby.md
// 4b): the row, the sheet of lines and the screen of one line. A choice saves at once, like "Rodzina" in the
// same form (wieniec.md D16) — "Zapisz" of the form does not touch it.

const String _saveFailed = 'Nie udało się zapisać wieńca. Spróbuj jeszcze raz.';

void _sayFailed(BuildContext context) => ScaffoldMessenger.of(
  context,
).showSnackBar(const SnackBar(content: Text(_saveFailed)));

String _fullName(FamilyTreeData data, int? id) {
  final TreePerson? p = id == null ? null : data.people[id];
  return personName(p?.givenNames, p?.surname);
}

String _firstName(FamilyTreeData data, int id) {
  final TreePerson? p = data.people[id];
  final String name = shortPersonName(p?.givenNames, p?.surname);
  return name.isEmpty ? 'Osoba bez imienia' : name;
}

/// "Jan, Maria, Kasia i 3 inne osoby" — up to [shown] first names, then how many more.
String _namesOf(FamilyTreeData data, List<int> ids, {required int shown}) {
  final List<String> names = [
    for (final int id in ids.take(shown)) _firstName(data, id),
  ];
  final int more = ids.length - names.length;
  if (more > 0) {
    return '${names.join(', ')} i\u00A0$more ${plural(more, 'inna osoba', 'inne osoby', 'innych osób')}';
  }
  if (names.length == 1) return names.first;
  return '${names.sublist(0, names.length - 1).join(', ')} i\u00A0${names.last}';
}

/// Text of 150 % and more (drzewo.md D20 — the same threshold).
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) >= 24;

/// A row of a wreath's sign, its words and its buttons. With large text the sign and the buttons go above and
/// the words take the whole width — beside them a line's name broke in the middle of a word at 200 % on
/// 360 dp (emulator pass), and words must not break there (osoba.md v2.2).
Widget _layout(
  BuildContext context, {
  required bool large,
  required Widget sign,
  required Widget words,
  required List<Widget> trailing,
}) {
  if (large) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [sign, const Spacer(), ...trailing]),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.only(left: 6), child: words),
      ],
    );
  }
  return Row(
    children: [
      sign,
      const SizedBox(width: 10),
      Expanded(child: words),
      ...trailing,
    ],
  );
}

/// Element 4b of the form (wieniec.md E1, E1a): the person's wreath, where it comes from and "Zmień" — or
/// "Wybierz ród" when there is none to come.
class WreathFormRow extends StatelessWidget {
  const WreathFormRow({
    super.key,
    required this.database,
    required this.personId,
  });

  final GrobingDatabase database;
  final int personId;

  @override
  Widget build(BuildContext context) => StreamBuilder<FamilyTreeData>(
    stream: watchFamilyTree(database),
    builder: (context, snapshot) {
      final FamilyTreeData? data = snapshot.data;
      if (data == null) return const SizedBox(height: 88);
      return _row(context, data, data.wreaths.of(personId));
    },
  );

  Widget _row(BuildContext context, FamilyTreeData data, PersonWreath w) {
    final Clan? own = w.own;
    final bool nothing =
        w.origin == WreathOrigin.noFather ||
        w.origin == WreathOrigin.fatherWithout;
    final String title = switch (w.origin) {
      WreathOrigin.noneHere => 'Bez wieńca',
      _ => own?.name ?? 'Brak',
    };
    final String line = switch (w.origin) {
      WreathOrigin.noFather =>
        'Ojca nie ma w\u00A0drzewie, więc wieniec nie ma po kim przyjść.',
      WreathOrigin.fatherWithout =>
        'Ojciec: ${_fullName(data, w.fatherId)} — bez wieńca.',
      WreathOrigin.fromFather => 'Po ojcu: ${_fullName(data, w.fatherId)}.',
      WreathOrigin.chosenHere || WreathOrigin.noneHere =>
        w.overridesFather
            ? 'Wybrane tutaj. Po ojcu byłoby: ${w.fatherClan!.name}.'
            : _chosenHere(data, w),
    };
    final Clan? husband = w.husbandClan;
    final String? married = husband == null || husband == own
        ? null
        : own == null
        ? 'Po ślubie wieniec męża: ${husband.name} (mąż: ${_fullName(data, w.husbandId)}).'
        : 'Po ślubie prawa połowa: ${husband.name} (mąż: ${_fullName(data, w.husbandId)}).';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Wieniec rodu',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: GrobingColors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
              child: _layout(
                context,
                large: _largeText(context),
                sign: WreathSign(wreath: w, side: 56),
                words: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The words are one node for the reader; the button stays a node of its own, or it would
                    // merge into them and lose its 48 dp (retro 3 R2 test).
                    MergeSemantics(
                      child: Semantics(
                        label: 'Wieniec rodu',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: GrobingColors.text,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              line,
                              style: const TextStyle(
                                color: GrobingColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            if (married != null)
                              Text(
                                married,
                                style: const TextStyle(
                                  color: GrobingColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (nothing) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: secondaryButtonStyle.copyWith(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 48),
                          ),
                        ),
                        onPressed: () =>
                            showWreathSheet(context, database, personId),
                        icon: const GrobingIcon(Glyphs.add),
                        label: const Text('Wybierz ród'),
                      ),
                    ],
                  ],
                ),
                trailing: [
                  if (!nothing)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: GrobingColors.amber,
                        minimumSize: const Size(48, 48),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: () =>
                          showWreathSheet(context, database, personId),
                      child: const Text(
                        'Zmień',
                        semanticsLabel: 'Zmień wieniec rodu',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // E1a: back to the father's wreath.
        if (w.overridesFather)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: GrobingColors.amber,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () async {
                try {
                  await setWreathChoice(
                    database,
                    personId,
                    const WreathChoice.inherit(),
                  );
                } catch (_) {
                  if (context.mounted) _sayFailed(context);
                }
              },
              icon: const GrobingIcon(Glyphs.undo, size: 20),
              label: const Text('Wróć do wieńca po ojcu'),
            ),
          ),
      ],
    );
  }

  String _chosenHere(FamilyTreeData data, PersonWreath w) {
    if (w.origin == WreathOrigin.noneHere) return 'Wybrane tutaj.';
    final List<int> heirs = data.wreaths.heirs(personId);
    if (heirs.isEmpty) return 'Wybrane tutaj.';
    return 'Wybrane tutaj. Po tej osobie wieniec mają: ${_namesOf(data, heirs, shown: 3)}.';
  }
}

/// The sheet "Wieniec rodu — Jan" (wieniec.md E2): every line A–Z with its wreath, colour, motif and how many
/// have it, ✎ to correct it; "Nowy ród"; "Bez wieńca" when the person has or would get a wreath.
Future<void> showWreathSheet(
  BuildContext context,
  GrobingDatabase database,
  int personId,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: GrobingColors.surface,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (sheetContext) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
    ),
    child: StreamBuilder<FamilyTreeData>(
      stream: watchFamilyTree(database),
      builder: (context, snapshot) {
        final FamilyTreeData? data = snapshot.data;
        if (data == null) return const SizedBox(height: 160);
        return _WreathSheet(database: database, personId: personId, data: data);
      },
    ),
  ),
);

class _WreathSheet extends StatelessWidget {
  const _WreathSheet({
    required this.database,
    required this.personId,
    required this.data,
  });

  final GrobingDatabase database;
  final int personId;
  final FamilyTreeData data;

  Future<void> _choose(BuildContext context, WreathChoice choice) async {
    try {
      await setWreathChoice(database, personId, choice);
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) _sayFailed(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PersonWreath w = data.wreaths.of(personId);
    final List<Clan> clans = data.wreaths.clans.toList();
    final bool offerNone =
        w.origin == WreathOrigin.noneHere ||
        w.own != null ||
        w.fatherClan != null;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Semantics(
            header: true,
            child: Text(
              'Wieniec rodu — ${_firstName(data, personId)}',
              style: const TextStyle(
                color: GrobingColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (clans.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Rodów jeszcze nie ma.',
              style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
            ),
          ),
        for (final Clan clan in clans)
          _ClanRow(
            clan: clan,
            count: data.wreaths.countWith(clan.id),
            fromFather: w.fatherClan?.id == clan.id,
            selected: w.origin != WreathOrigin.noneHere && w.own?.id == clan.id,
            onTap: () => _choose(
              context,
              // The father's line is no exception: choosing it goes back to his (E2).
              w.fatherClan?.id == clan.id
                  ? const WreathChoice.inherit()
                  : WreathChoice.clan(clan.id),
            ),
            onEdit: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ClanScreen(database: database, data: data, clan: clan),
              ),
            ),
          ),
        _ActionRow(
          icon: const GrobingIcon(Glyphs.add, color: GrobingColors.amber),
          label: 'Nowy ród',
          onTap: () async {
            final bool? saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => ClanScreen(
                  database: database,
                  data: data,
                  forPersonId: personId,
                ),
              ),
            );
            if (saved == true && context.mounted) Navigator.of(context).pop();
          },
        ),
        if (offerNone)
          _ActionRow(
            icon: const GrobingIcon(
              Glyphs.block,
              color: GrobingColors.textMuted,
            ),
            label: 'Bez wieńca',
            selected: w.origin == WreathOrigin.noneHere,
            onTap: () => _choose(context, const WreathChoice.none()),
          ),
      ],
    );
  }
}

/// A line in the sheet (E2): sign · name · "Dąb · Stare złoto · 7 osób" · ✓ · ✎.
class _ClanRow extends StatelessWidget {
  const _ClanRow({
    required this.clan,
    required this.count,
    required this.fromFather,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final Clan clan;
  final int count;
  final bool fromFather;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final String details = [
      clan.motif?.label ?? 'Wzór nieznany',
      clan.colour.label,
      // A hard space between the number and the noun, and after each "·": no line ends on either (style-b.md
      // rule 6; ui review of ISSUE-044).
      '$count\u00A0${plural(count, 'osoba', 'osoby', 'osób')}',
      if (fromFather) 'po\u00A0ojcu',
    ].join(' ·\u00A0');
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: _layout(
              context,
              large: _largeText(context),
              sign: WreathSign(wreath: wreathOfClan(clan), side: 56),
              words: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clan.name,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    details,
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              trailing: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: GrobingIcon(
                      Glyphs.check,
                      color: GrobingColors.amber,
                    ),
                  ),
                IconButton(
                  icon: const GrobingIcon(
                    Glyphs.inkPen,
                    color: GrobingColors.amber,
                    applyTextScaling: false,
                  ),
                  tooltip: 'Popraw ród',
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
          child: Row(
            children: [
              SizedBox(width: 56, child: Center(child: icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 16,
                  ),
                ),
              ),
              if (selected)
                const GrobingIcon(Glyphs.check, color: GrobingColors.amber),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The screen of one line (wieniec.md F): "Nowy ród" for [forPersonId], or "Ród" — the correction of
/// [clan]. Pops `true` after a save.
class ClanScreen extends StatefulWidget {
  const ClanScreen({
    super.key,
    required this.database,
    required this.data,
    this.clan,
    this.forPersonId,
  });

  final GrobingDatabase database;

  /// The tree when the screen opened: who uses which motif and colour, and whom the line reaches (F5).
  final FamilyTreeData data;
  final Clan? clan;
  final int? forPersonId;

  @override
  State<ClanScreen> createState() => _ClanScreenState();
}

class _ClanScreenState extends State<ClanScreen> {
  late final List<Clan> _others = [
    for (final Clan c in widget.data.wreaths.clans)
      if (c.id != widget.clan?.id) c,
  ];
  late final TextEditingController _name = TextEditingController(
    text: widget.clan?.name,
  );

  // F3, F4: a new line starts with the first colour and the first motif nobody has (D20: then the first
  // motif nobody has in that colour).
  late ClanColour _colour = widget.clan?.colour ?? firstFreeColour(_others);
  late WreathMotif _motif =
      widget.clan?.motif ?? firstFreeMotif(_others, _colour);
  ClanNameProblem? _nameProblem;
  bool _saving = false;

  bool get _isNew => widget.clan == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final Clan? clan = widget.clan;
      if (clan == null) {
        await createClan(
          widget.database,
          name: _name.text,
          motif: _motif,
          colour: _colour,
          forPerson: widget.forPersonId,
        );
      } else {
        await updateClan(
          widget.database,
          clan.id,
          name: _name.text,
          motif: _motif,
          colour: _colour,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ClanNameException catch (e) {
      if (mounted) setState(() => _nameProblem = e.problem);
    } catch (_) {
      if (mounted) _sayFailed(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// F5: whom the line reaches.
  String _reach() {
    final FamilyTreeData data = widget.data;
    final Clan? clan = widget.clan;
    if (clan != null) {
      final int n = data.wreaths.countWith(clan.id);
      return 'Zmiana dotyczy $n ${n == 1 ? 'osoby' : 'osób'}.';
    }
    final int? person = widget.forPersonId;
    if (person == null) return '';
    final String name = _fullName(data, person);
    final List<int> heirs = data.wreaths.heirs(person);
    if (heirs.isEmpty) return 'Wieniec dostanie $name.';
    return 'Wieniec dostanie $name, a\u00A0po nim, po linii ojca, ${peopleLabel(heirs.length)}: '
        '${_namesOf(data, heirs, shown: 4)}.';
  }

  @override
  Widget build(BuildContext context) => Theme(
    // The fields as in the person's form: framed, not underlined.
    data: Theme.of(context).copyWith(inputDecorationTheme: GrobingTheme.fields),
    child: Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BackTitleBar(_isNew ? 'Nowy ród' : 'Ród'),
            Expanded(child: _content()),
            // F6: pinned at the foot, above the keyboard.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                style: primaryButtonStyle,
                onPressed: _saving ? null : _save,
                child: Text(_isNew ? 'Zapisz ród' : 'Zapisz'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _content() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      // F2.
      TextField(
        controller: _name,
        autofocus: _isNew,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 16),
        onChanged: (_) {
          if (_nameProblem != null) setState(() => _nameProblem = null);
        },
        decoration: InputDecoration(
          labelText: 'Nazwa',
          hintText: 'np. Wymyślscy',
          error: switch (_nameProblem) {
            ClanNameProblem.empty => const ErrorLine('Wpisz nazwę rodu.'),
            ClanNameProblem.taken => const ErrorLine(
              'Taki ród już jest — wybierz go z\u00A0listy.',
            ),
            null => null,
          },
        ),
      ),
      const SizedBox(height: 24),
      // F3.
      const _Label('Kolor'),
      // Six in a row on a phone of 360–412 dp (wieniec.md F3): 6 × 48 + 5 × 8 dp.
      Wrap(
        spacing: 8,
        children: [
          for (final ClanColour c in ClanColour.values)
            _ColourDot(
              colour: c,
              selected: c == _colour,
              onTap: () => setState(() => _colour = c),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Kolor: ${_colour.label}',
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
        ),
      ),
      const SizedBox(height: 24),
      // F4.
      const _Label('Wzór'),
      // Rows of three, each as tall as its tallest tile: "też: …" and large text never overflow a fixed cell.
      // Two columns with large text: in three, the motifs' names broke in the middle at 200 % on 360 dp.
      for (int i = 0; i < WreathMotif.values.length; i += _columns)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int j = i; j < i + _columns; j++) ...[
                  if (j > i) const SizedBox(width: 8),
                  Expanded(
                    child: j < WreathMotif.values.length
                        ? _motifTile(WreathMotif.values[j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      // F5.
      Text(
        _reach(),
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
    ],
  );

  int get _columns => _largeText(context) ? 2 : 3;

  Widget _motifTile(WreathMotif m) => _MotifTile(
    motif: m,
    colour: _colour,
    selected: m == _motif,
    // D20: a line is told by its motif and colour together — "też" only for this motif in this colour.
    usedBy: [
      for (final Clan o in _others)
        if (o.motif == m && o.colour == _colour) o.name,
    ],
    onTap: () => setState(() => _motif = m),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
    ),
  );
}

/// F3: a colour of the palette — a 36 dp dot in a 48 dp target; chosen: a ring in amber with a gap in the
/// background's colour, and ✓ in the background's colour on the dot.
class _ColourDot extends StatelessWidget {
  const _ColourDot({
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final ClanColour colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: colour.label,
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox.square(
        dimension: 48,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: GrobingColors.amber, width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GrobingColors.clan(colour),
              ),
              child: selected
                  ? const GrobingIcon(
                      Glyphs.check,
                      size: 20,
                      color: GrobingColors.background,
                      applyTextScaling: false,
                    )
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
}

/// F4: a motif in the chosen colour, its name, and which lines have it in that colour already (D2, D20).
class _MotifTile extends StatelessWidget {
  const _MotifTile({
    required this.motif,
    required this.colour,
    required this.selected,
    required this.usedBy,
    required this.onTap,
  });

  final WreathMotif motif;
  final ClanColour colour;
  final bool selected;
  final List<String> usedBy;
  final VoidCallback onTap;

  static const TextStyle _usedByStyle = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? GrobingColors.amber : GrobingColors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        // Centred in the tile: a Stack lays its child at the top left by default, and the column is as wide as
        // its widest line — the signs of one column stood at different places (ui review of ISSUE-044, MAJOR).
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Column(
                children: [
                  WreathSign(
                    wreath: wreathOfClan(
                      Clan(id: -1, name: '', motif: motif, colour: colour),
                    ),
                    side: 72,
                  ),
                  // One word: on one line, a little smaller rather than broken in the middle.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      motif.label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: GrobingColors.text,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // "też:" and each line's name on its own line, a name a little smaller rather than broken in the
                  // middle (200 % on 360 dp).
                  if (usedBy.isNotEmpty) ...[
                    const Text('też:', style: _usedByStyle),
                    for (final String name in usedBy)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(name, maxLines: 1, style: _usedByStyle),
                      ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Positioned(
                top: 4,
                right: 4,
                child: GrobingIcon(
                  Glyphs.check,
                  size: 18,
                  color: GrobingColors.amber,
                  applyTextScaling: false,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
