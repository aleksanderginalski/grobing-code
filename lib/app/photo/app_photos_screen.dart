import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/families.dart';
import '../../data/graves.dart';
import '../../data/photos.dart';
import '../dates.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'person_photos_draft.dart';
import 'photo_cell.dart';
import 'photo_people_screen.dart' show PeopleSectionHeader;
import 'photo_viewer_screen.dart';
import 'profile_circle.dart';

/// One person's group on "Zdjęcia w aplikacji" (05_DESIGN/zdjecia-w-aplikacji.md 6): who, and their
/// photos that the person being edited does not have yet, in the order of their links.
class AppPhotoGroup {
  const AppPhotoGroup({
    required this.person,
    required this.profile,
    required this.photos,
  });

  final PersonChoice person;

  /// Their first link — the circle of the row.
  final PersonPhoto profile;
  final List<PersonPhoto> photos;
}

/// What the screen shows: the nearest first (4), then everyone else (5), each by surname, then given
/// names; and the photos whose file is missing — inactive (*States*).
class AppPhotos {
  const AppPhotos({
    required this.nearest,
    required this.others,
    required this.missing,
  });

  final List<AppPhotoGroup> nearest;
  final List<AppPhotoGroup> others;
  final Set<int> missing;

  bool get isEmpty => nearest.isEmpty && others.isEmpty;
}

/// Whether "Ze zdjęć w aplikacji" has a photo to show (zdjecie.md D10) — one query, before the sheet opens;
/// the files are looked at only when the row is chosen ([loadAppPhotos]).
Future<bool> hasAppPhotos(PersonPhotosDraft draft) async {
  final Map<int, List<PersonPhoto>> all = await allPersonPhotos(draft.database);
  final Set<int> mine = draft.savedMediaIds;
  return all.entries.any(
    (e) =>
        e.key != draft.personId &&
        e.value.any((p) => !mine.contains(p.mediaId)),
  );
}

/// The photos of everyone else that [draft]'s person does not have yet ([PersonPhotosDraft.savedMediaIds]
/// — zdjecia-w-aplikacji.md D3), grouped by person (D1). A group photo is in the group of each person on
/// it (D2). "Najbliżsi" — the parents, partners and children (osoba.md 6) and this grave's people (D4).
Future<AppPhotos> loadAppPhotos(PersonPhotosDraft draft) async {
  final Map<int, List<PersonPhoto>> all = await allPersonPhotos(draft.database);
  final Set<int> mine = draft.savedMediaIds;
  final int? self = draft.personId;
  final ({List<PersonChoice> all, List<int> inGrave}) choices =
      await loadPersonChoices(draft.database, graveId: draft.graveId);
  final Set<int> nearIds = {...choices.inGrave};
  if (self != null) {
    final PersonRelations r = await loadRelations(draft.database, self);
    nearIds.addAll([
      for (final FamilyMember m in r.parents) m.id,
      for (final PersonUnion u in r.unions) ...[
        if (u.partner case final FamilyMember p) p.id,
        for (final FamilyMember c in u.children) c.id,
      ],
    ]);
  }
  final List<AppPhotoGroup> nearest = [];
  final List<AppPhotoGroup> others = [];
  final Set<int> missing = {};
  for (final PersonChoice c in choices.all) {
    if (c.id == self) continue;
    final List<PersonPhoto>? theirs = all[c.id];
    if (theirs == null || theirs.isEmpty) continue;
    final List<PersonPhoto> left = [
      for (final PersonPhoto p in theirs)
        if (!mine.contains(p.mediaId)) p,
    ];
    if (left.isEmpty) continue;
    for (final PersonPhoto p in left) {
      if (!await draft.photos.fileOf(p.relativePath).exists()) {
        missing.add(p.mediaId);
      }
    }
    final AppPhotoGroup group = AppPhotoGroup(
      person: c,
      profile: theirs.first,
      photos: left,
    );
    (nearIds.contains(c.id) ? nearest : others).add(group);
  }
  nearest.sort(_byName);
  others.sort(_byName);
  return AppPhotos(nearest: nearest, others: others, missing: missing);
}

int _byName(AppPhotoGroup a, AppPhotoGroup b) {
  final int bySurname = polishCompare(
    a.person.surname ?? '',
    b.person.surname ?? '',
  );
  return bySurname != 0
      ? bySurname
      : polishCompare(a.person.givenNames ?? '', b.person.givenNames ?? '');
}

/// "Zdjęcia w aplikacji" (05_DESIGN/zdjecia-w-aplikacji.md): the photos of everyone else, by person, a
/// filter by name, several ticked. Pops the ticked photos in the order they were ticked on "Dodaj"; back
/// pops nothing and changes nothing (style-b.md rule 10).
class AppPhotosScreen extends StatefulWidget {
  const AppPhotosScreen({
    super.key,
    required this.photos,
    required this.fileOf,
    required this.personName,
    this.firstName,
  });

  final AppPhotos photos;
  final File Function(String relativePath) fileOf;

  /// The person the photos join, without "z d." (element 1).
  final String personName;

  /// Their first given name for the line under the field (3); null — "ta osoba".
  final String? firstName;

  @override
  State<AppPhotosScreen> createState() => _AppPhotosScreenState();
}

class _AppPhotosScreenState extends State<AppPhotosScreen> {
  final TextEditingController _filter = TextEditingController();

  /// The ticked photos in the order they were ticked — a tick belongs to the photo, not to its place
  /// (D2), so a group photo is framed in every group it is in.
  final List<PersonPhoto> _ticked = [];

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

  bool _isTicked(PersonPhoto p) => _ticked.any((t) => t.mediaId == p.mediaId);

  void _toggle(PersonPhoto p) => setState(() {
    if (_isTicked(p)) {
      _ticked.removeWhere((t) => t.mediaId == p.mediaId);
    } else {
      _ticked.add(p);
    }
  });

  bool _matches(AppPhotoGroup g) =>
      _filter.text.trim().isEmpty ||
      matchesQuery(_filter.text, [
        g.person.givenNames,
        g.person.surname,
        g.person.birthSurname,
      ]);

  @override
  Widget build(BuildContext context) {
    final List<AppPhotoGroup> nearest = widget.photos.nearest
        .where(_matches)
        .toList();
    final List<AppPhotoGroup> others = widget.photos.others
        .where(_matches)
        .toList();
    final int n = _ticked.length;
    final double width = MediaQuery.sizeOf(context).width;
    const double gap = 8;
    final double cell = (width - 2 * 16 - 2 * gap) / 3;
    final int decode = coverDecodeWidth(context, cell);
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
              // Element 1.
              PhotoViewerBar(
                title: 'Zdjęcia w\u00A0aplikacji',
                subtitle: 'dla: ${widget.personName}',
              ),
              // Element 2 — pinned: it does not scroll away with the groups.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _filter,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 16,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Szukaj osoby',
                    prefixIcon: GrobingIcon(
                      Glyphs.search,
                      color: GrobingColors.textMuted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      sliver: SliverToBoxAdapter(
                        // Element 3.
                        child: Text(
                          'Bez zdjęć, które ${widget.firstName ?? 'ta osoba'} '
                          'już ma. Dotknij zdjęć, które dodać.',
                          style: const TextStyle(
                            color: GrobingColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    ..._section('Najbliżsi', nearest, cell, decode),
                    ..._section('Inne osoby', others, cell, decode),
                    if (nearest.isEmpty && others.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Nie ma osoby ze zdjęciami pasującej do '
                            '„${_filter.text.trim()}”.',
                            style: const TextStyle(
                              color: GrobingColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
              // Element 7.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: n == 0
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(List<PersonPhoto>.of(_ticked)),
                  child: Text(
                    n == 0
                        ? 'Dodaj'
                        : 'Dodaj $n ${plural(n, 'zdjęcie', 'zdjęcia', 'zdjęć')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Elements 4–5: the header of a section, then each group — its person's row and a grid built lazily,
  /// for hundreds of photos.
  List<Widget> _section(
    String title,
    List<AppPhotoGroup> groups,
    double cell,
    int decode,
  ) => [
    if (groups.isNotEmpty)
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(child: PeopleSectionHeader(title)),
      ),
    for (final AppPhotoGroup g in groups) ...[
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(child: _personRow(g)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: g.photos.length,
          itemBuilder: (context, i) => _cell(g, i, cell, decode),
        ),
      ),
    ],
  ];

  /// Element 6 — the row: not a button; the circle shows their profile photo in its crop.
  Widget _personRow(AppPhotoGroup g) {
    final PersonChoice c = g.person;
    final String life = lifeLine(birth: c.birth, death: c.death);
    final int count = g.photos.length;
    final String photos =
        '$count ${plural(count, 'zdjęcie', 'zdjęcia', 'zdjęć')}';
    // One heading for a screen reader — the name and the line — so it jumps from person to person past the
    // photos (ui review; WCAG 2.2 SC 1.3.1).
    return MergeSemantics(
      child: Semantics(header: true, child: _personRowBody(g, c, life, photos)),
    );
  }

  Widget _personRowBody(
    AppPhotoGroup g,
    PersonChoice c,
    String life,
    String photos,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ExcludeSemantics(
              child: ProfileCircle(
                file: widget.fileOf(g.profile.relativePath),
                crop: g.profile.crop,
                size: 40,
                unreadable: const UnreadableCell(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    personName(
                      c.givenNames,
                      c.surname,
                      birthSurname: c.birthSurname,
                    ),
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    life.isEmpty ? photos : '$life ·\u00A0$photos',
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A photo of the group: a tap ticks it or not; ticked — the frame around it (style-b.md rule 14), and
  /// the state for a screen reader, not the colour alone (SC 1.4.1). A missing file cannot be ticked.
  Widget _cell(AppPhotoGroup g, int i, double cell, int decode) {
    final PersonPhoto p = g.photos[i];
    final bool missing = widget.photos.missing.contains(p.mediaId);
    final bool ticked = _isTicked(p);
    final String who = personName(g.person.givenNames, g.person.surname);
    final String where = '$who, zdjęcie ${i + 1} z ${g.photos.length}';
    return PhotoCell(
      size: cell,
      selected: ticked,
      child: Semantics(
        button: true,
        enabled: !missing,
        selected: missing ? null : ticked,
        label: missing
            ? '$where, nie da się otworzyć zdjęcia'
            : ticked
            ? '$where, zaznaczone — odznacz'
            : '$where — zaznacz',
        onTap: missing ? null : () => _toggle(p),
        excludeSemantics: true,
        child: InkWell(
          onTap: missing ? null : () => _toggle(p),
          child: missing
              ? const UnreadableCell()
              : Image.file(
                  widget.fileOf(p.relativePath),
                  fit: BoxFit.cover,
                  cacheWidth: decode,
                  errorBuilder: (_, _, _) => const UnreadableCell(),
                ),
        ),
      ),
    );
  }
}
