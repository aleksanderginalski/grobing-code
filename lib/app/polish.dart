// Polish text for the screens: plural forms, alphabetical order, matching without diacritics and
// endings (05_DESIGN/cmentarze.md D3; style-b.md rule 6). One place, because every later screen needs
// the same rules.

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

const Map<String, String> _plain = {
  'ą': 'a',
  'ć': 'c',
  'ę': 'e',
  'ł': 'l',
  'ń': 'n',
  'ó': 'o',
  'ś': 's',
  'ź': 'z',
  'ż': 'z',
};

/// Lower case without Polish diacritics: "Łódź" → "lodz". Typing "ł" or "ź" on a phone keyboard needs
/// a long press, so the search does not ask for them.
String fold(String s) {
  final StringBuffer out = StringBuffer();
  for (final String ch in s.toLowerCase().split('')) {
    out.write(_plain[ch] ?? ch);
  }
  return out.toString();
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

/// Each word with a capital first letter: "cmentarz leśny" → "Cmentarz Leśny" (the name field's own
/// capitalisation, applied to what came from the search).
String capitalizeWords(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
