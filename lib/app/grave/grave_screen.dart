import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../../data/photos.dart' show gravePhotoPath;
import '../dates.dart';
import '../photo/photo_picker.dart';
import '../photo/photo_source_sheet.dart';
import '../photo/photo_viewer_screen.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'person_form_screen.dart';

/// One grave and everyone buried in it (ISSUE-012; 05_DESIGN/grob.md v3): R4 with the gravestone photo
/// above the title (ISSUE-016) and each person's profile photo in their card (v4, ISSUE-017). The grave's
/// name is set from the pencil next to the title.
class GraveScreen extends StatefulWidget {
  const GraveScreen({
    super.key,
    required this.database,
    required this.graveId,
    this.photos,
  });

  final GrobingDatabase database;
  final int graveId;

  /// Null only in tests of other features: then the screen has no photo and no "Dodaj zdjęcie".
  final Photos? photos;

  @override
  State<GraveScreen> createState() => _GraveScreenState();
}

class _GraveScreenState extends State<GraveScreen> {
  late Stream<GraveDetail?> _grave = _watch();

  /// "Zapisywanie zdjęcia" and "nieudany zapis zdjęcia" (grob.md → States).
  bool _savingPhoto = false;
  bool _photoFailed = false;

  Stream<GraveDetail?> _watch() => watchGrave(widget.database, widget.graveId);

  /// The title the person form shows below its own: the grave's name, or its cemetery's.
  String _graveTitle(GraveDetail g) => g.name ?? g.cemeteryName;

  Future<void> _addPerson(GraveDetail g) => _openForm(
    NextPerson(
      graveId: g.id,
      graveTitle: _graveTitle(g),
      peopleCount: g.people.length,
      suggestedSurname: g.people.isEmpty ? null : g.people.last.surname,
    ),
  );

  Future<void> _correct(GraveDetail g, BuriedPerson person) => _openForm(
    Correction(
      person: person,
      graveTitle: _graveTitle(g),
      peopleCount: g.people.length,
      graveId: g.id,
    ),
  );

  Future<void> _openForm(PersonFormMode mode) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonFormScreen(
        database: widget.database,
        mode: mode,
        photos: widget.photos,
      ),
    ),
  );

  /// The source sheet, then the system picker or camera; null when the user cancels either.
  Future<File?> _pickPhoto(Photos photos) async {
    final PhotoSource? source = await showPhotoSourceSheet(context);
    if (source == null) return null;
    return photos.pick(source);
  }

  /// "Dodaj zdjęcie" (element 6): the photo is kept at once, without a form; the view shows it.
  Future<void> _addPhoto(GraveDetail g) async {
    final Photos? photos = widget.photos;
    if (photos == null || _savingPhoto) return;
    setState(() => _photoFailed = false);
    try {
      final File? picked = await _pickPhoto(photos);
      if (picked == null || !mounted) return;
      setState(() => _savingPhoto = true);
      await photos.setGravePhoto(widget.database, g.id, picked);
    } on Object {
      if (mounted) setState(() => _photoFailed = true);
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  /// The photo on the whole screen (zdjecie.md, B), where it can be changed or deleted (D1').
  Future<void> _openPhoto(GraveDetail g, Photos photos, String path) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PhotoViewerScreen(
            title: g.name ?? 'Grób',
            subtitle: 'Zdjęcie nagrobka',
            file: photos.fileOf(path),
            pickReplacement: () => _pickPhoto(photos),
            replace: (picked) async {
              await photos.setGravePhoto(widget.database, g.id, picked);
              return photos.fileOf(
                (await gravePhotoPath(widget.database, g.id))!,
              );
            },
            onDelete: () => photos.deleteGravePhoto(widget.database, g.id),
          ),
        ),
      );

  Future<void> _editName(GraveDetail g) => showDialog<void>(
    context: context,
    builder: (_) => GraveNameDialog(
      name: g.name,
      save: (name) => setGraveName(widget.database, g.id, name),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<GraveDetail?>(
    stream: _grave,
    builder: (context, snapshot) {
      final GraveDetail? grave = snapshot.data;
      final bool failed =
          snapshot.hasError || (snapshot.hasData && grave == null);
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(grave),
              Expanded(
                child: failed
                    ? _readError()
                    : grave == null
                    ? const Center(child: CircularProgressIndicator())
                    : _content(grave),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Element 1: back, and the cemetery · locality as the bar's subtitle.
  Widget _bar(GraveDetail? grave) => Row(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: BackButton(color: GrobingColors.text),
      ),
      Expanded(
        child: Text(
          grave == null
              ? ''
              : [grave.cemeteryName, ?grave.cemeteryLocality].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ),
      const SizedBox(width: 16),
    ],
  );

  Widget _content(GraveDetail grave) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      // Element 1a: the gravestone photo; without one, the field "Dodaj zdjęcie nagrobka" in its place —
      // the action stands where its result will (grob.md v3.2, D12, the author's decision at stop #2).
      if (widget.photos case final Photos photos?) ...[
        if (grave.photoPath case final String path?)
          _GravePhoto(
            file: photos.fileOf(path),
            onTap: () => _openPhoto(grave, photos, path),
          )
        else if (_savingPhoto)
          const _SavingPhoto()
        else
          _AddPhotoField(onTap: () => _addPhoto(grave)),
        if (_photoFailed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: PhotoErrorLine(
              'Nie udało się zapisać zdjęcia. Spróbuj jeszcze raz.',
            ),
          ),
        const SizedBox(height: 10),
      ],
      _title(grave),
      const SizedBox(height: 6),
      _address(grave),
      // 24 dp between the heading and the list (style-b.md rule 5; ui review).
      const SizedBox(height: 24),
      if (grave.people.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'W tym grobie nie ma jeszcze wpisanych osób.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
          ),
        ),
      for (final BuriedPerson p in grave.people)
        _PersonCard(
          person: p,
          photo: switch ((widget.photos, p.profilePhotoPath)) {
            (final Photos photos, final String path) => photos.fileOf(path),
            _ => null,
          },
          onTap: () => _correct(grave, p),
        ),
      const SizedBox(height: 8),
      // Element 6: "Dodaj osobę" only — adding the photo is the field 1a (D10, D12).
      Row(
        children: [
          OutlinedButton.icon(
            style: _rowButton,
            onPressed: () => _addPerson(grave),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Dodaj osobę'),
          ),
        ],
      ),
    ],
  );

  static final ButtonStyle _rowButton = secondaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  );

  /// Elements 2 and 3: the name — "Grób" without one — centred, and the pencil to set it. The same
  /// room on the left keeps the title in the middle.
  Widget _title(GraveDetail grave) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(width: 48),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            grave.name ?? 'Grób',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GrobingColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined),
        color: GrobingColors.amber,
        tooltip: 'Popraw grób',
        onPressed: () => _editName(grave),
      ),
    ],
  );

  /// Element 4: the address in full words, or what is missing and when it gets filled in.
  Widget _address(GraveDetail grave) {
    const TextStyle muted = TextStyle(
      color: GrobingColors.textMuted,
      fontSize: 14,
    );
    final String? address = graveAddress(grave.sector, grave.row, grave.plot);
    if (address != null) {
      return Text(
        addressLine(address, hasPin: grave.hasPin),
        textAlign: TextAlign.center,
        style: muted,
      );
    }
    return Column(
      children: [
        Text.rich(
          TextSpan(
            children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: GrobingColors.textMuted,
                  ),
                ),
              ),
              TextSpan(text: addressLine(null, hasPin: grave.hasPin)),
            ],
          ),
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 2),
        const Text(
          'Uzupełnisz przy wizycie.',
          textAlign: TextAlign.center,
          style: muted,
        ),
      ],
    );
  }

  Widget _readError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Nie udało się odczytać grobu.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          style: secondaryButtonStyle,
          onPressed: () => setState(() => _grave = _watch()),
          child: const Text('Spróbuj ponownie'),
        ),
      ],
    ),
  );
}

/// Element 1a: the gravestone photo, the width of the content and the photo's own proportions, but
/// never taller than wide — a portrait photo is cut to a square from the middle (D8). All of it is one tap
/// away, in the viewer. Decoded at the size it is shown, not the stored 2048 px.
class _GravePhoto extends StatelessWidget {
  const _GravePhoto({required this.file, required this.onTap});

  final File file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final double width = constraints.maxWidth;
      return Semantics(
        button: true,
        label: 'Zdjęcie nagrobka — otwórz',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: GrobingColors.surface,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: width),
                child: Image.file(
                  file,
                  width: width,
                  fit: BoxFit.cover,
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  excludeFromSemantics: true,
                  // Until the file is read: the field at 4:3, so the title and the people do not jump down
                  // by the photo's height when it appears (ui review; grob.md → States).
                  frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                      frame == null && !wasSynchronouslyLoaded
                      ? const AspectRatio(aspectRatio: 4 / 3)
                      : child,
                  errorBuilder: (_, _, _) => const _UnreadablePhoto(),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Element 1a without a photo (grob.md v3.2, D12): the place of the photo as one button — an outline, the
/// icon in amber, the caption — never a placeholder picture (style-b.md rules 11, 14). 120 dp, not the
/// photo's 4:3: about 50 graves start without one, and a photo-sized field would push the people down on
/// every one of them.
class _AddPhotoField extends StatelessWidget {
  const _AddPhotoField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Dodaj zdjęcie nagrobka',
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GrobingColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_a_photo_outlined,
                  size: 32,
                  color: GrobingColors.amber,
                ),
                SizedBox(height: 8),
                Text(
                  'Dodaj zdjęcie nagrobka',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: GrobingColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// "Brak pliku zdjęcia" (grob.md → States): the row is there, the file cannot be read. A tap still
/// opens the viewer, where the photo can be changed or deleted.
class _UnreadablePhoto extends StatelessWidget {
  const _UnreadablePhoto();

  @override
  Widget build(BuildContext context) => const AspectRatio(
    aspectRatio: 4 / 3,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: GrobingColors.textMuted),
          SizedBox(height: 8),
          Text(
            'Nie udało się otworzyć zdjęcia.',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    ),
  );
}

/// "Zapisywanie zdjęcia" (grob.md → States): a 4:3 field on the surface where the photo will be.
class _SavingPhoto extends StatelessWidget {
  const _SavingPhoto();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: const ColoredBox(
      color: GrobingColors.surface,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                'Zapisuję zdjęcie…',
                style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Element 5: one person — "Imiona Nazwisko z d. Rodowe" and the dates as entered — leading to the
/// correction of the entry (ISSUE-012 D1).
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, this.photo, required this.onTap});

  final BuriedPerson person;

  /// The person's profile photo (v4, ISSUE-017); without one, no thumbnail and no indent (D11).
  final File? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
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
                if (photo case final File file) ...[
                  _ProfileThumbnail(file: file),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        personName(
                          person.givenNames,
                          person.surname,
                          birthSurname: person.birthSurname,
                        ),
                        style: const TextStyle(
                          color: GrobingColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lifeLine(
                          birth: person.birth.date,
                          death: person.death.date,
                          burial: person.burial.date,
                        ),
                        style: const TextStyle(
                          color: GrobingColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: GrobingColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Element 5 (v4): the profile photo in a 40 dp circle, cut from the middle, decoded at its size; no
/// label of its own — the card's text describes the card (style-b.md rule 14). A file that cannot be read
/// shows the broken-image icon on the background.
class _ProfileThumbnail extends StatelessWidget {
  const _ProfileThumbnail({required this.file});

  final File file;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipOval(
      child: SizedBox.square(
        dimension: _size,
        child: Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: coverDecodeWidth(context, _size),
          errorBuilder: (_, _, _) => const ColoredBox(
            color: GrobingColors.background,
            child: Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: GrobingColors.textMuted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The window "Popraw grób" (05_DESIGN/grob.md, element 3a): the grave's name, optional. It saves
/// itself, so a failed save keeps it open with the message.
class GraveNameDialog extends StatefulWidget {
  const GraveNameDialog({super.key, this.name, required this.save});

  final String? name;
  final Future<void> Function(String? name) save;

  @override
  State<GraveNameDialog> createState() => _GraveNameDialogState();
}

class _GraveNameDialogState extends State<GraveNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name ?? '',
  )..selection = TextSelection.collapsed(offset: (widget.name ?? '').length);
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.save(_name.text.trim().isEmpty ? null : _name.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(inputDecorationTheme: GrobingTheme.fields),
    child: AlertDialog(
      backgroundColor: GrobingColors.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Popraw grób',
        style: TextStyle(
          color: GrobingColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Nazwa grobu',
              // The text of R4 (05_DESIGN/brand/references.md).
              hintText: 'np. Grób rodzinny Nowaków',
              helperText: _failed
                  ? null
                  : 'Zostaw puste, jeśli grób nie ma nazwy.',
              helperStyle: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 13,
              ),
              helperMaxLines: 2,
              // Never colour alone (SC 1.4.1): the message comes with an icon.
              error: _failed
                  ? const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: GrobingColors.error,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Nie udało się zapisać. Spróbuj jeszcze raz.',
                            style: TextStyle(color: GrobingColors.error),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Zapisz'),
        ),
      ],
    ),
  );
}
