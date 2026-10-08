import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/dates.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/graves.dart';

// ISSUE-012, US-002 AC-3 — dates as the notes give them (FR-004): what a date field takes, and the one
// way every screen writes a date (style-b.md rule 6; 05_DESIGN/wpis-osoby.md, grob.md).

final DateTime _today = DateTime(2026, 10, 7);

PartialDate? _parse(String s) => parsePartialDate(s, today: _today);

void main() {
  group('a date field takes rrrr, mm.rrrr and dd.mm.rrrr', () {
    test('the three precisions, with any of the three separators', () {
      expect(_parse('1890'), const PartialDate(1890));
      expect(_parse('03.1951'), const PartialDate(1951, 3));
      expect(_parse('3/1951'), const PartialDate(1951, 3));
      expect(_parse('14.03.1951'), const PartialDate(1951, 3, 14));
      expect(_parse('14-3-1951'), const PartialDate(1951, 3, 14));
      expect(_parse(' 1.1.1900 '), const PartialDate(1900, 1, 1));
    });

    test(
      'a leap day only in a leap year; the last year allowed is this one',
      () {
        expect(_parse('29.02.1904'), const PartialDate(1904, 2, 29));
        expect(_parse('29.02.1900'), isNull);
        expect(_parse('2026'), const PartialDate(2026));
        expect(_parse('2027'), isNull);
      },
    );

    test('anything else is refused', () {
      for (final String bad in [
        '196', // "1960" with a typo — the reason for the lower bound
        '1499',
        '31.02.1951',
        '13.1951',
        '00.1951',
        '1951.03',
        '14.03.51',
        '1.2.3.1951',
        'ok. 1890',
        '',
      ]) {
        expect(_parse(bad), isNull, reason: bad);
      }
    });
  });

  test('"między": the second date is later as far as both dates say', () {
    expect(isLater(const PartialDate(1893), const PartialDate(1895)), isTrue);
    expect(isLater(const PartialDate(1895), const PartialDate(1893)), isFalse);
    expect(isLater(const PartialDate(1893), const PartialDate(1893)), isFalse);
    expect(
      isLater(const PartialDate(1893, 3), const PartialDate(1893, 4)),
      isTrue,
    );
    expect(
      isLater(const PartialDate(1893, 3, 1), const PartialDate(1893, 3, 2)),
      isTrue,
    );
    // The same year, one without a month: nothing says it is later.
    expect(
      isLater(const PartialDate(1893), const PartialDate(1893, 4)),
      isFalse,
    );
  });

  test('US-002 AC-3 — each of the five qualifiers is written with it', () {
    expect(
      formatDate(const QualifiedDate(DateQualifier.exact, PartialDate(1890))),
      '1890',
    );
    expect(
      formatDate(const QualifiedDate(DateQualifier.about, PartialDate(1890))),
      'ok. 1890',
    );
    expect(
      formatDate(const QualifiedDate(DateQualifier.before, PartialDate(1920))),
      'przed 1920',
    );
    expect(
      formatDate(const QualifiedDate(DateQualifier.after, PartialDate(1945))),
      'po 1945',
    );
    expect(
      formatDate(
        const QualifiedDate(
          DateQualifier.between,
          PartialDate(1893),
          PartialDate(1895),
        ),
      ),
      'między 1893 a 1895',
    );
    expect(
      formatDate(
        const QualifiedDate(DateQualifier.exact, PartialDate(1951, 3, 14)),
      ),
      '14.03.1951',
    );
    expect(formatPartialDate(const PartialDate(1951, 3)), '03.1951');
  });

  test('the dates line of a person in a grave (grob.md, element 5)', () {
    const QualifiedDate y1921 = QualifiedDate(
      DateQualifier.exact,
      PartialDate(1921),
    );
    const QualifiedDate y1987 = QualifiedDate(
      DateQualifier.exact,
      PartialDate(1987),
    );
    const QualifiedDate about1890 = QualifiedDate(
      DateQualifier.about,
      PartialDate(1890),
    );
    const QualifiedDate died = QualifiedDate(
      DateQualifier.exact,
      PartialDate(1951, 3, 14),
    );
    const QualifiedDate buried = QualifiedDate(
      DateQualifier.exact,
      PartialDate(1951, 3, 18),
    );

    // Bare years: no spaces round the dash; anything more: spaces.
    expect(lifeLine(birth: y1921, death: y1987), '1921–1987');
    expect(lifeLine(birth: about1890, death: died), 'ok. 1890 – 14.03.1951');
    expect(
      lifeLine(birth: about1890, death: died, burial: buried),
      'ok. 1890 – 14.03.1951 · poch. 18.03.1951',
    );
    expect(lifeLine(birth: about1890), 'ur. ok. 1890');
    expect(lifeLine(death: died), 'zm. 14.03.1951');
    expect(lifeLine(burial: buried), 'poch. 18.03.1951');
    expect(lifeLine(), 'bez dat');
  });

  // ISSUE-022 — the years of a life in the list of people (05_DESIGN/osoby.md, element 4).
  test('lifeYears: years alone, with their qualifiers', () {
    QualifiedDate d(DateQualifier q, PartialDate from, [PartialDate? to]) =>
        QualifiedDate(q, from, to);
    final QualifiedDate born = d(
      DateQualifier.exact,
      const PartialDate(1926, 3, 14),
    );
    final QualifiedDate died = d(
      DateQualifier.exact,
      const PartialDate(2010, 11),
    );
    expect(lifeYears(birth: born, death: died), '1926–2010');
    expect(
      lifeYears(birth: d(DateQualifier.exact, const PartialDate(1955))),
      'ur. 1955',
    );
    expect(lifeYears(death: died), 'zm. 2010');
    expect(
      lifeYears(
        birth: d(DateQualifier.about, const PartialDate(1890)),
        death: died,
      ),
      'ok. 1890 – 2010',
    );
    expect(
      lifeYears(
        birth: d(
          DateQualifier.between,
          const PartialDate(1893),
          const PartialDate(1895),
        ),
      ),
      'ur. między 1893 a 1895',
    );
    expect(
      lifeYears(
        birth: d(
          DateQualifier.between,
          const PartialDate(1893, 3),
          const PartialDate(1893, 5),
        ),
      ),
      'ur. 1893',
      reason: 'between two dates of one year is that year',
    );
    expect(lifeYears(), 'bez dat');
  });
}
