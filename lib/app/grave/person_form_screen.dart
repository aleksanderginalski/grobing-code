import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../../data/places.dart' show PlaceList;
import '../../data/residences.dart';
import '../family/family_section.dart';
import '../person/clan_screen.dart';
import '../person/residence_screen.dart';
import '../photo/person_photos_draft.dart';
import '../photo/person_photos_screen.dart';
import '../photo/photo_viewer_screen.dart' show PhotoErrorLine;
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../tabs.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/date_block.dart';
import '../widgets/sex_toggle.dart';
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

  /// The grave's name, or its cemetery's; null for a person buried nowhere — opened from a relative's
  /// chip in "Rodzina" (05_DESIGN/wpis-osoby.md v5, "poprawa osoby bez grobu").
  final String? graveTitle;
  final int peopleCount;

  /// The grave the person was opened from: its people come first in "Kto jest na zdjęciu?".
  final int? graveId;
}

/// The correction of [personId]'s entry — from ✎ in their view (05_DESIGN/osoba.md element 1; wpis-osoby.md
/// v5.8), or from "Dodaj zdjęcie" there with the photo sheet over it at once ([pickPhotosAtStart],
/// osoba.md D20). Their first grave, when they have one, is the form's subtitle and comes first in "Kto
/// jest na zdjęciu?".
///
/// One correction of a person at a time (osoba.md D15): when theirs lies lower on the stack — the form,
/// a relative's chip, their mini tree, back to the same person — this returns to it instead of opening a
/// second over the first, whose later "Zapisz" would write the older values over the newer.
Future<void> openPersonEntry(
  BuildContext context,
  GrobingDatabase database,
  int personId, {
  Photos? photos,
  AppTab tab = AppTab.map,
  bool pickPhotosAtStart = false,
  bool addResidenceAtStart = false,
}) async {
  if (PersonFormScreen.isCorrecting(personId)) {
    Navigator.of(context).popUntil(
      (route) =>
          route.settings.name == PersonFormScreen.correctionRoute(personId) ||
          route.isFirst,
    );
    return;
  }
  final ({
    BuriedPerson person,
    int? graveId,
    String? graveTitle,
    int peopleCount,
  })?
  found = await loadPersonForCorrection(database, personId);
  if (found == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: PersonFormScreen.correctionRoute(personId)),
      builder: (_) => PersonFormScreen(
        database: database,
        mode: Correction(
          person: found.person,
          graveTitle: found.graveTitle,
          peopleCount: found.peopleCount,
          graveId: found.graveId,
        ),
        photos: photos,
        tab: tab,
        pickPhotosAtStart: pickPhotosAtStart,
        addResidenceAtStart: addResidenceAtStart,
      ),
    ),
  );
}

/// One person buried in a grave, as the notes give them (ISSUE-012; 05_DESIGN/wpis-osoby.md v2). The
/// screen of the transcription used about 100 times (G6), so every field, key and question counts.
class PersonFormScreen extends StatefulWidget {
  const PersonFormScreen({
    super.key,
    required this.database,
    required this.mode,
    this.photos,
    this.tab = AppTab.map,
    this.pickPhotosAtStart = false,
    this.addResidenceAtStart = false,
    this.places,
  });

  final GrobingDatabase database;
  final PersonFormMode mode;

  /// "Dodaj miejsce" in the person's view (05_DESIGN/zamieszkanie.md, element 4): the window "Miejsce
  /// zamieszkania" opens over the form at once, as "Dodaj zdjęcie" opens the photo sheet.
  final bool addResidenceAtStart;

  /// The list of places for the residences' choice; the bundled one when null (tests give a made-up one).
  final Future<PlaceList>? places;

  /// The person's photos (element 1a, ISSUE-017), and passed on to the grave view that replaces the form
  /// after a new grave (ISSUE-016). Null only in tests of other features: then the form has no photos.
  final Photos? photos;

  /// The tab of the stack the form was opened in — for the views it opens (a relative's, the grave
  /// after a new one): the bar keeps it active (style-b.md rule 12).
  final AppTab tab;

  /// "Dodaj zdjęcie" in the person's view (osoba.md D20): the photo sheet opens over the form at once, as
  /// element 1a would.
  final bool pickPhotosAtStart;

  /// The route of [personId]'s correction (osoba.md D15).
  static String correctionRoute(int personId) => '/correction/$personId';

  /// The people whose correction is open now, lower on the stack or on top.
  static final Set<int> _correcting = {};

  static bool isCorrecting(int personId) => _correcting.contains(personId);

  @override
  State<PersonFormScreen> createState() => _PersonFormScreenState();
}

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

  final FocusNode _givenNode = FocusNode();
  final FocusNode _surnameNode = FocusNode();

  /// Element 4a (v5.6): the sex written, or the one suggested from the given names. A correction of
  /// someone with a sex keeps it — the form never changes it by itself; without one, the suggestion is
  /// where the form starts, so going back unchanged asks nothing (D-płeć).
  late Sex? _sex = _initial.sex ?? suggestSex(_initial.givenNames);
  late bool _sexTouched = _initial.sex != null;

  late final List<DateInput> _dates = [
    DateInput(
      'Urodzenie',
      _initial.birth,
      readOnly: !_correctable((p) => p.birth),
    ),
    DateInput('Zgon', _initial.death, readOnly: !_correctable((p) => p.death)),
    // No burial date: the author found it superfluous, and every field counts a hundred times (the author's
    // decision at stop #2, ISSUE-012 D7). The data model keeps it (GEDCOM BURI next to DEAT).
  ];

  /// The suggested surname is selected, so typing replaces it, until it is touched.
  bool _surnameTouched = false;
  bool _nameMissing = false;
  bool _saving = false;
  bool _saveFailed = false;
  bool _done = false;

  late final String _initialSnapshot = _snapshot();

  /// The person's residences while the form is open, in the order they were entered (element 9b); written
  /// with "Zapisz" (zamieszkanie.md D5). A correction reads the stored ones first; until then the section
  /// is not shown and "Zapisz" leaves them as they are.
  List<Residence> _residences = [];
  List<Residence> _storedResidences = [];
  late bool _residencesRead = widget.mode is! Correction;

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
    final Future<void>? loaded = _photos?.load();
    if (widget.mode case Correction(:final BuriedPerson person)) {
      PersonFormScreen._correcting.add(person.id);
      residencesOf(widget.database, person.id).then((stored) {
        if (!mounted) return;
        setState(() {
          _storedResidences = stored;
          _residences = [...stored];
          _residencesRead = true;
        });
        if (widget.addResidenceAtStart) _editResidence(null);
      }, onError: (Object _) {});
    } else if (widget.addResidenceAtStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editResidence(null);
      });
    }
    if (widget.pickPhotosAtStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await loaded;
        final PersonPhotosDraft? photos = _photos;
        if (mounted && photos != null) await addPersonPhotos(context, photos);
      });
    }
  }

  void _photosChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.mode case Correction(:final BuriedPerson person)) {
      PersonFormScreen._correcting.remove(person.id);
    }
    for (final TextEditingController c in [
      _given,
      _surname,
      _birthSurname,
      _bio,
    ]) {
      c.dispose();
    }
    for (final FocusNode n in [_givenNode, _surnameNode]) {
      n.dispose();
    }
    for (final DateInput d in _dates) {
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
    _sex?.name ?? '',
    for (final DateInput d in _dates) ...[
      d.qualifier.name,
      d.from.text,
      if (d.between) d.to.text,
    ],
  ].join('\u0000');

  /// A photo picked or changed is entered data too (wpis-osoby.md → Navigation), and so is a residence
  /// added, corrected or removed (zamieszkanie.md D5).
  bool get _dirty =>
      _snapshot() != _initialSnapshot ||
      (_photos?.hasChanges ?? false) ||
      _residencesChanged;

  bool get _residencesChanged {
    if (_residences.length != _storedResidences.length) return true;
    final Map<int, Residence> stored = {
      for (final Residence r in _storedResidences) r.id!: r,
    };
    return _residences.any((r) {
      final Residence? s = r.id == null ? null : stored[r.id];
      return s == null || !s.sameAs(r);
    });
  }

  /// The window "Miejsce zamieszkania" (A) for [residence], or a new one: its answer changes the list here,
  /// not the database.
  Future<void> _editResidence(Residence? residence) async {
    final ResidenceChange? change = await Navigator.of(context)
        .push<ResidenceChange>(
          MaterialPageRoute(
            builder: (_) => ResidenceScreen(
              initial: residence,
              recent: _recentPlaces,
              places: widget.places,
            ),
          ),
        );
    if (change == null || !mounted) return;
    setState(() {
      final int at = residence == null ? -1 : _residences.indexOf(residence);
      switch (change) {
        case ResidenceDone(residence: final Residence r) when at >= 0:
          _residences[at] = r;
        case ResidenceDone(residence: final Residence r):
          _residences.add(r);
        case ResidenceRemoved() when at >= 0:
          _residences.removeAt(at);
        case ResidenceRemoved():
      }
    });
  }

  /// "Ostatnio wybrane" (zamieszkanie.md D6): the places of this form's residences first — the newest
  /// entered first — then those written before.
  Future<List<ResidencePlace>> _recentPlaces() async {
    final List<ResidencePlace> places = [];
    for (final ResidencePlace p in [
      for (final Residence r in _residences.reversed) r.place,
      ...await recentPlaces(widget.database),
    ]) {
      if (!places.contains(p)) places.add(p);
    }
    return places.take(5).toList();
  }

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
      graveTitle: final String graveTitle,
      :final int peopleCount,
    ) => '$graveTitle · w grobie: ${peopleLabel(peopleCount)}',
    Correction(graveTitle: null) => 'bez grobu w aplikacji',
  };

  /// Checks every field and marks what is wrong; the first such field gets the focus, which also
  /// scrolls it into view. Null when everything is right.
  FocusNode? _validate() {
    FocusNode? first;
    final bool hasName =
        _given.text.trim().isNotEmpty || _surname.text.trim().isNotEmpty;
    _nameMissing = !hasName;
    if (!hasName) first = _givenNode;
    for (final DateInput d in _dates) {
      final DateRead r = d.read();
      d.showError = r.error != null;
      if (r.error != null) first ??= r.toBad ? d.toNode : d.fromNode;
    }
    return first;
  }

  PersonEntry _entry() => PersonEntry(
    givenNames: _given.text,
    surname: _surname.text,
    birthSurname: _birthSurname.text,
    bio: _bio.text,
    // The source of "kim była" is not on the screen any more (v5.4, SPIKE-004 D28): a correction keeps
    // the one stored, a new text gets the notes'.
    bioSource: _initial.bioSource,
    sex: _sex,
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
    // The photos and the residences go in the person's transaction (D-zdjęcie-2; zamieszkanie.md D5);
    // without them it is the write alone.
    final List<Residence>? residences = _residencesRead && _residencesChanged
        ? List.of(_residences)
        : null;
    Future<T> write<T>(Future<T> Function(AlsoWrite? alsoWrite) w) {
      Future<T> withResidences(AlsoWrite? photos) => w(
        residences == null
            ? photos
            : (personId) async {
                await photos?.call(personId);
                await writeResidences(widget.database, personId, residences);
              },
      );
      return switch (widget.photos) {
        final Photos photos => photos.writeWithPersonPhotos(
          widget.database,
          _photos?.edits(),
          withResidences,
        ),
        null => withResidences(null),
      };
    }

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
                tab: widget.tab,
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
        // Elements 2 and 4a (v5.6): the given names, and the sex beside them, suggested from them.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _given,
                focusNode: _givenNode,
                // A correction is first read against the notes, so no keyboard covers it (ui review).
                autofocus: widget.mode is! Correction,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: inputTextStyle,
                onChanged: (text) => setState(() {
                  _nameMissing = false;
                  if (!_sexTouched) _sex = suggestSex(text);
                }),
                decoration: InputDecoration(
                  labelText: 'Imiona',
                  error: _nameMissing
                      ? const ErrorLine('Podaj imiona albo nazwisko.')
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SexToggle(
              value: _sex,
              onChanged: (sex) => setState(() {
                _sex = sex;
                _sexTouched = true;
              }),
            ),
          ],
        ),
        // Element 4a stood here in v5.5 (a segment under the birth surname).
        const SizedBox(height: 16),
        TextField(
          controller: _surname,
          focusNode: _surnameNode,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: inputTextStyle,
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
          style: inputTextStyle,
          decoration: const InputDecoration(
            labelText: 'Nazwisko rodowe (z domu)',
          ),
        ),
        // Element 4b (v5.10, ISSUE-044): the wreath of the family line — in a correction only, outside the
        // `next` order; a choice saves at once, like "Rodzina" (wieniec.md D16).
        if (widget.mode case Correction(:final BuriedPerson person)) ...[
          const SizedBox(height: 16),
          WreathFormRow(database: widget.database, personId: person.id),
        ],
        // Elements 5–7.
        for (final DateInput d in _dates) ...[
          const SizedBox(height: 16),
          DateBlock(
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
          style: inputTextStyle,
          decoration: const InputDecoration(
            labelText: 'Kim była',
            hintText:
                'Krótka biografia — np. zawód, miejsce, co warto zapamiętać',
            hintMaxLines: 2,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            alignLabelWithHint: true,
          ),
        ),
        // Element 9 ("Źródło: notatki · Zmień") is gone, and so is element 10 below: no sources in the app
        // (v5.4, SPIKE-004 D28). The data keeps them, written with the notes' by default.
        // Element 9a (v5.6): the person's families — in a correction only: the family sheet points at
        // "ta osoba", so the person must be written first (rodzina.md D2). Outside the `next` order.
        if (widget.mode case Correction(:final BuriedPerson person)) ...[
          const SizedBox(height: 24),
          FamilySection(
            database: widget.database,
            personId: person.id,
            tab: widget.tab,
            graveId: switch (widget.mode) {
              Correction(:final int? graveId) => graveId,
              _ => null,
            },
            photos: widget.photos,
          ),
        ],
        // Element 9b (v5.9): the residences — in every mode, written with "Zapisz" (zamieszkanie.md D5).
        // Outside the `next` order.
        if (_residencesRead) ...[
          const SizedBox(height: 24),
          ResidencesFormSection(
            residences: inStayOrder(_residences),
            onEdit: _editResidence,
            onAdd: () => _editResidence(null),
          ),
        ],
      ],
    ),
  );

  /// Element 11: "Zapisz", pinned above the keyboard; a failed save says so above it.
  Widget _bottom() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_saveFailed) ...[
          const ErrorLine('Nie udało się zapisać. Spróbuj jeszcze raz.'),
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
      // v4.1: in the link's crop, or from the middle (ISSUE-018).
      final DraftPhoto p => ProfileCircle(
        file: p.file,
        crop: draft.cropOf(p),
        size: _size,
        unreadable: const ColoredBox(
          color: GrobingColors.surface,
          child: Icon(
            Icons.broken_image_outlined,
            color: GrobingColors.textMuted,
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
