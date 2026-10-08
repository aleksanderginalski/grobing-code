import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/date_block.dart';
import '../widgets/sex_toggle.dart';
import 'person_choice_list.dart';

// C of 05_DESIGN/rodzina.md v2 — the union wizard (ISSUE-025): a union is a timeline, together since →
// the wedding → the end, asked one question at a time in a sheet from below. The author: "najpierw do
// wyboru osoba, potem czy razem/małżeństwo, potem opcja zakończenia lub »ewolucji« relacji". The same
// wizard adds parents (P1). It writes once, at the last step, through `saveFamily` — the one way a family
// is written — and the summary (D) and "Dodaj dziecko" (E) use its pieces.

/// Which union the wizard adds: one of the person's own, or their parents' (rodzina.md C-r1, C-r2).
enum UnionWizardKind { partner, parents }

/// Opens the wizard over the person form. [self] is the person whose form it is; [partnersAlready] are
/// the people already in a union with them — "już partner tej osoby" in "Z kim?".
Future<void> showUnionWizard(
  BuildContext context, {
  required GrobingDatabase database,
  required FamilyMember self,
  required UnionWizardKind kind,
  Set<int> partnersAlready = const {},
  bool another = false,
  int? graveId,
}) => showFamilySheet<void>(
  context,
  builder: (_) => _UnionWizard(
    database: database,
    self: self,
    kind: kind,
    partnersAlready: partnersAlready,
    another: another,
    graveId: graveId,
  ),
);

/// A sheet from below on the surface (rodzina.md C0): it closes only by its own ✕ or back, so a half
/// told union asks before it goes. **Always the same height** — about 92 % of the screen — and the keyboard
/// shrinks what is inside it, never moves it: the author at stop #2 of ISSUE-025, *„aby po otwarciu się
/// klawiatury ten pop-up nie przesuwał się stale góra-dół”*. A page puts its buttons at the foot
/// ([SheetPage]), so they stand above the keyboard.
Future<T?> showFamilySheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  backgroundColor: GrobingColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (context) => Theme(
    data: Theme.of(context).copyWith(inputDecorationTheme: GrobingTheme.fields),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Padding(
        // The keyboard takes the foot of the sheet; the page above it shrinks.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: builder(context),
      ),
    ),
  ),
);

/// One page of a family sheet: the header, then either [children] scrolling or, for a list of people,
/// [above] and the [list] taking the rest; the step's [actions] pinned at the foot.
class SheetPage extends StatelessWidget {
  const SheetPage({
    super.key,
    required this.header,
    this.body = const [],
    this.above = const [],
    this.list,
    this.actions,
  });

  final Widget header;
  final List<Widget> body;
  final List<Widget> above;
  final Widget? list;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header,
      if (list case final Widget list) ...[
        ...above,
        Expanded(child: list),
      ] else
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
          ),
        ),
      ?actions,
    ],
  );
}

/// The top of a sheet: back a step (on the first, close — rodzina.md C0), what and which step, and ✕.
/// Without [onBack] the title stands on the 16 dp edge of the content (style-b rule 5; ui review).
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.onBack,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (onBack != null)
        IconButton(
          icon: const Icon(Icons.arrow_back, color: GrobingColors.text),
          tooltip: 'Wstecz',
          onPressed: onBack,
        )
      else
        const SizedBox(width: 16),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.close, color: GrobingColors.text),
        tooltip: 'Zamknij',
        onPressed: onClose,
      ),
    ],
  );
}

/// The question of a step (20 sp) and, under it, what is told so far — the union's timeline.
class StepQuestion extends StatelessWidget {
  const StepQuestion(this.question, {super.key, this.sofar});

  final String question;
  final String? sofar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: const TextStyle(
            color: GrobingColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (sofar case final String sofar) ...[
          const SizedBox(height: 4),
          Text(
            sofar,
            style: const TextStyle(
              color: GrobingColors.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ],
    ),
  );
}

/// A choice of a step (rodzina.md C2, C3): ≥ 56 dp, the icon in amber; the chosen one has a 2 dp amber
/// frame and the selected state, never the colour alone (SC 1.4.1).
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;

  /// Null while the step saves: the card is inactive, in the muted colour (rodzina.md States → zapisywanie).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? GrobingColors.amber : GrobingColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: onTap == null
                        ? GrobingColors.textMuted
                        : GrobingColors.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: onTap == null
                                ? GrobingColors.textMuted
                                : GrobingColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle case final String subtitle)
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: GrobingColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                      ],
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

/// The buttons at the foot of a step: a text one ("Nie znam daty", in the text colour) and the one filled
/// — amber is for the main action only (style-b rule 1; ui review).
class StepActions extends StatelessWidget {
  const StepActions({
    super.key,
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.busy = false,
    this.error,
  });

  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final bool busy;

  /// A failed save, said above the buttons.
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error case final String error) ...[
          ErrorLine(error),
          const SizedBox(height: 8),
        ],
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (secondary case final String secondary)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: GrobingColors.text,
                ),
                onPressed: busy ? null : onSecondary,
                child: Text(secondary),
              ),
            StepActionsButton(
              label: primary,
              onPressed: busy ? null : onPrimary,
            ),
          ],
        ),
      ],
    ),
  );
}

/// The one filled button of a step, as wide as its text (style-b rule 1; ≥ 52 dp high).
class StepActionsButton extends StatelessWidget {
  const StepActionsButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  static final ButtonStyle _style = primaryButtonStyle.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size(120, 52)),
  );

  @override
  Widget build(BuildContext context) =>
      FilledButton(style: _style, onPressed: onPressed, child: Text(label));
}

/// A new person typed in a sheet (rodzina.md C1'): given names with ♀ ♂ beside them, suggested from
/// the names until touched, and a surname suggested and selected, so typing replaces it.
class NewPersonInput {
  NewPersonInput({required String given, required String surname, Sex? sex})
    : given = TextEditingController(text: given),
      surname = TextEditingController(text: surname),
      sex = sex ?? suggestSex(given),
      sexTouched = sex != null;

  final TextEditingController given;
  final TextEditingController surname;
  final FocusNode givenNode = FocusNode();
  final FocusNode surnameNode = FocusNode();
  Sex? sex;
  bool sexTouched;
  bool surnameTouched = false;
  bool nameMissing = false;

  NewMember get draft =>
      NewMember(givenNames: given.text, surname: surname.text, sex: sex);

  String get shortName => _firstWord(given.text) ?? surname.text.trim();

  /// Marks a missing name; true when the person can be written.
  bool validate() {
    nameMissing = given.text.trim().isEmpty && surname.text.trim().isEmpty;
    if (nameMissing) givenNode.requestFocus();
    return !nameMissing;
  }

  void dispose() {
    given.dispose();
    surname.dispose();
    givenNode.dispose();
    surnameNode.dispose();
  }
}

/// The fields of a [NewPersonInput]: "Imiona" with the keyboard and the cursor at its end, `next` to
/// "Nazwisko", `done` from there to [onDone].
class NewPersonFields extends StatefulWidget {
  const NewPersonFields({super.key, required this.input, required this.onDone});

  final NewPersonInput input;
  final VoidCallback onDone;

  @override
  State<NewPersonFields> createState() => _NewPersonFieldsState();
}

class _NewPersonFieldsState extends State<NewPersonFields> {
  NewPersonInput get p => widget.input;
  late final String _suggested = p.surname.text;

  @override
  void initState() {
    super.initState();
    p.surnameNode.addListener(_selectSuggested);
    p.surname.addListener(() {
      if (p.surnameNode.hasFocus && p.surname.text != _suggested) {
        p.surnameTouched = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      p.givenNode.requestFocus();
      p.given.selection = TextSelection.collapsed(offset: p.given.text.length);
    });
  }

  @override
  void dispose() {
    p.surnameNode.removeListener(_selectSuggested);
    super.dispose();
  }

  void _selectSuggested() {
    if (!p.surnameNode.hasFocus || p.surnameTouched) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || p.surnameTouched) return;
      p.surname.selection = TextSelection(
        baseOffset: 0,
        extentOffset: p.surname.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: p.given,
                focusNode: p.givenNode,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: p.surnameNode.requestFocus,
                style: inputTextStyle,
                onChanged: (text) => setState(() {
                  p.nameMissing = false;
                  if (!p.sexTouched) p.sex = suggestSex(text);
                }),
                decoration: InputDecoration(
                  labelText: 'Imiona',
                  error: p.nameMissing
                      ? const ErrorLine('Podaj imiona albo nazwisko.')
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SexToggle(
              value: p.sex,
              onChanged: (sex) => setState(() {
                p.sex = sex;
                p.sexTouched = true;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: p.surname,
          focusNode: p.surnameNode,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onDone(),
          style: inputTextStyle,
          onChanged: (_) {
            if (p.nameMissing) setState(() => p.nameMissing = false);
          },
          decoration: const InputDecoration(labelText: 'Nazwisko'),
        ),
      ],
    ),
  );
}

/// A window of the family sheets: the title, the text, the safe action in amber.
Widget familyDialog(
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

/// "Przerwać dodawanie?" (rodzina.md C0): true when the author lets go of what was told.
Future<bool> confirmAbandon(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => familyDialog(
        context,
        title: 'Przerwać dodawanie?',
        content: const Text(
          'To, co podałeś, nie zapisze się.',
          style: TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Przerwij'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Wróć'),
          ),
        ],
      ),
    ) ??
    false;

/// The union's timeline as the card and the wizard say it: "razem od 1946 · ślub ok. 1948 · koniec
/// 1960"; a wedding or an end without a date is the bare word; a union with nothing written is
/// "Razem", and a wedding alone without a date "Małżeństwo" (wpis-osoby.md 9a c).
String unionTimeline({
  QualifiedDate? together,
  required bool married,
  QualifiedDate? marriage,
  required bool ended,
  QualifiedDate? end,
}) {
  final List<String> parts = [
    if (together case final QualifiedDate t) 'razem od ${formatDate(t)}',
    if (married) marriage == null ? 'ślub' : 'ślub ${formatDate(marriage)}',
    if (ended) end == null ? 'koniec' : 'koniec ${formatDate(end)}',
  ];
  if (parts.isEmpty) return 'Razem';
  if (parts.length == 1 && parts.first == 'ślub') return 'Małżeństwo';
  return parts.join(' · ');
}

/// The first given name, as R4's chips ("Partner: Jan"); without given names, null.
String? _firstWord(String? text) {
  final String t = (text ?? '').trim();
  return t.isEmpty ? null : t.split(RegExp(r'\s+')).first;
}

/// How a person is named in a short line: the first given name, else the surname.
String shortPersonName(String? givenNames, String? surname) =>
    _firstWord(givenNames) ?? (surname ?? '').trim();

/// A date as a number that orders it — the first bound of "między" (families.dart does the same).
int dateOrderKey(QualifiedDate d) =>
    d.from.year * 10000 + (d.from.month ?? 0) * 100 + (d.from.day ?? 0);

/// Someone chosen or typed in the wizard.
class _Party {
  _Party.existing(PersonChoice c)
    : id = c.id,
      givenNames = c.givenNames,
      surname = c.surname,
      newPerson = null;

  _Party.typed(NewPersonInput this.newPerson)
    : id = null,
      givenNames = null,
      surname = null;

  final int? id;
  final String? givenNames;
  final String? surname;
  final NewPersonInput? newPerson;

  MemberDraft get draft => switch (newPerson) {
    final NewPersonInput p => p.draft,
    null => ExistingMember(id!),
  };

  String get shortName =>
      newPerson?.shortName ?? shortPersonName(givenNames, surname);
}

enum _Step {
  who,
  whoNew,
  mother,
  motherNew,
  father,
  fatherNew,
  kind,
  next,
  marriage,
  end,
}

enum _Kind { together, married }

class _UnionWizard extends StatefulWidget {
  const _UnionWizard({
    required this.database,
    required this.self,
    required this.kind,
    required this.partnersAlready,
    required this.another,
    this.graveId,
  });

  final GrobingDatabase database;
  final FamilyMember self;
  final UnionWizardKind kind;
  final Set<int> partnersAlready;
  final bool another;
  final int? graveId;

  @override
  State<_UnionWizard> createState() => _UnionWizardState();
}

class _UnionWizardState extends State<_UnionWizard> {
  late final List<_Step> _steps = [
    widget.kind == UnionWizardKind.partner ? _Step.who : _Step.mother,
  ];
  _Party? _partner, _mother, _father;
  _Kind? _kind;
  QualifiedDate? _together, _marriage, _end;
  bool _married = false, _ended = false;
  final DateInput _startInput = DateInput('Razem od', null, readOnly: false);
  final DateInput _weddingInput = DateInput('Ślub', null, readOnly: false);
  final DateInput _endInput = DateInput(
    'Koniec związku',
    null,
    readOnly: false,
  );
  String? _orderError;
  bool _saving = false;
  bool _saveFailed = false;

  static const String _endNote =
      'np. rozwód albo rozstanie. Owdowienie to zgon osoby — zapisuje się w jej '
      'wpisie.';

  bool get _parents => widget.kind == UnionWizardKind.parents;
  _Step get _step => _steps.last;

  @override
  void dispose() {
    for (final _Party? p in [_partner, _mother, _father]) {
      p?.newPerson?.dispose();
    }
    _startInput.dispose();
    _weddingInput.dispose();
    _endInput.dispose();
    super.dispose();
  }

  void _go(_Step step) {
    setState(() {
      _steps.add(step);
      _orderError = null;
      _saveFailed = false;
    });
    // A date step is one date: the cursor in it at once, its key does the step's button (ui review).
    final DateInput? date = switch (step) {
      _Step.marriage => _weddingInput,
      _Step.end => _endInput,
      _ => null,
    };
    if (date != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) date.fromNode.requestFocus();
      });
    }
  }

  /// "Kto jest mamą?" answered "Nie wiem": the father alone with the child is no union to tell, so choosing
  /// him writes at once, as "Nie wiem" for the father does (rodzina.md C-r2; ui review).
  bool get _fatherAlone => _parents && _mother == null;

  /// Back a step; on the first one, the wizard closes.
  Future<void> _back() async {
    if (_steps.length == 1) return _close();
    setState(() {
      final _Step left = _steps.removeLast();
      // Leaving a step takes back what it told.
      switch (left) {
        case _Step.whoNew:
          _partner?.newPerson?.dispose();
          _partner = null;
        case _Step.motherNew:
          _mother?.newPerson?.dispose();
          _mother = null;
        case _Step.fatherNew:
          _father?.newPerson?.dispose();
          _father = null;
        case _Step.kind:
          _kind = null;
          if (_steps.last == _Step.who) _partner = null;
          if (_steps.last == _Step.father) _father = null;
        case _Step.next:
          _together = null;
          _married = false;
          _marriage = null;
        case _Step.marriage || _Step.end:
          break;
        case _Step.who || _Step.mother || _Step.father:
          break;
      }
      _orderError = null;
    });
  }

  Future<void> _close() async {
    final bool told = _steps.length > 1;
    if (told && !await confirmAbandon(context)) return;
    if (mounted) Navigator.of(context).pop();
  }

  String get _title {
    final String what = _parents
        ? 'Dodaj rodziców'
        : widget.another
        ? 'Kolejny partner'
        : 'Dodaj partnera';
    final bool alone =
        _fatherAlone && (_step == _Step.father || _step == _Step.fatherNew);
    final int total = alone ? 2 : (_parents ? 4 : 3);
    final int step = switch (_step) {
      _Step.who || _Step.whoNew || _Step.mother || _Step.motherNew => 1,
      _Step.father || _Step.fatherNew => 2,
      _Step.kind => _parents ? 3 : 2,
      _Step.next || _Step.marriage || _Step.end => _parents ? 4 : 3,
    };
    return '$what · krok $step z $total';
  }

  /// "Maria i Jan · razem od 1946" — the pair and what is told of their union.
  String _sofar() {
    final String pair = _parents
        ? [?_mother?.shortName, ?_father?.shortName].join(' i ')
        : '${shortPersonName(widget.self.givenNames, widget.self.surname)} i '
              '${_partner?.shortName ?? ''}';
    // The timeline once its start is told (C3 on): on C2 the choice is not told yet.
    final bool told = switch (_step) {
      _Step.next || _Step.marriage || _Step.end => true,
      _ => false,
    };
    final String timeline = !told
        ? ''
        : unionTimeline(
            together: _together,
            married: _married,
            marriage: _marriage,
            ended: _ended,
            end: _end,
          );
    return timeline.isEmpty ? pair : '$pair · $timeline';
  }

  Map<int, String> get _unavailable => {
    for (final int id in widget.partnersAlready) id: 'już partner tej osoby',
    if (_mother?.id case final int id) id: 'już wybrana jako mama',
    widget.self.id: 'ta osoba',
  };

  NewPersonInput _newPerson(String typed, {Sex? sex}) => NewPersonInput(
    given: typed,
    surname: widget.self.surname ?? '',
    sex: sex,
  );

  void _picked(
    PickedMember picked, {
    required _Step thenNew,
    required _Step thenNext,
  }) {
    switch (picked) {
      case PickedPerson(:final PersonChoice choice):
        _setParty(thenNew, _Party.existing(choice));
        if (thenNew == _Step.fatherNew && _fatherAlone) {
          _save();
        } else {
          _go(thenNext);
        }
      case PickedNew(:final String text):
        _setParty(
          thenNew,
          _Party.typed(
            _newPerson(
              text,
              sex: switch (thenNew) {
                _Step.motherNew => Sex.female,
                _Step.fatherNew => Sex.male,
                _ => null,
              },
            ),
          ),
        );
        _go(thenNew);
    }
  }

  void _setParty(_Step newStep, _Party party) {
    switch (newStep) {
      case _Step.motherNew:
        _mother = party;
      case _Step.fatherNew:
        _father = party;
      default:
        _partner = party;
    }
  }

  void _newPersonDone(_Party? party, _Step next) {
    if (party?.newPerson case final NewPersonInput p when !p.validate()) {
      setState(() {});
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (party == _father && _fatherAlone) {
      _save();
    } else {
      _go(next);
    }
  }

  void _chooseKind(_Kind kind) {
    setState(() => _kind = kind);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startDateInput.fromNode.requestFocus();
    });
  }

  DateInput get _startDateInput =>
      _kind == _Kind.together ? _startInput : _weddingInput;

  /// C2 "Dalej" or "Nie znam daty": the start of the union, then C3.
  void _startDone({required bool known}) {
    final DateInput input = _startDateInput;
    QualifiedDate? date;
    if (known) {
      final DateRead read = input.read();
      if (read.error != null) {
        setState(() => input.showError = true);
        (read.toBad ? input.toNode : input.fromNode).requestFocus();
        return;
      }
      date = read.date;
    } else {
      input.from.clear();
      input.to.clear();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (_kind == _Kind.together) {
      _together = date;
    } else {
      _married = true;
      _marriage = date;
    }
    _go(_Step.next);
  }

  /// C3a: the wedding after living together, never before it.
  void _weddingDone({required bool known}) {
    QualifiedDate? date;
    if (known) {
      final DateRead read = _weddingInput.read();
      if (read.error != null) {
        setState(() => _weddingInput.showError = true);
        _weddingInput.fromNode.requestFocus();
        return;
      }
      date = read.date;
      if (date != null &&
          _together != null &&
          dateOrderKey(date) < dateOrderKey(_together!)) {
        setState(() => _orderError = 'Ślub nie może być przed „Razem od”.');
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _married = true;
      _marriage = date;
    });
    _steps.removeLast(); // back to C3, which now offers no wedding
    setState(() {});
  }

  /// C3b: the end, never before the start; then the union is written.
  Future<void> _endDone({required bool known}) async {
    QualifiedDate? date;
    if (known) {
      final DateRead read = _endInput.read();
      if (read.error != null) {
        setState(() => _endInput.showError = true);
        _endInput.fromNode.requestFocus();
        return;
      }
      date = read.date;
      final QualifiedDate? start = _together ?? _marriage;
      if (date != null &&
          start != null &&
          dateOrderKey(date) < dateOrderKey(start)) {
        setState(
          () => _orderError = 'Koniec nie może być przed początkiem związku.',
        );
        return;
      }
    }
    _ended = true;
    _end = date;
    await _save();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final NavigatorState navigator = Navigator.of(context);
    try {
      await saveFamily(
        widget.database,
        _parents
            ? FamilyDraft(
                partners: [?_mother?.draft, ?_father?.draft],
                children: [ExistingMember(widget.self.id)],
                together: _together,
                married: _married,
                marriage: _marriage,
                ended: _ended,
                end: _end,
              )
            : FamilyDraft(
                partners: [ExistingMember(widget.self.id), _partner!.draft],
                children: const [],
                together: _together,
                married: _married,
                marriage: _marriage,
                ended: _ended,
                end: _end,
              ),
      );
      navigator.pop();
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
          // A failed end is told again; the steps stay.
          if (_step == _Step.end) _ended = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: switch (_step) {
      _Step.who => _pickerStep(
        'Z kim w związku?',
        sofar: personName(
          widget.self.givenNames,
          widget.self.surname,
          birthSurname: widget.self.birthSurname,
        ),
        onPicked: (p) =>
            _picked(p, thenNew: _Step.whoNew, thenNext: _Step.kind),
      ),
      _Step.whoNew => _newStep('Nowa osoba', _partner, _Step.kind),
      _Step.mother => _pickerStep(
        'Kto jest mamą?',
        sofar: personName(widget.self.givenNames, widget.self.surname),
        extra: OptionCard(
          icon: Icons.help_outline,
          title: 'Nie wiem',
          subtitle: 'przejdź do taty',
          onTap: () => _go(_Step.father),
        ),
        onPicked: (p) =>
            _picked(p, thenNew: _Step.motherNew, thenNext: _Step.father),
      ),
      _Step.motherNew => _newStep('Nowa osoba — mama', _mother, _Step.father),
      _Step.father => _pickerStep(
        'Kto jest tatą?',
        sofar: _mother == null ? null : 'Mama: ${_mother!.shortName}',
        // Without a father there is no union to tell: "Nie wiem" writes the mother and the child at
        // once (rodzina.md C-r2). Without a mother either, there is nothing to write.
        extra: _mother == null
            ? null
            : OptionCard(
                icon: Icons.help_outline,
                title: 'Nie wiem — zapisz',
                subtitle: 'dodasz go później przez ✎',
                onTap: _saving ? null : _save,
              ),
        onPicked: (p) =>
            _picked(p, thenNew: _Step.fatherNew, thenNext: _Step.kind),
      ),
      _Step.fatherNew => _newStep(
        'Nowa osoba — tata',
        _father,
        _Step.kind,
        primary: _fatherAlone ? 'Zapisz' : 'Dalej',
      ),
      _Step.kind => _kindStep(),
      _Step.next => _nextStep(),
      _Step.marriage => _dateStep(
        'Kiedy był ślub?',
        _weddingInput,
        primary: 'Dalej',
        onDone: _weddingDone,
      ),
      _Step.end => _dateStep(
        'Kiedy związek się zakończył?',
        _endInput,
        note: _endNote,
        primary: 'Zapisz',
        onDone: _endDone,
      ),
    },
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SheetHeader(title: _title, onBack: _back, onClose: _close),
  );

  /// C1, C-r1, C-r2: the question over the list of people, tall — the list needs the room.
  Widget _pickerStep(
    String question, {
    String? sofar,
    Widget? extra,
    required ValueChanged<PickedMember> onPicked,
  }) => SheetPage(
    header: _header(),
    above: [
      StepQuestion(question, sofar: sofar),
      if (extra != null)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: extra),
      if (_saveFailed)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ErrorLine('Nie udało się zapisać. Spróbuj jeszcze raz.'),
        ),
    ],
    list: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PersonChoiceList(
        database: widget.database,
        unavailable: _unavailable,
        graveId: widget.graveId,
        onPicked: onPicked,
      ),
    ),
  );

  /// C1': a new person, "Dalej" to the next step.
  Widget _newStep(
    String question,
    _Party? party,
    _Step next, {
    String primary = 'Dalej',
  }) => SheetPage(
    header: _header(),
    body: [
      StepQuestion(question),
      if (party?.newPerson case final NewPersonInput p)
        NewPersonFields(input: p, onDone: () => _newPersonDone(party, next)),
    ],
    actions: StepActions(
      primary: primary,
      onPrimary: () => _newPersonDone(party, next),
      busy: _saving,
      error: _saveFailed ? 'Nie udało się zapisać. Spróbuj jeszcze raz.' : null,
    ),
  );

  /// C2: "Razem" or "Małżeństwo", then the date of its start.
  Widget _kindStep() => SheetPage(
    header: _header(),
    body: [
      StepQuestion('Jaki to był związek?', sofar: _sofar()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionCard(
              icon: Icons.favorite_border,
              title: 'Razem',
              subtitle: 'bez ślubu — ślub możesz dodać w następnym kroku',
              selected: _kind == _Kind.together,
              onTap: () => _chooseKind(_Kind.together),
            ),
            OptionCard(
              icon: Icons.diamond_outlined,
              title: 'Małżeństwo',
              subtitle: 'od ślubu',
              selected: _kind == _Kind.married,
              onTap: () => _chooseKind(_Kind.married),
            ),
            if (_kind != null) ...[
              const SizedBox(height: 16),
              DateBlock(
                input: _startDateInput,
                onDone: () => _startDone(known: true),
                onChanged: () =>
                    setState(() => _startDateInput.showError = false),
              ),
            ],
          ],
        ),
      ),
    ],
    actions: _kind == null
        ? null
        : StepActions(
            primary: 'Dalej',
            onPrimary: () => _startDone(known: true),
            secondary: 'Nie znam daty',
            onSecondary: () => _startDone(known: false),
          ),
  );

  /// C3: what came next — the wedding (until there is one), the end, or nothing more.
  Widget _nextStep() => SheetPage(
    header: _header(),
    body: [
      StepQuestion('Co było dalej?', sofar: _sofar()),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_married)
              OptionCard(
                icon: Icons.diamond_outlined,
                title: 'Wzięli ślub',
                subtitle: 'związek staje się małżeństwem',
                onTap: () => _go(_Step.marriage),
              ),
            OptionCard(
              icon: Icons.call_split_outlined,
              title: 'Związek się zakończył',
              subtitle: 'rozwód albo rozstanie',
              onTap: () => _go(_Step.end),
            ),
            OptionCard(
              icon: Icons.check,
              title: 'Nic więcej — zapisz',
              subtitle: _parents
                  ? 'rodzice pojawią się w sekcji „Rodzina”'
                  : 'partner pojawi się w sekcji „Rodzina”',
              onTap: _saving ? null : _save,
            ),
            if (_saveFailed) ...[
              const SizedBox(height: 12),
              const ErrorLine('Nie udało się zapisać. Spróbuj jeszcze raz.'),
            ],
          ],
        ),
      ),
    ],
  );

  /// C3a, C3b: one date, "Nie znam daty" and the step's button.
  Widget _dateStep(
    String question,
    DateInput input, {
    String? note,
    required String primary,
    required void Function({required bool known}) onDone,
  }) => SheetPage(
    header: _header(),
    body: [
      StepQuestion(question, sofar: _sofar()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DateBlock(
          input: input,
          note: note,
          error: _orderError,
          onDone: () => onDone(known: true),
          onChanged: () => setState(() {
            input.showError = false;
            _orderError = null;
          }),
        ),
      ),
    ],
    actions: StepActions(
      primary: primary,
      onPrimary: () => onDone(known: true),
      secondary: 'Nie znam daty',
      onSecondary: () => onDone(known: false),
      busy: _saving,
      error: _saveFailed ? 'Nie udało się zapisać. Spróbuj jeszcze raz.' : null,
    ),
  );
}
