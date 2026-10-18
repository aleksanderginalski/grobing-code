import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/graves.dart' show QualifiedDate;
import '../../data/places.dart';
import '../../data/residences.dart';
import '../dates.dart';
import '../polish.dart' show fold;
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/date_block.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'place_picker_screen.dart';

// Places of residence (ISSUE-042; 05_DESIGN/zamieszkanie.md): the window "Miejsce zamieszkania" (A), the
// section of the person form (9b, elements 5–7), and the words both and the person's view (9a) show.

/// The view's row (element 2): the first line, and the second when there is one — the country under an
/// address, "cały kraj — miejscowość nieznana" under a country, "dziś: …" under the name of the time (N2).
({String first, String? second}) residenceLines(Residence r) {
  final ResidencePlace p = r.place;
  final String? then = r.nameThen;
  return switch (r.level) {
    PlaceLevel.country =>
      then == null
          ? (first: p.countryName, second: 'cały kraj — miejscowość nieznana')
          : (first: then, second: 'dziś:\u00A0${p.countryName} — cały kraj'),
    PlaceLevel.locality =>
      then == null
          ? (first: '${p.name}, ${p.countryName}', second: null)
          : (first: then, second: 'dziś:\u00A0${p.name}, ${p.countryName}'),
    PlaceLevel.address =>
      then == null
          ? (first: '${r.address}, ${p.name}', second: p.countryName)
          : (
              first: '${r.address}, $then',
              second: 'dziś:\u00A0${p.name}, ${p.countryName}',
            ),
  };
}

/// What a screen reader says for a row (element 2): "ok. 1925 – 1945: Zmyślin, Polska, dziś Zmyślin, Ukraina".
/// [impliedTo] — the end the next residence gives one without its own (v1.2, D12; `impliedEnds`).
String residenceLabel(Residence r, {QualifiedDate? impliedTo}) {
  final ({String first, String? second}) l = residenceLines(r);
  final String place = l.second == null
      ? l.first
      : '${l.first}, ${l.second!.replaceFirst('dziś:\u00A0', 'dziś ')}';
  return '${stayYears(r.from, r.to ?? impliedTo) ?? 'bez lat'}: $place';
}

/// The card's line under the years (element 6): "Zmyślin, Polska · dziś Ukraina" — the country alone when
/// the name stayed — "ul. Przykładowa 3, Wymyślowo, Polska", "Ukraina · cały kraj".
String residenceCardLine(Residence r) {
  final ResidencePlace p = r.place;
  final String? then = r.nameThen;
  final String today = r.level == PlaceLevel.country
      ? p.countryName
      : '${p.name}, ${p.countryName}';
  final String main = switch (r.level) {
    PlaceLevel.country => then ?? '${p.countryName} ·\u00A0cały kraj',
    PlaceLevel.locality => then ?? today,
    PlaceLevel.address => '${r.address}, ${then ?? today}',
  };
  if (then == null) return main;
  // The whole part before the first comma, not its start: "Zmyślinek" by today's "Zmyślin" is another name
  // (v1.1, D10 — ui review).
  final bool sameName =
      r.level != PlaceLevel.country &&
      fold(then.split(',').first.trim()) == fold(p.name);
  return '$main ·\u00A0dziś\u00A0${sameName ? p.countryName : today}';
}

/// The place in the window's field (element 12): "Zmyślin · Ukraina", "Ukraina · cały kraj". A line breaks
/// before a "·", never after it, as `joinPlaceLine` (ui review of the cemeteries).
String placeFieldText(ResidencePlace p) => p.isCountry
    ? '${p.countryName} ·\u00A0cały kraj'
    : '${p.name} ·\u00A0${p.countryName}';

/// What the window gives back: the residence as written, or that it goes.
sealed class ResidenceChange {
  const ResidenceChange();
}

class ResidenceDone extends ResidenceChange {
  const ResidenceDone(this.residence);

  final Residence residence;
}

class ResidenceRemoved extends ResidenceChange {
  const ResidenceRemoved();
}

/// The window "Miejsce zamieszkania" (A, elements 8–16): the years from and to, the place from the list,
/// the name of the time (N2) and the address (A1). "Gotowe" gives the residence back to the form, which
/// writes it with "Zapisz" (D5); nothing is written here.
class ResidenceScreen extends StatefulWidget {
  const ResidenceScreen({
    super.key,
    this.initial,
    required this.recent,
    this.places,
  });

  /// The residence of the card ✎ was pressed on; null — a new one.
  final Residence? initial;

  /// "Ostatnio wybrane" of the choice (element 18).
  final Future<List<ResidencePlace>> Function() recent;

  /// The list of places; the bundled one when null.
  final Future<PlaceList>? places;

  @override
  State<ResidenceScreen> createState() => _ResidenceScreenState();
}

class _ResidenceScreenState extends State<ResidenceScreen> {
  late final DateInput _from = DateInput(
    'Od',
    widget.initial?.from,
    readOnly: false,
  );
  late final DateInput _to = DateInput(
    'Do',
    widget.initial?.to,
    readOnly: false,
  );
  late ResidencePlace? _place = widget.initial?.place;
  late final TextEditingController _then = TextEditingController(
    text: widget.initial?.nameThen,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.address,
  );
  final FocusNode _placeNode = FocusNode();
  bool _placeMissing = false;
  bool _endBeforeStart = false;
  late final String _initialSnapshot = _snapshot();

  @override
  void initState() {
    super.initState();
    _initialSnapshot; // before anything is typed
    // Element 9: a new residence starts at "Od", with the keyboard up.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _from.fromNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _then.dispose();
    _address.dispose();
    _placeNode.dispose();
    super.dispose();
  }

  String _snapshot() => [
    for (final DateInput d in [_from, _to]) ...[d.qualifier.name, d.from.text],
    _place?.countryCode ?? '',
    '${_place?.geonamesId ?? ''}',
    _then.text,
    _address.text,
  ].join('\u0000');

  bool get _dirty => _snapshot() != _initialSnapshot;

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Element 11: the period as the view will show it.
  String _preview() {
    final QualifiedDate? from = _from.read().date, to = _to.read().date;
    return '→ ${stayYears(from, to) ?? 'bez lat'}';
  }

  Future<void> _choosePlace() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ResidencePlace? chosen = await Navigator.of(context)
        .push<ResidencePlace>(
          MaterialPageRoute(
            builder: (_) => PlacePickerScreen(
              recent: widget.recent(),
              places: widget.places,
            ),
          ),
        );
    if (chosen == null || !mounted) return;
    setState(() {
      _place = chosen;
      _placeMissing = false;
    });
  }

  void _done() {
    FocusNode? first;
    final DateRead from = _from.read(), to = _to.read();
    _from.showError = from.error != null;
    _to.showError = to.error != null;
    if (from.error != null) first = _from.fromNode;
    if (to.error != null) first ??= _to.fromNode;
    _endBeforeStart =
        from.date != null &&
        to.date != null &&
        !notBefore(from.date!.from, to.date!.from);
    if (_endBeforeStart) first ??= _to.fromNode;
    _placeMissing = _place == null;
    if (_placeMissing) first ??= _placeNode;
    if (first != null) {
      setState(() {});
      first.requestFocus();
      return;
    }
    final ResidencePlace place = _place!;
    Navigator.of(context).pop(
      ResidenceDone(
        Residence(
          id: widget.initial?.id,
          from: from.date,
          to: to.date,
          place: place,
          nameThen: _text(_then),
          // An address needs a locality (element 14).
          address: place.isCountry ? null : _text(_address),
        ),
      ),
    );
  }

  Future<void> _remove() async {
    final bool? remove = await showDialog<bool>(
      context: context,
      builder: (context) => _dialog(
        context,
        title: 'Usunąć to miejsce zamieszkania?',
        text: 'Zniknie z\u00A0wpisu po „Zapisz”.',
        destructive: 'Usuń',
      ),
    );
    if (remove == true && mounted) {
      Navigator.of(context).pop(const ResidenceRemoved());
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (context) => _dialog(
        context,
        title: 'Odrzucić zmiany?',
        text: 'Zmiany w\u00A0tym miejscu nie zostaną zapisane.',
        destructive: 'Odrzuć',
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  /// The safe action, "Wróć", is the main one, in the accent (style-b.md rule 10).
  static Widget _dialog(
    BuildContext context, {
    required String title,
    required String text,
    required String destructive,
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
    content: Text(
      text,
      style: const TextStyle(color: GrobingColors.text, fontSize: 16),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(destructive),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Wróć'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
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

  /// Element 8.
  Widget _bar() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
    child: Row(
      children: [
        IconButton(
          icon: const GrobingIcon(
            Glyphs.close,
            color: GrobingColors.text,
            applyTextScaling: false,
          ),
          tooltip: 'Zamknij',
          onPressed: _close,
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Text(
            'Miejsce zamieszkania',
            style: TextStyle(
              color: GrobingColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _form() {
    final ResidencePlace? place = _place;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Elements 9–11.
          DateBlock(
            input: _from,
            qualifiers: stayQualifiers,
            preview: false,
            onChanged: () => setState(() {
              _from.showError = false;
              _endBeforeStart = false;
            }),
          ),
          const SizedBox(height: 16),
          DateBlock(
            input: _to,
            // v1.2, D12: an empty end is the start of the next residence, worked out in the view.
            note: 'Puste — do początku następnego miejsca.',
            qualifiers: stayQualifiers,
            preview: false,
            onNext: _choosePlace,
            error: _endBeforeStart
                ? 'Koniec nie może być przed początkiem.'
                : null,
            onChanged: () => setState(() {
              _to.showError = false;
              _endBeforeStart = false;
            }),
          ),
          if (!_endBeforeStart &&
              !(_from.showError && _from.read().error != null) &&
              !(_to.showError && _to.read().error != null))
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                _preview(),
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
          const SizedBox(height: 20),
          // Element 12.
          const Text(
            'Miejsce',
            style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 6),
          _PlaceField(
            place: place,
            focusNode: _placeNode,
            bad: _placeMissing,
            onTap: _choosePlace,
          ),
          if (_placeMissing)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: ErrorLine('Wybierz miejsce.'),
            ),
          const SizedBox(height: 20),
          // Element 13 (N2).
          TextField(
            controller: _then,
            textCapitalization: TextCapitalization.words,
            textInputAction: place == null || place.isCountry
                ? TextInputAction.done
                : TextInputAction.next,
            style: inputTextStyle,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nazwa z\u00A0tamtego czasu',
              hintText: 'np. Zmyślin, Polska',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
          // Element 14 (A1): only in a locality — an address needs one ("okno — miejsce „kraj”").
          if (place != null && !place.isCountry) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: inputTextStyle,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Adres',
                hintText: 'np. ul. Przykładowa 3',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Elements 15–16: "Usuń to miejsce" (from a card only) over "Gotowe", pinned above the keyboard.
  Widget _bottom() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.initial != null) ...[
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: GrobingColors.text,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _remove,
            child: const Text('Usuń to miejsce'),
          ),
          const SizedBox(height: 4),
        ],
        FilledButton(
          style: primaryButtonStyle,
          onPressed: _done,
          child: const Text('Gotowe'),
        ),
      ],
    ),
  );
}

/// Element 12: a field that is a button — the place chosen or the hint, and a chevron to the choice.
class _PlaceField extends StatelessWidget {
  const _PlaceField({
    required this.place,
    required this.focusNode,
    required this.bad,
    required this.onTap,
  });

  final ResidencePlace? place;
  final FocusNode focusNode;
  final bool bad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ResidencePlace? p = place;
    return Semantics(
      button: true,
      label: p == null
          ? 'Miejsce: wybierz kraj albo miejscowość'
          : 'Miejsce: ${placeFieldText(p)}',
      hint: 'zmień',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: bad ? GrobingColors.error : GrobingColors.outline,
            ),
          ),
          child: Row(
            children: [
              const GrobingIcon(Glyphs.place, color: GrobingColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p == null
                      ? 'Wybierz kraj albo miejscowość'
                      : placeFieldText(p),
                  style: TextStyle(
                    color: p == null
                        ? GrobingColors.textMuted
                        : GrobingColors.text,
                    fontSize: 16,
                  ),
                ),
              ),
              const GrobingIcon(
                Glyphs.chevronRight,
                color: GrobingColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The section "Miejsca zamieszkania" of the person form (9b, elements 5–7): a card for each residence in
/// the order of the years, ✎ on it, and "Dodaj miejsce". The list lives in the form until "Zapisz" (D5).
class ResidencesFormSection extends StatelessWidget {
  const ResidencesFormSection({
    super.key,
    required this.residences,
    required this.onEdit,
    required this.onAdd,
  });

  final List<Residence> residences;
  final void Function(Residence residence) onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Element 5: as "Rodzina" above it.
      Semantics(
        header: true,
        child: const Row(
          children: [
            GrobingIcon(Glyphs.home, size: 20, color: GrobingColors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Miejsca zamieszkania',
                style: TextStyle(
                  color: GrobingColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      // Element 6.
      for (final (Residence r, QualifiedDate? impliedTo) in [
        for (final (int i, QualifiedDate? end) in impliedEnds(
          residences,
        ).indexed)
          (residences[i], end),
      ])
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: GrobingColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stayYears(r.from, r.to ?? impliedTo) ?? 'Bez lat',
                              style: const TextStyle(
                                color: GrobingColors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              residenceCardLine(r),
                              style: const TextStyle(
                                color: GrobingColors.textMuted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const GrobingIcon(
                        Glyphs.inkPen,
                        color: GrobingColors.amber,
                        applyTextScaling: false,
                      ),
                      tooltip: 'Popraw miejsce',
                      onPressed: () => onEdit(r),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      // Element 7.
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: secondaryButtonStyle.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
            ),
            onPressed: onAdd,
            icon: const GrobingIcon(Glyphs.addHome),
            label: const Text('Dodaj miejsce'),
          ),
        ),
      ),
    ],
  );
}
