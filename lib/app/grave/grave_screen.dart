import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/address_text.dart';
import '../../data/database.dart';
import '../../data/graves.dart';
import '../../data/photos.dart' show PhotoCrop, gravePhotoPath;
import '../../data/sectors.dart';
import '../dates.dart';
import '../person/person_screen.dart';
import '../photo/add_photo_field.dart';
import '../photo/photo_picker.dart';
import '../photo/photo_source_sheet.dart';
import '../photo/photo_viewer_screen.dart';
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'cemetery_plan_map.dart' show MapLayer;
import 'person_form_screen.dart';
import 'pin_screen.dart';

/// One grave and everyone buried in it (ISSUE-012; 05_DESIGN/grob.md v3): R4 with the gravestone photo
/// above the title (ISSUE-016) and each person's profile photo in their card (v4, ISSUE-017). The grave's
/// name is set from the pencil next to the title; a person's card opens their view (v5, ISSUE-024).
class GraveScreen extends StatefulWidget {
  const GraveScreen({
    super.key,
    required this.database,
    required this.graveId,
    this.photos,
    this.tab = AppTab.map,
    this.layer = MapLayer.plan,
  });

  final GrobingDatabase database;
  final int graveId;

  /// The cemetery map's layer: "Postaw pinezkę" opens mode D on it (cmentarz.md D36).
  final MapLayer layer;

  /// The tab of the stack — the map, or Osoby through a person's view (style-b.md rule 12).
  final AppTab tab;

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

  /// A person's card: their view, where ✎ corrects them (style-b.md rule 15; grob.md v5).
  Future<void> _openPerson(BuriedPerson person) => openPersonView(
    context,
    widget.database,
    person.id,
    photos: widget.photos,
    tab: widget.tab,
  );

  Future<void> _openForm(PersonFormMode mode) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonFormScreen(
        database: widget.database,
        mode: mode,
        photos: widget.photos,
        tab: widget.tab,
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

  /// ✎ and "Wpisz adres" (elements 3, 4): the window "Popraw grób" with the cemetery's sectors as chips.
  Future<void> _editGrave(GraveDetail g, {bool address = false}) async {
    final List<Sector> sectors = await watchSectors(
      widget.database,
      g.cemeteryId,
    ).first;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => GraveDialog(
        grave: g,
        sectors: sectors,
        focusAddress: address,
        save: ({name, sector, row, plot}) => setGraveDetails(
          widget.database,
          g.id,
          name: name,
          sector: sector,
          row: row,
          plot: plot,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<GraveDetail?>(
    stream: _grave,
    builder: (context, snapshot) {
      final GraveDetail? grave = snapshot.data;
      final bool failed =
          snapshot.hasError || (snapshot.hasData && grave == null);
      return Scaffold(
        // From the map's cemetery, or from a person's view in whatever tab it was opened (ISSUE-024).
        bottomNavigationBar: GrobingTabBar(
          active: widget.tab,
          database: widget.database,
          photos: widget.photos,
        ),
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
      // the action stands where its result will (grob.md v3.2, D12, the author's decision at stop #2), one
      // button, never a placeholder picture (style-b.md rules 11, 14).
      if (widget.photos case final Photos photos?) ...[
        if (grave.photoPath case final String path?)
          _GravePhoto(
            file: photos.fileOf(path),
            onTap: () => _openPhoto(grave, photos, path),
          )
        else if (_savingPhoto)
          const _SavingPhoto()
        else
          // 120 dp, not the photo's 4:3: about 50 graves start without one, and a photo-sized field would
          // push the people down on every one of them.
          AddPhotoField(
            label: 'Dodaj zdjęcie nagrobka',
            onTap: () => _addPhoto(grave),
          ),
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
          onTap: () => _openPerson(p),
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
        onPressed: () => _editGrave(grave),
      ),
    ],
  );

  /// Element 4: the address in full words, or what is missing and "Wpisz adres" — the address is copied at
  /// home from the manager's search, not at the visit (grob.md v6, D13).
  Widget _address(GraveDetail grave) {
    const TextStyle muted = TextStyle(
      color: GrobingColors.textMuted,
      fontSize: 14,
    );
    final String? address = graveAddress(grave.sector, grave.row, grave.plot);
    if (address != null) {
      return Column(
        children: [
          Text(
            addressLine(address, hasPin: grave.hasPin),
            textAlign: TextAlign.center,
            style: muted,
          ),
          _pin(grave),
        ],
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
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: GrobingColors.amber,
            minimumSize: const Size(48, 48),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => _editGrave(grave, address: true),
          child: const Text('Wpisz adres'),
        ),
        _pin(grave),
      ],
    );
  }

  /// Element 4, the pin (grob.md v7, D14): with one, where it came from and when — "Pinezka: GPS ±4 m ·
  /// 12.10.2026"; without, "Postaw pinezkę" → mode D of the cemetery. Correcting a pin is on the map, next
  /// to its candle (cmentarz.md element 11).
  Widget _pin(GraveDetail grave) {
    final GravePin? pin = grave.pin;
    if (pin != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Pinezka: ${pinLine(pin.source, pin.accuracyM, pin.recordedAt)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: OutlinedButton.icon(
          style: secondaryButtonStyle.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          ),
          onPressed: () => _placePin(grave),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Postaw pinezkę'),
        ),
      ),
    );
  }

  /// "Postaw pinezkę" → mode D; a saved pin closes the grave too, and the cemetery shows its new candle
  /// (cmentarz.md D36).
  Future<void> _placePin(GraveDetail grave) async {
    final PinSaved? saved = await Navigator.of(context).push<PinSaved>(
      MaterialPageRoute<PinSaved>(
        builder: (_) => PinScreen(
          database: widget.database,
          cemeteryId: grave.cemeteryId,
          graveId: grave.id,
          layer: widget.layer,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop(saved);
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
                  _ProfileThumbnail(file: file, crop: person.profileCrop),
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

/// Element 5 (v4.1): the profile photo in a 40 dp circle, in its link's crop or cut from the middle
/// (ISSUE-018); no label of its own — the card's text describes the card (style-b.md rule 14). A file that
/// cannot be read shows the broken-image icon on the background.
class _ProfileThumbnail extends StatelessWidget {
  const _ProfileThumbnail({required this.file, this.crop});

  final File file;
  final PhotoCrop? crop;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ProfileCircle(
      file: file,
      crop: crop,
      size: 40,
      unreadable: const ColoredBox(
        color: GrobingColors.background,
        child: Icon(
          Icons.broken_image_outlined,
          size: 20,
          color: GrobingColors.textMuted,
        ),
      ),
    ),
  );
}

/// The window "Popraw grób" (05_DESIGN/grob.md v6, elements 3a, 3b): the grave's name and the manager's
/// address — sector, row and plot — all optional, copied from the manager's search at home (EPIC-002). The
/// sector is one of the cemetery's sectors: its chips fill the field, and a name no sector has becomes a new
/// one without a zone (ADR-016). It saves itself, so a failed save keeps it open with the message.
class GraveDialog extends StatefulWidget {
  const GraveDialog({
    super.key,
    required this.grave,
    required this.sectors,
    required this.save,
    this.focusAddress = false,
  });

  final GraveDetail grave;

  /// The cemetery's sectors, for the chips.
  final List<Sector> sectors;
  final Future<void> Function({
    String? name,
    String? sector,
    String? row,
    String? plot,
  })
  save;

  /// "Wpisz adres" (element 4): the focus in "Kwatera" instead of the name.
  final bool focusAddress;

  @override
  State<GraveDialog> createState() => _GraveDialogState();
}

class _GraveDialogState extends State<GraveDialog> {
  late final TextEditingController _name = _field(widget.grave.name);
  late final TextEditingController _sector = _field(widget.grave.sector);
  late final TextEditingController _row = _field(widget.grave.row);
  late final TextEditingController _plot = _field(widget.grave.plot);
  late final List<Sector> _chips = [...widget.sectors]
    ..sort((a, b) => sectorOrder(a.name, b.name));
  bool _saving = false;
  bool _failed = false;

  static TextEditingController _field(String? value) =>
      TextEditingController(text: value ?? '')
        ..selection = TextSelection.collapsed(offset: (value ?? '').length);

  @override
  void dispose() {
    _name.dispose();
    _sector.dispose();
    _row.dispose();
    _plot.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.save(
        name: _name.text,
        sector: _sector.text,
        row: _row.text,
        plot: _plot.text,
      );
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

  /// The cemetery's sector the field names — "b" is "B" — or null.
  Sector? get _matched {
    final String? typed = addressPart(_sector.text, sectorWord);
    if (typed == null) return null;
    return _chips
        .where((s) => sectorKey(s.name) == sectorKey(typed))
        .firstOrNull;
  }

  void _pick(Sector s) {
    _sector
      ..text = s.name
      ..selection = TextSelection.collapsed(offset: s.name.length);
    setState(() {});
  }

  static const TextStyle _note = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context) {
    final Sector? matched = _matched;
    final String? typed = addressPart(_sector.text, sectorWord);
    final Widget row = TextField(
      controller: _row,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: rowWord),
    );
    final Widget plot = TextField(
      controller: _plot,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: const InputDecoration(labelText: plotWord),
    );
    // Side by side, but one under the other at a large system text (element 3b).
    final bool stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(inputDecorationTheme: GrobingTheme.fields),
      child: AlertDialog(
        backgroundColor: GrobingColors.surface,
        surfaceTintColor: Colors.transparent,
        scrollable: true,
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              autofocus: !widget.focusAddress,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nazwa grobu',
                // The text of R4 (05_DESIGN/brand/references.md).
                hintText: 'np. Grób rodzinny Nowaków',
                helperText: 'Zostaw puste, jeśli grób nie ma nazwy.',
                helperStyle: _note,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Adres zarządcy', style: _note),
            const SizedBox(height: 12),
            TextField(
              controller: _sector,
              autofocus: widget.focusAddress,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: sectorWord),
            ),
            if (_chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final Sector s in _chips)
                    _SectorChip(
                      sector: s,
                      selected: s.id == matched?.id,
                      onTap: () => _pick(s),
                    ),
                ],
              ),
            ],
            if (typed != null && matched == null) ...[
              const SizedBox(height: 4),
              Text(
                'Nowa kwatera „$typed” — powstanie bez strefy; zaznaczysz ją '
                'w „Kwaterach”.',
                style: _note,
              ),
            ],
            const SizedBox(height: 12),
            if (stacked) ...[
              row,
              const SizedBox(height: 12),
              plot,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: row),
                  const SizedBox(width: 12),
                  Expanded(child: plot),
                ],
              ),
            const SizedBox(height: 8),
            const Text(
              'Z wyszukiwarki zarządcy. Zostaw puste, czego nie wiesz.',
              style: _note,
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              const PhotoErrorLine(
                'Nie udało się zapisać. Spróbuj jeszcze raz.',
              ),
            ],
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
}

/// A sector of the cemetery under "Kwatera" (element 3b; style-b.md rule 11 — a chip with an outline, a
/// 48 dp target): the one the field names has a check, its outline and text in amber, and "zaznaczone" for a
/// screen reader (SC 1.4.1).
class _SectorChip extends StatelessWidget {
  const _SectorChip({
    required this.sector,
    required this.selected,
    required this.onTap,
  });

  final Sector sector;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text('$sectorWord ${sector.name}'),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: true,
    checkmarkColor: GrobingColors.amber,
    backgroundColor: GrobingColors.surface,
    selectedColor: GrobingColors.surface,
    side: BorderSide(
      color: selected ? GrobingColors.amber : GrobingColors.outline,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    labelStyle: TextStyle(
      color: selected ? GrobingColors.amber : GrobingColors.text,
      fontSize: 14,
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
