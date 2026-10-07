import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../photo/photo_people_screen.dart' show PeopleSectionHeader;
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/date_block.dart';
import 'person_picker_screen.dart';

/// Where a new family puts the person the sheet was opened from: in the pair ("Dodaj związek") or
/// among the children ("Dodaj rodziców") — 05_DESIGN/rodzina.md → Navigation.
enum FamilyStart { asPartner, asChild }

/// A, the family sheet (05_DESIGN/rodzina.md v1.1): one family at once — the pair, their children,
/// the start and the end of the union — as the canon's family group sheet (brief, Step 0; FR-002). It
/// saves itself, all or nothing, and goes back to the person form (D1); new people get their names
/// here and the rest in their own entry (D4). No roles in the rows: there is no sex, and the headers
/// "Para" and "Dzieci" say the rest (v1.1).
class FamilySheetScreen extends StatefulWidget {
  const FamilySheetScreen({
    super.key,
    required this.database,
    required this.personId,
    required this.personName,
    this.familyId,
    this.start = FamilyStart.asPartner,
    this.graveId,
  });

  final GrobingDatabase database;

  /// "Ta osoba" — whose form opened the sheet; the subtitle (A1) is [personName].
  final int personId;
  final String personName;

  /// The family to correct; null for a new one, starting from [start].
  final int? familyId;
  final FamilyStart start;

  /// The grave of "ta osoba": its people come first on the person picker (B4).
  final int? graveId;

  @override
  State<FamilySheetScreen> createState() => _FamilySheetScreenState();
}

/// A row of the sheet (A3, A3'): someone already in the app, or a new person typed here.
class _Row {
  _Row.existing(FamilyMember this.member)
    : given = null,
      surname = null,
      givenNode = null,
      surnameNode = null;

  _Row.typed({required String given, required String surname})
    : member = null,
      given = TextEditingController(text: given),
      surname = TextEditingController(text: surname),
      givenNode = FocusNode(),
      surnameNode = FocusNode();

  final FamilyMember? member;
  final TextEditingController? given;
  final TextEditingController? surname;
  final FocusNode? givenNode;
  final FocusNode? surnameNode;

  /// The suggested surname is selected, so typing replaces it, until it is touched (as the person form).
  bool surnameTouched = false;
  bool nameMissing = false;

  bool get isNew => member == null;

  MemberDraft get draft => switch (member) {
    final FamilyMember m => ExistingMember(m.id),
    null => NewMember(givenNames: given!.text, surname: surname!.text),
  };

  String get key => switch (member) {
    final FamilyMember m => '#${m.id}',
    null => '+${given!.text}\u0001${surname!.text}',
  };

  void dispose() {
    given?.dispose();
    surname?.dispose();
    givenNode?.dispose();
    surnameNode?.dispose();
  }
}

class _FamilySheetScreenState extends State<FamilySheetScreen> {
  final List<_Row> _partners = [];
  final List<_Row> _children = [];
  late DateInput _marriage;
  late DateInput _end;
  bool _endShown = false;
  bool _loaded = false;
  String _initialSnapshot = '';

  /// A1 and the rules of A12: what the family is missing, said above "Zapisz".
  String? _shapeError;
  bool _saving = false;
  bool _saveFailed = false;
  bool _done = false;

  static final ButtonStyle _rowButton = secondaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
  );

  static const String _endNote =
      'np. rozwód albo rozstanie. Owdowienie to zgon osoby — zapisuje się w jej '
      'wpisie.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final GrobingDatabase db = widget.database;
    if (widget.familyId case final int id) {
      final FamilyDetail? family = await loadFamily(db, id);
      if (family == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      _partners.addAll(family.partners.map(_Row.existing));
      _children.addAll(family.children.map(_Row.existing));
      _marriage = _date('Ślub', family.marriage);
      _end = _date('Koniec związku', family.end);
      // A6': a union with an end shows it at once.
      _endShown = family.end.date != null;
    } else {
      final FamilyMember self = await loadFamilyMember(db, widget.personId);
      (widget.start == FamilyStart.asPartner ? _partners : _children).add(
        _Row.existing(self),
      );
      _marriage = _date('Ślub', null);
      _end = _date('Koniec związku', null);
    }
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _initialSnapshot = _snapshot();
    });
  }

  DateInput _date(String label, DatedFact? fact) =>
      DateInput(label, fact?.date, readOnly: !(fact?.correctable ?? true));

  @override
  void dispose() {
    for (final _Row r in [..._partners, ..._children]) {
      r.dispose();
    }
    if (_loaded) {
      _marriage.dispose();
      _end.dispose();
    }
    super.dispose();
  }

  String _snapshot() => [
    for (final _Row r in _partners) r.key,
    '|',
    for (final _Row r in _children) r.key,
    '|',
    for (final DateInput d in [_marriage, _end]) ...[
      d.qualifier.name,
      d.from.text,
      if (d.between) d.to.text,
    ],
  ].join('\u0000');

  bool get _dirty => _loaded && _snapshot() != _initialSnapshot;

  Set<int> get _inFamily => {
    for (final _Row r in [..._partners, ..._children])
      if (r.member case final FamilyMember m) m.id,
  };

  /// A3' — the surname a new person starts from: the first in the pair's, or, with no pair yet, the
  /// first child's ("Dodaj rodziców").
  String _suggestedSurname() {
    String? surnameOf(_Row r) => (r.member?.surname ?? r.surname?.text)?.trim();
    for (final _Row r in [..._partners, ..._children]) {
      final String? s = surnameOf(r);
      if (s != null && s.isNotEmpty) return s;
    }
    return '';
  }

  Future<void> _add({required bool child}) async {
    final PickedMember? picked = await Navigator.of(context).push(
      MaterialPageRoute<PickedMember>(
        builder: (_) => PersonPickerScreen(
          database: widget.database,
          title: child ? 'Dodaj dziecko' : 'Dodaj do pary',
          inFamily: _inFamily,
          graveId: widget.graveId,
          forChild: child,
          familyId: widget.familyId,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final _Row row = switch (picked) {
      PickedPerson(:final PersonChoice choice) => _Row.existing(
        FamilyMember(
          id: choice.id,
          givenNames: choice.givenNames,
          surname: choice.surname,
          birthSurname: choice.birthSurname,
          birth: choice.birth,
          death: choice.death,
        ),
      ),
      PickedNew(:final String text) => _Row.typed(
        given: text,
        surname: _suggestedSurname(),
      ),
    };
    setState(() {
      (child ? _children : _partners).add(row);
      _shapeError = null;
    });
    if (row.isNew) _watchNewRow(row);
  }

  /// A new row: the keyboard in "Imiona", the cursor at its end; the suggested surname selected.
  void _watchNewRow(_Row row) {
    row.surnameNode!.addListener(() {
      if (!row.surnameNode!.hasFocus || row.surnameTouched) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || row.surnameTouched) return;
        row.surname!.selection = TextSelection(
          baseOffset: 0,
          extentOffset: row.surname!.text.length,
        );
      });
    });
    final String suggested = row.surname!.text;
    row.surname!.addListener(() {
      if (row.surnameNode!.hasFocus && row.surname!.text != suggested) {
        row.surnameTouched = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      row.givenNode!.requestFocus();
      row.given!.selection = TextSelection.collapsed(
        offset: row.given!.text.length,
      );
    });
  }

  void _remove(_Row row) => setState(() {
    _partners.remove(row);
    _children.remove(row);
    row.dispose();
    _shapeError = null;
  });

  /// Marks what is wrong; the first such field gets the focus. Null when the fields are right — the
  /// family's own shape is told above "Zapisz".
  FocusNode? _validate() {
    FocusNode? first;
    for (final _Row r in [..._partners, ..._children]) {
      if (!r.isNew) continue;
      r.nameMissing =
          r.given!.text.trim().isEmpty && r.surname!.text.trim().isEmpty;
      if (r.nameMissing) first ??= r.givenNode;
    }
    for (final DateInput d in [_marriage, if (_endShown) _end]) {
      final DateRead read = d.read();
      d.showError = read.error != null;
      if (read.error != null) first ??= read.toBad ? d.toNode : d.fromNode;
    }
    _shapeError = _partners.isEmpty
        ? 'Dodaj osobę do pary — rodzina to para i jej dzieci.'
        : _partners.length + _children.length < 2
        ? 'Dodaj drugą osobę do pary albo dziecko.'
        : null;
    return first;
  }

  Future<void> _save() async {
    if (_saving) return;
    final FocusNode? wrong = _validate();
    if (wrong != null || _shapeError != null) {
      setState(() {});
      wrong?.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final NavigatorState navigator = Navigator.of(context);
    try {
      await saveFamily(
        widget.database,
        FamilyDraft(
          familyId: widget.familyId,
          partners: [for (final _Row r in _partners) r.draft],
          children: [for (final _Row r in _children) r.draft],
          marriage: _marriage.read().date,
          // A hidden end is no end; a correction keeps its read-only one (DateInput.read).
          end: _endShown ? _end.read().date : null,
        ),
      );
      _done = true;
      navigator.pop();
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  Future<void> _confirmDiscard() async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (context) => _dialog(
        context,
        title: 'Odrzucić zmiany w rodzinie?',
        content: const Text(
          'Zmiany w tej rodzinie nie zostaną zapisane.',
          style: TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Odrzuć'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Wróć do rodziny'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _done = true;
      Navigator.of(context).pop();
    }
  }

  /// A11 (D8): the window, the deletion at once, and its failure inside the window.
  Future<void> _confirmDelete() async {
    final int familyId = widget.familyId!;
    final bool? deleted = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool failed = false;
        bool deleting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => _dialog(
            context,
            title: 'Usunąć rodzinę?',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Osoby zostają w aplikacji. Znikną tylko ich powiązania w tej '
                  'rodzinie i daty ślubu i końca.',
                  style: TextStyle(color: GrobingColors.text, fontSize: 16),
                ),
                if (failed) ...[
                  const SizedBox(height: 12),
                  const ErrorLine(
                    'Nie udało się usunąć rodziny. Spróbuj jeszcze raz.',
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: GrobingColors.text,
                ),
                onPressed: deleting
                    ? null
                    : () async {
                        setDialogState(() {
                          deleting = true;
                          failed = false;
                        });
                        try {
                          await deleteFamily(widget.database, familyId);
                          if (context.mounted) Navigator.of(context).pop(true);
                        } on Object {
                          if (context.mounted) {
                            setDialogState(() {
                              deleting = false;
                              failed = true;
                            });
                          }
                        }
                      },
                child: const Text('Usuń'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Zostaw'),
              ),
            ],
          ),
        );
      },
    );
    if (deleted == true && mounted) {
      _done = true;
      Navigator.of(context).pop();
    }
  }

  static Widget _dialog(
    BuildContext context, {
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) => AlertDialog(
    backgroundColor: GrobingColors.surface,
    surfaceTintColor: Colors.transparent,
    title: Text(
      title,
      style: const TextStyle(
        color: GrobingColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    content: content,
    actions: actions,
  );

  @override
  Widget build(BuildContext context) => PopScope(
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
        backgroundColor: GrobingColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(),
              Expanded(child: _loaded ? _form() : const SizedBox.shrink()),
              if (_loaded) _bottom(),
            ],
          ),
        ),
      ),
    ),
  );

  /// A1.
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
                  widget.familyId == null ? 'Nowa rodzina' : 'Rodzina',
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.personName,
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

  /// Built whole, as the person form: every field in the `next` order.
  Widget _form() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A2–A4.
        const PeopleSectionHeader('Para'),
        for (final _Row r in _partners) _row(r),
        if (_partners.length < 2) ...[
          const SizedBox(height: 8),
          _addButton('Dodaj osobę do pary', () => _add(child: false)),
        ],
        const SizedBox(height: 24),
        // A5.
        DateBlock(
          input: _marriage,
          onChanged: () => setState(() => _marriage.showError = false),
        ),
        // A6, A6'.
        if (_endShown) ...[
          const SizedBox(height: 16),
          DateBlock(
            input: _end,
            note: _endNote,
            onChanged: () => setState(() => _end.showError = false),
          ),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              // The text on the 16 dp edge of the content, as the headers (style-b rule 5; ui review).
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () {
                setState(() => _endShown = true);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _end.fromNode.requestFocus(),
                );
              },
              child: const Text('Dodaj koniec związku'),
            ),
          ),
        // 24 dp between the groups: the header brings its own 16 (ui review).
        const SizedBox(height: 8),
        // A7–A9.
        const PeopleSectionHeader('Dzieci'),
        for (final _Row r in _children) _row(r),
        const SizedBox(height: 8),
        _addButton('Dodaj dziecko', () => _add(child: true)),
        const SizedBox(height: 24),
        // A10: the source is shown, not asked (FR-001 cost decision).
        const Text(
          'Rodzina i jej daty zapiszą się ze źródłem: notatki.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        // A11 (D8): a correction only.
        if (widget.familyId != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // The icon on the 16 dp edge of the content (style-b rule 5; ui review).
              style: TextButton.styleFrom(
                foregroundColor: GrobingColors.text,
                padding: EdgeInsets.zero,
              ),
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Usuń rodzinę'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _addButton(String label, VoidCallback onPressed) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      style: _rowButton,
      onPressed: onPressed,
      icon: const Icon(Icons.person_add_alt_outlined),
      label: Text(label),
    ),
  );

  /// A3 / A3'. "Ta osoba" has no ✕: the sheet is hers.
  Widget _row(_Row r) {
    final bool self = r.member?.id == widget.personId;
    final Widget remove = IconButton(
      icon: const Icon(Icons.close, color: GrobingColors.textMuted),
      tooltip: 'Usuń z rodziny',
      onPressed: () => _remove(r),
    );
    if (r.member case final FamilyMember m) {
      final String life = lifeLine(birth: m.birth, death: m.death);
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      personName(
                        m.givenNames,
                        m.surname,
                        birthSurname: m.birthSurname,
                      ),
                      style: const TextStyle(
                        color: GrobingColors.text,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      self ? '$life · ta osoba' : life,
                      style: const TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!self) remove,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: r.given,
                  focusNode: r.givenNode,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  // `next` names its field: the reading order went from here to ✕ beside it and, without
                  // it, to "Zapisz" (seen on the emulator) — never to "Nazwisko" below.
                  onEditingComplete: () => r.surnameNode!.requestFocus(),
                  style: inputTextStyle,
                  onChanged: (_) {
                    if (r.nameMissing) setState(() => r.nameMissing = false);
                  },
                  decoration: InputDecoration(
                    labelText: 'Imiona',
                    error: r.nameMissing
                        ? const ErrorLine('Podaj imiona albo nazwisko.')
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: r.surname,
                  focusNode: r.surnameNode,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  style: inputTextStyle,
                  onChanged: (_) {
                    if (r.nameMissing) setState(() => r.nameMissing = false);
                  },
                  decoration: const InputDecoration(labelText: 'Nazwisko'),
                ),
              ],
            ),
          ),
          remove,
        ],
      ),
    );
  }

  /// A12: "Zapisz", pinned above the keyboard; what the family is missing, or a failed save, above it.
  Widget _bottom() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_shapeError case final String error) ...[
          ErrorLine(error),
          const SizedBox(height: 8),
        ] else if (_saveFailed) ...[
          const ErrorLine('Nie udało się zapisać. Spróbuj jeszcze raz.'),
          const SizedBox(height: 8),
        ],
        FilledButton(
          style: primaryButtonStyle,
          onPressed: _saving ? null : _save,
          child: const Text('Zapisz'),
        ),
      ],
    ),
  );
}
