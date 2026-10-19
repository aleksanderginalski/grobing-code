import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/photos.dart' show PersonPhoto, PersonPhotoEdits, PhotoCrop;
import '../polish.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'app_photos_screen.dart';
import 'person_photo_viewer_screen.dart';
import 'person_photos_draft.dart';
import 'photo_cell.dart';
import 'photo_picker.dart';
import 'photo_source_sheet.dart';
import 'photo_viewer_screen.dart';
import 'profile_circle.dart';
import 'profile_crop_screen.dart';

/// Picks a person's photos (05_DESIGN/zdjecie.md A, the person's mode) and hands them to [draft]: several
/// from the gallery or one with the camera, to prepare — or, on "Ze zdjęć w aplikacji" (v1.7, A4), photos
/// already in the app on someone else (zdjecia-w-aplikacji.md). A4 is in the sheet only when there is a
/// photo to choose (D10). Shared by the form's element 1a, the tile of the person's photos, "Zdjęcie
/// profilowe" and the person's view. [personName] without "z d." and [firstName] are for the screen of A4.
Future<void> addPersonPhotos(
  BuildContext context,
  PersonPhotosDraft draft, {
  required String personName,
  String? firstName,
}) async {
  final bool fromApp = await hasAppPhotos(draft);
  if (!context.mounted) return;
  final PersonPhotoSource? source = await showPersonPhotoSourceSheet(
    context,
    fromApp: fromApp,
  );
  if (source == null || !context.mounted) return;
  switch (source) {
    case PersonPhotoSource.gallery:
      await draft.addPicked(await draft.photos.pickMany());
    case PersonPhotoSource.camera:
      await draft.addPicked([?await draft.photos.pick(PhotoSource.camera)]);
    case PersonPhotoSource.app:
      final AppPhotos inApp = await loadAppPhotos(draft);
      if (!context.mounted) return;
      final List<PersonPhoto>? chosen = await Navigator.of(context)
          .push<List<PersonPhoto>>(
            MaterialPageRoute(
              builder: (_) => AppPhotosScreen(
                photos: inApp,
                fileOf: draft.photos.fileOf,
                personName: personName,
                firstName: firstName,
              ),
            ),
          );
      for (final PersonPhoto p in chosen ?? const <PersonPhoto>[]) {
        draft.addSaved(p.mediaId, draft.photos.fileOf(p.relativePath));
      }
  }
}

/// Writes [draft]'s changes at once — from the person's view, where choosing or adding a picture is not a
/// correction of the entry (05_DESIGN/osoba.md D21, D24) — and reads the draft again, so a screen that
/// stays open works on what is saved. Nothing changed, nothing written. Throws when the write fails; the
/// draft keeps its changes then, to try again.
Future<void> savePersonPhotosNow(PersonPhotosDraft draft) async {
  final int personId = draft.personId!;
  final PersonPhotoEdits? edits = draft.edits();
  if (edits == null) return;
  await draft.photos.writeWithPersonPhotos<void>(
    draft.database,
    edits,
    (alsoWrite) => draft.database.transaction(() => alsoWrite!(personId)),
  );
  await draft.reload();
}

/// What "Zdjęcie w tle" gives back (zdjecia-osoby.md v1.4): the photo chosen — one of the draft's, or one
/// just added to it — or [photo] null for "Bez zdjęcia w tle". Back gives nothing.
class BackgroundChoice {
  const BackgroundChoice(this.photo);

  final DraftPhoto? photo;
}

/// A person's photos (05_DESIGN/zdjecia-osoby.md): the profile photo in a circle, every photo in a grid
/// of squares, "Dodaj zdjęcie" as the last cell. Nothing here is written: back returns to the form, whose
/// "Zapisz" writes the changes (D1). From the person's view only to look at ([readOnly], v1.2), to
/// choose the background ([chooseBackground], v1.4) — the screen pops a [BackgroundChoice] and the view
/// writes it — or to choose the profile photo and add photos ([chooseProfile], v1.5), written at once
/// here.
class PersonPhotosScreen extends StatefulWidget {
  const PersonPhotosScreen({
    super.key,
    required this.draft,
    required this.personName,
    required this.shortName,
    this.firstName,
    this.readOnly = false,
    this.chooseBackground = false,
    this.chooseProfile = false,
  });

  /// "Zdjęcie w tle" from the band of the person's view (zdjecia-osoby.md v1.4; osoba.md D21): a tap on a
  /// photo chooses it, the tile adds one photo and chooses it, "Bez zdjęcia w tle" takes it off.
  final bool chooseBackground;

  /// "Zdjęcie profilowe" from the portrait of the person's view (zdjecia-osoby.md v1.5, P1–P6; osoba.md
  /// D23): "Obejrzyj zdjęcie", a tap on a photo → the crop → "Gotowe" makes it the profile photo, written
  /// at once, and the screen pops back to the view; the tile adds photos, written at once, and the screen
  /// stays with them (D7).
  final bool chooseProfile;

  /// The person's first given name, for "Zdjęcia w aplikacji" (zdjecia-w-aplikacji.md 3); null — "ta
  /// osoba".
  final String? firstName;

  /// From the person's view (zdjecia-osoby.md v1.2; osoba.md W2): no "Dodaj zdjęcie" tile, no line about
  /// saving, and the photo opens without actions.
  final bool readOnly;

  final PersonPhotosDraft draft;

  /// The person as the form has them now, with "z d." (element 1).
  final String personName;

  /// The same without "z d.", for the photo's bar and "Na zdjęciu" (zdjecie.md B1, B5).
  final String shortName;

  @override
  State<PersonPhotosScreen> createState() => _PersonPhotosScreenState();
}

class _PersonPhotosScreenState extends State<PersonPhotosScreen> {
  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_changed);
  }

  @override
  void dispose() {
    widget.draft.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// "Zdjęcie profilowe": a write that failed ("Zapis — błąd", v1.5) — the draft is back to what is saved,
  /// and the line stays until the next try.
  bool _saveFailed = false;

  /// A write at once in progress — the photos and the tile wait for it.
  bool _saving = false;

  /// P2 "Obejrzyj zdjęcie": the profile photo whole, only to look at (zdjecie.md B, viewing mode).
  Future<void> _look() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonPhotoViewerScreen(
        draft: widget.draft,
        initialIndex: 0,
        personName: widget.shortName,
        readOnly: true,
      ),
    ),
  );

  /// P5: a photo → the crop → "Gotowe" — the profile photo with that crop, written at once, and back to the
  /// person's view with the new portrait (kadr-profilowego.md v1.3). Back from the crop changes nothing.
  Future<void> _chooseProfile(DraftPhoto photo) async {
    final PersonPhotosDraft draft = widget.draft;
    final PhotoCrop? crop = await Navigator.of(context).push<PhotoCrop>(
      MaterialPageRoute(
        builder: (_) => ProfileCropScreen(
          file: photo.file,
          personName: widget.shortName,
          initial: draft.cropOf(photo),
        ),
      ),
    );
    if (crop == null || !mounted) return;
    draft.setProfile(photo, crop: crop);
    if (await _saveNow() && mounted) Navigator.of(context).pop();
  }

  /// P6: the tile — photos added, several from the gallery or from the app, written at once; the screen
  /// stays with them in the grid, so one of them becomes the profile photo with one more tap (D7).
  Future<void> _addPhotosNow() async {
    setState(() => _saveFailed = false);
    await addPersonPhotos(
      context,
      widget.draft,
      personName: widget.shortName,
      firstName: widget.firstName,
    );
    if (mounted) await _saveNow();
  }

  /// The write at once (osoba.md D24). On a failure the draft goes back to what is saved and the line
  /// says it (v1.5, "Zapis — błąd"); true when written.
  Future<bool> _saveNow() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await savePersonPhotosNow(widget.draft);
      return true;
    } on Object {
      try {
        await widget.draft.reload();
      } on Object {
        // The line below says it; the view reads the database again anyway.
      }
      if (mounted) setState(() => _saveFailed = true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(int index) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonPhotoViewerScreen(
        draft: widget.draft,
        initialIndex: index,
        personName: widget.shortName,
        readOnly: widget.readOnly,
      ),
    ),
  );

  /// The tile in "Zdjęcie w tle": one photo, from the gallery or the camera, joins the person's photos and
  /// is the choice (v1.4).
  Future<void> _addBackground() async {
    final PersonPhotosDraft draft = widget.draft;
    final PhotoSource? source = await showPhotoSourceSheet(
      context,
      title: 'Zdjęcie w tle',
    );
    if (source == null) return;
    final File? picked = await draft.photos.pick(source);
    if (picked == null) return;
    final int before = draft.count;
    await draft.addPicked([picked]);
    if (!mounted || draft.count == before) return;
    Navigator.of(context).pop(BackgroundChoice(draft.items.last));
  }

  @override
  Widget build(BuildContext context) {
    final PersonPhotosDraft draft = widget.draft;
    final List<DraftPhoto> items = draft.items;
    final ({int failed, int of})? failure = draft.failure;
    if (widget.chooseBackground) {
      return _backgroundChooser(draft, items, failure);
    }
    if (widget.chooseProfile) {
      return _profileChooser(draft, items, failure);
    }
    return Scaffold(
      backgroundColor: GrobingColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Element 1.
            PhotoViewerBar(title: 'Zdjęcia', subtitle: widget.personName),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                children: [
                  if (draft.profile case final DraftPhoto profile) ...[
                    _ProfileHeader(
                      photo: profile,
                      crop: draft.cropOf(profile),
                      onTap: () => _open(0),
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(count: items.length),
                    const SizedBox(height: 12),
                  ] else
                    const Padding(
                      // The empty state (rule 9): what is here, and one action.
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Ta osoba nie ma zdjęć.',
                        style: TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  _grid(items),
                  if (failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: PhotoErrorLine(_failureText(failure)),
                    ),
                  if (draft.hasChanges && !widget.readOnly)
                    const Padding(
                      // Element 6.
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Zmiany zdjęć zapiszą się razem z wpisem osoby.',
                        style: TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 13,
                        ),
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

  /// "Zdjęcie w tle" (v1.4): the hint, the grid with the current background framed in amber, the tile, and
  /// "Bez zdjęcia w tle" while there is one.
  Widget _backgroundChooser(
    PersonPhotosDraft draft,
    List<DraftPhoto> items,
    ({int failed, int of})? failure,
  ) => Scaffold(
    backgroundColor: GrobingColors.background,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhotoViewerBar(title: 'Zdjęcie w tle', subtitle: widget.personName),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    // Without photos there is nothing to tap yet — the empty state says the one action
                    // (rule 9).
                    items.isEmpty
                        ? 'Ta osoba nie ma jeszcze zdjęć. Dodaj zdjęcie, które ma być w tle.'
                        : 'Dotknij zdjęcia, które ma być w tle.',
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
                _grid(items),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: PhotoErrorLine(_failureText(failure)),
                  ),
                if (draft.background != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: GrobingColors.text,
                          iconColor: GrobingColors.text,
                        ),
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(const BackgroundChoice(null)),
                        icon: const GrobingIcon(Glyphs.hideImage),
                        label: const Text('Bez zdjęcia w tle'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// "Zdjęcie profilowe" (v1.5, P1–P6): the profile photo with "Obejrzyj zdjęcie", the line, the grid with
  /// the profile photo framed in amber, the tile "Dodaj zdjęcia".
  Widget _profileChooser(
    PersonPhotosDraft draft,
    List<DraftPhoto> items,
    ({int failed, int of})? failure,
  ) => Scaffold(
    backgroundColor: GrobingColors.background,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // P1.
          PhotoViewerBar(
            title: 'Zdjęcie profilowe',
            subtitle: widget.personName,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              children: [
                // P2.
                if (draft.profile case final DraftPhoto profile)
                  _ProfileHeader(
                    photo: profile,
                    crop: draft.cropOf(profile),
                    onTap: _look,
                    look: true,
                  ),
                const SizedBox(height: 8),
                // P3.
                const Text(
                  'Dotknij zdjęcia, które ma być profilowym.',
                  style: TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                // P4.
                _SectionHeader(count: items.length),
                const SizedBox(height: 12),
                // P5, P6.
                _grid(items),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: PhotoErrorLine(_failureText(failure)),
                  ),
                if (_saveFailed)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: PhotoErrorLine(
                      'Nie udało się zapisać zdjęć. Spróbuj jeszcze raz.',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// Elements 4–5: squares cut from the middle, then the cells of photos still being prepared, then the
  /// tile. Choosing the background, a tap chooses the photo and the current one has a frame in amber; so
  /// does the profile photo when choosing it (v1.5).
  Widget _grid(List<DraftPhoto> items) => LayoutBuilder(
    builder: (context, constraints) {
      const double gap = 8;
      final double cell = (constraints.maxWidth - 2 * gap) / 3;
      final int decode = coverDecodeWidth(context, cell);
      final PersonPhotosDraft draft = widget.draft;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (int i, DraftPhoto p) in items.indexed)
            PhotoCell(
              size: cell,
              selected: _chosen(i, p),
              child: Semantics(
                button: true,
                // A state of choice only where there is a choice (ui review: false is not "none").
                selected: widget.chooseBackground || widget.chooseProfile
                    ? _chosen(i, p)
                    : null,
                label: widget.chooseBackground
                    ? _chooseLabel(i, items.length, draft.isBackground(p))
                    : widget.chooseProfile
                    ? _profileLabel(i, items.length)
                    : _cellLabel(i, items.length, draft.isBackground(p)),
                // The label replaces the cell's own semantics, so the tap is given here too, or a
                // screen reader, Switch Access and Voice Access get a button they cannot press (ui
                // review, MAJOR; WCAG 2.2 SC 4.1.2).
                onTap: () => _tapCell(i, p),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _tapCell(i, p),
                  child: Image.file(
                    p.file,
                    fit: BoxFit.cover,
                    cacheWidth: decode,
                    errorBuilder: (_, _, _) => const UnreadableCell(),
                  ),
                ),
              ),
            ),
          for (int i = 0; i < widget.draft.preparing; i++)
            PhotoCell(
              size: cell,
              color: GrobingColors.surface,
              child: const Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          if (!widget.readOnly)
            _AddTile(
              size: cell,
              // "Zdjęcie profilowe" adds several and stays (P6, D7).
              label: widget.chooseProfile ? 'Dodaj zdjęcia' : 'Dodaj zdjęcie',
              onTap: widget.draft.preparing > 0 || _saving
                  ? null
                  : widget.chooseBackground
                  ? _addBackground
                  : widget.chooseProfile
                  ? _addPhotosNow
                  : () => addPersonPhotos(
                      context,
                      widget.draft,
                      personName: widget.shortName,
                      firstName: widget.firstName,
                    ),
            ),
        ],
      );
    },
  );

  /// The frame of the current choice: the background in "Zdjęcie w tle", the profile photo — the first —
  /// in "Zdjęcie profilowe".
  bool _chosen(int index, DraftPhoto photo) =>
      (widget.chooseBackground && widget.draft.isBackground(photo)) ||
      (widget.chooseProfile && index == 0);

  void _tapCell(int index, DraftPhoto photo) {
    if (widget.chooseBackground) {
      Navigator.of(context).pop(BackgroundChoice(photo));
    } else if (widget.chooseProfile) {
      // The photos still being prepared would be dropped with the draft when the screen pops after
      // "Gotowe" (ui review, MAJOR): the photos wait for them, as the tile does.
      if (!_saving && widget.draft.preparing == 0) _chooseProfile(photo);
    } else {
      _open(index);
    }
  }

  /// In "Zdjęcie profilowe": what a tap does, and which is the profile photo now (v1.5, P5).
  static String _profileLabel(int i, int count) => i == 0
      ? 'Zdjęcie 1 z $count, profilowe, zaznaczone — popraw kadr'
      : 'Zdjęcie ${i + 1} z $count — ustaw jako profilowe';

  /// In "Zdjęcie w tle": what a tap does, and which is the background now (v1.4).
  static String _chooseLabel(int i, int count, bool background) => background
      ? 'Zdjęcie ${i + 1} z $count, tło — wybierz'
      : 'Zdjęcie ${i + 1} z $count — ustaw jako tło';

  /// The background has no mark on the photo (rule 14); the screen reader hears it (v1.2).
  static String _cellLabel(int i, int count, bool background) {
    final List<String> state = [if (i == 0) 'profilowe', if (background) 'tło'];
    return 'Zdjęcie ${i + 1} z $count${state.isEmpty ? '' : ', ${state.join(', ')}'} — otwórz';
  }

  static String _failureText(({int failed, int of}) f) => f.of == 1
      ? 'Nie udało się wczytać zdjęcia. Spróbuj jeszcze raz.'
      : 'Nie udało się wczytać ${f.failed} '
            '${plural(f.failed, 'zdjęcia', 'zdjęć', 'zdjęć')} z ${f.of}. '
            'Spróbuj jeszcze raz.';
}

/// Element 2: the profile photo in a 96 dp circle, in its crop (v1.1, ISSUE-018) — as the form and the
/// grave view will show it — and "Profilowe" under it. In "Zdjęcie profilowe" ([look], v1.5, P2) the
/// caption is the button "Obejrzyj zdjęcie" instead, and the circle opens the photo to look at too.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.photo,
    this.crop,
    required this.onTap,
    this.look = false,
  });

  final DraftPhoto photo;
  final PhotoCrop? crop;
  final VoidCallback onTap;
  final bool look;

  @override
  Widget build(BuildContext context) {
    final Widget circle = ProfileCircle(
      file: photo.file,
      crop: crop,
      size: 96,
      unreadable: const UnreadableCell(),
    );
    if (look) {
      return Center(
        child: Column(
          children: [
            Semantics(
              // Its own node, the circle's bounds — without it the label merged into the whole header,
              // over "Obejrzyj zdjęcie" too (seen in the dump on the emulator).
              container: true,
              button: true,
              label: 'Zdjęcie profilowe — obejrzyj',
              onTap: onTap,
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: circle,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: GrobingColors.amber,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: onTap,
              child: const Text('Obejrzyj zdjęcie'),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Semantics(
        button: true,
        label: 'Zdjęcie profilowe — otwórz',
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Column(
            children: [
              circle,
              const SizedBox(height: 8),
              const Text(
                'Profilowe',
                style: TextStyle(color: GrobingColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Element 3: the section's icon in amber (a section header — rule 3), the count after a dot.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const GrobingIcon(
        Glyphs.photoLibrary,
        size: 20,
        color: GrobingColors.amber,
      ),
      const SizedBox(width: 8),
      Text(
        'Wszystkie zdjęcia · $count',
        style: const TextStyle(
          color: GrobingColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// Element 5: the place of a new photo as a button — an outline, the icon in amber, a caption — never a
/// grey placeholder (rules 11 and 14).
class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.size,
    required this.onTap,
    required this.label,
  });

  final double size;
  final VoidCallback? onTap;

  /// "Dodaj zdjęcie", or "Dodaj zdjęcia" in "Zdjęcie profilowe" (v1.5, P6).
  final String label;

  /// The width of a cell, and at least its height: with a large system font the caption makes the tile
  /// taller instead of being cut (style-b.md → Thresholds, SC 1.4.4; ui review).
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints.tightFor(width: size).copyWith(minHeight: size),
    child: Opacity(
      opacity: onTap == null ? 0.38 : 1,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: '$label osoby',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: GrobingColors.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GrobingIcon(
                    Glyphs.addPhotoAlternate,
                    size: 28,
                    color: GrobingColors.amber,
                    applyTextScaling: false,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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
