import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../photo/person_photos_draft.dart';
import '../photo/person_photos_screen.dart';
import '../photo/photo_viewer_screen.dart'
    show PhotoErrorLine, coverDecodeWidth;
import '../photo/photos.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'grave_screen.dart';

/// Where the form was opened from, and so what it writes (05_DESIGN/wpis-osoby.md → Navigation).
sealed class PersonFormMode {
  const PersonFormMode();
}

/// "Dodaj grób": the first person of a new grave — the grave is written with them.
class NewGrave extends PersonFormMode {
  const NewGrave({required this.cemeteryId, required this.cemeteryName});

  final int cemeteryId;
  final String cemeteryName;
}

/// "Dodaj osobę": one more person in a grave.
class NextPerson extends PersonFormMode {
  const NextPerson({
    required this.graveId,
    required this.graveTitle,
    required this.peopleCount,
    this.suggestedSurname,
  });

  final int graveId;

  /// The grave's name, or its cemetery's when it has none.
  final String graveTitle;
  final int peopleCount;

  /// The surname of the last person entered in this grave: in a family grave it usually repeats.
  final String? suggestedSurname;
}

/// A person tapped in the grave view: the entry corrected in place (ISSUE-012 D1).
class Correction extends PersonFormMode {
  const Correction({
    required this.person,
    required this.graveTitle,
    required this.peopleCount,
    this.graveId,
  });

  final BuriedPerson person;
  final String graveTitle;
  final int peopleCount;

  /// The grave the person was opened from: its people come first in "Kto jest na zdjęciu?".
  final int? graveId;
}

/// One person buried in a grave, as the notes give them (ISSUE-012; 05_DESIGN/wpis-osoby.md v2). The
/// screen of the transcription used about 100 times (G6), so every field, key and question counts.
class PersonFormScreen extends StatefulWidget {
  const PersonFormScreen({
    super.key,
    required this.database,
    required this.mode,
    this.photos,
  });

  final GrobingDatabase database;
  final PersonFormMode mode;

  /// The person's photos (element 1a, ISSUE-017), and passed on to the grave view that replaces the form
  /// after a new grave (ISSUE-016). Null only in tests of other features: then the form has no photos.
  final Photos? photos;

  @override
  State<PersonFormScreen> createState() => _PersonFormScreenState();
}

const String _badDate =
    'Nie rozumiem tej daty — wpisz rok, mm.rrrr albo dd.mm.rrrr.';

class _PersonFormScreenState extends State<PersonFormScreen> {
  late final PersonEntry _initial = switch (widget.mode) {
    NewGrave() => const PersonEntry(),
    NextPerson(:final String? suggestedSurname) => PersonEntry(
      surname: suggestedSurname,
    ),
    Correction(:final BuriedPerson person) => person.entry,
  };

  late final TextEditingController _given = TextEditingController(
    text: _initial.givenNames,
  );
  late final TextEditingController _surname = TextEditingController(
    text: _initial.surname,
  );
  late final TextEditingController _birthSurname = TextEditingController(
    text: _initial.birthSurname,
  );
  late final TextEditingController _bio = TextEditingController(
    text: _initial.bio,
  );
  late final TextEditingController _bioSource = TextEditingController(
    text: _initial.bioSource ?? defaultBioSource,
  );

  final FocusNode _givenNode = FocusNode();
  final FocusNode _surnameNode = FocusNode();
  final FocusNode _bioSourceNode = FocusNode();

  late final List<_DateInput> _dates = [
    _DateInput(
      'Urodzenie',
      _initial.birth,
      readOnly: !_correctable((p) => p.birth),
    ),
    _DateInput('Zgon', _initial.death, readOnly: !_correctable((p) => p.death)),
    // No burial date: the author found it superfluous, and every field counts a hundred times (the author's
    // decision at stop #2, ISSUE-012 D7). The data model keeps it (GEDCOM BURI next to DEAT).
  ];

  /// The suggested surname is selected, so typing replaces it, until it is touched.
  bool _surnameTouched = false;
  bool _editingSource = false;
  bool _nameMissing = false;
  bool _sourceMissing = false;
  bool _saving = false;
  bool _saveFailed = false;
  bool _done = false;

  late final String _initialSnapshot = _snapshot();

  /// The person's photos while the form is open; written with "Zapisz" (wpis-osoby.md D-zdjęcie-2).
  late final PersonPhotosDraft? _photos = switch (widget.photos) {
    final Photos photos => PersonPhotosDraft(
      database: widget.database,
      photos: photos,
      personId: switch (widget.mode) {
        Correction(:final BuriedPerson person) => person.id,
        _ => null,
      },
      graveId: switch (widget.mode) {
        NewGrave() => null,
        NextPerson(:final int graveId) => graveId,
        Correction(:final int? graveId) => graveId,
      },
    ),
    null => null,
  };

  bool _correctable(DatedFact Function(BuriedPerson) fact) =>
      switch (widget.mode) {
        Correction(:final BuriedPerson person) => fact(person).correctable,
        _ => true,
      };

  @override
  void initState() {
    super.initState();
    _initialSnapshot; // taken before anything is typed
    _surnameNode.addListener(_selectSuggestedSurname);
    _surname.addListener(() {
      if (_surnameNode.hasFocus && _surname.text != _initial.surname) {
        _surnameTouched = true;
      }
    });
    _photos?.addListener(_photosChanged);
    _photos?.load();
  }

  void _photosChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final TextEditingController c in [
      _given,
      _surname,
      _birthSurname,
      _bio,
      _bioSource,
    ]) {
      c.dispose();
    }
    for (final FocusNode n in [_givenNode, _surnameNode, _bioSourceNode]) {
      n.dispose();
    }
    for (final _DateInput d in _dates) {
      d.dispose();
    }
    // Drops the photos prepared and not saved; after "Zapisz" they are in the media directory already.
    _photos
      ?..removeListener(_photosChanged)
      ..dispose();
    super.dispose();
  }

  void _selectSuggestedSurname() {
    if (!_surnameNode.hasFocus || _surnameTouched) return;
    if (widget.mode is! NextPerson || _surname.text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _surname.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _surname.text.length,
      );
    });
  }

  String _snapshot() => [
    _given.text,
    _surname.text,
    _birthSurname.text,
    _bio.text,
    _bioSource.text,
    for (final _DateInput d in _dates) ...[
      d.qualifier.name,
      d.from.text,
      if (d.between) d.to.text,
    ],
  ].join('\u0000');

  /// A photo picked or changed is entered data too (wpis-osoby.md → Navigation).
  bool get _dirty =>
      _snapshot() != _initialSnapshot || (_photos?.hasChanges ?? false);

  /// The person as typed now, for the photo screens: "Nowa osoba" before a name is typed.
  String _nameNow({bool withBirthSurname = false}) {
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    if (t(_given) == null && t(_surname) == null) return 'Nowa osoba';
    return personName(
      t(_given),
      t(_surname),
      birthSurname: withBirthSurname ? t(_birthSurname) : null,
    );
  }

  String get _title => switch (widget.mode) {
    Correction() => 'Poprawa wpisu',
    _ => 'Osoba w grobie',
  };

  String get _subtitle => switch (widget.mode) {
    NewGrave(:final String cemeteryName) => '$cemeteryName · nowy grób',
    NextPerson(:final String graveTitle, :final int peopleCount) ||
    Correction(
      :final String graveTitle,
      :final int peopleCount,
    ) => '$graveTitle · w grobie: ${peopleLabel(peopleCount)}',
  };

  /// Checks every field and marks what is wrong; the first such field gets the focus, which also
  /// scrolls it into view. Null when everything is right.
  FocusNode? _validate() {
    FocusNode? first;
    final bool hasName =
        _given.text.trim().isNotEmpty || _surname.text.trim().isNotEmpty;
    _nameMissing = !hasName;
    if (!hasName) first = _givenNode;
    for (final _DateInput d in _dates) {
      final _DateRead r = d.read();
      d.showError = r.error != null;
      if (r.error != null) first ??= r.toBad ? d.toNode : d.fromNode;
    }
    _sourceMissing =
        _bio.text.trim().isNotEmpty && _bioSource.text.trim().isEmpty;
    if (_sourceMissing) {
      _editingSource = true;
      first ??= _bioSourceNode;
    }
    return first;
  }

  PersonEntry _entry() => PersonEntry(
    givenNames: _given.text,
    surname: _surname.text,
    birthSurname: _birthSurname.text,
    bio: _bio.text,
    bioSource: _bioSource.text,
    birth: _dates[0].read().date,
    death: _dates[1].read().date,
    // The form has no burial date (D7): a correction leaves the one a person has as it is.
    burial: _initial.burial,
  );

  Future<void> _save() async {
    if (_saving) return;
    final FocusNode? wrong = _validate();
    if (wrong != null) {
      setState(() {});
      wrong.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final NavigatorState navigator = Navigator.of(context);
    // The photos go in the person's transaction (D-zdjęcie-2); without photos it is the write alone.
    Future<T> write<T>(Future<T> Function(AlsoWrite? alsoWrite) w) =>
        switch (widget.photos) {
          final Photos photos => photos.writeWithPersonPhotos(
            widget.database,
            _photos?.edits(),
            w,
          ),
          null => w(null),
        };
    try {
      final PersonEntry entry = _entry();
      switch (widget.mode) {
        case NewGrave(:final int cemeteryId):
          final int grave = await write(
            (alsoWrite) => addPersonToNewGrave(
              widget.database,
              cemeteryId: cemeteryId,
              entry: entry,
              alsoWrite: alsoWrite,
            ),
          );
          _done = true;
          // The grave replaces the form: back from it returns to the cemetery (style-b.md rule 10).
          await navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => GraveScreen(
                database: widget.database,
                graveId: grave,
                photos: widget.photos,
              ),
            ),
          );
        case NextPerson(:final int graveId):
          await write(
            (alsoWrite) => addPersonToGrave(
              widget.database,
              graveId: graveId,
              entry: entry,
              alsoWrite: alsoWrite,
            ),
          );
          _done = true;
          navigator.pop();
        case Correction(:final BuriedPerson person):
          await write(
            (alsoWrite) => updatePersonEntry(
              widget.database,
              person.id,
              entry,
              alsoWrite: alsoWrite,
            ),
          );
          _done = true;
          navigator.pop();
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  /// Back with something typed asks first (style-b.md rule 10: a window only when something may be
  /// lost). The safe action is the main one.
  Future<void> _confirmDiscard() async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GrobingColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Odrzucić wpis?',
          style: TextStyle(
            color: GrobingColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          (_photos?.hasChanges ?? false)
              ? 'Wpisane dane i zmiany zdjęć nie zostaną zapisane.'
              : 'Wpisane dane nie zostaną zapisane.',
          style: const TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Odrzuć'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Wróć do wpisu'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _done = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Decided when back is pressed, not when the screen was last built: typing rebuilds nothing.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_done || !_dirty) {
        _done = true;
        Navigator.of(context).pop();
      } else {
        _confirmDiscard();
      }
    },
    child: Theme(
      data: Theme.of(
        context,
      ).copyWith(inputDecorationTheme: GrobingTheme.fields),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(),
              Expanded(child: _form()),
              _bottom(),
            ],
          ),
        ),
      ),
    ),
  );

  /// Element 1.
  Widget _bar() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BackButton(color: GrobingColors.text),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
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
  );

  /// Built whole, not lazily like a ListView: a field outside the screen must still be in the `next`
  /// order — lazily, `next` from "Pochówek" skipped "Kim była" and landed on "Zapisz" (seen on the
  /// emulator, ISSUE-012).
  Widget _form() => SingleChildScrollView(
    // 24 dp from the bar to the first field (style-b.md rule 5; ui review).
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Element 1a (v4): the person's photos — outside the `next` order, it takes no focus.
        if (_photos case final PersonPhotosDraft photos) ...[
          _PhotoField(
            draft: photos,
            onAdd: () => addPersonPhotos(context, photos),
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PersonPhotosScreen(
                  draft: photos,
                  personName: _nameNow(withBirthSurname: true),
                  shortName: _nameNow(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        // Elements 2–4.
        TextField(
          controller: _given,
          focusNode: _givenNode,
          // A correction is first read against the notes, so no keyboard covers it (ui review).
          autofocus: widget.mode is! Correction,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: _input,
          onChanged: (_) {
            if (_nameMissing) setState(() => _nameMissing = false);
          },
          decoration: InputDecoration(
            labelText: 'Imiona',
            error: _nameMissing
                ? const _ErrorLine('Podaj imiona albo nazwisko.')
                : null,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _surname,
          focusNode: _surnameNode,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: _input,
          onChanged: (_) {
            if (_nameMissing) setState(() => _nameMissing = false);
          },
          decoration: const InputDecoration(labelText: 'Nazwisko'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _birthSurname,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: _input,
          decoration: const InputDecoration(
            labelText: 'Nazwisko rodowe (z domu)',
          ),
        ),
        // Elements 5–7.
        for (final _DateInput d in _dates) ...[
          const SizedBox(height: 16),
          _DateBlock(
            input: d,
            onChanged: () => setState(() => d.showError = false),
          ),
        ],
        const SizedBox(height: 24),
        // Element 8: "kim była" is the short biography (D5).
        TextField(
          controller: _bio,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          style: _input,
          onChanged: (_) {
            if (_sourceMissing) setState(() => _sourceMissing = false);
          },
          decoration: const InputDecoration(
            labelText: 'Kim była',
            hintText:
                'Krótka biografia — np. zawód, miejsce, co warto zapamiętać',
            hintMaxLines: 2,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            alignLabelWithHint: true,
          ),
        ),
        _sourceLine(),
        const SizedBox(height: 16),
        // Element 10: the dates' source is shown, not asked (FR-001 cost decision). In a correction a
        // date keeps its claim and the grave does not change (D1), so the line says what is true
        // there (ui review).
        Text(
          widget.mode is Correction
              ? 'Poprawa nie zmienia źródła dat. Nowa data zapisze się ze '
                    'źródłem: notatki.'
              : 'Daty i miejsce pochówku zapiszą się ze źródłem: notatki.',
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ],
    ),
  );

  /// Element 9: the one source line of "kim była" — shown, and changed only when asked.
  Widget _sourceLine() {
    if (!_editingSource) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Źródło: ${_bioSource.text.trim()}',
              style: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _editingSource = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _bioSourceNode.requestFocus();
                _bioSource.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _bioSource.text.length,
                );
              });
            },
            child: const Text('Zmień'),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: _bioSource,
        focusNode: _bioSourceNode,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        style: _input,
        onChanged: (_) {
          if (_sourceMissing) setState(() => _sourceMissing = false);
        },
        decoration: InputDecoration(
          labelText: 'Źródło „kim była”',
          error: _sourceMissing
              ? const _ErrorLine(
                  'Podaj źródło — kto to powiedział albo skąd to wiesz.',
                )
              : null,
        ),
      ),
    );
  }

  /// Element 11: "Zapisz", pinned above the keyboard; a failed save says so above it.
  Widget _bottom() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_saveFailed) ...[
          const _ErrorLine('Nie udało się zapisać. Spróbuj jeszcze raz.'),
          const SizedBox(height: 8),
        ],
        FilledButton(
          style: primaryButtonStyle,
          onPressed: _saving ? null : _save,
          // With new photos the write takes longer (their files move first): the progress replaces the
          // label (wpis-osoby.md → States, "zapisywanie").
          child: _saving && (_photos?.hasChanges ?? false)
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Zapisz'),
        ),
      ],
    ),
  );
}

const TextStyle _input = TextStyle(color: GrobingColors.text, fontSize: 16);

/// Element 1a (05_DESIGN/wpis-osoby.md v4): without photos, an 80 dp circle with an outline, the icon in
/// amber and "Dodaj zdjęcie" — a button, never a silhouette (style-b.md rules 11, 14); with photos, the
/// profile photo cut to the circle and how many photos there are, which opens the person's photos. The
/// circle with its caption is one button.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.draft,
    required this.onAdd,
    required this.onOpen,
  });

  final PersonPhotosDraft draft;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  static const double _size = 80;

  @override
  Widget build(BuildContext context) {
    final DraftPhoto? profile = draft.profile;
    final int count = draft.count;
    final ({int failed, int of})? failure = draft.failure;
    final VoidCallback? action = draft.preparing > 0
        ? null
        : (count == 0 ? onAdd : onOpen);
    final Widget circle = switch (profile) {
      final DraftPhoto p => ClipOval(
        child: SizedBox.square(
          dimension: _size,
          child: Image.file(
            p.file,
            fit: BoxFit.cover,
            cacheWidth: coverDecodeWidth(context, _size),
            errorBuilder: (_, _, _) => const ColoredBox(
              color: GrobingColors.surface,
              child: Icon(
                Icons.broken_image_outlined,
                color: GrobingColors.textMuted,
              ),
            ),
          ),
        ),
      ),
      null => Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            BorderSide(color: GrobingColors.outline),
          ),
        ),
        child: Center(
          child: draft.preparing > 0
              ? const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : const Icon(
                  Icons.add_a_photo_outlined,
                  size: 28,
                  color: GrobingColors.amber,
                ),
        ),
      ),
    };
    final Widget caption = failure != null
        ? PhotoErrorLine(
            failure.of == 1
                ? 'Nie udało się wczytać zdjęcia. Spróbuj jeszcze raz.'
                : 'Nie udało się wczytać ${failure.failed} '
                      '${plural(failure.failed, 'zdjęcia', 'zdjęć', 'zdjęć')} '
                      'z ${failure.of}. Spróbuj jeszcze raz.',
          )
        : Text(
            count == 0
                ? 'Dodaj zdjęcie'
                : '$count ${plural(count, 'zdjęcie', 'zdjęcia', 'zdjęć')}',
            style: TextStyle(
              color: count == 0 ? GrobingColors.text : GrobingColors.textMuted,
              fontSize: 14,
            ),
          );
    return Center(
      child: Semantics(
        button: true,
        label: count == 0
            ? 'Dodaj zdjęcie osoby'
            : 'Zdjęcia osoby: $count — otwórz',
        enabled: action != null,
        // The tap too, not only the label: the label replaces the field's own semantics (ui review, MAJOR).
        onTap: action,
        excludeSemantics: failure == null,
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                circle,
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An error under a field: the error colour with its icon, never colour alone (SC 1.4.1).
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.error_outline, size: 16, color: GrobingColors.error),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: GrobingColors.error, fontSize: 13),
        ),
      ),
    ],
  );
}

/// What one date block holds: its qualifier, one or two typed dates, and whether its error shows.
class _DateInput {
  _DateInput(this.label, QualifiedDate? initial, {required this.readOnly})
    : original = initial,
      qualifier = initial?.qualifier ?? DateQualifier.exact,
      from = TextEditingController(
        text: initial == null ? '' : formatPartialDate(initial.from),
      ),
      to = TextEditingController(
        text: initial?.to == null ? '' : formatPartialDate(initial!.to!),
      );

  final String label;

  /// Another source spoke for this date: the correction form leaves it alone (ISSUE-012 D1).
  final bool readOnly;
  final QualifiedDate? original;
  DateQualifier qualifier;
  final TextEditingController from;
  final TextEditingController to;
  final FocusNode fromNode = FocusNode();
  final FocusNode toNode = FocusNode();

  /// Outside the `next` order, so `next` goes from date to date (05_DESIGN/wpis-osoby.md, element b).
  final FocusNode qualifierNode = FocusNode(skipTraversal: true);
  bool showError = false;

  bool get between => qualifier == DateQualifier.between;

  /// The date typed — null when the field is empty: an empty date writes nothing, and a qualifier
  /// without a date is ignored.
  _DateRead read() {
    if (readOnly) return (date: original, error: null, toBad: false);
    final String f = from.text.trim(), t = to.text.trim();
    if (f.isEmpty) {
      return between && t.isNotEmpty
          ? (date: null, error: 'Podaj pierwszą datę.', toBad: false)
          : (date: null, error: null, toBad: false);
    }
    final PartialDate? start = parsePartialDate(f);
    if (start == null) return (date: null, error: _badDate, toBad: false);
    if (!between) {
      return (date: QualifiedDate(qualifier, start), error: null, toBad: false);
    }
    if (t.isEmpty) return (date: null, error: 'Podaj drugą datę.', toBad: true);
    final PartialDate? end = parsePartialDate(t);
    if (end == null) return (date: null, error: _badDate, toBad: true);
    if (!isLater(start, end)) {
      return (
        date: null,
        error: 'Druga data musi być późniejsza od pierwszej.',
        toBad: true,
      );
    }
    return (
      date: QualifiedDate(DateQualifier.between, start, end),
      error: null,
      toBad: false,
    );
  }

  void dispose() {
    from.dispose();
    to.dispose();
    fromNode.dispose();
    toNode.dispose();
    qualifierNode.dispose();
  }
}

typedef _DateRead = ({QualifiedDate? date, String? error, bool toBad});

const Map<DateQualifier, String> _qualifierLabels = {
  DateQualifier.exact: 'dokładnie',
  DateQualifier.about: 'około',
  DateQualifier.before: 'przed',
  DateQualifier.after: 'po',
  DateQualifier.between: 'między',
};

/// Elements 5–7, the date block: label, qualifier, date (and the second one for "między"), and the
/// preview — the date exactly as the grave will show it.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.input, required this.onChanged});

  final _DateInput input;
  final VoidCallback onChanged;

  _DateInput get d => input;

  static const TextStyle _muted = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 14,
  );

  void _choose(DateQualifier q) {
    d.qualifier = q;
    onChanged();
    d.fromNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (d.readOnly) return _readOnly();
    final _DateRead r = d.read();
    final bool fromBad = d.showError && r.error != null && !r.toBad;
    final bool toBad = d.showError && r.error != null && r.toBad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.label, style: _muted),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _qualifierButton(),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                d.from,
                d.fromNode,
                fromBad,
                d.between ? 'od' : 'rok albo dd.mm.rrrr',
              ),
            ),
            if (d.between) ...[
              const SizedBox(width: 8),
              Expanded(child: _field(d.to, d.toNode, toBad, 'do')),
            ],
          ],
        ),
        if (d.showError && r.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _ErrorLine(r.error!),
          )
        else if (r.date != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text('→ ${formatDate(r.date!)}', style: _muted),
          ),
      ],
    );
  }

  Widget _qualifierButton() => MenuAnchor(
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(GrobingColors.surface),
    ),
    menuChildren: [
      for (final DateQualifier q in DateQualifier.values)
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            foregroundColor: q == d.qualifier
                ? GrobingColors.amber
                : GrobingColors.text,
            iconColor: GrobingColors.amber,
            minimumSize: const Size(160, 48),
          ),
          // The choice is a check and a selected state too, never colour alone (SC 1.4.1; ui review).
          leadingIcon: q == d.qualifier
              ? const Icon(Icons.check)
              : const SizedBox(width: 24),
          onPressed: () => _choose(q),
          child: Semantics(
            selected: q == d.qualifier,
            child: Text(_qualifierLabels[q]!),
          ),
        ),
    ],
    // A least size, not a fixed one: with a larger system text the label grows instead of being cut
    // (SC 1.4.4; ui review).
    builder: (context, controller, _) => OutlinedButton(
      focusNode: d.qualifierNode,
      style: OutlinedButton.styleFrom(
        foregroundColor: GrobingColors.text,
        side: const BorderSide(color: GrobingColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
        minimumSize: const Size(116, 56),
        alignment: Alignment.centerLeft,
        textStyle: const TextStyle(fontSize: 15),
      ),
      onPressed: () {
        if (controller.isOpen) {
          controller.close();
          return;
        }
        // The menu does not keep clear of the keyboard, which covered its lower items — "między"
        // among them (seen on the emulator): the keyboard goes first, and choosing brings the
        // focus, and the keyboard, back to the date.
        FocusManager.instance.primaryFocus?.unfocus();
        controller.open();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_qualifierLabels[d.qualifier]!),
          const Icon(Icons.arrow_drop_down, color: GrobingColors.textMuted),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    FocusNode node,
    bool bad,
    String hint,
  ) => TextField(
    controller: controller,
    focusNode: node,
    // Digits and a separator without switching keyboards (05_DESIGN/wpis-osoby.md → Open 2).
    keyboardType: TextInputType.datetime,
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]')),
      LengthLimitingTextInputFormatter(10),
    ],
    textInputAction: TextInputAction.next,
    style: _input,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      hintText: hint,
      // The frame turns to the error colour; the message stands under the whole block.
      error: bad ? const SizedBox.shrink() : null,
    ),
  );

  /// A date backed by more than one source: shown, not corrected here (ISSUE-012 D1).
  Widget _readOnly() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(d.label, style: _muted),
      const SizedBox(height: 6),
      InputDecorator(
        decoration: const InputDecoration(),
        child: Text(
          d.original == null ? 'bez daty' : formatDate(d.original!),
          style: _input,
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, left: 2),
        child: Text(
          'Kilka źródeł — tej daty tu nie poprawisz.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 13),
        ),
      ),
    ],
  );
}
