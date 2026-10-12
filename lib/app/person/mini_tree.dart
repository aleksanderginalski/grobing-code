import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/families.dart';
import '../../data/photos.dart' show ProfilePhoto;
import '../dates.dart';
import '../family/role_names.dart';
import '../family/union_wizard.dart' show shortPersonName;
import '../people/people_list.dart' show InitialsCircle;
import '../photo/photos.dart';
import '../photo/profile_circle.dart';
import '../polish.dart';
import '../theme.dart';

/// What someone is in the mini tree of the person in the middle.
enum MiniRole { parent, self, partner, child }

/// The kinds of line (05_DESIGN/osoba.md element 6, as drzewo.md): a married pair — level and solid; a
/// pair "razem" — level and dashed; parent–child — stepped down. Colour and shape both carry the kind
/// (SC 1.4.1).
enum MiniLineKind { married, together, parentChild }

class MiniTreeNode {
  const MiniTreeNode({
    required this.member,
    required this.role,
    required this.x,
    required this.y,
    this.married = false,
  });

  final FamilyMember member;
  final MiniRole role;

  /// The middle of the node's slot, and the top of its circle.
  final double x;
  final double y;

  /// For a partner: whether the pair married (żona / mąż).
  final bool married;
}

class MiniTreeLine {
  const MiniTreeLine(this.kind, this.from, this.to);

  final MiniLineKind kind;
  final Offset from;
  final Offset to;
}

class MiniTreeLayout {
  const MiniTreeLayout({
    required this.nodes,
    required this.lines,
    required this.width,
    required this.height,
    required this.focusX,
    this.slot = miniSlot,
  });

  final List<MiniTreeNode> nodes;
  final List<MiniTreeLine> lines;
  final double width;
  final double height;

  /// Where the person in the middle stands — the tree starts scrolled to put them in the middle.
  final double focusX;

  /// The width of a node's slot — wider with large text, so the role is never cut (ui review, SC 1.4.4).
  final double slot;
}

/// The node's slot (osoba.md D12: 4 slots at 360 dp), its circle, and the room for lines between rows.
const double miniSlot = 80;
const double miniNode = 44;
const double _labelGap = 4;
const double _rowGap = 36;

/// The parents' distance from the middle, in slots (56 dp of the 80 dp slot).
const double _spreadOfSlot = 0.7;

/// The mini tree of one level (osoba.md element 6, D12): the parents in a row above the person; beside
/// them their partners — one on the right; two with the earlier union on the left and the later on the
/// right; any further on the right — each union's children under it, by birth. With two unions that both
/// have children, the left one's end before the person and the right one's start after, so their lines
/// never meet. [unions] come by their first date ([loadRelations]). [labelHeight] is the height of a
/// node's two lines of text, which grows with the system's text size; [viewport] the width the tree is
/// shown in — a narrower tree is centred in it, a wider one scrolls; [slot] the width of a node's place,
/// which grows with the text too.
MiniTreeLayout layoutMiniTree({
  required FamilyMember person,
  required List<FamilyMember> parents,
  bool parentsMarried = false,
  required List<PersonUnion> unions,
  required double labelHeight,
  required double viewport,
  double slot = miniSlot,
}) {
  final double spread = slot * _spreadOfSlot;
  final double half = slot / 2;
  final double rowHeight = miniNode + _labelGap + labelHeight + _rowGap;
  final bool hasParents = parents.isNotEmpty;
  const double yP = 0;
  final double yF = hasParents ? rowHeight : 0;
  final double yC = yF + rowHeight + 8;

  // The middle row, in slots from the left.
  final List<PersonUnion> paired = [
    for (final PersonUnion u in unions)
      if (u.partner != null) u,
  ];
  final PersonUnion? left = paired.length >= 2 ? paired.first : null;
  final Map<PersonUnion, double> at = {};
  double x = 0;
  if (left != null) {
    at[left] = x;
    x += slot;
  }
  final double fx = x;
  x += slot;
  for (final PersonUnion u in paired) {
    if (identical(u, left)) continue;
    at[u] = x;
    x += slot;
  }

  // The children's groups, each under its union.
  final List<_Group> groups = [
    for (final PersonUnion u in unions)
      if (u.children.isNotEmpty)
        _Group(
          u,
          ux: u.partner == null ? fx : (at[u]! + fx) / 2,
          width: u.children.length * slot,
        ),
  ];
  for (final _Group g in groups) {
    g.start = g.ux - (g.width - slot) / 2;
  }
  final _Group? leftGroup = groups
      .where((g) => identical(g.union, left))
      .firstOrNull;
  final List<_Group> rest = [
    for (final _Group g in groups)
      if (!identical(g, leftGroup)) g,
  ]..sort((a, b) => a.ux.compareTo(b.ux));
  if (leftGroup != null && rest.isNotEmpty) {
    leftGroup.start = math.min(
      leftGroup.start,
      fx - half - (leftGroup.width - slot),
    );
    rest.first.start = math.max(rest.first.start, fx + half);
  }
  double edge = double.negativeInfinity;
  for (final _Group g in rest) {
    g.start = math.max(g.start, edge);
    edge = g.start + g.width;
  }

  final List<double> parentXs = parents.length >= 2
      ? [fx - spread, fx + spread]
      : [if (hasParents) fx];
  final List<double> xs = [
    0,
    x - slot,
    ...parentXs,
    for (final _Group g in groups) ...[g.start, g.start + g.width - slot],
  ];
  final double minX = xs.reduce(math.min);
  final double maxX = xs.reduce(math.max);
  final double width = math.max(viewport, maxX - minX + slot + 32);
  final double shift = (width - (maxX - minX)) / 2 - minX;
  double sx(double v) => v + shift;

  final List<MiniTreeNode> nodes = [];
  final List<MiniTreeLine> lines = [];
  const double mid = miniNode / 2;
  final double labelsEnd = miniNode + _labelGap + labelHeight;

  for (int i = 0; i < parents.length && i < parentXs.length; i++) {
    nodes.add(
      MiniTreeNode(
        member: parents[i],
        role: MiniRole.parent,
        x: sx(parentXs[i]),
        y: yP,
      ),
    );
  }
  if (parentXs.length == 2) {
    lines
      ..add(
        MiniTreeLine(
          parentsMarried ? MiniLineKind.married : MiniLineKind.together,
          Offset(sx(parentXs[0]) + mid, yP + mid),
          Offset(sx(parentXs[1]) - mid, yP + mid),
        ),
      )
      ..add(
        MiniTreeLine(
          MiniLineKind.parentChild,
          Offset(sx(fx), yP + mid),
          Offset(sx(fx), yF),
        ),
      );
  } else if (hasParents) {
    lines.add(
      MiniTreeLine(
        MiniLineKind.parentChild,
        Offset(sx(fx), yP + labelsEnd),
        Offset(sx(fx), yF),
      ),
    );
  }

  nodes.add(
    MiniTreeNode(member: person, role: MiniRole.self, x: sx(fx), y: yF),
  );
  for (final PersonUnion u in paired) {
    final double ux = at[u]!;
    nodes.add(
      MiniTreeNode(
        member: u.partner!,
        role: MiniRole.partner,
        x: sx(ux),
        y: yF,
        married: u.married,
      ),
    );
    lines.add(
      MiniTreeLine(
        u.married ? MiniLineKind.married : MiniLineKind.together,
        Offset(sx(math.min(ux, fx)) + mid, yF + mid),
        Offset(sx(math.max(ux, fx)) - mid, yF + mid),
      ),
    );
  }

  // Buses whose spans overlap are drawn a step apart, so two families' children never share a line.
  final List<(double, double, double)> buses = [];
  for (final _Group g in [?leftGroup, ...rest]) {
    final List<double> kids = [
      for (int i = 0; i < g.union.children.length; i++) g.start + i * slot,
    ];
    final double lo = math.min(g.ux, kids.first);
    final double hi = math.max(g.ux, kids.last);
    double busY = yC - 12;
    while (buses.any((b) => b.$3 == busY && b.$1 <= hi && lo <= b.$2)) {
      busY -= 8;
    }
    buses.add((lo, hi, busY));
    final double top = g.union.partner == null ? yF + labelsEnd : yF + mid;
    lines.add(
      MiniTreeLine(
        MiniLineKind.parentChild,
        Offset(sx(g.ux), top),
        Offset(sx(g.ux), busY),
      ),
    );
    if (hi > lo) {
      lines.add(
        MiniTreeLine(
          MiniLineKind.parentChild,
          Offset(sx(lo), busY),
          Offset(sx(hi), busY),
        ),
      );
    }
    for (int i = 0; i < kids.length; i++) {
      nodes.add(
        MiniTreeNode(
          member: g.union.children[i],
          role: MiniRole.child,
          x: sx(kids[i]),
          y: yC,
        ),
      );
      lines.add(
        MiniTreeLine(
          MiniLineKind.parentChild,
          Offset(sx(kids[i]), busY),
          Offset(sx(kids[i]), yC),
        ),
      );
    }
  }

  final double height = (groups.isEmpty ? yF : yC) + labelsEnd + 8;
  return MiniTreeLayout(
    nodes: nodes,
    lines: lines,
    width: width,
    height: height,
    focusX: sx(fx),
    slot: slot,
  );
}

class _Group {
  _Group(this.union, {required this.ux, required this.width});

  final PersonUnion union;
  final double ux;
  final double width;
  double start = 0;
}

/// The role under a node (rodzina.md → Role names): from sex, and for a partner from the wedding.
String miniRoleName(MiniTreeNode n) => switch (n.role) {
  MiniRole.parent => roleName(FamilyRole.parent, n.member.sex),
  MiniRole.partner => roleName(
    FamilyRole.partner,
    n.member.sex,
    married: n.married,
  ),
  MiniRole.child => roleName(FamilyRole.child, n.member.sex),
  MiniRole.self => '',
};

/// The mini tree on the person's view (osoba.md element 6): a node's circle — the profile photo in its
/// crop, or the initials — its role and first name; the person in the middle with a ring in amber. A
/// relative's node opens their view ([onOpen]). Wider than the screen, it scrolls sideways and starts
/// with the person in the middle.
class MiniTree extends StatefulWidget {
  const MiniTree({
    super.key,
    required this.person,
    required this.relations,
    required this.profiles,
    required this.onOpen,
    this.photos,
  });

  final FamilyMember person;
  final PersonRelations relations;
  final Map<int, ProfilePhoto> profiles;
  final ValueChanged<int> onOpen;
  final Photos? photos;

  @override
  State<MiniTree> createState() => _MiniTreeState();
}

class _MiniTreeState extends State<MiniTree> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final TextScaler scaler = MediaQuery.textScalerOf(context);
      // Two lines of 13 sp at height 1.3, and a little room for the font's own metrics — without it the
      // lines overflowed their box by a fraction of a pixel (found by the tests, ISSUE-024).
      final double labelHeight = scaler.scale(13) * 1.3 * 2 + 4;
      // The slot grows with the text, up to twice: "Partnerka" at 200% needs about 130 dp (ui review).
      final double slot = miniSlot * (scaler.scale(13) / 13).clamp(1.0, 2.0);
      final MiniTreeLayout layout = layoutMiniTree(
        person: widget.person,
        parents: widget.relations.parents,
        parentsMarried: widget.relations.parentsUnion?.married ?? false,
        unions: widget.relations.unions,
        labelHeight: labelHeight,
        viewport: constraints.maxWidth,
        slot: slot,
      );
      final double start = (layout.focusX - constraints.maxWidth / 2).clamp(
        0,
        math.max(0, layout.width - constraints.maxWidth),
      );
      final ScrollController scroll = _scroll ??= ScrollController(
        initialScrollOffset: start,
      );
      return SingleChildScrollView(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: layout.width,
          height: layout.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _LinesPainter(layout.lines)),
              ),
              for (final MiniTreeNode n in layout.nodes)
                Positioned(
                  left: n.x - layout.slot / 2,
                  top: n.y,
                  width: layout.slot,
                  child: _Node(
                    node: n,
                    profile: widget.profiles[n.member.id],
                    photos: widget.photos,
                    labelHeight: labelHeight,
                    onTap: n.role == MiniRole.self
                        ? null
                        : () => widget.onOpen(n.member.id),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _Node extends StatelessWidget {
  const _Node({
    required this.node,
    required this.profile,
    required this.photos,
    required this.labelHeight,
    required this.onTap,
  });

  final MiniTreeNode node;
  final ProfilePhoto? profile;
  final Photos? photos;
  final double labelHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final FamilyMember m = node.member;
    final bool self = node.role == MiniRole.self;
    final String role = miniRoleName(node);
    final Widget initials = InitialsCircle(
      text: _initials(m.givenNames, m.surname),
      size: miniNode,
    );
    final Widget circle = switch ((photos, profile)) {
      (final Photos photos?, final ProfilePhoto p?) => ProfileCircle(
        file: photos.fileOf(p.relativePath),
        crop: p.crop,
        size: miniNode,
        unreadable: initials,
      ),
      _ => initials,
    };
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The ring over the photo: under it, the opaque circle would hide it (ui review).
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: self
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: GrobingColors.amber, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: GrobingColors.amber.withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                  ],
                )
              : const BoxDecoration(),
          child: circle,
        ),
        const SizedBox(height: _labelGap),
        SizedBox(
          height: labelHeight,
          child: Column(
            children: [
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GrobingColors.textMuted,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              Text(
                shortPersonName(m.givenNames, m.surname),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GrobingColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final String who = personName(
      m.givenNames,
      m.surname,
      birthSurname: m.birthSurname,
    );
    final String years = lifeYears(birth: m.birth, death: m.death);
    return Semantics(
      container: true,
      button: !self,
      label: self ? '$who, $years' : '$role: $who, $years',
      hint: self ? null : 'otwórz',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: body,
        ),
      ),
    );
  }

  static String _initials(String? given, String? surname) {
    final String letters = [
      for (final String? part in [given, surname])
        if (part != null && part.trim().isNotEmpty)
          part.trim().characters.first.toUpperCase(),
    ].join();
    return letters.isEmpty ? '?' : letters;
  }
}

/// The relation lines (style-b.md v1.16): the colour of the relation, and the shape — dashed 5/4 for
/// a pair "razem".
class _LinesPainter extends CustomPainter {
  _LinesPainter(this.lines);

  final List<MiniTreeLine> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final MiniTreeLine l in lines) {
      final Paint paint = Paint()
        ..color = l.kind == MiniLineKind.parentChild
            ? GrobingColors.relParentChild
            : GrobingColors.relPartners
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      if (l.kind == MiniLineKind.together) {
        _dashed(canvas, l.from, l.to, paint);
      } else {
        canvas.drawLine(l.from, l.to, paint);
      }
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final double length = (b - a).distance;
    if (length == 0) return;
    final Offset unit = (b - a) / length;
    for (double d = 0; d < length; d += 9) {
      canvas.drawLine(a + unit * d, a + unit * math.min(d + 5, length), paint);
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.lines != lines;
}
