import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// One photo on the whole screen (05_DESIGN/zdjecie.md, B): all of it, nothing cut off, with zoom —
/// an inscription has to be readable (brief §4a, step 3). Nothing is drawn on the photo (style-b.md
/// rule 14): the title is in the bar, the actions below.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.file,
    this.pickReplacement,
    this.replace,
    this.onDelete,
  });

  final String title;

  /// What the photo is, e.g. "Zdjęcie nagrobka" — also its label for a screen reader.
  final String subtitle;
  final File file;

  /// B4 "Zmień zdjęcie", step 1: asks for another photo (the source sheet and the system window); null
  /// when the user cancels. Nothing is saved yet, so the viewer keeps showing the photo meanwhile.
  final Future<File?> Function()? pickReplacement;

  /// Step 2: keeps [picked] instead of the photo and returns the kept file. Throws when it fails — the
  /// old photo stays.
  final Future<File> Function(File picked)? replace;

  /// Deletes the photo after the window C; the viewer closes then.
  final Future<void> Function()? onDelete;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late File _file = widget.file;
  final TransformationController _zoom = TransformationController();
  Offset? _doubleTapAt;
  bool _changing = false;
  bool _changeFailed = false;

  /// Double tap zooms 2.5× at the tapped point and back — the single-pointer way to zoom
  /// (WCAG 2.2 SC 2.5.1, zdjecie.md D4), which also chooses what to look at.
  static const double _tapZoom = 2.5;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final Offset? at = _doubleTapAt;
    if (at == null) return;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
        -at.dx * (_tapZoom - 1),
        -at.dy * (_tapZoom - 1),
        0,
        1,
      )
      ..scaleByDouble(_tapZoom, _tapZoom, 1, 1);
  }

  /// "Zapisuję zdjęcie…" shows only once a photo is chosen (zdjecie.md, B — "zmiana w toku": after the
  /// choice), never while the sheet or the system window is open (ui review, MAJOR).
  Future<void> _change() async {
    final Future<File?> Function()? pick = widget.pickReplacement;
    final Future<File> Function(File picked)? replace = widget.replace;
    if (pick == null || replace == null || _changing) return;
    setState(() => _changeFailed = false);
    try {
      final File? picked = await pick();
      if (picked == null || !mounted) return;
      setState(() => _changing = true);
      final File changed = await replace(picked);
      if (!mounted) return;
      setState(() {
        _file = changed;
        _zoom.value = Matrix4.identity();
        _changing = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _changing = false;
          _changeFailed = true;
        });
      }
    }
  }

  Future<void> _delete() async {
    final Future<void> Function()? delete = widget.onDelete;
    if (delete == null) return;
    final bool? deleted = await showDialog<bool>(
      context: context,
      builder: (_) => DeletePhotoDialog(delete: delete),
    );
    if (deleted == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: GrobingColors.background,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(),
          Expanded(child: _changing ? const _Changing() : _photo()),
          if (_changeFailed)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PhotoErrorLine(
                'Nie udało się zapisać zdjęcia. Spróbuj jeszcze raz.',
              ),
            ),
          if (widget.replace != null || widget.onDelete != null) _actions(),
        ],
      ),
    ),
  );

  /// B1: back, the title and what the photo is — on the background, never on the photo.
  Widget _bar() => Row(
    children: [
      const Padding(
        padding: EdgeInsets.all(4),
        child: BackButton(color: GrobingColors.text),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: GrobingColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.subtitle,
              style: const TextStyle(
                color: GrobingColors.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
    ],
  );

  /// B2: the whole photo, fitted; pinch to 4×, or double tap.
  Widget _photo() => GestureDetector(
    onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
    onDoubleTap: _toggleZoom,
    child: InteractiveViewer(
      transformationController: _zoom,
      minScale: 1,
      maxScale: 4,
      child: SizedBox.expand(
        child: Image.file(
          _file,
          fit: BoxFit.contain,
          semanticLabel: widget.subtitle,
          errorBuilder: (_, _, _) => const _Unreadable(),
        ),
      ),
    ),
  );

  /// B4: "Zmień zdjęcie" in amber — the viewer's main action — and "Usuń zdjęcie" in the text colour,
  /// not inviting (style-b.md rule 14).
  Widget _actions() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 8,
      children: [
        if (widget.replace != null)
          TextButton.icon(
            onPressed: _changing ? null : _change,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Zmień zdjęcie'),
          ),
        if (widget.onDelete != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: GrobingColors.text,
              iconColor: GrobingColors.text,
            ),
            onPressed: _changing ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Usuń zdjęcie'),
          ),
      ],
    ),
  );
}

/// "B — zmiana w toku".
class _Changing extends StatelessWidget {
  const _Changing();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text(
          'Zapisuję zdjęcie…',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ],
    ),
  );
}

/// "B — błąd odczytu": the photo cannot be read; the actions stay, so it can be changed or deleted.
class _Unreadable extends StatelessWidget {
  const _Unreadable();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: GrobingColors.textMuted),
        SizedBox(height: 8),
        Text(
          'Nie udało się otworzyć zdjęcia.',
          style: TextStyle(color: GrobingColors.textMuted, fontSize: 14),
        ),
      ],
    ),
  );
}

/// A photo action that failed: the error colour, never alone — with the icon (SC 1.4.1).
class PhotoErrorLine extends StatelessWidget {
  const PhotoErrorLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.error_outline, size: 18, color: GrobingColors.error),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(color: GrobingColors.error, fontSize: 14),
        ),
      ),
    ],
  );
}

/// The window "Usunąć zdjęcie?" (05_DESIGN/zdjecie.md, C): it says what goes and what stays. The safe
/// action, "Zostaw", is the main one. It deletes itself, so a failure keeps it open with the message.
/// Pops true once the photo is deleted.
class DeletePhotoDialog extends StatefulWidget {
  const DeletePhotoDialog({super.key, required this.delete});

  final Future<void> Function() delete;

  @override
  State<DeletePhotoDialog> createState() => _DeletePhotoDialogState();
}

class _DeletePhotoDialogState extends State<DeletePhotoDialog> {
  bool _deleting = false;
  bool _failed = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _failed = false;
    });
    try {
      await widget.delete();
      if (mounted) Navigator.of(context).pop(true);
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
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: GrobingColors.surface,
    surfaceTintColor: Colors.transparent,
    title: const Text(
      'Usunąć zdjęcie?',
      style: TextStyle(
        color: GrobingColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Like the window "Odrzucić wpis?" it follows: the content in the text colour, 16 sp (ui review).
        const Text(
          'Zdjęcia nie będzie w aplikacji ani w kolejnych kopiach. '
          'Jeśli jest w galerii telefonu, tam zostaje.',
          style: TextStyle(color: GrobingColors.text, fontSize: 16),
        ),
        if (_failed) ...[
          const SizedBox(height: 12),
          const PhotoErrorLine(
            'Nie udało się usunąć zdjęcia. Spróbuj jeszcze raz.',
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: GrobingColors.text),
        onPressed: _deleting ? null : _delete,
        child: const Text('Usuń'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Zostaw'),
      ),
    ],
  );
}
