import 'package:flutter/material.dart';

import '../theme.dart';
import 'photo_picker.dart';

/// The source sheet (05_DESIGN/zdjecie.md, A): the gallery first, then the camera (D1). Null when the
/// sheet is closed without a choice. For a person's photos the title is "Zdjęcia osoby" and the caller
/// picks several from the gallery (v1.3).
Future<PhotoSource?> showPhotoSourceSheet(
  BuildContext context, {
  String title = 'Zdjęcie nagrobka',
}) => showModalBottomSheet<PhotoSource>(
  context: context,
  backgroundColor: GrobingColors.surface,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: GrobingColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const _SourceRow(
          icon: Icons.photo_library_outlined,
          label: 'Wybierz z galerii',
          source: PhotoSource.gallery,
        ),
        const _SourceRow(
          icon: Icons.photo_camera_outlined,
          label: 'Zrób zdjęcie',
          source: PhotoSource.camera,
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// A2–A3: a row ≥ 56 dp, the icon in amber (an action — style-b.md rule 3), the label in the text colour.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.source,
  });

  final IconData icon;
  final String label;
  final PhotoSource source;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).pop(source),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: GrobingColors.amber),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: GrobingColors.text, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
