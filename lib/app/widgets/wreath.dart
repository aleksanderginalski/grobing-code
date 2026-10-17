import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/clans.dart';
import '../../data/wreaths.dart';
import '../theme.dart';

// The wreath of a family line (ISSUE-044; 05_DESIGN/wieniec.md A): one of the author's motifs in the line's
// colour, with the C3 shading carried by the motif's image (tool/wreaths/) and a halo in the background's
// colour around every leaf (A5). Tinted once per pair of halves and size and kept: a frame of the tree only
// draws ready images — no blur, no layer per node (style-b.md rule 2; retro 4, R3).

/// The common frame (wieniec.md A2, D13): the wreath's box is twice the portrait, and the portrait's centre
/// sits at (0.5, [centreY]) of it.
abstract final class WreathFrame {
  static const double portraitFraction = 0.5;
  static const double centreY = 0.434;

  /// The halo's width, as a part of the box (A5: 1.5 dp around a 104 dp portrait).
  static const double halo = 0.0075;

  /// The box for a portrait of [portraitDiameter].
  static double box(double portraitDiameter) =>
      portraitDiameter / portraitFraction;

  /// Where the box goes for a portrait whose centre is [centre]: its top-left corner.
  static Offset origin(Offset centre, double portraitDiameter) {
    final double side = box(portraitDiameter);
    return Offset(centre.dx - side / 2, centre.dy - side * centreY);
  }

  /// How far the box reaches under the portrait's centre — the bottom of the knot is about 0.91 of it.
  static double below(double portraitDiameter) =>
      box(portraitDiameter) * (0.91 - centreY);
}

/// Tinted wreaths, kept for the life of the app: a handful of lines × a few sizes.
abstract final class WreathImages {
  static final Map<WreathMotif, Future<ui.Image?>> _motifs = {};
  static final Map<String, ui.Image> _ready = {};
  static final Map<String, Future<ui.Image?>> _pending = {};

  static String _key(Clan left, Clan right, int px) =>
      '${left.motif?.key}/${left.colour.key}|${right.motif?.key}/${right.colour.key}|$px';

  /// The image for [left] and [right] halves (the same line twice: the whole wreath) at [px] × [px], when
  /// it is ready; null while it is being made.
  static ui.Image? ready(Clan left, Clan right, int px) =>
      _ready[_key(left, right, px)];

  /// The image, made once; null when a motif's image cannot be read (wieniec.md *States*: no wreath).
  static Future<ui.Image?> get(Clan left, Clan right, int px) {
    final String key = _key(left, right, px);
    if (_ready[key] case final ui.Image image?) return Future.value(image);
    return _pending.putIfAbsent(key, () async {
      final ui.Image? image = await _compose(left, right, px);
      if (image != null) _ready[key] = image;
      unawaited(_pending.remove(key));
      return image;
    });
  }

  static Future<ui.Image?> _motif(WreathMotif motif) =>
      _motifs.putIfAbsent(motif, () async {
        try {
          final ByteData data = await rootBundle.load(motif.asset);
          final ui.Codec codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          return (await codec.getNextFrame()).image;
        } catch (_) {
          return null;
        }
      });

  static Future<ui.Image?> _compose(Clan left, Clan right, int px) async {
    final WreathMotif? lm = left.motif, rm = right.motif;
    if (lm == null || rm == null) return null;
    final ui.Image? li = await _motif(lm);
    final ui.Image? ri = await _motif(rm);
    if (li == null || ri == null) return null;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Rect box = Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble());
    final bool halves = left != right;
    if (halves) {
      _half(
        canvas,
        li,
        left.colour,
        box,
        Rect.fromLTWH(0, 0, px / 2, px * 1.0),
      );
      _half(
        canvas,
        ri,
        right.colour,
        box,
        Rect.fromLTWH(px / 2, 0, px / 2, px * 1.0),
      );
    } else {
      _half(canvas, li, left.colour, box, box);
    }
    return recorder.endRecording().toImage(px, px);
  }

  static void _half(
    Canvas canvas,
    ui.Image motif,
    ClanColour colour,
    Rect box,
    Rect clip,
  ) {
    final Rect src = Rect.fromLTWH(
      0,
      0,
      motif.width.toDouble(),
      motif.height.toDouble(),
    );
    canvas
      ..save()
      ..clipRect(clip);
    // A5: the halo — the leaves' shape in the background's colour, a little around every side.
    final Paint halo = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = const ColorFilter.mode(
        GrobingColors.background,
        BlendMode.srcIn,
      );
    final double r = box.width * WreathFrame.halo;
    for (int i = 0; i < 12; i++) {
      final double a = i * math.pi / 6;
      canvas.drawImageRect(
        motif,
        src,
        box.shift(Offset(math.cos(a) * r, math.sin(a) * r)),
        halo,
      );
    }
    // The line's colour times the shading: grey 128 is the colour itself (tool/wreaths/build_wreaths.py).
    final Color tone = GrobingColors.clan(colour);
    const double k = 255 / 128;
    canvas
      ..drawImageRect(
        motif,
        src,
        box,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.matrix(<double>[
            tone.r * k, 0, 0, 0, 0, //
            tone.g * k, 0, 0, 0, 0, //
            tone.b * k, 0, 0, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
      )
      ..restore();
  }
}

/// The wreath of [wreath] in a square box of [side] — under a portrait of half the box, centred at
/// (0.5, 0.434) of it (WreathFrame). Not touchable and outside the screen reader: the line is read where
/// it is written (osoba.md 4a). [oversample]: draw it sharper than the box, for a tree that is zoomed in.
class WreathView extends StatefulWidget {
  const WreathView({
    super.key,
    required this.wreath,
    required this.side,
    this.oversample = 1,
  });

  final PersonWreath wreath;
  final double side;
  final double oversample;

  @override
  State<WreathView> createState() => _WreathViewState();
}

class _WreathViewState extends State<WreathView> {
  ui.Image? _image;
  String? _wanted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(WreathView old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  void _resolve() {
    final Clan? left = widget.wreath.left, right = widget.wreath.right;
    if (left == null || right == null) {
      _image = null;
      _wanted = null;
      return;
    }
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    // Sizes in steps of 16 px: a few images per line, not one per zoom level.
    final int px = ((widget.side * dpr * widget.oversample / 16).ceil() * 16)
        .clamp(16, 1024);
    final String wanted = '${left.hashCode}|${right.hashCode}|$px';
    if (wanted == _wanted) return;
    _wanted = wanted;
    _image = WreathImages.ready(left, right, px);
    if (_image != null) return;
    WreathImages.get(left, right, px).then((ui.Image? image) {
      if (!mounted || _wanted != wanted) return;
      setState(() => _image = image);
    });
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.side,
        child: _image == null
            ? null
            : RawImage(
                image: _image,
                width: widget.side,
                height: widget.side,
                filterQuality: FilterQuality.medium,
              ),
      ),
    ),
  );
}

/// The wreath's sign in a list, a row or a tile (wieniec.md E1, E2, F4): the wreath around an empty circle
/// with an outline — the portrait's place. Without a wreath ([wreath] empty): a dashed circle (E1 „Brak”,
/// „Bez wieńca”).
class WreathSign extends StatelessWidget {
  const WreathSign({super.key, required this.wreath, required this.side});

  final PersonWreath wreath;
  final double side;

  @override
  Widget build(BuildContext context) {
    final double portrait = side * WreathFrame.portraitFraction;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          children: [
            if (!wreath.isEmpty) WreathView(wreath: wreath, side: side),
            Positioned(
              left: (side - portrait) / 2,
              top: side * WreathFrame.centreY - portrait / 2,
              width: portrait,
              height: portrait,
              child: CustomPaint(painter: _HolePainter(dashed: wreath.isEmpty)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line in words under the years (osoba.md 4a; wieniec.md C2, B5): "Ród: X", a married woman's
/// "Ród: X · po mężu Y" (hard spaces after "·" and "po": the line breaks before "·" — style-b.md rule 6); null without a wreath.
String? clanLine(PersonWreath w) {
  final Clan? own = w.own, husband = w.husbandClan;
  if (own != null && husband != null && own != husband) {
    return 'Ród: ${own.name} ·\u00A0po\u00A0mężu ${husband.name}';
  }
  if (own != null) return 'Ród: ${own.name}';
  if (husband != null) return 'Ród: po mężu ${husband.name}';
  return null;
}

/// A wreath of one line, for its sign where the line is chosen (wieniec.md E2, F4).
PersonWreath wreathOfClan(Clan clan) =>
    PersonWreath(own: clan, origin: WreathOrigin.chosenHere);

class _HolePainter extends CustomPainter {
  const _HolePainter({required this.dashed});

  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = GrobingColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Rect circle = (Offset.zero & size).deflate(0.5);
    if (!dashed) {
      canvas.drawOval(circle, paint);
      return;
    }
    // Dashed 4/3, as the uncertain node of the tree (drzewo.md D32).
    final double r = circle.width / 2;
    final double step = 7 / r;
    for (double a = 0; a < 2 * math.pi; a += step) {
      canvas.drawArc(circle, a, 4 / r, false, paint);
    }
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.dashed != dashed;
}
