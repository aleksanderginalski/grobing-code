import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/date_block.dart';
import 'person_choice_list.dart';
import 'union_wizard.dart';

/// D of 05_DESIGN/rodzina.md v2 — the summary of one union, from ✎ on its card or by "Rodzice": each row
/// of the timeline changes alone, through one step of the wizard, without going through it all (D16).
/// Each change is written at once, as the wizard writes (D1), and the rows show it.
Future<void> showUnionSummary(
  BuildContext context, {
  required GrobingDatabase database,
  required int familyId,
  required int selfId,
  required bool parents,
  int? graveId,
}) => showFamilySheet<void>(
  context,
  builder: (_) => _UnionSummary(
    database: database,
    familyId: familyId,
    selfId: selfId,
    parents: parents,
    graveId: graveId,
  ),
);

/// What a row of the summary changes.
sealed class _Edit {
  const _Edit();
}

/// A person of the pair — [replacing] null adds the second one.
class _EditPerson extends _Edit {
  const _EditPerson(this.replacing, this.label);

  final int? replacing;
  final String label;
}

class _EditNew extends _Edit {
  const _EditNew(this.replacing, this.input);

  final int? replacing;
  final NewPersonInput input;
}

enum _DateField { together, marriage, end }

class _EditDate extends _Edit {
  _EditDate(this.field, DatedFact fact, String label)
    : input = DateInput(label, fact.date, readOnly: !fact.correctable);

  final _DateField field;
  final DateInput input;
}

class _UnionSummary extends StatefulWidget {
  const _UnionSummary({
    required this.database,
    required this.familyId,
    required this.selfId,
    required this.parents,
    this.graveId,
  });

  final GrobingDatabase database;
  final int familyId;

  /// The person whose form opened the summary: never removed here — the union is theirs.
  final int selfId;
  final bool parents;
  final int? graveId;

  @override
  State<_UnionSummary> createState() => _UnionSummaryState();
}

class _UnionSummaryState extends State<_UnionSummary> {
  FamilyDetail? _family;
  _Edit? _edit;
  String? _orderError;
  bool _saving = false;
  bool _saveFailed = false;

  static const String _endNote =
      'np. rozwód albo rozstanie. Owdowienie to zgon osoby — zapisuje się w jej '
      'wpisie.';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _disposeEdit();
    super.dispose();
  }

  void _disposeEdit() {
    switch (_edit) {
      case _EditNew(:final NewPersonInput input):
        input.dispose();
      case _EditDate(:final DateInput input):
        input.dispose();
      case _EditPerson() || null:
        break;
    }
  }

  Future<void> _reload() async {
    final FamilyDetail? family = await loadFamily(
      widget.database,
      widget.familyId,
    );
    if (!mounted) return;
    if (family == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _family = family);
  }

  void _open(_Edit edit) {
    setState(() {
      _disposeEdit();
      _edit = edit;
      _orderError = null;
      _saveFailed = false;
    });
    // One date to change: the cursor in it at once (ui review), unless another source keeps it.
    if (edit case _EditDate(:final DateInput input) when !input.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) input.fromNode.requestFocus();
      });
    }
  }

  void _closeEdit() => setState(() {
    _disposeEdit();
    _edit = null;
    _orderError = null;
    _saveFailed = false;
  });

  /// The family as it is now, with [change] applied, written all or nothing.
  Future<void> _write(
    FamilyDraft Function(FamilyDetail f, FamilyDraft now) change,
  ) async {
    final FamilyDetail f = _family!;
    final FamilyDraft now = FamilyDraft(
      familyId: f.id,
      partners: [for (final FamilyMember p in f.partners) ExistingMember(p.id)],
      children: [for (final FamilyMember c in f.children) ExistingMember(c.id)],
      together: f.together.date,
      married: f.married,
      marriage: f.marriage.date,
      ended: f.ended,
      end: f.end.date,
    );
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await saveFamily(widget.database, change(f, now));
      _disposeEdit();
      _edit = null;
      await _reload();
    } on Object {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  FamilyDraft _with(
    FamilyDraft d, {
    List<MemberDraft>? partners,
    List<MemberDraft>? children,
    QualifiedDate? Function()? together,
    bool? married,
    QualifiedDate? Function()? marriage,
    bool? ended,
    QualifiedDate? Function()? end,
  }) => FamilyDraft(
    familyId: d.familyId,
    partners: partners ?? d.partners,
    children: children ?? d.children,
    together: together == null ? d.together : together(),
    married: married ?? d.married,
    marriage: marriage == null ? d.marriage : marriage(),
    ended: ended ?? d.ended,
    end: end == null ? d.end : end(),
  );

  List<MemberDraft> _partnersWith(
    FamilyDetail f,
    int? replacing,
    MemberDraft person,
  ) => [
    for (final FamilyMember p in f.partners)
      if (p.id == replacing) person else ExistingMember(p.id),
    if (replacing == null) person,
  ];

  void _picked(_EditPerson edit, PickedMember picked) {
    switch (picked) {
      case PickedPerson(:final PersonChoice choice):
        _write(
          (f, d) => _with(
            d,
            partners: _partnersWith(
              f,
              edit.replacing,
              ExistingMember(choice.id),
            ),
          ),
        );
      case PickedNew(:final String text):
        final FamilyMember? self = _family!.partners
            .where((p) => p.id == widget.selfId)
            .firstOrNull;
        _open(
          _EditNew(
            edit.replacing,
            NewPersonInput(
              given: text,
              surname: (self ?? _family!.children.firstOrNull)?.surname ?? '',
              sex: switch (edit.label) {
                'Mama' => Sex.female,
                'Tata' => Sex.male,
                _ => null,
              },
            ),
          ),
        );
    }
  }

  void _newDone(_EditNew edit) {
    if (!edit.input.validate()) {
      setState(() {});
      return;
    }
    _write(
      (f, d) => _with(
        d,
        partners: _partnersWith(f, edit.replacing, edit.input.draft),
      ),
    );
  }

  /// The date of [edit] as typed, or null with the error shown.
  ({bool ok, QualifiedDate? date}) _read(_EditDate edit) {
    final DateRead read = edit.input.read();
    if (read.error != null) {
      setState(() => edit.input.showError = true);
      (read.toBad ? edit.input.toNode : edit.input.fromNode).requestFocus();
      return (ok: false, date: null);
    }
    return (ok: true, date: read.date);
  }

  /// The order of the timeline: the wedding not before "Razem od", the end not before the start.
  String? _orderProblem(_DateField field, QualifiedDate? date) {
    final FamilyDetail f = _family!;
    if (date == null) return null;
    final int key = dateOrderKey(date);
    switch (field) {
      case _DateField.together:
        if (f.marriage.date case final QualifiedDate m
            when dateOrderKey(m) < key) {
          return 'Ślub nie może być przed „Razem od”.';
        }
      case _DateField.marriage:
        if (f.together.date case final QualifiedDate t
            when key < dateOrderKey(t)) {
          return 'Ślub nie może być przed „Razem od”.';
        }
      case _DateField.end:
        final QualifiedDate? start = f.together.date ?? f.marriage.date;
        if (start != null && key < dateOrderKey(start)) {
          return 'Koniec nie może być przed początkiem związku.';
        }
    }
    return null;
  }

  /// "Zapisz" of a date row; [known] false is "Nie znam daty": the event happened, its date is not known.
  void _dateDone(_EditDate edit, {required bool known}) {
    QualifiedDate? date;
    if (known) {
      final ({bool ok, QualifiedDate? date}) r = _read(edit);
      if (!r.ok) return;
      date = r.date;
      final String? problem = _orderProblem(edit.field, date);
      if (problem != null) {
        setState(() => _orderError = problem);
        return;
      }
    }
    _write(
      (f, d) => switch (edit.field) {
        // "Razem od" without a date is no "Razem od": the union is together anyway.
        _DateField.together => _with(d, together: () => date),
        _DateField.marriage => _with(d, married: true, marriage: () => date),
        _DateField.end => _with(d, ended: true, end: () => date),
      },
    );
  }

  /// "To nie było małżeństwo", "Usuń koniec", "Usuń" of "Razem od": the event goes.
  void _dateRemove(_EditDate edit) => _write(
    (f, d) => switch (edit.field) {
      _DateField.together => _with(d, together: () => null),
      _DateField.marriage => _with(d, married: false, marriage: () => null),
      _DateField.end => _with(d, ended: false, end: () => null),
    },
  );

  void _removeChild(FamilyMember child) => _write(
    (f, d) => _with(
      d,
      children: [
        for (final FamilyMember c in f.children)
          if (c.id != child.id) ExistingMember(c.id),
      ],
    ),
  );

  Future<void> _confirmDelete() async {
    final bool? deleted = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool failed = false;
        bool deleting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => familyDialog(
            context,
            title: 'Usunąć związek?',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Osoby zostają w aplikacji. Znikną tylko ich powiązania w tej '
                  'rodzinie i daty związku.',
                  style: TextStyle(color: GrobingColors.text, fontSize: 16),
                ),
                if (failed) ...[
                  const SizedBox(height: 12),
                  const ErrorLine(
                    'Nie udało się usunąć związku. Spróbuj jeszcze raz.',
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
                          await deleteFamily(widget.database, widget.familyId);
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
    if (deleted == true && mounted) Navigator.of(context).pop();
  }

  /// "Maria i Jan", "Zofia i Józef" — the pair, by their first names.
  String get _pairName {
    final FamilyDetail f = _family!;
    final List<FamilyMember> pair = widget.parents
        ? f.partners
        : [
            ...f.partners.where((p) => p.id == widget.selfId),
            ...f.partners.where((p) => p.id != widget.selfId),
          ];
    return pair
        .map((p) => shortPersonName(p.givenNames, p.surname))
        .join(' i ');
  }

  /// "Partner", or for parents "Mama", "Tata" — from the person's sex; unknown, "Rodzic".
  String _personLabel(FamilyMember m) => !widget.parents
      ? 'Partner'
      : switch (m.sex) {
          Sex.female => 'Mama',
          Sex.male => 'Tata',
          null => 'Rodzic',
        };

  @override
  Widget build(BuildContext context) {
    final FamilyDetail? f = _family;
    if (f == null) return const SizedBox.shrink();
    return PopScope(
      canPop: _edit == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeEdit();
      },
      child: switch (_edit) {
        null => _summary(f),
        final _EditPerson e => _pickerView(e),
        final _EditNew e => _newView(e),
        final _EditDate e => _dateView(e),
      },
    );
  }

  Widget _summary(FamilyDetail f) {
    final List<FamilyMember> others = [
      for (final FamilyMember p in f.partners)
        if (widget.parents || p.id != widget.selfId) p,
    ];
    final int people = f.partners.length + f.children.length;
    return SheetPage(
      header: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SheetHeader(
          title: widget.parents ? 'Związek rodziców' : 'Związek',
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
      body: [
        StepQuestion(_pairName),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final FamilyMember p in others)
                _row(
                  _personLabel(p),
                  personName(p.givenNames, p.surname),
                  () => _open(_EditPerson(p.id, _personLabel(p))),
                ),
              if (f.partners.length < 2)
                _row(
                  widget.parents ? 'Rodzic' : 'Partner',
                  null,
                  () => _open(
                    _EditPerson(null, widget.parents ? 'Rodzic' : 'Partner'),
                  ),
                ),
              _row(
                'Razem od',
                f.together.date == null ? null : formatDate(f.together.date!),
                () => _open(
                  _EditDate(_DateField.together, f.together, 'Razem od'),
                ),
              ),
              _row(
                'Ślub',
                !f.married
                    ? null
                    : f.marriage.date == null
                    ? 'bez daty'
                    : formatDate(f.marriage.date!),
                () => _open(_EditDate(_DateField.marriage, f.marriage, 'Ślub')),
              ),
              _row(
                'Koniec',
                !f.ended
                    ? null
                    : f.end.date == null
                    ? 'bez daty'
                    : formatDate(f.end.date!),
                () => _open(_EditDate(_DateField.end, f.end, 'Koniec związku')),
              ),
              if (f.children.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  widget.parents ? 'Dzieci' : 'Dzieci z tego związku',
                  style: const TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final FamilyMember c in f.children)
                  _childRow(c, removable: c.id != widget.selfId && people > 2),
              ],
              if (_saveFailed) ...[
                const SizedBox(height: 12),
                const ErrorLine('Nie udało się zapisać. Spróbuj jeszcze raz.'),
              ],
            ],
          ),
        ),
      ],
      actions: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Usuń związek'),
            ),
            StepActionsButton(
              label: 'Gotowe',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// A row ≥ 56 dp: label · value (or "Dodaj" in amber) · chevron; the whole row one target.
  Widget _row(
    String label,
    String? value,
    VoidCallback onTap,
  ) => MergeSemantics(
    child: Semantics(
      button: true,
      child: InkWell(
        onTap: _saving ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: GrobingColors.outline)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value ?? 'Dodaj',
                  style: TextStyle(
                    color: value == null
                        ? GrobingColors.amber
                        : GrobingColors.text,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: GrobingColors.textMuted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _childRow(FamilyMember c, {required bool removable}) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Row(
      children: [
        Expanded(
          child: Text(
            c.id == widget.selfId
                ? '${personName(c.givenNames, c.surname)} · ta osoba'
                : personName(c.givenNames, c.surname),
            style: const TextStyle(color: GrobingColors.text, fontSize: 16),
          ),
        ),
        if (removable)
          IconButton(
            icon: const Icon(Icons.close, color: GrobingColors.textMuted),
            tooltip: 'Usuń z tej rodziny',
            onPressed: _saving ? null : () => _removeChild(c),
          ),
      ],
    ),
  );

  Widget _editHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SheetHeader(title: title, onBack: _closeEdit, onClose: _closeEdit),
  );

  Widget _pickerView(_EditPerson e) {
    final FamilyDetail f = _family!;
    return SheetPage(
      header: _editHeader(_pairName),
      above: [
        StepQuestion(switch (e.label) {
          'Mama' => 'Kto jest mamą?',
          'Tata' => 'Kto jest tatą?',
          'Rodzic' => 'Kto jest drugim rodzicem?',
          _ => 'Z kim w związku?',
        }),
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
          graveId: widget.graveId,
          unavailable: {
            for (final FamilyMember m in [...f.partners, ...f.children])
              m.id: m.id == widget.selfId ? 'ta osoba' : 'już w tej rodzinie',
          },
          onPicked: (picked) => _picked(e, picked),
        ),
      ),
    );
  }

  Widget _newView(_EditNew e) => SheetPage(
    header: _editHeader(_pairName),
    body: [
      const StepQuestion('Nowa osoba'),
      NewPersonFields(input: e.input, onDone: () => _newDone(e)),
    ],
    actions: StepActions(
      primary: 'Zapisz',
      onPrimary: () => _newDone(e),
      busy: _saving,
      error: _saveFailed ? 'Nie udało się zapisać. Spróbuj jeszcze raz.' : null,
    ),
  );

  Widget _dateView(_EditDate e) {
    final FamilyDetail f = _family!;
    final (String question, String? remove) = switch (e.field) {
      _DateField.together => (
        'Od kiedy byli razem?',
        f.together.date == null ? null : 'Usuń',
      ),
      _DateField.marriage => (
        'Kiedy był ślub?',
        f.married ? 'To nie było małżeństwo' : null,
      ),
      _DateField.end => (
        'Kiedy związek się zakończył?',
        f.ended ? 'Usuń koniec' : null,
      ),
    };
    final bool canBeDateless = e.field != _DateField.together;
    return SheetPage(
      header: _editHeader(_pairName),
      body: [
        StepQuestion(question),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DateBlock(
                input: e.input,
                note: e.field == _DateField.end ? _endNote : null,
                error: _orderError,
                onDone: () => _dateDone(e, known: true),
                onChanged: () => setState(() {
                  e.input.showError = false;
                  _orderError = null;
                }),
              ),
              if (remove case final String remove)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: GrobingColors.text,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _saving ? null : () => _dateRemove(e),
                    child: Text(remove),
                  ),
                ),
            ],
          ),
        ),
      ],
      actions: e.input.readOnly
          ? null
          : StepActions(
              primary: 'Zapisz',
              onPrimary: () => _dateDone(e, known: true),
              secondary: canBeDateless ? 'Nie znam daty' : null,
              onSecondary: canBeDateless
                  ? () => _dateDone(e, known: false)
                  : null,
              busy: _saving,
              error: _saveFailed
                  ? 'Nie udało się zapisać. Spróbuj jeszcze raz.'
                  : null,
            ),
    );
  }
}
