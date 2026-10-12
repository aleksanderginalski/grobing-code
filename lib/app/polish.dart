// Polish text for the screens: plural forms, alphabetical order, matching without diacritics and
// endings (05_DESIGN/cmentarze.md D3; style-b.md rule 6). One place, because every later screen needs
// the same rules.

import '../data/database.dart' show PositionSource, Sex;
import '../data/folding.dart';

export '../data/folding.dart' show fold;

/// The form of a noun after [n]: 1 grób · 2–4 groby (but 12–14 grobów) · 0, 5+ grobów.
String plural(int n, String one, String few, String many) {
  if (n == 1) return one;
  final int lastDigit = n % 10, lastTwo = n % 100;
  if (lastDigit >= 2 && lastDigit <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return few;
  }
  return many;
}

String gravesLabel(int n) => '$n ${plural(n, 'grób', 'groby', 'grobów')}';
String peopleLabel(int n) => '$n ${plural(n, 'osoba', 'osoby', 'osób')}';
String cemeteriesLabel(int n) =>
    '$n ${plural(n, 'cmentarz', 'cmentarze', 'cmentarzy')}';
String cornersLabel(int n) => '$n ${plural(n, 'róg', 'rogi', 'rogów')}';

/// "Adresy 1 grobu", "Adresy 2 grobów" — the genitive after a number (05_DESIGN/cmentarz.md, element 19b).
String gravesGenitive(int n) => '$n ${n == 1 ? 'grobu' : 'grobów'}';

/// The order of sectors on a list (05_DESIGN/cmentarz.md, element 17a): numbers as numbers — 2 before 10 —
/// and the rest in the Polish alphabet, digits before letters as in [polishCompare].
int sectorOrder(String a, String b) {
  final RegExp chunk = RegExp(r'\d+|\D+');
  final List<String> x = [for (final m in chunk.allMatches(a)) m[0]!];
  final List<String> y = [for (final m in chunk.allMatches(b)) m[0]!];
  for (int i = 0; i < x.length && i < y.length; i++) {
    final int? nx = int.tryParse(x[i]), ny = int.tryParse(y[i]);
    final int c = nx != null && ny != null
        ? nx.compareTo(ny)
        : polishCompare(x[i], y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// "Imiona Nazwisko", with " z d. Rodowe" when [birthSurname] is given (style-b.md rule 6); what there
/// is when a part is missing.
String personName(String? givenNames, String? surname, {String? birthSurname}) {
  final String name = [?givenNames, ?surname].join(' ');
  final String shown = name.isEmpty ? 'Osoba bez imienia' : name;
  return birthSurname == null ? shown : '$shown z d. $birthSurname';
}

/// The manager's address in full words: "Kwatera B · Rząd 4 · Miejsce 12" (style-b.md rule 6); null
/// when the grave has none.
String? graveAddress(String? sector, String? row, String? plot) {
  final List<String> parts = [
    if (sector != null) 'Kwatera $sector',
    if (row != null) 'Rząd $row',
    if (plot != null) 'Miejsce $plot',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The address with what is missing said as a fact (style-b.md rule 7; 05_DESIGN/cmentarz.md,
/// element 3c): "Kwatera B · Rząd 3 · Miejsce 12 · bez pinezki", "Bez adresu kwatery · bez pinezki".
String addressLine(String? address, {required bool hasPin}) =>
    [address ?? 'Bez adresu kwatery', if (!hasPin) 'bez pinezki'].join(' · ');

/// Where a pin's position came from (05_DESIGN/cmentarz.md, element 14, D33): "GPS ±4 m" with the phone's
/// accuracy in whole metres, or the layer the author's hand placed it on.
String pinSourceText(PositionSource source, double? accuracyM) =>
    switch (source) {
      PositionSource.gps =>
        accuracyM == null ? 'GPS' : 'GPS ±${accuracyM.round()} m',
      PositionSource.plan => 'postawiona na planie',
      PositionSource.satellite => 'postawiona na zdjęciu z góry',
    };

/// The pin's line under the grave's address (05_DESIGN/grob.md v7, element 4): "GPS ±4 m · 12.10.2026";
/// a pin without a date (written before v12) has none.
String pinLine(PositionSource source, double? accuracyM, DateTime? recordedAt) {
  final String what = pinSourceText(source, accuracyM);
  if (recordedAt == null) return what;
  String two(int v) => v.toString().padLeft(2, '0');
  final DateTime d = recordedAt.toLocal();
  return '$what · ${two(d.day)}.${two(d.month)}.${d.year}';
}

/// What a query is matched with: its words, folded, and those of 5 letters or more without the last
/// two — Polish endings change ("Powązki" → "na Powązkach"), the stem does not (measured on the
/// OpenStreetMap extract, ISSUE-014 → Stop #1 — round 1).
List<String> searchStems(String query) => [
  for (final String w in fold(query).split(RegExp(r'\s+')))
    if (w.isNotEmpty) w.length >= 5 ? w.substring(0, w.length - 2) : w,
];

/// Whether every stem of [query] occurs in one of [fields].
bool matchesQuery(String query, Iterable<String?> fields) {
  final String haystack = fold(fields.whereType<String>().join(' | '));
  final List<String> stems = searchStems(query);
  return stems.isNotEmpty && stems.every(haystack.contains);
}

/// Whether every word of [query] starts a word of one of [fields], folded (05_DESIGN/osoby.md, element
/// 2): "wymys" finds "Wymyślona", "zmys" finds "Zmyślonek" and "Testowa-Zmyślonek", but not "Przezmyślonek".
/// Unlike [matchesQuery] no ending is cut: a name is typed from its start, and a cut stem would find
/// names inside other names.
bool matchesWordStart(String query, Iterable<String?> fields) {
  final List<String> words = _words(query);
  if (words.isEmpty) return false;
  final List<String> haystack = [
    for (final String field in fields.whereType<String>()) ..._words(field),
  ];
  return words.every((w) => haystack.any((h) => h.startsWith(w)));
}

/// Folded words of [s], split at spaces and hyphens (a double surname is two words).
List<String> _words(String s) => [
  for (final String w in fold(s).split(RegExp(r'[\s-]+')))
    if (w.isNotEmpty) w,
];

const String _alphabet = 'aąbcćdeęfghijklłmnńoópqrsśtuvwxyzźż';

/// Compares in the order of the Polish alphabet (ą after a, ł after l, ż last), ignoring case. Other
/// characters keep their code order after the letters.
int polishCompare(String a, String b) {
  final String x = a.toLowerCase(), y = b.toLowerCase();
  for (int i = 0; i < x.length && i < y.length; i++) {
    final int c = _rank(x[i]).compareTo(_rank(y[i]));
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

int _rank(String ch) {
  final int i = _alphabet.indexOf(ch);
  // Digits, spaces and punctuation before letters, in their own order.
  return i >= 0 ? 1000 + i : ch.codeUnitAt(0);
}

/// Men's names ending in "-a" — the rule's mistakes among the dead in the PESEL register's first names
/// (ISSUE-019 → Prior art: 0.066%).
const Set<String> _menOnA = {
  'kuba',
  'bonawentura',
  'dyzma',
  'kosma',
  'jarema',
  'kuźma',
  'barnaba',
};

/// The sex the form suggests from the first given name (05_DESIGN/wpis-osoby.md D-płeć): "-a" is a woman,
/// anything else a man, but for [_menOnA]; no given names, no suggestion. A suggestion is shown before it
/// is saved, and a touch changes it.
Sex? suggestSex(String? givenNames) {
  final List<String> words = (givenNames ?? '').trim().split(RegExp(r'\s+'));
  final String first = words.first.toLowerCase();
  if (first.isEmpty) return null;
  if (_menOnA.contains(first)) return Sex.male;
  return first.endsWith('a') ? Sex.female : Sex.male;
}

/// Each word with a capital first letter: "cmentarz leśny" → "Cmentarz Leśny" (the name field's own
/// capitalisation, applied to what came from the search).
String capitalizeWords(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
