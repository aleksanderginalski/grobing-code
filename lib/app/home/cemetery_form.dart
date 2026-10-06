import 'package:flutter/material.dart';

import '../theme.dart';

/// What the cemetery window returns.
typedef CemeteryFormValues = ({String name, String? locality});

/// The window "Nowy cmentarz" / "Popraw cmentarz" (05_DESIGN/cmentarze.md, element 15): name and an
/// optional locality, then "Dalej" to the pick mode. Null when cancelled.
Future<CemeteryFormValues?> showCemeteryForm(
  BuildContext context, {
  required String title,
  String name = '',
  String? locality,
}) => showDialog<CemeteryFormValues>(
  context: context,
  builder: (_) =>
      _CemeteryForm(title: title, name: name, locality: locality ?? ''),
);

class _CemeteryForm extends StatefulWidget {
  const _CemeteryForm({
    required this.title,
    required this.name,
    required this.locality,
  });

  final String title;
  final String name;
  final String locality;

  @override
  State<_CemeteryForm> createState() => _CemeteryFormState();
}

class _CemeteryFormState extends State<_CemeteryForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _locality = TextEditingController(
    text: widget.locality,
  );
  bool _nameMissing = false;

  @override
  void dispose() {
    _name.dispose();
    _locality.dispose();
    super.dispose();
  }

  void _next() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    Navigator.of(context).pop((
      name: _name.text.trim(),
      locality: _locality.text.trim().isEmpty ? null : _locality.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Focus and keyboard at once, in the first empty field.
    final bool nameFirst = _name.text.isEmpty || _locality.text.isNotEmpty;
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(inputDecorationTheme: GrobingTheme.fields),
      child: _dialog(nameFirst),
    );
  }

  Widget _dialog(bool nameFirst) {
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: nameFirst,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_nameMissing) setState(() => _nameMissing = false);
            },
            decoration: InputDecoration(
              labelText: 'Nazwa',
              // Never colour alone (SC 1.4.1): the message comes with an icon.
              error: _nameMissing
                  ? const Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: GrobingColors.error,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Podaj nazwę cmentarza.',
                          style: TextStyle(color: GrobingColors.error),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _locality,
            autofocus: !nameFirst,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _next(),
            decoration: const InputDecoration(
              labelText: 'Miejscowość (opcjonalnie)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(onPressed: _next, child: const Text('Dalej')),
      ],
    );
  }
}
