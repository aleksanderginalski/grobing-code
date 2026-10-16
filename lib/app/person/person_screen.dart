import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart' show QualifiedDate;
import '../../data/person_view.dart';
import '../../data/photos.dart' show PersonPhotoEdits, ProfilePhoto;
import '../../data/residences.dart' show Residence, impliedEnds;
import '../dates.dart';
import '../grave/cemetery_screen.dart';
import '../grave/person_form_screen.dart';
import '../people/me_picker_screen.dart';
import '../people/people_list.dart' show InitialsCircle;
import '../photo/person_photo_viewer_screen.dart';
import '../photo/person_photos_draft.dart';
import '../photo/person_photos_screen.dart';
import '../photo/photo_viewer_screen.dart' show coverDecodeWidth;
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'kinship_names.dart';
import 'mini_tree.dart';
import 'residence_screen.dart' show residenceLabel, residenceLines;

/// Opens the view of [personId] (05_DESIGN/osoba.md, ISSUE-024) — the one way to it: a person's card in
/// the grave and in Osoby, a relative's chip or card in the form, a node of the mini tree or the chain
/// (D14). [tab] stays active in the bottom bar (style-b.md rule 12).
Future<void> openPersonView(
  BuildContext context,
  GrobingDatabase database,
  int personId, {
  Photos? photos,
  AppTab tab = AppTab.map,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PersonScreen(
      database: database,
      personId: personId,
      photos: photos,
      tab: tab,
    ),
  ),
);

/// One person's view (osoba.md v2.1): the background, the portrait on its edge, the name and years, "kim
/// była", the family as a mini tree, the chain from "ja", the dates with the burial, the photos. Only to
/// look at — the correction is under ✎ (style-b.md rule 15; W2: the photos open without actions).
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.database,
    required this.personId,
    this.photos,
    this.tab = AppTab.map,
  });

  final GrobingDatabase database;
  final int personId;

  /// Null only in tests of other features: then the view has no photos.
  final Photos? photos;
  final AppTab tab;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Stream<PersonView?> _view = _watch();

  Stream<PersonView?> _watch() =>
      watchPersonView(widget.database, widget.personId);

  void _open(int personId) => openPersonView(
    context,
    widget.database,
    personId,
    photos: widget.photos,
    tab: widget.tab,
  );

  /// ✎ (element 1) — and "Dodaj zdjęcie" (element 10, D20), which opens the same correction with the
  /// photo sheet over it at once.
  Future<void> _correct({bool pickPhotos = false, bool addResidence = false}) =>
      openPersonEntry(
        context,
        widget.database,
        widget.personId,
        photos: widget.photos,
        tab: widget.tab,
        pickPhotosAtStart: pickPhotos,
        addResidenceAtStart: addResidence,
      );

  /// Pochówek (element 9): the cemetery with this grave marked — on the map when it has a pin, on the list
  /// without one (05_DESIGN/cmentarz.md D23; D17 holds until pins can be set, US-008).
  Future<void> _openBurial(BurialPlace b) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CemeteryScreen(
        database: widget.database,
        cemeteryId: b.cemeteryId,
        photos: widget.photos,
        tab: widget.tab,
        highlightGraveId: b.graveId,
      ),
    ),
  );

  Future<void> _chooseMe() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          MePickerScreen(database: widget.database, photos: widget.photos),
    ),
  );

  /// The person's photos only to look at (W2): a draft read from the database, never written.
  Future<void> _lookAt(PersonView v, {required bool grid}) async {
    final Photos? photos = widget.photos;
    if (photos == null) return;
    final PersonPhotosDraft draft = PersonPhotosDraft(
      database: widget.database,
      photos: photos,
      personId: v.id,
      graveId: v.burial?.graveId,
    );
    await draft.load();
    if (!mounted || draft.count == 0) {
      draft.dispose();
      return;
    }
    final String short = personName(v.givenNames, v.surname);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => grid
            ? PersonPhotosScreen(
                draft: draft,
                personName: _fullName(v),
                shortName: short,
                readOnly: true,
              )
            : PersonPhotoViewerScreen(
                draft: draft,
                initialIndex: 0,
                personName: short,
                readOnly: true,
              ),
      ),
    );
    draft.dispose();
  }

  /// The band (element 2, osoba.md D21): "Zdjęcie w tle" over the person's photos; the choice is written at
  /// once, as the gravestone's photo is (grob.md) — it chooses a picture, it corrects no entry — and the
  /// view shows it (rule 10).
  Future<void> _chooseBackground(PersonView v) async {
    final Photos? photos = widget.photos;
    if (photos == null) return;
    final PersonPhotosDraft draft = PersonPhotosDraft(
      database: widget.database,
      photos: photos,
      personId: v.id,
      graveId: v.burial?.graveId,
    );
    try {
      await draft.load();
      if (!mounted) return;
      final BackgroundChoice? choice = await Navigator.of(context)
          .push<BackgroundChoice>(
            MaterialPageRoute(
              builder: (_) => PersonPhotosScreen(
                draft: draft,
                personName: _fullName(v),
                shortName: personName(v.givenNames, v.surname),
                chooseBackground: true,
              ),
            ),
          );
      if (choice == null) return;
      if (choice.photo case final DraftPhoto photo) {
        draft.setBackground(photo);
      } else {
        draft.clearBackground();
      }
      final PersonPhotoEdits? edits = draft.edits();
      if (edits == null) return;
      await photos.writeWithPersonPhotos<void>(
        widget.database,
        edits,
        (alsoWrite) => widget.database.transaction(() => alsoWrite!(v.id)),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nie udało się zapisać zdjęcia w tle. Spróbuj jeszcze raz.',
            ),
          ),
        );
      }
    } finally {
      draft.dispose();
    }
  }

  static String _fullName(PersonView v) =>
      personName(v.givenNames, v.surname, birthSurname: v.birthSurname);

  @override
  Widget build(BuildContext context) => StreamBuilder<PersonView?>(
    stream: _view,
    builder: (context, snapshot) {
      final PersonView? v = snapshot.data;
      final bool failed = snapshot.hasError || (snapshot.hasData && v == null);
      return Scaffold(
        bottomNavigationBar: GrobingTabBar(
          active: widget.tab,
          database: widget.database,
          photos: widget.photos,
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(v),
              Expanded(
                child: failed
                    ? _readError()
                    // Reading the local database takes a moment: the background alone, no spinner.
                    : v == null
                    ? const SizedBox.shrink()
                    : _content(v),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Element 1: back and ✎; no title — the name stands in the header (4).
  Widget _bar(PersonView? v) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
    child: Row(
      children: [
        const BackButton(color: GrobingColors.text),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: GrobingColors.amber),
          tooltip: 'Popraw wpis',
          onPressed: v == null ? null : _correct,
        ),
      ],
    ),
  );

  Widget _readError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Nie udało się odczytać wpisu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
          ),
          TextButton(
            onPressed: () => setState(() => _view = _watch()),
            child: const Text('Spróbuj ponownie'),
          ),
        ],
      ),
    ),
  );

  Widget _content(PersonView v) {
    final Photos? photos = widget.photos;
    final String? background = photos == null ? null : v.backgroundPath;
    final bool hasRelatives =
        v.relations.parents.isNotEmpty || v.relations.unions.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Elements 2–3: the band always (v2.3, D21) — the background, or a plain one — and the portrait
        // half over its lower edge. Without photos at all (only in tests of other features), under the bar.
        if (photos != null)
          SizedBox(
            height: 140 + 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 140,
                  child: _Background(
                    file: background == null ? null : photos.fileOf(background),
                    onTap: () => _chooseBackground(v),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 140 - 52,
                  child: Center(child: _portrait(v)),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(child: _portrait(v)),
          ),
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              header: true,
              child: Text(
                _fullName(v),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GrobingColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        if (v.birth != null || v.death != null)
          _padded(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                lifeLine(birth: v.birth, death: v.death),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        // Element 5: "kim była", whole (D16), without a source line (D10).
        if (v.bio case final String bio when bio.trim().isNotEmpty)
          _padded(
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                bio.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GrobingColors.text,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ),
          ),
        // Element 6: the family as a mini tree, to the screen's edges — it scrolls sideways when wider.
        _padded(
          const _SectionHeader(icon: Icons.people_outline, text: 'Rodzina'),
        ),
        if (hasRelatives) ...[
          MiniTree(
            person: FamilyMember(
              id: v.id,
              givenNames: v.givenNames,
              surname: v.surname,
              birthSurname: v.birthSurname,
              sex: v.sex,
              birth: v.birth,
              death: v.death,
            ),
            relations: v.relations,
            profiles: v.relativeProfiles,
            photos: photos,
            onOpen: _open,
          ),
          // "Pokaż w drzewie" (osoba.md v2.4, D11; US-009 AC-6): the Drzewo tab with this person in the
          // middle — a change of tab, not a tree on this stack (drzewo.md D15). Only with a family: without
          // one the tree would show the person alone.
          _padded(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: GrobingColors.amber,
                ),
                onPressed: () => openTab(
                  context,
                  AppTab.tree,
                  database: widget.database,
                  photos: photos,
                  treeFocus: v.id,
                ),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Pokaż w drzewie'),
              ),
            ),
          ),
        ] else
          _padded(
            const Text(
              'Rodziny jeszcze nie ma. Dodasz ją pod ✎.',
              style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
            ),
          ),
        // Element 7: none for "ja" themselves.
        if (v.meId != v.id) ...[
          _padded(
            const _SectionHeader(
              icon: Icons.link,
              text: 'Jak łączy się ze mną',
            ),
          ),
          _padded(_chain(v)),
        ],
        // Elements 8–9.
        if (v.birth != null || v.death != null || v.burial != null) ...[
          _padded(
            const _SectionHeader(icon: Icons.event_note_outlined, text: 'Daty'),
          ),
          _padded(_dates(v)),
        ],
        // Element 9a (v2.5): the residences — also without any, as the place to add them (zamieszkanie.md D1).
        _padded(
          const _SectionHeader(
            icon: Icons.home_outlined,
            text: 'Miejsca zamieszkania',
          ),
        ),
        _padded(_residences(v)),
        // Element 10: the photos — also without any (D20), as the place to add them.
        _padded(
          _SectionHeader(
            icon: Icons.photo_library_outlined,
            text: v.photoCount == 0 ? 'Zdjęcia' : 'Zdjęcia · ${v.photoCount}',
          ),
        ),
        _padded(_photos(v)),
      ],
    );
  }

  static Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );

  /// Element 3: the profile photo in a 104 dp circle with a ring in amber; without a photo, the initials
  /// in a circle with an outline — no action (W2), the place to add photos is element 10.
  Widget _portrait(PersonView v) {
    final Photos? photos = widget.photos;
    final ProfilePhoto? profile = v.profile;
    if (photos == null || profile == null) {
      return ExcludeSemantics(
        child: Container(
          width: 104,
          height: 104,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GrobingColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: GrobingColors.outline, width: 2),
          ),
          child: Text(
            _initials(v.givenNames, v.surname),
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 34,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      button: true,
      label: 'Zdjęcie profilowe',
      hint: 'otwórz',
      excludeSemantics: true,
      onTap: () => _lookAt(v, grid: false),
      child: GestureDetector(
        onTap: () => _lookAt(v, grid: false),
        // The ring over the photo: under it, the opaque circle of the same size would hide it (ui review). The
        // glow under the photo: over it, it toned the portrait amber (ui review of ISSUE-033; style-b.md rule 14
        // — no filters, nothing on the photo; author's "ok" at its stop #2).
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: GrobingColors.amber.withValues(alpha: 0.25),
                blurRadius: 18,
              ),
            ],
          ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: GrobingColors.amber, width: 2),
            ),
            child: ProfileCircle(
              file: photos.fileOf(profile.relativePath),
              crop: profile.crop,
              size: 104,
              unreadable: const _Unreadable(size: 104),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String? given, String? surname) {
    final String letters = [
      for (final String? part in [given, surname])
        if (part != null && part.trim().isNotEmpty)
          part.trim().characters.first.toUpperCase(),
    ].join();
    return letters.isEmpty ? '?' : letters;
  }

  /// Element 7 (D13'): the chain from "Ja" — each row the step to the person above and the first name,
  /// as R3's path card; the circles joined by a line in amber. Without "ja", the way to choose them;
  /// without a path, a fact.
  Widget _chain(PersonView v) {
    if (v.meId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aplikacja nie wie jeszcze, która osoba to Ty.',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
          ),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: _chooseMe,
            child: const Text('Wybierz, która osoba to Ty'),
          ),
        ],
      );
    }
    final List<ChainLink>? chain = v.chain;
    if (chain == null) {
      return const Text(
        'Nie wiadomo jeszcze, jak łączy się z Tobą — w drzewie brakuje rodziny '
        'między wami.',
        style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
      );
    }
    final List<String> labels = chainLabels([
      for (final ChainLink l in chain)
        ChainPerson(
          edge: l.step.edge,
          sex: l.sex,
          married: l.step.married,
          name: _firstName(l.givenNames, l.surname),
        ),
    ]);
    final List<Widget> rows = [
      _ChainRow(
        circle: const InitialsCircle(text: 'Ja', accent: true),
        label: 'Ja',
        lineBelow: chain.isNotEmpty,
        onTap: () => _open(v.meId!),
      ),
      for (final (int i, ChainLink l) in chain.indexed)
        _ChainRow(
          circle: _chainCircle(l),
          label: labels[i],
          lineAbove: true,
          lineBelow: i < chain.length - 1,
          onTap: i == chain.length - 1 ? null : () => _open(l.step.personId),
        ),
    ];
    // The circles joined by one line in amber (R4): each row draws it above and below its circle, and
    // the gap between rows carries it on — at any height of a row (ui review).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (int i, Widget row) in rows.indexed) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 19),
              child: Container(width: 2, height: 8, color: GrobingColors.amber),
            ),
          row,
        ],
      ],
    );
  }

  Widget _chainCircle(ChainLink l) {
    final Widget initials = InitialsCircle(
      text: _initials(l.givenNames, l.surname),
    );
    return switch ((widget.photos, l.profile)) {
      (final Photos photos?, final ProfilePhoto p?) => ProfileCircle(
        file: photos.fileOf(p.relativePath),
        crop: p.crop,
        size: 40,
        unreadable: initials,
      ),
      _ => initials,
    };
  }

  static String _firstName(String? given, String? surname) {
    final String first = (given ?? '').trim().split(RegExp(r'\s+')).first;
    if (first.isNotEmpty) return first;
    final String s = (surname ?? '').trim();
    return s.isEmpty ? 'bez imienia' : s;
  }

  /// Elements 8–9: the first birth and death (ADR-006 D3), without a source (D10); then the burial.
  Widget _dates(PersonView v) {
    final List<Widget> rows = [
      if (v.birth case final QualifiedDate b)
        _DateRow('Urodzenie', formatDate(b)),
      if (v.death case final QualifiedDate d) _DateRow('Zgon', formatDate(d)),
      if (v.burial case final BurialPlace b)
        _BurialRow(place: b, onTap: () => _openBurial(b)),
    ];
    return Column(
      // Full width: a row with its label on top is narrower than the screen and would stand centred.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (int i, Widget row) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1, color: GrobingColors.outline),
          row,
        ],
      ],
    );
  }

  /// Element 9a (zamieszkanie.md 1–4): a row for each residence in the order of the years, without an action
  /// (the map is ISSUE-045's); without any, "Dodaj miejsce" opens the correction with the window at once.
  Widget _residences(PersonView v) {
    if (v.residences.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nie ma jeszcze zapisanych miejsc.',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: secondaryButtonStyle.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
            ),
            onPressed: () => _correct(addResidence: true),
            icon: const Icon(Icons.add_home_outlined),
            label: const Text('Dodaj miejsce'),
          ),
        ],
      );
    }
    final List<QualifiedDate?> ends = impliedEnds(v.residences);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (int i, Residence r) in v.residences.indexed) ...[
          if (i > 0) const Divider(height: 1, color: GrobingColors.outline),
          _ResidenceRow(r, impliedTo: ends[i]),
        ],
      ],
    );
  }

  /// Element 10: up to four thumbnails, the whole row one target to the photos (only to look at, W2);
  /// without photos, the place to add them (D20).
  Widget _photos(PersonView v) {
    final Photos? photos = widget.photos;
    if (v.photoCount == 0 || photos == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ta osoba nie ma jeszcze zdjęć.',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            // The width of its content (osoba.md element 10), not the full row of the shared style.
            style: secondaryButtonStyle.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
            ),
            onPressed: photos == null ? null : () => _correct(pickPhotos: true),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Dodaj zdjęcie'),
          ),
        ],
      );
    }
    final int decode = coverDecodeWidth(context, 56);
    return Semantics(
      container: true,
      button: true,
      label: 'Zdjęcia osoby, ${v.photoCount}',
      hint: 'otwórz',
      excludeSemantics: true,
      onTap: () => _lookAt(v, grid: true),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _lookAt(v, grid: true),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              for (final String path in v.firstPhotos) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    photos.fileOf(path),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    cacheWidth: decode,
                    errorBuilder: (_, _, _) => const _Unreadable(size: 56),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              const Icon(Icons.chevron_right, color: GrobingColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's header: its icon in amber and the title (style-b.md rule 3; R4).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Icon(icon, size: 22, color: GrobingColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: GrobingColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Element 2 (v2.3, D21): the band over the whole width — the background cut from the middle, nothing on
/// it (rule 14), or without one a plain band on the surface with a small icon in amber, so the place to tap
/// is seen. The whole band chooses the background.
class _Background extends StatelessWidget {
  const _Background({required this.file, required this.onTap});

  /// The background's file; null — none.
  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final File? f = file;
    return Semantics(
      container: true,
      button: true,
      // Without one, the reader hears that there is none (ui review).
      label: f == null ? 'Zdjęcie w tle: brak' : 'Zdjęcie w tle',
      hint: 'wybierz',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: f == null
            // The icon means "choose the background": its words on a long press (rule 3).
            ? const Tooltip(
                message: 'Zdjęcie w tle',
                child: ColoredBox(
                  color: GrobingColors.surface,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: GrobingColors.amber,
                      ),
                    ),
                  ),
                ),
              )
            : Image.file(
                f,
                fit: BoxFit.cover,
                cacheWidth: coverDecodeWidth(
                  context,
                  MediaQuery.sizeOf(context).width,
                ),
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: GrobingColors.surface,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: GrobingColors.textMuted,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    color: GrobingColors.background,
    alignment: Alignment.center,
    child: const Icon(
      Icons.broken_image_outlined,
      size: 20,
      color: GrobingColors.textMuted,
    ),
  );
}

/// One row of the chain: a 40 dp circle with a ring in amber and its label; at least 48 dp, the whole
/// row one target ([onTap] null — the person of the view, no action). The chain's line runs into the row
/// above and below the circle ([lineAbove], [lineBelow]).
class _ChainRow extends StatelessWidget {
  const _ChainRow({
    required this.circle,
    required this.label,
    this.lineAbove = false,
    this.lineBelow = false,
    this.onTap,
  });

  final Widget circle;
  final String label;
  final bool lineAbove;
  final bool lineBelow;
  final VoidCallback? onTap;

  static Widget _line(bool shown) => Expanded(
    child: Center(
      child: Container(
        width: 2,
        color: shown ? GrobingColors.amber : Colors.transparent,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onTap != null,
    label: label,
    hint: onTap == null ? null : 'otwórz',
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    _line(lineAbove),
                    // The ring over the photo (MAJOR in the ui review: under it, it was hidden).
                    DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: GrobingColors.amber,
                          width: 2,
                        ),
                      ),
                      child: SizedBox.square(
                        dimension: 40,
                        child: ClipOval(child: circle),
                      ),
                    ),
                    _line(lineBelow),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Whether a row of element 8 puts its label over the value: when the label grows past its 96 dp column
/// with the system's text size, so a word is never broken in the middle ("Pochów / ek" at 200% — ui review,
/// SC 1.4.4).
bool _labelOnTop(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 18;

/// The label of a row of element 8.
class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text, {required this.onTop});

  final String text;
  final bool onTop;

  @override
  Widget build(BuildContext context) {
    final Widget label = Text(
      text,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
    );
    return onTop
        ? Padding(padding: const EdgeInsets.only(bottom: 2), child: label)
        : SizedBox(width: 96, child: label);
  }
}

/// A row of element 8: the label in 96 dp, the value; with large text the label over the value.
class _DateRow extends StatelessWidget {
  const _DateRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bool onTop = _labelOnTop(context);
    final Widget valueText = Text(
      value,
      style: const TextStyle(color: GrobingColors.text, fontSize: 16),
    );
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: onTop
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_RowLabel(label, onTop: true), valueText],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RowLabel(label, onTop: false),
                    const SizedBox(width: 12),
                    Expanded(child: valueText),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A row of element 9a (zamieszkanie.md, element 2): the years in a column of 112 dp — over the place with
/// large text, as the rows of element 8 — and the place in one or two lines. No action.
class _ResidenceRow extends StatelessWidget {
  const _ResidenceRow(this.residence, {this.impliedTo});

  final Residence residence;

  /// The end the next residence gives this one when it has none (zamieszkanie.md v1.2, D12).
  final QualifiedDate? impliedTo;

  @override
  Widget build(BuildContext context) {
    final ({String first, String? second}) lines = residenceLines(residence);
    final bool onTop = _labelOnTop(context);
    final Widget years = Text(
      stayYears(residence.from, residence.to ?? impliedTo) ?? '',
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
    );
    final Widget place = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lines.first,
          style: const TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        if (lines.second case final String second)
          Text(
            second,
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 14,
            ),
          ),
      ],
    );
    final bool noYears = residence.from == null && residence.to == null;
    return Semantics(
      container: true,
      label: residenceLabel(residence, impliedTo: impliedTo),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: onTop
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!noYears)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: years,
                      ),
                    place,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 112, child: years),
                    const SizedBox(width: 12),
                    Expanded(child: place),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Element 9: the grave, its cemetery and address; to the cemetery with the grave marked (D17).
class _BurialRow extends StatelessWidget {
  const _BurialRow({required this.place, required this.onTap});

  final BurialPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String title = place.graveName ?? 'Grób';
    final String? address = graveAddress(place.sector, place.row, place.plot);
    final bool onTop = _labelOnTop(context);
    const TextStyle muted = TextStyle(
      color: GrobingColors.textMuted,
      fontSize: 14,
    );
    final Widget value = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        const SizedBox(height: 2),
        Text(place.cemeteryName, style: muted),
        if (address != null) Text(address, style: muted),
      ],
    );
    const Widget chevron = Padding(
      padding: EdgeInsets.only(top: 8),
      child: Icon(Icons.chevron_right, color: GrobingColors.textMuted),
    );
    return Semantics(
      container: true,
      button: true,
      label: 'Pochówek: $title, ${place.cemeteryName}',
      hint: 'pokaż na cmentarzu',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onTop)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _RowLabel('Pochówek', onTop: true),
                        value,
                      ],
                    ),
                  )
                else ...[
                  const _RowLabel('Pochówek', onTop: false),
                  const SizedBox(width: 12),
                  Expanded(child: value),
                ],
                chevron,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
