import '../data/database.dart';
import '../data/graves.dart';

// Dates as the notes give them (FR-004) — read from what is typed in a date field and written in
// Polish the one way every screen shows them (style-b.md rule 6; 05_DESIGN/wpis-osoby.md, date block;
// 05_DESIGN/grob.md, element 5).

/// The earliest year a date field takes: catches "190" typed for "1890", with room to spare
/// (05_DESIGN/wpis-osoby.md → Decisions).
const int earliestYear = 1500;

final RegExp _separators = RegExp(r'[.\-/]');

/// What is typed in a date field: `rrrr`, `mm.rrrr` or `dd.mm.rrrr`, with `.`, `-` or `/` between the
/// parts; a year from [earliestYear] to this year and a day that exists in its month. Null for
/// anything else.
PartialDate? parsePartialDate(String text, {DateTime? today}) {
  final List<String> parts = text.trim().split(_separators);
  if (parts.isEmpty || parts.length > 3) return null;
  final List<int?> numbers = [
    for (final String p in parts)
      RegExp(r'^\d{1,4}$').hasMatch(p.trim()) ? int.parse(p.trim()) : null,
  ];
  if (numbers.contains(null)) return null;
  final int year = numbers.last!;
  final int? month = numbers.length >= 2 ? numbers[numbers.length - 2] : null;
  final int? day = numbers.length == 3 ? numbers.first : null;
  if (parts.last.trim().length != 4) return null;
  if (year < earliestYear || year > (today ?? DateTime.now()).year) return null;
  if (month != null && (month < 1 || month > 12)) return null;
  if (day != null && (day < 1 || day > _daysIn(year, month!))) return null;
  return PartialDate(year, month, day);
}

int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Whether [to] is later than [from], as far as both say: a year apart, or the same year with both
/// months given and later, or the same month with both days given and later.
bool isLater(PartialDate from, PartialDate to) {
  if (to.year != from.year) return to.year > from.year;
  if (from.month == null || to.month == null) return false;
  if (to.month != from.month) return to.month! > from.month!;
  if (from.day == null || to.day == null) return false;
  return to.day! > from.day!;
}

/// `14.03.1951`, `03.1951`, `1890`.
String formatPartialDate(PartialDate d) => [
  if (d.day != null) _two(d.day!),
  if (d.month != null) _two(d.month!),
  '${d.year}',
].join('.');

String _two(int n) => n.toString().padLeft(2, '0');

/// The date with its qualifier: `1890`, `ok. 1890`, `przed 1920`, `po 1945`, `między 1893 a 1895`.
String formatDate(QualifiedDate d) {
  final String from = formatPartialDate(d.from);
  return switch (d.qualifier) {
    DateQualifier.exact => from,
    DateQualifier.about => 'ok. $from',
    DateQualifier.before => 'przed $from',
    DateQualifier.after => 'po $from',
    DateQualifier.between =>
      'między $from a ${d.to == null ? '…' : formatPartialDate(d.to!)}',
  };
}

/// The years of a life, for a list of people (05_DESIGN/osoby.md, element 4): `1926–2010`, `ur. 1955`,
/// `ok. 1890 – 1951`; `bez dat` when nothing is known. Months and days stay in the person's entry.
String lifeYears({QualifiedDate? birth, QualifiedDate? death}) =>
    lifeLine(birth: _yearOnly(birth), death: _yearOnly(death));

/// [d] with its years alone; "between" two dates of one year is that year.
QualifiedDate? _yearOnly(QualifiedDate? d) {
  if (d == null) return null;
  final PartialDate from = PartialDate(d.from.year);
  final PartialDate? to = d.to == null ? null : PartialDate(d.to!.year);
  if (to != null && to.year == from.year) {
    return QualifiedDate(DateQualifier.exact, from);
  }
  return QualifiedDate(d.qualifier, from, to);
}

/// A bare year — the one form that sits next to a dash without spaces.
bool _bareYear(QualifiedDate d) =>
    d.qualifier == DateQualifier.exact && d.from.month == null;

/// The dates line of a person in a grave (05_DESIGN/grob.md, element 5): `1921–1987`,
/// `ok. 1890 – 14.03.1951`, `ur. 1890`, `zm. 1951`, then `· poch. 18.03.1951` when the burial has a
/// date; `bez dat` when nothing is known.
String lifeLine({
  QualifiedDate? birth,
  QualifiedDate? death,
  QualifiedDate? burial,
}) {
  final String? life = switch ((birth, death)) {
    (null, null) => null,
    (final QualifiedDate b, null) => 'ur. ${formatDate(b)}',
    (null, final QualifiedDate d) => 'zm. ${formatDate(d)}',
    (final QualifiedDate b, final QualifiedDate d) =>
      _bareYear(b) && _bareYear(d)
          ? '${formatDate(b)}–${formatDate(d)}'
          : '${formatDate(b)} – ${formatDate(d)}',
  };
  final List<String> parts = [
    ?life,
    if (burial != null) 'poch. ${formatDate(burial)}',
  ];
  return parts.isEmpty ? 'bez dat' : parts.join(' · ');
}
