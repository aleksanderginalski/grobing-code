import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/graves.dart';
import '../dates.dart';
import '../polish.dart';
import '../theme.dart';
import 'photo_viewer_screen.dart';

/// "Kto jest na zdjęciu?" (05_DESIGN/zdjecie.md, D): everyone in the app to tick, this grave's people
/// first and a filter over all (D7, accepted by the author at stop #1 of ISSUE-017). The person whose
/// photos these are stays ticked and inactive. Pops the ids of everyone else ticked on "Gotowe"; back
/// pops nothing and changes nothing.
class PhotoPeopleScreen extends StatefulWidget {
  const PhotoPeopleScreen({
    super.key,
    required this.photo,
    required this.personName,
    required this.personId,
    required this.choices,
    required this.ticked,
  });

  final File photo;

  /// The person whose photos these are, as the form has them now — a new person is not in [choices].
  final String personName;
  final int? personId;
  final ({List<PersonChoice> all, List<int> inGrave}) choices;

  /// Everyone else on the photo when the screen opens.
  final Set<int> ticked;

  @override
  State<PhotoPeopleScreen> createState() => _PhotoPeopleScreenState();
}

class _PhotoPeopleScreenState extends State<PhotoPeopleScreen> {
  late final Set<int> _ticked = {...widget.ticked};
  final TextEditingController _filter = TextEditingController();

  late final Map<int, PersonChoice> _byId = {
    for (final PersonChoice c in widget.choices.all) c.id: c,
  };

  /// This grave's people in the order entered, without the person whose photos these are.
  late final List<PersonChoice> _inGrave = [
    for (final int id in widget.choices.inGrave)
      if (id != widget.personId && _byId[id] != null) _byId[id]!,
  ];

  /// Everyone else, by surname, then given names (Polish order — D5).
  late final List<PersonChoice> _others = [
    for (final PersonChoice c in widget.choices.all)
      if (c.id != widget.personId && !widget.choices.inGrave.contains(c.id)) c,
  ]..sort(_compare);

  static int _compare(PersonChoice a, PersonChoice b) {
    final int bySurname = polishCompare(a.surname ?? '', b.surname ?? '');
    return bySurname != 0
        ? bySurname
        : polishCompare(a.givenNames ?? '', b.givenNames ?? '');
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

  bool _matches(PersonChoice c) =>
      _filter.text.trim().isEmpty ||
      matchesQuery(_filter.text, [c.givenNames, c.surname, c.birthSurname]);

  @override
  Widget build(BuildContext context) {
    final List<PersonChoice> inGrave = _inGrave.where(_matches).toList();
    final List<PersonChoice> others = _others.where(_matches).toList();
    final bool selfShown =
        _filter.text.trim().isEmpty ||
        matchesQuery(_filter.text, [widget.personName]);
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(inputDecorationTheme: GrobingTheme.fields),
      child: Scaffold(
        backgroundColor: GrobingColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // D1.
              const PhotoViewerBar(title: 'Kto jest na zdjęciu?'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    // D2: the whole photo, to see the faces while choosing the names.
                    SizedBox(
                      height: 160,
                      child: Image.file(
                        widget.photo,
                        fit: BoxFit.contain,
                        cacheHeight:
                            (160 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const UnreadablePhoto(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // D3.
                    TextField(
                      controller: _filter,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        color: GrobingColors.text,
                        fontSize: 16,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Szukaj osoby',
                        prefixIcon: Icon(
                          Icons.search,
                          color: GrobingColors.textMuted,
                        ),
                      ),
                    ),
                    if (selfShown || inGrave.isNotEmpty) ...[
                      const PeopleSectionHeader('W tym grobie'),
                      // D4: the person whose photos these are — ticked, inactive.
                      if (selfShown)
                        _PersonRow(
                          name: widget.personName,
                          line: 'ta osoba',
                          ticked: true,
                          onChanged: null,
                        ),
                      for (final PersonChoice c in inGrave) _row(c),
                    ],
                    if (others.isNotEmpty) ...[
                      const PeopleSectionHeader('Inne osoby'),
                      for (final PersonChoice c in others)
                        _row(c, withPlace: true),
                    ],
                    if (!selfShown && inGrave.isEmpty && others.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Nie ma osoby pasującej do „${_filter.text.trim()}”.',
                          style: const TextStyle(
                            color: GrobingColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // D6.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(_ticked),
                  child: const Text(
                    'Gotowe',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// D4–D5: a row of a person; [withPlace] adds where they lie, so two of the same name differ.
  Widget _row(PersonChoice c, {bool withPlace = false}) {
    final String life = lifeLine(birth: c.birth, death: c.death);
    final String? place = withPlace ? (c.graveName ?? c.cemeteryName) : null;
    return _PersonRow(
      name: personName(c.givenNames, c.surname, birthSurname: c.birthSurname),
      line: place == null ? life : '$life · $place',
      ticked: _ticked.contains(c.id),
      onChanged: (on) => setState(() {
        if (on) {
          _ticked.add(c.id);
        } else {
          _ticked.remove(c.id);
        }
      }),
    );
  }
}

/// A section header of a list of people — "W tym grobie", "Inne osoby" (05_DESIGN/zdjecie.md D4–D5) and
/// the family sheet's "Para", "Dzieci" (rodzina.md A2, A7): 14 sp, semi-bold, the muted colour.
class PeopleSectionHeader extends StatelessWidget {
  const PeopleSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 2),
    child: Text(
      text,
      style: const TextStyle(
        color: GrobingColors.textMuted,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A row ≥ 56 dp, the whole row one target: the checkbox carries the amber and a check, never the colour
/// alone (SC 1.4.1). [onChanged] null = inactive.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.line,
    required this.ticked,
    required this.onChanged,
  });

  final String name;
  final String line;
  final bool ticked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!ticked),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Checkbox(
              value: ticked,
              onChanged: onChanged == null ? null : (v) => onChanged!(v!),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: GrobingColors.text,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      line,
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
          ],
        ),
      ),
    ),
  );
}
