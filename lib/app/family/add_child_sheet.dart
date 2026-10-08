import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/families.dart';
import '../../data/graves.dart';
import '../widgets/date_block.dart';
import 'person_choice_list.dart';
import 'union_wizard.dart';

/// E of 05_DESIGN/rodzina.md v2 — "Dodaj dziecko" on a union's card (C1, the author's choice at stop #1
/// of ISSUE-025): the child of this pair, chosen from the list or typed new, written at once with the
/// claim on its link (ADR-011). The pair is told by name without declining it — "Maria i Jan", not
/// "Marii i Jana": a wrong genitive of a name jars (grob.md D1).
Future<void> showAddChild(
  BuildContext context, {
  required GrobingDatabase database,
  required int familyId,
  required String pairName,
  String? suggestedSurname,
  int? graveId,
}) => showFamilySheet<void>(
  context,
  builder: (_) => _AddChild(
    database: database,
    familyId: familyId,
    pairName: pairName,
    suggestedSurname: suggestedSurname ?? '',
    graveId: graveId,
  ),
);

class _AddChild extends StatefulWidget {
  const _AddChild({
    required this.database,
    required this.familyId,
    required this.pairName,
    required this.suggestedSurname,
    this.graveId,
  });

  final GrobingDatabase database;
  final int familyId;
  final String pairName;
  final String suggestedSurname;
  final int? graveId;

  @override
  State<_AddChild> createState() => _AddChildState();
}

class _AddChildState extends State<_AddChild> {
  FamilyDetail? _family;
  NewPersonInput? _new;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    loadFamily(widget.database, widget.familyId).then((f) {
      if (!mounted) return;
      if (f == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _family = f);
      }
    });
  }

  @override
  void dispose() {
    _new?.dispose();
    super.dispose();
  }

  Future<void> _add(MemberDraft child) async {
    final FamilyDetail f = _family!;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final NavigatorState navigator = Navigator.of(context);
    try {
      await saveFamily(
        widget.database,
        FamilyDraft(
          familyId: f.id,
          partners: [
            for (final FamilyMember p in f.partners) ExistingMember(p.id),
          ],
          children: [
            for (final FamilyMember c in f.children) ExistingMember(c.id),
            child,
          ],
          together: f.together.date,
          married: f.married,
          marriage: f.marriage.date,
          ended: f.ended,
          end: f.end.date,
        ),
      );
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

  void _picked(PickedMember picked) {
    switch (picked) {
      case PickedPerson(:final PersonChoice choice):
        _add(ExistingMember(choice.id));
      case PickedNew(:final String text):
        setState(
          () => _new = NewPersonInput(
            given: text,
            surname: widget.suggestedSurname,
          ),
        );
    }
  }

  void _newDone() {
    final NewPersonInput p = _new!;
    if (!p.validate()) {
      setState(() {});
      return;
    }
    _add(p.draft);
  }

  void _back() {
    if (_new == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _new!.dispose();
      _new = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final FamilyDetail? f = _family;
    if (f == null) return const SizedBox.shrink();
    final Widget header = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SheetHeader(
        title: 'Dodaj dziecko',
        onBack: _back,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
    return PopScope(
      canPop: _new == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: switch (_new) {
        null => SheetPage(
          header: header,
          above: [
            StepQuestion('Dziecko tej pary', sofar: widget.pairName),
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
              forChild: true,
              familyId: f.id,
              unavailable: {
                for (final FamilyMember m in [...f.partners, ...f.children])
                  m.id: 'już w tej rodzinie',
              },
              onPicked: _saving ? (_) {} : _picked,
            ),
          ),
        ),
        final NewPersonInput p => SheetPage(
          header: header,
          body: [
            StepQuestion('Nowe dziecko', sofar: widget.pairName),
            NewPersonFields(input: p, onDone: _newDone),
          ],
          actions: StepActions(
            primary: 'Dodaj',
            onPrimary: _newDone,
            busy: _saving,
            error: _saveFailed
                ? 'Nie udało się zapisać. Spróbuj jeszcze raz.'
                : null,
          ),
        ),
      },
    );
  }
}
