import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/deletion.dart';
import '../external_link.dart' show recommendedTimeout;
import '../theme.dart';
import 'date_block.dart' show ErrorLine;
import 'glyphs.dart';
import 'grobing_icon.dart';

// What every deletion looks like (ISSUE-053; 05_DESIGN/brand/style-b.md rule 16): "Usuń …" only in a correction,
// a window that says what goes and what stays, and the bar with "Cofnij" on the screen one comes back to.

/// "Usuń …" (rule 16): a text button with the bin in the text colour — not amber, which is the main action's,
/// and not the error's, which is a state; a target of 48 dp.
class DeleteButton extends StatelessWidget {
  const DeleteButton(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: GrobingColors.text,
      iconColor: GrobingColors.text,
      minimumSize: const Size(48, 48),
    ),
    onPressed: onPressed,
    icon: const GrobingIcon(Glyphs.delete),
    label: Text(label),
  );
}

/// A window's buttons (cmentarze.md 15a, grob.md 3d): "Usuń …" on the first line at the left, the rest under it
/// at the right. Two lines always: in a window on a phone the three did not fit one line even at 100% text (dev
/// pass, 411 dp), and a row that wraps put "Usuń …" at the right, next to the window's main action.
class DeletionActions extends StatelessWidget {
  const DeletionActions({
    super.key,
    required this.delete,
    required this.actions,
  });

  final Widget delete;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.maxFinite,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: delete),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OverflowBar(
            spacing: 8,
            overflowAlignment: OverflowBarAlignment.end,
            children: actions,
          ),
        ),
      ],
    ),
  );
}

/// The window "Usunąć …?" (rule 16): [content] says what goes and what stays — only what the thing has — and
/// "Anuluj" · "Usuń" stand in the text colour, neither inviting. "Usuń" runs [delete] with the window open; when
/// it fails the window stays and says so. Returns what [delete] returned; null when cancelled.
Future<T?> confirmDeletion<T extends Object>(
  BuildContext context, {
  required String title,
  required List<Widget> content,
  required Future<T> Function() delete,
}) => showDialog<T>(
  context: context,
  builder: (_) =>
      _DeletionDialog<T>(title: title, content: content, delete: delete),
);

class _DeletionDialog<T extends Object> extends StatefulWidget {
  const _DeletionDialog({
    required this.title,
    required this.content,
    required this.delete,
  });

  final String title;
  final List<Widget> content;
  final Future<T> Function() delete;

  @override
  State<_DeletionDialog<T>> createState() => _DeletionDialogState<T>();
}

class _DeletionDialogState<T extends Object> extends State<_DeletionDialog<T>> {
  bool _deleting = false;
  bool _failed = false;

  /// The words scroll under the title with a bar always shown: at 200% on 360 dp "what stays" fell under the
  /// edge with nothing saying there was more (ui review of ISSUE-053; the precedent — mode F's card, ISSUE-028).
  final ScrollController _words = ScrollController();

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _failed = false;
    });
    try {
      final T taken = await widget.delete();
      if (mounted) Navigator.of(context).pop(taken);
    } on Object {
      if (mounted) {
        setState(() {
          _deleting = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle quiet = TextButton.styleFrom(
      foregroundColor: GrobingColors.text,
      minimumSize: const Size(48, 48),
    );
    return AlertDialog(
      backgroundColor: GrobingColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.title,
        style: const TextStyle(
          color: GrobingColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Scrollbar(
        controller: _words,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _words,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widget.content,
              if (_failed) ...[
                const SizedBox(height: 12),
                const ErrorLine('Nie udało się usunąć. Spróbuj jeszcze raz.'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: quiet,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          style: quiet,
          onPressed: _deleting ? null : _delete,
          child: const Text('Usuń'),
        ),
      ],
    );
  }
}

/// A sentence of the window, 16 sp in the text colour.
class DeletionText extends StatelessWidget {
  const DeletionText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: GrobingColors.text, fontSize: 16),
    ),
  );
}

/// What stays, under the rest — 14 sp, the muted text.
class DeletionNote extends StatelessWidget {
  const DeletionNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
    ),
  );
}

/// What goes, one line each: ", " after all but the last, "." after it.
class DeletionList extends StatelessWidget {
  const DeletionList(this.items, {super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '•  ',
                  style: TextStyle(color: GrobingColors.text, fontSize: 16),
                ),
                Expanded(
                  child: Text(
                    '${items[i]}${i == items.length - 1 ? '.' : ','}',
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// "a", "a i b", "a, b i c" — a hard space after "i" (style-b.md rule 6).
String andList(List<String> items) => switch (items) {
  [] => '',
  [final String one] => one,
  _ => '${items.sublist(0, items.length - 1).join(', ')} i\u00A0${items.last}',
};

/// "z planem" but "ze zdjęciem", with a hard space: "z" before a cluster becomes "ze" — of the words these windows
/// list, before "zdjęciem" and "zdjęciami".
String withWord(String first) =>
    first.startsWith('zdj') ? 'ze\u00A0' : 'z\u00A0';

/// How long the bar with "Cofnij" stays (K2 — the author at stop #1 of ISSUE-053: "tak K2 4s").
const Duration undoBarTime = Duration(seconds: 4);

/// The bar after a deletion (K2; style-b.md rule 16): "Usunięto …" and "Cofnij" for [undoBarTime], or as long as
/// "Czas na działanie" asks; with a screen reader on it stays until it is touched (SC 2.2.1). Flutter 3.41 keeps
/// every bar with an action until it is touched (`SnackBar.persist` defaults to true then — dev pass: the bar was
/// still there after a minute), so the time is given here. On the surface with an outline, so the text and amber
/// "Cofnij" keep their contrast (the app's other bars are light). "Cofnij" puts back what [snapshot] took, then
/// [onRestored].
Future<void> showUndoBar(
  ScaffoldMessengerState messenger, {
  required GrobingDatabase database,
  required String message,
  required DeletionSnapshot snapshot,
  VoidCallback? onRestored,
}) async {
  final Duration time = await recommendedTimeout(undoBarTime);
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _bar(
        messenger,
        time: time,
        message: message,
        action: SnackBarAction(
          label: 'Cofnij',
          textColor: GrobingColors.amber,
          onPressed: () async {
            try {
              await restoreDeletion(database, snapshot);
              onRestored?.call();
            } on RestoreRefused {
              // Someone taken out of a grave lies in another one now (grob.md D23): no "Cofnij" can help.
              if (!messenger.mounted) return;
              messenger.showSnackBar(
                _bar(
                  messenger,
                  time: time,
                  message:
                      'Nie da się cofnąć — ta osoba leży już w\u00A0innym grobie.',
                ),
              );
            } on Object {
              // The same bar again (ui review of ISSUE-053): "Cofnij" can be tried once more.
              await showUndoBar(
                messenger,
                database: database,
                message: 'Nie udało się cofnąć.',
                snapshot: snapshot,
                onRestored: onRestored,
              );
            }
          },
        ),
      ),
    );
}

/// A bar of rule 16: on the surface with an outline, the text in the text colour.
SnackBar _bar(
  ScaffoldMessengerState messenger, {
  required Duration time,
  required String message,
  SnackBarAction? action,
}) => SnackBar(
  duration: time,
  persist:
      action != null && MediaQuery.accessibleNavigationOf(messenger.context),
  behavior: SnackBarBehavior.floating,
  backgroundColor: GrobingColors.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    side: const BorderSide(color: GrobingColors.outline),
  ),
  content: Text(
    message,
    style: const TextStyle(color: GrobingColors.text, fontSize: 14),
  ),
  action: action,
);
