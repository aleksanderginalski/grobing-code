import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../photo/photos.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'grave_screen.dart';
import 'person_form_screen.dart';

/// The graves of one cemetery (ISSUE-012; 05_DESIGN/cmentarz.md v3): R2 without the satellite photo —
/// the sheet of graves over the whole screen (D1), each with its gravestone thumbnail when it has a
/// photo (D9, ISSUE-016), and "Dodaj grób" to transcribe the next one.
class CemeteryScreen extends StatefulWidget {
  const CemeteryScreen({
    super.key,
    required this.database,
    required this.cemeteryId,
    this.photos,
  });

  final GrobingDatabase database;
  final int cemeteryId;

  /// Null only in tests of other features: then the cards have no thumbnails.
  final Photos? photos;

  @override
  State<CemeteryScreen> createState() => _CemeteryScreenState();
}

class _CemeteryScreenState extends State<CemeteryScreen> {
  late Stream<CemeteryGraves?> _graves = _watch();

  Stream<CemeteryGraves?> _watch() =>
      watchCemeteryGraves(widget.database, widget.cemeteryId);

  Future<void> _openGrave(int id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GraveScreen(
        database: widget.database,
        graveId: id,
        photos: widget.photos,
      ),
    ),
  );

  /// "Dodaj grób" opens the form of the grave's first person at once: the grave is written with them
  /// (05_DESIGN/cmentarz.md → Navigation).
  Future<void> _addGrave(CemeteryGraves cemetery) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PersonFormScreen(
        database: widget.database,
        mode: NewGrave(cemeteryId: cemetery.id, cemeteryName: cemetery.name),
        photos: widget.photos,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<CemeteryGraves?>(
    stream: _graves,
    builder: (context, snapshot) {
      final CemeteryGraves? cemetery = snapshot.data;
      final bool failed =
          snapshot.hasError || (snapshot.hasData && cemetery == null);
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(cemetery),
              Expanded(
                child: failed
                    ? _readError()
                    : cemetery == null
                    ? const Center(child: CircularProgressIndicator())
                    : cemetery.graves.isEmpty
                    ? _empty()
                    : _list(cemetery),
              ),
              _addButton(failed ? null : cemetery),
            ],
          ),
        ),
      );
    },
  );

  /// Element 1: back, the cemetery's name (up to two lines) and its locality.
  Widget _bar(CemeteryGraves? cemetery) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BackButton(color: GrobingColors.text),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cemetery?.name ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GrobingColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cemetery?.locality != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    cemetery!.locality!,
                    style: const TextStyle(
                      color: GrobingColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// Elements 2 and 3: the counts, then the graves in the order they were entered. The last card keeps
  /// clear of the pinned button.
  Widget _list(CemeteryGraves cemetery) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    children: [
      Text(
        '${gravesLabel(cemetery.graves.length)} · '
        '${peopleLabel(cemetery.personCount)}',
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 14),
      ),
      const SizedBox(height: 8),
      for (final GraveSummary g in cemetery.graves)
        _GraveCard(
          grave: g,
          photo: switch ((widget.photos, g.photoPath)) {
            (final Photos photos?, final String path?) => photos.fileOf(path),
            _ => null,
          },
          onTap: () => _openGrave(g.id),
        ),
    ],
  );

  /// What will be here; the one action is the pinned "Dodaj grób" (style-b.md rule 9).
  Widget _empty() => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Na tym cmentarzu nie ma jeszcze grobów.',
        textAlign: TextAlign.center,
        style: TextStyle(color: GrobingColors.textMuted, fontSize: 16),
      ),
    ),
  );

  Widget _readError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Nie udało się odczytać grobów.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          style: secondaryButtonStyle,
          onPressed: () => setState(() => _graves = _watch()),
          child: const Text('Spróbuj ponownie'),
        ),
      ],
    ),
  );

  /// Element 4: the main action, pinned at the bottom; inactive while it is not known where it adds.
  Widget _addButton(CemeteryGraves? cemetery) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: FilledButton(
      style: primaryButtonStyle,
      onPressed: cemetery == null ? null : () => _addGrave(cemetery),
      child: const Text('Dodaj grób'),
    ),
  );
}

/// Element 3: a grave on the surface with a chevron (style-b.md rule 11). Its title is the grave's
/// name; without one, the people buried in it (D5).
class _GraveCard extends StatelessWidget {
  const _GraveCard({required this.grave, required this.onTap, this.photo});

  final GraveSummary grave;
  final VoidCallback onTap;

  /// Element 3 (d): the gravestone photo, when the grave has one.
  final File? photo;

  static const TextStyle _title = TextStyle(
    color: GrobingColors.text,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _muted = TextStyle(
    color: GrobingColors.textMuted,
    fontSize: 14,
  );

  @override
  Widget build(BuildContext context) {
    final List<String> people = [
      for (final p in grave.people) personName(p.givenNames, p.surname),
    ];
    final Widget title = grave.name != null
        ? Text(
            grave.name!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _title,
          )
        : people.isEmpty
        ? const Text('Grób bez wpisanych osób', style: _muted)
        : NamesText(names: people, style: _title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: GrobingColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  if (photo case final File file?) _Thumbnail(file: file),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        title,
                        if (grave.name != null && people.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          NamesText(names: people, style: _muted),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          addressLine(
                            graveAddress(grave.sector, grave.row, grave.plot),
                            hasPin: grave.hasPin,
                          ),
                          style: _muted,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: GrobingColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Element 3 (d): a 56 dp square, corners 8 dp, cut from the middle, 12 dp before the text (cmentarz.md
/// v3). The card's text tells a screen reader what it is, so the picture stays out of it. A photo that
/// cannot be read leaves no thumbnail and no gap (cmentarz.md → States).
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file});

  final File file;
  static const double _size = 56;

  @override
  Widget build(BuildContext context) => Image.file(
    file,
    width: _size,
    height: _size,
    fit: BoxFit.cover,
    cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
    excludeFromSemantics: true,
    frameBuilder: (_, child, _, _) => Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    ),
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

/// Names after commas in at most [maxLines] lines; those that do not fit become "i jeszcze 2"
/// (05_DESIGN/cmentarz.md, element 3a). Measured, so it holds at any text size.
class NamesText extends StatelessWidget {
  const NamesText({
    super.key,
    required this.names,
    required this.style,
    this.maxLines = 2,
  });

  final List<String> names;
  final TextStyle style;
  final int maxLines;

  static String _shown(List<String> names, int count) => count == names.length
      ? names.join(', ')
      : '${names.take(count).join(', ')} i jeszcze ${names.length - count}';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final TextScaler scaler = MediaQuery.textScalerOf(context);
      final TextDirection direction = Directionality.of(context);
      bool fits(String text) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        final bool result = !painter.didExceedMaxLines;
        painter.dispose();
        return result;
      }

      int count = names.length;
      while (count > 1 && !fits(_shown(names, count))) {
        count--;
      }
      return Text(
        _shown(names, count),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    },
  );
}
