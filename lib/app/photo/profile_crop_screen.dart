import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/photos.dart';
import '../theme.dart';
import 'crop_geometry.dart';
import 'photo_viewer_screen.dart' show PhotoViewerBar;
import 'profile_circle.dart' show imageSizeOf;

/// "Kadr profilowego" (05_DESIGN/kadr-profilowego.md v1.2, K1, K2, K5): the circle stands still and the
/// photo moves and grows under it (D1); a tap brings a point to the middle and a double tap grows the photo
/// ×2 there — the one-pointer ways (D7', SC 2.5.1). No hint and no zoom buttons: the author's choice at
/// stop #2. Pops the square under the circle on "Gotowe", and nothing on back (D9). The photo stops at its
/// edge, so the circle is always all on it (D4).
class ProfileCropScreen extends StatefulWidget {
  const ProfileCropScreen({
    super.key,
    required this.file,
    required this.personName,
    this.initial,
  });

  final File file;

  /// The person as the form has them now (K1).
  final String personName;

  /// The link's crop; none starts from the middle (D3).
  final PhotoCrop? initial;

  @override
  State<ProfileCropScreen> createState() => _ProfileCropScreenState();
}

class _ProfileCropScreenState extends State<ProfileCropScreen>
    with SingleTickerProviderStateMixin {
  Size? _image;
  bool _failed = false;
  CropSquare? _square;

  /// Taps and double taps glide there in 250 ms; a finger moves it directly. Made in [initState],
  /// not lazily: a screen left without a tap would otherwise make it first in [dispose] (qa, ISSUE-018).
  late final AnimationController _glide;
  CropSquare? _from;
  CropSquare? _to;

  CropSquare? _start;
  Offset _startFocal = Offset.zero;

  /// Where the second tap of a double tap came down, in the area.
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_glided);
    imageSizeOf(widget.file).then(
      (size) {
        if (!mounted) return;
        setState(() {
          _image = size;
          _square = squareOf(widget.initial, size);
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  void _glided() {
    final CropSquare? from = _from;
    final CropSquare? to = _to;
    if (from == null || to == null) return;
    setState(
      () => _square = CropSquare.lerp(
        from,
        to,
        Curves.easeOut.transform(_glide.value),
      ),
    );
  }

  void _glideTo(CropSquare target) {
    final CropSquare? now = _square;
    if (now == null) return;
    _from = now;
    _to = target;
    _glide.forward(from: 0);
  }

  void _stopGlide() {
    if (_glide.isAnimating) _glide.stop();
    _from = _to = null;
  }

  /// A tap: the point is found on the photo as shown, the size kept from where a glide is heading — a tap
  /// during a double tap's glide keeps its whole step (ui review).
  void _centre(Offset tap, double diameter, Size image) {
    final CropSquare shown = _square!;
    final Offset point = centreOn(
      square: shown,
      tap: tap,
      diameter: diameter,
      image: image,
    ).centre;
    final double side = (_to ?? shown).side;
    _glideTo(
      clampSquare(
        CropSquare(point.dx - side / 2, point.dy - side / 2, side),
        image,
      ),
    );
  }

  /// The header read fine but the picture does not decode (e.g. a file cut short): "błąd odczytu" from
  /// the next frame on, so "Gotowe" cannot save a crop of nothing (ui review).
  Widget _decodeFailed() {
    if (!_failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _failed = true);
      });
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final Size? image = _image;
    final CropSquare? square = _square;
    final bool ready = !_failed && image != null && square != null;
    return Scaffold(
      backgroundColor: GrobingColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhotoViewerBar(
              title: 'Kadr profilowego',
              subtitle: widget.personName,
            ),
            Expanded(
              child: _failed
                  ? const _Unreadable()
                  : ready
                  ? _area(image, square)
                  : const SizedBox.expand(),
            ),
            // K5.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: ready
                    ? () => Navigator.of(
                        context,
                      ).pop((_to ?? square).toCrop(image))
                    : null,
                child: const Text(
                  'Gotowe',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// K2: the photo under a still circle, the rest of the photo dimmed around it.
  Widget _area(Size image, CropSquare square) => LayoutBuilder(
    builder: (context, constraints) {
      final double width = constraints.maxWidth;
      final double height = constraints.maxHeight;
      final double diameter = math.max(0, math.min(width, height) - 48);
      final Offset box = Offset(
        (width - diameter) / 2,
        (height - diameter) / 2,
      );
      final double k = diameter / square.side;
      return Semantics(
        label: 'Kadr profilowego — zdjęcie w okręgu',
        image: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Hidden from the screen reader: its "double tap" would tap the middle, which moves nothing
          // (ui review). Moving the photo with TalkBack is a named gap; zooming works (K4).
          excludeFromSemantics: true,
          onTapUp: (d) => _centre(d.localPosition - box, diameter, image),
          onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
          onDoubleTap: () => _glideTo(
            doubleTapped(
              square: _square!,
              tap: _doubleTapAt - box,
              diameter: diameter,
              image: image,
            ),
          ),
          onScaleStart: (d) {
            _stopGlide();
            _start = _square;
            _startFocal = d.localFocalPoint - box;
          },
          onScaleUpdate: (d) {
            final CropSquare? start = _start;
            if (start == null) return;
            setState(
              () => _square = moveAndScale(
                start: start,
                startFocal: _startFocal,
                focal: d.localFocalPoint - box,
                scale: d.scale,
                diameter: diameter,
                image: image,
              ),
            );
          },
          onScaleEnd: (_) => _start = null,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: box.dx - square.left * k,
                  top: box.dy - square.top * k,
                  width: image.width * k,
                  height: image.height * k,
                  child: Image.file(
                    widget.file,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _decodeFailed(),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CropFramePainter(box: box, diameter: diameter),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The frame of the crop — the only thing ever drawn on a photo (style-b.md rule 14, v1.10): the photo
/// outside the circle dimmed with the background at 72 %; the rule of thirds inside it, in the text
/// colour at 60 % with a shadow in the background colour (D6); the ring 2 dp in amber between two 1 dp
/// lines of the background, so it stands 8.81:1 against its neighbour on any photo (D10). No text.
class _CropFramePainter extends CustomPainter {
  const _CropFramePainter({required this.box, required this.diameter});

  final Offset box;
  final double diameter;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect circle = box & Size.square(diameter);
    final Path outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(circle),
    );
    canvas.drawPath(
      outside,
      Paint()..color = GrobingColors.background.withValues(alpha: 0.72),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    final Paint shadow = Paint()
      ..color = GrobingColors.background.withValues(alpha: 0.5)
      ..strokeWidth = 3;
    final Paint line = Paint()
      ..color = GrobingColors.text.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final Paint paint in [shadow, line]) {
      for (final double third in [1 / 3, 2 / 3]) {
        final double x = circle.left + diameter * third;
        final double y = circle.top + diameter * third;
        canvas.drawLine(Offset(x, circle.top), Offset(x, circle.bottom), paint);
        canvas.drawLine(Offset(circle.left, y), Offset(circle.right, y), paint);
      }
    }
    canvas.restore();

    final Offset centre = circle.center;
    final double radius = diameter / 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = GrobingColors.background,
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GrobingColors.amber,
    );
  }

  @override
  bool shouldRepaint(_CropFramePainter old) =>
      old.box != box || old.diameter != diameter;
}

/// "Błąd odczytu": the file cannot be opened — no circle, and "Gotowe" inactive.
class _Unreadable extends StatelessWidget {
  const _Unreadable();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: GrobingColors.textMuted,
        ),
        SizedBox(height: 12),
        Text(
          'Nie udało się otworzyć zdjęcia.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ],
    ),
  );
}
