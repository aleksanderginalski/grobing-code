import 'folding.dart';

// The manager's address as the author types it (05_DESIGN/grob.md v6, element 3b; ISSUE-028): one place for
// the window, the writes and the v10→v11 migration, so they never disagree on what one sector is.

/// The words the address puts before each part: "Kwatera B · Rząd 4 · Miejsce 12".
const String sectorWord = 'Kwatera', rowWord = 'Rząd', plotWord = 'Miejsce';

/// One part of the address as stored: trimmed, inner spaces single, without the part's own [word] in front
/// — typed "Kwatera B" is "B", so the address never says "Kwatera Kwatera B" — and none when nothing is left.
String? addressPart(String? typed, String word) {
  String s = (typed ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  final RegExp lead = RegExp(
    '^${RegExp.escape(word)}(?:[\\s.:]+|\$)',
    caseSensitive: false,
    unicode: true,
  );
  s = s.replaceFirst(lead, '').trim();
  return s.isEmpty ? null : s;
}

/// What makes two names one sector on a cemetery: without case, Polish letters and "Kwatera" in front —
/// "b", "B" and "Kwatera B" are one (05_DESIGN/cmentarz.md, element 19). Unique per cemetery (ADR-016).
String sectorKey(String name) => fold(addressPart(name, sectorWord) ?? '');
