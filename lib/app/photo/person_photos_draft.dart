import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/database.dart';
import '../../data/graves.dart';
import '../../data/photos.dart' as data;
import 'photos.dart';

/// One photo of the person being edited: what it is and where to show it from — the kept file, or the
/// prepared one while it waits for "Zapisz".
class DraftPhoto {
  const DraftPhoto(this.ref, this.file);

  final data.PhotoRef ref;
  final File file;
}

/// A person's photos while their form is open (05_DESIGN/zdjecia-osoby.md D1): every change — added
/// photos, the profile, who else is on a photo, a photo removed — waits here and is written with the
/// person's "Zapisz" ([edits]), or dropped with "Odrzuć" ([dispose]).
class PersonPhotosDraft extends ChangeNotifier {
  PersonPhotosDraft({
    required this.database,
    required this.photos,
    this.personId,
    this.graveId,
  });

  final GrobingDatabase database;
  final Photos photos;

  /// The person being corrected; null for a new one.
  final int? personId;

  /// The grave the form was opened from — its people come first when choosing who is on a photo.
  final int? graveId;

  final List<DraftPhoto> _items = [];
  List<int> _savedOrder = const [];
  final Map<data.PhotoRef, Set<int>> _others = {};
  final Map<data.PhotoRef, Set<int>> _savedOthers = {};
  final List<data.NewPhoto> _created = [];
  int _preparing = 0;
  ({int failed, int of})? _failure;
  bool _disposed = false;

  /// The photos in their order; the first is the profile photo.
  List<DraftPhoto> get items => List.unmodifiable(_items);
  DraftPhoto? get profile => _items.isEmpty ? null : _items.first;
  int get count => _items.length;

  /// How many picked photos are still being prepared.
  int get preparing => _preparing;

  /// The last adding of photos, when some of them could not be read.
  ({int failed, int of})? get failure => _failure;

  bool get hasChanges =>
      _others.isNotEmpty ||
      !listEquals(_savedOrder, [
        for (final DraftPhoto p in _items)
          if (p.ref case data.SavedPhoto(:final int mediaId)) mediaId else -1,
      ]);

  /// Loads the person's saved photos (a correction); nothing for a new person.
  Future<void> load() async {
    final int? id = personId;
    if (id == null) return;
    final List<data.PersonPhoto> saved = await data.personPhotos(database, id);
    _items
      ..clear()
      ..addAll([
        for (final data.PersonPhoto p in saved)
          DraftPhoto(data.SavedPhoto(p.mediaId), photos.fileOf(p.relativePath)),
      ]);
    _savedOrder = [for (final data.PersonPhoto p in saved) p.mediaId];
    _notify();
  }

  /// Prepares [picked] one by one and adds each at the end (zdjecia-osoby.md → States); a photo that
  /// cannot be read is counted in [failure], and the others stay.
  Future<void> addPicked(List<File> picked) async {
    if (picked.isEmpty) return;
    _failure = null;
    _preparing += picked.length;
    _notify();
    int failed = 0;
    for (final File file in picked) {
      try {
        final data.NewPhoto photo = await photos.preparePersonPhoto(file);
        if (_disposed) {
          await photos.discard(photo);
        } else {
          _created.add(photo);
          _items.add(DraftPhoto(photo, photo.prepared));
        }
      } on Object {
        failed++;
      } finally {
        _preparing--;
        _notify();
      }
    }
    if (failed > 0) {
      _failure = (failed: failed, of: picked.length);
      _notify();
    }
  }

  /// Makes [photo] the profile photo: the first of this person's (zdjecie.md B4').
  void setProfile(DraftPhoto photo) {
    if (!_items.remove(photo)) return;
    _items.insert(0, photo);
    _notify();
  }

  /// Removes [photo] from this person only (zdjecie.md C1'); others on it keep it.
  void remove(DraftPhoto photo) {
    if (!_items.remove(photo)) return;
    _notify();
  }

  /// Everyone else on [photo]: as changed in this form, or as saved.
  Future<Set<int>> othersOf(DraftPhoto photo) async {
    final Set<int>? changed = _others[photo.ref];
    if (changed != null) return {...changed};
    return {...await _savedOthersOf(photo.ref)};
  }

  /// Everyone else on [photo] after "Gotowe" in "Kto jest na zdjęciu?" (zdjecie.md, D).
  Future<void> setOthers(DraftPhoto photo, Set<int> others) async {
    final Set<int> wanted = {...others}..remove(personId);
    if (setEquals(wanted, await _savedOthersOf(photo.ref))) {
      _others.remove(photo.ref);
    } else {
      _others[photo.ref] = wanted;
    }
    _notify();
  }

  Future<Set<int>> _savedOthersOf(data.PhotoRef ref) async {
    if (ref is! data.SavedPhoto) return const {};
    return _savedOthers[ref] ??= {
      ...await data.photoPeopleIds(database, ref.mediaId),
    }..remove(personId);
  }

  /// Who can be chosen on a photo — everyone, this grave's people first (zdjecie.md D7).
  Future<({List<PersonChoice> all, List<int> inGrave})> choices() =>
      loadPersonChoices(database, graveId: graveId);

  /// What "Zapisz" writes; null when nothing changed.
  data.PersonPhotoEdits? edits() => hasChanges
      ? data.PersonPhotoEdits(
          photos: [for (final DraftPhoto p in _items) p.ref],
          others: {
            for (final MapEntry<data.PhotoRef, Set<int>> e in _others.entries)
              e.key: {...e.value},
          },
        )
      : null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Drops the prepared files that were not saved. After a successful "Zapisz" they have moved into the
  /// media directory already, so nothing of the person's photos goes.
  @override
  void dispose() {
    _disposed = true;
    for (final data.NewPhoto p in _created) {
      photos.discard(p);
    }
    super.dispose();
  }
}
