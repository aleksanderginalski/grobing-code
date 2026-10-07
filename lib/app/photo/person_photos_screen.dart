import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/photos.dart' show PhotoCrop;
import '../polish.dart';
import '../theme.dart';
import 'person_photo_viewer_screen.dart';
import 'person_photos_draft.dart';
import 'photo_picker.dart';
import 'photo_source_sheet.dart';
import 'photo_viewer_screen.dart';
import 'profile_circle.dart';

/// Picks a person's photos — several from the gallery, one with the camera (05_DESIGN/zdjecie.md v1.3,
/// A) — and hands them to [draft] to prepare. Shared by the form's element 1a and the tile here.
Future<void> addPersonPhotos(
  BuildContext context,
  PersonPhotosDraft draft,
) async {
  final PhotoSource? source = await showPhotoSourceSheet(
    context,
    title: 'Zdjęcia osoby',
  );
  if (source == null) return;
  final List<File> picked = switch (source) {
    PhotoSource.gallery => await draft.photos.pickMany(),
    PhotoSource.camera => [?await draft.photos.pick(PhotoSource.camera)],
  };
  await draft.addPicked(picked);
}

/// A person's photos (05_DESIGN/zdjecia-osoby.md): the profile photo in a circle, every photo in a grid
/// of squares, "Dodaj zdjęcie" as the last cell. Nothing here is written: back returns to the form, whose
/// "Zapisz" writes the changes (D1).
class PersonPhotosScreen extends StatefulWidget {
  const PersonPhotosScreen({
    super.key,
    required this.draft,
    required this.personName,
    required this.shortName,
  });

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

  Future<void> _open(int index) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonPhotoViewerScreen(
        draft: widget.draft,
        initialIndex: index,
        personName: widget.shortName,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final PersonPhotosDraft draft = widget.draft;
    final List<DraftPhoto> items = draft.items;
    final ({int failed, int of})? failure = draft.failure;
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
                  if (draft.hasChanges)
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

  /// Elements 4–5: squares cut from the middle, then the cells of photos still being prepared, then the
  /// tile.
  Widget _grid(List<DraftPhoto> items) => LayoutBuilder(
    builder: (context, constraints) {
      const double gap = 8;
      final double cell = (constraints.maxWidth - 2 * gap) / 3;
      final int decode = coverDecodeWidth(context, cell);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (int i, DraftPhoto p) in items.indexed)
            _Cell(
              size: cell,
              child: Semantics(
                button: true,
                label: i == 0
                    ? 'Zdjęcie 1 z ${items.length}, profilowe — otwórz'
                    : 'Zdjęcie ${i + 1} z ${items.length} — otwórz',
                // The label replaces the cell's own semantics, so the tap is given here too, or a
                // screen reader, Switch Access and Voice Access get a button they cannot press (ui
                // review, MAJOR; WCAG 2.2 SC 4.1.2).
                onTap: () => _open(i),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _open(i),
                  child: Image.file(
                    p.file,
                    fit: BoxFit.cover,
                    cacheWidth: decode,
                    errorBuilder: (_, _, _) => const _Unreadable(),
                  ),
                ),
              ),
            ),
          for (int i = 0; i < widget.draft.preparing; i++)
            _Cell(
              size: cell,
              color: GrobingColors.surface,
              child: const Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          _AddTile(
            size: cell,
            onTap: widget.draft.preparing > 0
                ? null
                : () => addPersonPhotos(context, widget.draft),
          ),
        ],
      );
    },
  );

  static String _failureText(({int failed, int of}) f) => f.of == 1
      ? 'Nie udało się wczytać zdjęcia. Spróbuj jeszcze raz.'
      : 'Nie udało się wczytać ${f.failed} '
            '${plural(f.failed, 'zdjęcia', 'zdjęć', 'zdjęć')} z ${f.of}. '
            'Spróbuj jeszcze raz.';
}

/// Element 2: the profile photo in a 96 dp circle, in its crop (v1.1, ISSUE-018) — as the form and the
/// grave view will show it — and "Profilowe" under it.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.photo, this.crop, required this.onTap});

  final DraftPhoto photo;
  final PhotoCrop? crop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
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
            ProfileCircle(
              file: photo.file,
              crop: crop,
              size: 96,
              unreadable: const _Unreadable(),
            ),
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

/// Element 3: the section's icon in amber (a section header — rule 3), the count after a dot.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(
        Icons.photo_library_outlined,
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

class _Cell extends StatelessWidget {
  const _Cell({required this.size, required this.child, this.color});

  final double size;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Material(
      color: color ?? Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/// Element 5: the place of a new photo as a button — an outline, the icon in amber, a caption — never a
/// grey placeholder (rules 11 and 14).
class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onTap});

  final double size;
  final VoidCallback? onTap;

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
        label: 'Dodaj zdjęcie osoby',
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
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: 28,
                    color: GrobingColors.amber,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Dodaj zdjęcie',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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

/// "Brak pliku": the cell without text, the icon in the muted colour.
class _Unreadable extends StatelessWidget {
  const _Unreadable();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: GrobingColors.surface,
    child: Center(
      child: Icon(Icons.broken_image_outlined, color: GrobingColors.textMuted),
    ),
  );
}
