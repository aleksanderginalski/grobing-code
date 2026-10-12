// Folding Polish text for matching — one place for the screens (`app/polish.dart` exports it) and the data
// layer, which matches the names of sectors with it (ISSUE-028).

/// Polish lower-case letters → their plain letter, by UTF-16 code unit (all in one unit).
const Map<int, int> _plain = {
  0x0105: 0x61, // ą → a
  0x0107: 0x63, // ć → c
  0x0119: 0x65, // ę → e
  0x0142: 0x6C, // ł → l
  0x0144: 0x6E, // ń → n
  0x00F3: 0x6F, // ó → o
  0x015B: 0x73, // ś → s
  0x017A: 0x7A, // ź → z
  0x017C: 0x7A, // ż → z
};

/// Lower case without Polish diacritics: "Łódź" → "lodz". Typing "ł" or "ź" on a phone keyboard needs
/// a long press, so the search does not ask for them. By code unit: the cemetery database folds about
/// 16 thousand names at its first use (ISSUE-015 D5, measured).
String fold(String s) {
  final List<int> units = s.toLowerCase().codeUnits.toList();
  for (int i = 0; i < units.length; i++) {
    if (units[i] >= 0xF3) units[i] = _plain[units[i]] ?? units[i];
  }
  return String.fromCharCodes(units);
}
