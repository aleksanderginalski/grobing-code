import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../dates.dart';
import '../theme.dart';

// The date block of style B forms — label, qualifier, date (two for "między") and preview
// (05_DESIGN/wpis-osoby.md, elements b–e) — shared by the person form and the family sheet
// (05_DESIGN/rodzina.md A5, A6'; ISSUE-019).

/// Text typed into a style B field: ≥ 16 sp (style-b.md → Thresholds).
const TextStyle inputTextStyle = TextStyle(
  color: GrobingColors.text,
  fontSize: 16,
);

const String _badDate =
    'Nie rozumiem tej daty — wpisz rok, mm.rrrr albo dd.mm.rrrr.';

/// An error under a field: the error colour with its icon, never colour alone (SC 1.4.1).
class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});

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
class DateInput {
  DateInput(this.label, QualifiedDate? initial, {required this.readOnly})
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
  DateRead read() {
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

typedef DateRead = ({QualifiedDate? date, String? error, bool toBad});

const Map<DateQualifier, String> _qualifierLabels = {
  DateQualifier.exact: 'dokładnie',
  DateQualifier.about: 'około',
  DateQualifier.before: 'przed',
  DateQualifier.after: 'po',
  DateQualifier.between: 'między',
};

/// Elements 5–7, the date block: label, qualifier, date (and the second one for "między"), and the
/// preview — the date exactly as the grave will show it.
class DateBlock extends StatelessWidget {
  const DateBlock({
    super.key,
    required this.input,
    required this.onChanged,
    this.note,
  });

  final DateInput input;
  final VoidCallback onChanged;

  /// A line under the label — "np. rozwód albo rozstanie…" at the end of a union (05_DESIGN/rodzina.md A6').
  final String? note;

  DateInput get d => input;

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
    final DateRead r = d.read();
    final bool fromBad = d.showError && r.error != null && !r.toBad;
    final bool toBad = d.showError && r.error != null && r.toBad;
    return _RevealOnError(
      showing: d.showError && r.error != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.label, style: _muted),
          if (note case final String note)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
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
              child: ErrorLine(r.error!),
            )
          else if (r.date != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text('→ ${formatDate(r.date!)}', style: _muted),
            ),
        ],
      ),
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
    // When the keyboard comes up, the field scrolls into view with room below it for the error line
    // (ui review, ISSUE-019).
    scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]')),
      LengthLimitingTextInputFormatter(10),
    ],
    textInputAction: TextInputAction.next,
    style: inputTextStyle,
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
          style: inputTextStyle,
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

/// Brings the whole block into view when its error appears — the message line under the fields too,
/// above whatever is pinned below the form ("Zapisz" over the keyboard). Focusing the field scrolls only
/// the field, and a field already focused does not scroll at all (ui review, ISSUE-019: the message hid
/// behind "Zapisz").
class _RevealOnError extends StatefulWidget {
  const _RevealOnError({required this.showing, required this.child});

  final bool showing;
  final Widget child;

  @override
  State<_RevealOnError> createState() => _RevealOnErrorState();
}

class _RevealOnErrorState extends State<_RevealOnError> {
  @override
  void didUpdateWidget(_RevealOnError old) {
    super.didUpdateWidget(old);
    if (widget.showing && !old.showing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
