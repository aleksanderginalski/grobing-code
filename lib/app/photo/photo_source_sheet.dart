import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/grobing_icon.dart';
import 'photo_picker.dart';

/// The source sheet (05_DESIGN/zdjecie.md, A): the gallery first, then the camera (D1). Null when the
/// sheet is closed without a choice. One photo — a gravestone's, a cemetery's, a person's background.
Future<PhotoSource?> showPhotoSourceSheet(
  BuildContext context, {
  String title = 'Zdjęcie nagrobka',
}) => _showSourceSheet<PhotoSource>(
  context,
  title: title,
  rows: const [
    _SourceRow(
      icon: Glyphs.photoLibrary,
      label: 'Wybierz z galerii',
      value: PhotoSource.gallery,
    ),
    _SourceRow(
      icon: Glyphs.photoCamera,
      label: 'Zrób zdjęcie',
      value: PhotoSource.camera,
    ),
  ],
);

/// Where a person's photos come from (zdjecie.md v1.7): the system's gallery or camera, or a photo already
/// in the app on someone else (A4).
enum PersonPhotoSource { gallery, camera, app }

/// The sheet of a person's photos, "Zdjęcia osoby" (zdjecie.md v1.3, A): several from the gallery. With
/// [fromApp] — only when there is a photo to choose (D10) — a third row, "Ze zdjęć w aplikacji" (v1.7, A4).
Future<PersonPhotoSource?> showPersonPhotoSourceSheet(
  BuildContext context, {
  required bool fromApp,
}) => _showSourceSheet<PersonPhotoSource>(
  context,
  title: 'Zdjęcia osoby',
  rows: [
    const _SourceRow(
      icon: Glyphs.photoLibrary,
      label: 'Wybierz z galerii',
      value: PersonPhotoSource.gallery,
    ),
    const _SourceRow(
      icon: Glyphs.photoCamera,
      label: 'Zrób zdjęcie',
      value: PersonPhotoSource.camera,
    ),
    if (fromApp)
      const _SourceRow(
        icon: Glyphs.group,
        label: 'Ze zdjęć w\u00A0aplikacji',
        detail: 'zdjęcia, które już są u\u00A0innych osób',
        value: PersonPhotoSource.app,
      ),
  ],
);

Future<T?> _showSourceSheet<T>(
  BuildContext context, {
  required String title,
  required List<_SourceRow<T>> rows,
}) => showModalBottomSheet<T>(
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
        ...rows,
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// A2–A4: a row ≥ 56 dp, the icon in amber (an action — style-b.md rule 3), the label in the text colour;
/// A4 with a muted line under it.
class _SourceRow<T> extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final Glyph icon;
  final String label;
  final String? detail;
  final T value;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).pop(value),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            GrobingIcon(icon, color: GrobingColors.amber),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: GrobingColors.text,
                      fontSize: 16,
                    ),
                  ),
                  if (detail case final String line)
                    Text(
                      line,
                      style: const TextStyle(
                        color: GrobingColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
