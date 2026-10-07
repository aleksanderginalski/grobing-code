import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/photos.dart';
import 'crop_geometry.dart';
import 'photo_viewer_screen.dart' show coverDecodeWidth;

/// The size of a photo's file in pixels, read from its header — no decoding of the picture. Remembered
/// per path: a photo's file never changes in place (ADR-008), and a new one gets a new path.
Future<Size> imageSizeOf(File file) {
  return _sizes[file.path] ??= () async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(
      file.path,
    );
    try {
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final Size size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      return size;
    } finally {
      buffer.dispose();
    }
  }();
}

final Map<String, Future<Size>> _sizes = {};

/// A person's profile photo in a circle of [size] (05_DESIGN/kadr-profilowego.md → "Gdzie kadr widać"):
/// the [crop] of their link, or without one the largest square from the middle, as every circle showed
/// before ISSUE-018. One widget for the three circles — the form (80 dp), the grave view's card (40 dp)
/// and the header of the person's photos (96 dp). [unreadable] stands in for a file that cannot be read.
///
/// A crop needs the photo's size; until the header is read (a moment) the circle stays empty — the middle
/// of a group photo may be someone else (ui review).
class ProfileCircle extends StatefulWidget {
  const ProfileCircle({
    super.key,
    required this.file,
    this.crop,
    required this.size,
    required this.unreadable,
  });

  final File file;
  final PhotoCrop? crop;
  final double size;
  final Widget unreadable;

  @override
  State<ProfileCircle> createState() => _ProfileCircleState();
}

class _ProfileCircleState extends State<ProfileCircle> {
  Size? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _readSize();
  }

  @override
  void didUpdateWidget(ProfileCircle old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      _image = null;
      _failed = false;
      _readSize();
    } else if (old.crop == null && widget.crop != null && _image == null) {
      _readSize();
    }
  }

  void _readSize() {
    if (widget.crop == null) return;
    final String path = widget.file.path;
    imageSizeOf(widget.file).then(
      (size) {
        if (mounted && widget.file.path == path) setState(() => _image = size);
      },
      onError: (Object _) {
        if (mounted && widget.file.path == path) setState(() => _failed = true);
      },
    );
  }

  /// The picture failed to decode after its header read fine: [ProfileCircle.unreadable] from the next
  /// frame on (a builder cannot set state itself).
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
    final double size = widget.size;
    final Size? image = _image;
    final PhotoCrop? crop = widget.crop;
    final Widget content;
    if (_failed) {
      content = widget.unreadable;
    } else if (crop != null && image == null) {
      content = const SizedBox.shrink();
    } else if (crop == null || image == null) {
      content = Image.file(
        widget.file,
        fit: BoxFit.cover,
        cacheWidth: coverDecodeWidth(context, size),
        errorBuilder: (_, _, _) => widget.unreadable,
      );
    } else {
      final CropSquare square = squareOf(crop, image);
      final double k = size / square.side;
      content = Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -square.left * k,
            top: -square.top * k,
            width: image.width * k,
            height: image.height * k,
            child: Image.file(
              widget.file,
              fit: BoxFit.fill,
              cacheWidth: cropDecodeWidth(
                imageWidth: image.width,
                cropSide: square.side,
                circlePixels: size * MediaQuery.devicePixelRatioOf(context),
              ),
              errorBuilder: (_, _, _) => _decodeFailed(),
            ),
          ),
        ],
      );
    }
    return ClipOval(
      child: SizedBox.square(dimension: size, child: content),
    );
  }
}
