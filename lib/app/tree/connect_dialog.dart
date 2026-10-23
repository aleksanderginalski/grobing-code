import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/family_tree.dart';
import '../people/people_list.dart' show InitialsCircle, initialsOf;
import '../people/person_choice_screen.dart';
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';

/// Element 7 (05_DESIGN/drzewo.md v1.29; US-011 AC-1, ISSUE-039, ISSUE-055): the window "Połącz dwie osoby" with the
/// tiles "Od" — the person in the middle of the tree, [from], at each opening (D78; "Ja" until v1.28) — and "Do",
/// empty. A tile opens the list of people; choosing "Od" comes back here, choosing "Do" closes the window with the
/// pair. "Anuluj", back or a tap beside it close it with nothing (D49).
Future<({int from, int to})?> showConnectDialog(
  BuildContext context, {
  required GrobingDatabase database,
  required FamilyTreeData family,
  required int? from,
  Photos? photos,
}) => showDialog<({int from, int to})>(
  context: context,
  builder: (_) => _ConnectDialog(
    database: database,
    family: family,
    from: from,
    photos: photos,
  ),
);

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({
    required this.database,
    required this.family,
    required this.from,
    this.photos,
  });

  final GrobingDatabase database;
  final FamilyTreeData family;
  final int? from;
  final Photos? photos;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late int? _from = widget.from ?? widget.family.meId;

  Future<void> _choose({required bool from}) async {
    final int? id = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => PersonChoiceScreen(
          database: widget.database,
          title: from ? 'Od kogo?' : 'Do kogo?',
          // The person on the other tile is not on the list: the same person has no path.
          without: from ? null : _from,
          photos: widget.photos,
        ),
      ),
    );
    if (id == null || !mounted) return;
    if (from) {
      setState(() => _from = id);
      return;
    }
    final int? start = _from;
    if (start != null) Navigator.of(context).pop((from: start, to: id));
  }

  @override
  Widget build(BuildContext context) {
    // From 150 % of the system text the tiles stand one under the other (element 7).
    final bool large = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final Widget od = _Tile(
      label: 'Od',
      person: _from == null ? null : widget.family.people[_from],
      isMe: _from != null && _from == widget.family.meId,
      photos: widget.photos,
      large: large,
      onTap: () => _choose(from: true),
    );
    final Widget to = _Tile(
      label: 'Do',
      person: null,
      isMe: false,
      photos: widget.photos,
      large: large,
      onTap: () => _choose(from: false),
    );
    final Widget arrow = ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: GrobingIcon(
          large ? Glyphs.arrowDownward : Glyphs.arrowForward,
          color: GrobingColors.textMuted,
          size: 20,
          applyTextScaling: false,
        ),
      ),
    );
    return Dialog(
      backgroundColor: GrobingColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 328),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Semantics(
                  header: true,
                  child: const Text(
                    'Połącz dwie osoby',
                    style: TextStyle(
                      color: GrobingColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (large)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    od,
                    Center(child: arrow),
                    to,
                  ],
                )
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: od),
                      Center(child: arrow),
                      Expanded(child: to),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: GrobingColors.text,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Anuluj',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tile: "Od" / "Do" (13 sp, muted), the circle — the profile photo, the initials, the mark "Ja" (D14) — and
/// the name without "z d." (14 sp, wrapped at spaces); empty — a dashed circle and "Wybierz osobę" in amber,
/// the window's main action (style-b.md rule 1). The outline on the surface, 3.10:1 (SC 1.4.11).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.person,
    required this.isMe,
    required this.photos,
    required this.large,
    required this.onTap,
  });

  final String label;
  final TreePerson? person;
  final bool isMe;
  final Photos? photos;
  final bool large;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TreePerson? p = person;
    final String name = p == null
        ? 'Wybierz osobę'
        : personName(p.givenNames, p.surname);
    final Widget circle = p == null ? const _EmptyCircle() : _avatar(p);
    final Widget nameText = Text(
      name,
      textAlign: large ? TextAlign.start : TextAlign.center,
      style: p == null
          ? const TextStyle(
              color: GrobingColors.amber,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            )
          : const TextStyle(color: GrobingColors.text, fontSize: 14),
    );
    final Widget labelText = Text(
      label,
      style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
    );
    final Widget content = large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelText,
              const SizedBox(height: 4),
              Row(
                children: [
                  circle,
                  const SizedBox(width: 12),
                  Expanded(child: nameText),
                ],
              ),
            ],
          )
        : Column(
            children: [
              Align(alignment: Alignment.centerLeft, child: labelText),
              const SizedBox(height: 6),
              circle,
              const SizedBox(height: 6),
              nameText,
            ],
          );
    return Semantics(
      button: true,
      label: '$label: ${p == null ? 'wybierz osobę' : name}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: GrobingColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: large
                  ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
                  : const EdgeInsets.fromLTRB(8, 10, 8, 12),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(TreePerson p) {
    final Widget initials = InitialsCircle(
      text: isMe ? 'Ja' : initialsOf(p.givenNames, p.surname),
      accent: isMe,
    );
    // "Ja" keeps its mark even with a photo, as on the tree (D14).
    return switch ((isMe, photos, p.profile)) {
      (false, final Photos photos?, final profile?) => ProfileCircle(
        file: photos.fileOf(profile.relativePath),
        crop: profile.crop,
        size: 40,
        unreadable: initials,
      ),
      _ => initials,
    };
  }
}

/// The empty tile's circle: dashed in amber with a plus.
class _EmptyCircle extends StatelessWidget {
  const _EmptyCircle();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 40,
    child: CustomPaint(
      painter: _DashedCircle(),
      child: GrobingIcon(
        Glyphs.add,
        color: GrobingColors.amber,
        size: 22,
        applyTextScaling: false,
      ),
    ),
  );
}

class _DashedCircle extends CustomPainter {
  const _DashedCircle();

  @override
  void paint(Canvas canvas, Size size) {
    const double width = 1.5, dash = 4, gap = 3;
    final double r = size.shortestSide / 2 - width / 2;
    final int count = (2 * math.pi * r / (dash + gap)).floor();
    final double step = 2 * math.pi / count;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = GrobingColors.amber;
    final Rect rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: r,
    );
    for (int i = 0; i < count; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * step,
        step * dash / (dash + gap),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => false;
}
