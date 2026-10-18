import 'package:flutter/material.dart';

import '../../data/graves.dart';
import '../../data/photos.dart' show PhotoCrop;
import '../polish.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'person_photos_draft.dart';
import 'photo_people_screen.dart';
import 'photo_viewer_screen.dart';
import 'profile_crop_screen.dart';

/// A person's photo on the whole screen (05_DESIGN/zdjecie.md v1.5, B in the person's mode): the photos
/// turn with a swipe or ‹ › (B3), "Na zdjęciu" names everyone on it (B5), and the actions make it the
/// profile through its crop, correct the profile's crop, make it the background or take it off, or
/// remove it from this person (B4'', C1'; kadr-profilowego.md). Every change goes to the [draft] and is
/// written with the person's "Zapisz" (zdjecia-osoby.md D1).
class PersonPhotoViewerScreen extends StatefulWidget {
  const PersonPhotoViewerScreen({
    super.key,
    required this.draft,
    required this.initialIndex,
    required this.personName,
    this.readOnly = false,
  });

  final PersonPhotosDraft draft;
  final int initialIndex;

  /// The person as the form has them now, for the bar and "Na zdjęciu".
  final String personName;

  /// From the person's view (zdjecie.md v1.5, "tryb oglądania"; osoba.md W2): no actions, no "Zmień".
  final bool readOnly;

  @override
  State<PersonPhotoViewerScreen> createState() =>
      _PersonPhotoViewerScreenState();
}

class _PersonPhotoViewerScreenState extends State<PersonPhotoViewerScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  ({List<PersonChoice> all, List<int> inGrave})? _choices;
  Set<int> _others = const {};

  /// The photo whose people [_others] are — until they are read, "Usuń z tej osoby" waits, so the window
  /// C1' never says the photo goes when someone else keeps it (ui review).
  DraftPhoto? _othersOf;

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    widget.draft.removeListener(_changed);
    _pages.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  DraftPhoto? get _photo {
    final List<DraftPhoto> items = widget.draft.items;
    return _index < items.length ? items[_index] : null;
  }

  Future<void> _load() async {
    _choices ??= await widget.draft.choices();
    await _loadOthers();
  }

  Future<void> _loadOthers() async {
    final DraftPhoto? photo = _photo;
    if (photo == null) return;
    final Set<int> others = await widget.draft.othersOf(photo);
    if (mounted && identical(photo, _photo)) {
      setState(() {
        _others = others;
        _othersOf = photo;
      });
    }
  }

  void _turnTo(int index) {
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// B5 "Zmień" → D; "Gotowe" gives everyone else ticked.
  Future<void> _choosePeople() async {
    final DraftPhoto? photo = _photo;
    final ({List<PersonChoice> all, List<int> inGrave})? choices = _choices;
    if (photo == null || choices == null) return;
    final Set<int>? ticked = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        builder: (_) => PhotoPeopleScreen(
          photo: photo.file,
          personName: widget.personName,
          personId: widget.draft.personId,
          choices: choices,
          ticked: _others,
        ),
      ),
    );
    if (ticked == null) return;
    await widget.draft.setOthers(photo, ticked);
    await _loadOthers();
  }

  /// The crop screen on [photo], from its link's crop; null when left with back (kadr-profilowego.md D9).
  Future<PhotoCrop?> _crop(DraftPhoto photo) =>
      Navigator.of(context).push<PhotoCrop>(
        MaterialPageRoute(
          builder: (_) => ProfileCropScreen(
            file: photo.file,
            personName: widget.personName,
            initial: widget.draft.cropOf(photo),
          ),
        ),
      );

  /// B4' "Ustaw jako profilowe": through the crop (kadr-profilowego.md D2) — on "Gotowe" the photo becomes
  /// the first, with that crop, and the view follows it there.
  Future<void> _makeProfile() async {
    final DraftPhoto? photo = _photo;
    if (photo == null) return;
    final PhotoCrop? crop = await _crop(photo);
    if (crop == null || !mounted) return;
    widget.draft.setProfile(photo, crop: crop);
    _index = 0;
    _pages.jumpToPage(0);
  }

  /// B4' "Popraw kadr" on the profile photo (zdjecie.md v1.4).
  Future<void> _correctCrop() async {
    final DraftPhoto? photo = _photo;
    if (photo == null) return;
    final PhotoCrop? crop = await _crop(photo);
    if (crop == null || !mounted) return;
    widget.draft.setCrop(photo, crop);
  }

  /// C1': what stays, and with whom; then back to the person's photos.
  Future<void> _remove() async {
    final DraftPhoto? photo = _photo;
    if (photo == null) return;
    final bool? removed = await showDialog<bool>(
      context: context,
      builder: (_) => RemovePersonPhotoDialog(
        staysWith: [for (final int id in _others) _nameOf(id)],
        isProfile: _index == 0,
        isLast: widget.draft.count == 1,
        isBackground: widget.draft.isBackground(photo),
      ),
    );
    if (removed != true || !mounted) return;
    widget.draft.remove(photo);
    Navigator.of(context).pop();
  }

  String _nameOf(int id) {
    for (final PersonChoice c in _choices?.all ?? const <PersonChoice>[]) {
      if (c.id == id) return personName(c.givenNames, c.surname);
    }
    return 'Osoba bez imienia';
  }

  /// B1: the photo's state is told by the bar, not by a mark on the photo (style-b.md rule 14).
  String get _subtitle {
    final DraftPhoto? photo = _photo;
    final bool background = photo != null && widget.draft.isBackground(photo);
    if (_index == 0) {
      return background ? 'Zdjęcie profilowe i tło' : 'Zdjęcie profilowe';
    }
    return background ? 'Zdjęcie w tle' : 'Zdjęcie osoby';
  }

  @override
  Widget build(BuildContext context) {
    final List<DraftPhoto> items = widget.draft.items;
    return Scaffold(
      backgroundColor: GrobingColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The profile and the background are told by the bar, not by colour (kadr-profilowego.md D8).
            PhotoViewerBar(title: widget.personName, subtitle: _subtitle),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: items.length,
                // Zoomed, a drag moves the photo, not to the next one (B3).
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                    _others = const {};
                    _othersOf = null;
                  });
                  _loadOthers();
                },
                itemBuilder: (_, i) => ZoomablePhoto(
                  key: ObjectKey(items[i].ref),
                  file: items[i].file,
                  semanticLabel: 'Zdjęcie osoby',
                  onZoomed: (z) => setState(() => _zoomed = z),
                ),
              ),
            ),
            _onPhoto(),
            if (items.length > 1) _turning(items.length),
            if (widget.readOnly) const SizedBox(height: 16) else _actions(),
          ],
        ),
      ),
    );
  }

  /// B5: "Na zdjęciu:" and everyone on it, this person first, then "Zmień" in the line.
  Widget _onPhoto() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Na zdjęciu: ',
                    style: TextStyle(color: GrobingColors.textMuted),
                  ),
                  TextSpan(
                    text: [
                      widget.personName,
                      for (final int id in _others) _nameOf(id),
                    ].join(', '),
                  ),
                ],
              ),
              style: const TextStyle(color: GrobingColors.text, fontSize: 14),
            ),
          ),
        ),
        if (widget.readOnly)
          const SizedBox(height: 48)
        else
          TextButton(
            onPressed: _choices == null ? null : _choosePeople,
            child: const Text('Zmień'),
          ),
      ],
    ),
  );

  /// B3: ‹ "2 z 5" › — the one-tap way to turn (SC 2.5.1).
  Widget _turning(int count) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Poprzednie zdjęcie',
        color: GrobingColors.text,
        onPressed: _index > 0 ? () => _turnTo(_index - 1) : null,
        icon: const GrobingIcon(Glyphs.chevronLeft, applyTextScaling: false),
      ),
      const SizedBox(width: 8),
      Text(
        '${_index + 1} z $count',
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Następne zdjęcie',
        color: GrobingColors.text,
        onPressed: _index < count - 1 ? () => _turnTo(_index + 1) : null,
        icon: const GrobingIcon(Glyphs.chevronRight, applyTextScaling: false),
      ),
    ],
  );

  /// B4'' (zdjecie.md v1.5): three equal columns, the icon over the label. The profile action in amber —
  /// "Ustaw jako profilowe", or "Popraw kadr" on the profile photo, the state being in the bar
  /// (kadr-profilowego.md D8); "Ustaw jako tło" with its icon in amber and the label in the text colour (a
  /// secondary action, style-b.md rule 1), or "Usuń z tła" on the background; "Usuń z tej osoby" in the text
  /// colour (rule 14). Fixed places, so turning the photos never moves "Usuń z tej osoby" under the
  /// finger; a long label wraps instead of being cut (SC 1.4.4).
  Widget _actions() {
    final DraftPhoto? photo = _photo;
    final bool background = photo != null && widget.draft.isBackground(photo);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _index == 0
                ? _StackedAction(
                    icon: Glyphs.crop,
                    label: 'Popraw kadr',
                    onPressed: _correctCrop,
                  )
                : _StackedAction(
                    icon: Glyphs.accountCircle,
                    label: 'Ustaw jako profilowe',
                    onPressed: _makeProfile,
                  ),
          ),
          Expanded(
            child: background
                ? _StackedAction(
                    icon: Glyphs.hideImage,
                    label: 'Usuń z tła',
                    color: GrobingColors.text,
                    iconColor: GrobingColors.text,
                    onPressed: widget.draft.clearBackground,
                  )
                : _StackedAction(
                    icon: Glyphs.wallpaper,
                    label: 'Ustaw jako tło',
                    color: GrobingColors.text,
                    onPressed: photo == null
                        ? null
                        : () => widget.draft.setBackground(photo),
                  ),
          ),
          Expanded(
            child: _StackedAction(
              icon: Glyphs.delete,
              label: 'Usuń z tej osoby',
              color: GrobingColors.text,
              iconColor: GrobingColors.text,
              onPressed: identical(_othersOf, _photo) ? _remove : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// One column of B4'': the icon over the label, the whole column one target of at least 48 dp.
class _StackedAction extends StatelessWidget {
  const _StackedAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.iconColor,
  });

  final Glyph icon;
  final String label;
  final VoidCallback? onPressed;

  /// The label's colour; null — the accent (the theme's text button).
  final Color? color;

  /// The icon's colour; null — the accent (rule 3: an action's icon).
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(48, 64),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    ),
    onPressed: onPressed,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GrobingIcon(
          icon,
          color: onPressed == null ? null : (iconColor ?? GrobingColors.amber),
        ),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// The window C1' (zdjecie.md v1.3): with others on the photo it says who keeps it; alone, it is the
/// window C. On the profile photo it adds what becomes of the profile. The removal itself waits for the
/// person's "Zapisz", so nothing here can fail. Pops true for "Usuń".
class RemovePersonPhotoDialog extends StatelessWidget {
  const RemovePersonPhotoDialog({
    super.key,
    required this.staysWith,
    required this.isProfile,
    required this.isLast,
    this.isBackground = false,
  });

  final List<String> staysWith;
  final bool isProfile;
  final bool isLast;

  /// The photo is the person's background (zdjecie.md v1.5, C1').
  final bool isBackground;

  @override
  Widget build(BuildContext context) {
    final String body = [
      if (staysWith.isEmpty)
        'Zdjęcia nie będzie w aplikacji ani w kolejnych kopiach. '
            'Jeśli jest w galerii telefonu, tam zostaje.'
      else
        'Zdjęcie zostaje u: ${staysWith.join(', ')}.',
      if (isLast)
        'Osoba nie będzie miała zdjęcia.'
      else if (isProfile)
        'Profilowym zostanie następne zdjęcie.',
      // The last photo going says already that nothing is left (ui review: two sentences, one fact).
      if (isBackground && !isLast) 'Osoba zostanie bez zdjęcia w tle.',
    ].join(' ');
    return AlertDialog(
      backgroundColor: GrobingColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        staysWith.isEmpty ? 'Usunąć zdjęcie?' : 'Usunąć zdjęcie z tej osoby?',
        style: const TextStyle(
          color: GrobingColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        body,
        style: const TextStyle(color: GrobingColors.text, fontSize: 16),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Usuń'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Zostaw'),
        ),
      ],
    );
  }
}
