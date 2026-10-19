import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/tree/tree_events.dart';
import 'package:grobing/app/tree/tree_layout.dart';
import 'package:grobing/data/database.dart';
import 'package:grobing/data/family_tree.dart';
import 'package:grobing/data/graves.dart' show PartialDate, QualifiedDate;
import 'package:grobing/dev/fictional_family.dart';

// ISSUE-050 — "Następne", the events of a year (lib/app/tree/tree_events.dart; 05_DESIGN/drzewo.md v1.26, element 6a):
// the years ⏭ goes to (N1 — D60: a qualified date in the year it names, a date without a year no event), the words of a
// line (F1 — D61, with "(a)" without a sex), "razem" and the wedding (D68), the order of a year, the people of the level
// shown (K1 — D59). The made-up family of the debug build, with ISSUE-037's uncertain dates. Made-up people only
// (family-data.md).

/// A hard space, as the captions write it (style-b.md rule 6).
final String _nb = String.fromCharCode(0xA0);

/// A line as the screen reads it, hard spaces as spaces.
String _text(List<CaptionPart> line) =>
    line.map((p) => p.text).join().replaceAll(_nb, ' ');

QualifiedDate _y(int year) =>
    QualifiedDate(DateQualifier.exact, PartialDate(year));

void main() {
  late FamilyTreeData family;
  late TreeEvents events;
  late Set<int> everyone;

  /// "Linia krwi" from "Ja" — the level shown at first (ISSUE-049, D50).
  late Set<int> bloodLine;

  List<String> lines(int year, Set<int> people) => [
    for (final TreeEvent e in events.inYear(year, people))
      _text(events.line(e)),
  ];

  setUpAll(() async {
    final GrobingDatabase db = GrobingDatabase(NativeDatabase.memory());
    await addFictionalFamily(db);
    family = await loadFamilyTree(db);
    await db.close();
    events = TreeEvents(family);
    everyone = family.people.keys.toSet();
    bloodLine = {
      for (final MapEntry<int, int> e in TreeGraph(
        family,
      ).unionLevels(family.meId!).entries)
        if (e.value <= 1) e.key,
    };
  });

  test(
    'N1, D60 — the years from the slider\'s start: the first is 1868; "ok. 1870" stands in 1870; a wedding and a birth '
    'without a date are no event; nothing from this year on, "dziś"',
    () {
      final List<int> years = events.yearsOf(everyone, start: 1860, now: 2026);
      expect(years.first, 1868);
      expect(years, contains(1870));
      // Antoni and Marianna married, the date not written: no 1892.
      expect(years, isNot(contains(1892)));
      // Stanisław (born — no date, died 1920): only his death is an event.
      expect(lines(1920, everyone), contains('Zmarł Stanisław Wymyślony'));
      expect(
        events
            .inYear(1901, everyone)
            .where((e) => e.kind == TreeEventKind.birth),
        isEmpty,
      );
      expect(years.every((y) => y >= 1860 && y < 2026), isTrue);
      expect(
        events.yearsOf(everyone, start: 1860, now: 1960).last,
        lessThan(1960),
      );
      expect(years, orderedEquals([...years]..sort()));
    },
  );

  test(
    'F1 — the words: "Urodziła się …", "Urodził się …", "Zmarł …", "Ślub: … i …"; the qualifier at the end: "(ok. 1870)", '
    '"(między 1895 a 1900)", "(przed 1900)", "(po 1905)"; names without "z d."',
    () {
      expect(lines(1870, everyone), [
        'Urodziła się Marianna Wymyślona (ok. 1870)',
      ]);
      expect(lines(1895, everyone), [
        'Urodził się Franciszek Wymyślony',
        'Urodził się Tadeusz Wymyślewicz (między 1895 a 1900)',
      ]);
      expect(
        lines(1900, everyone),
        contains('Urodził się Kazimierz Przykładek (przed 1900)'),
      );
      expect(
        lines(1905, everyone),
        contains('Urodziła się Leokadia Testowa (po 1905)'),
      );
      expect(lines(1944, everyone), ['Zmarł Leon Wymyślony (ok. 1944)']);
      // Helena "z d. Przykładzka" in the card — the caption says the name only.
      expect(lines(1946, everyone), [
        'Ślub: Helena Wymyślona i Józef Wymyślony',
      ]);
    },
  );

  test(
    'style-b.md rule 6 — a name holds together and the one-letter "i" holds the next one; the names are the line\'s bold parts',
    () {
      final TreeEvent wedding = events.inYear(1946, everyone).single;
      final List<CaptionPart> line = events.line(wedding);
      expect(line.where((p) => p.name).map((p) => p.text), [
        'Helena${_nb}Wymyślona',
        'Józef${_nb}Wymyślony',
      ]);
      expect(line.map((p) => p.text).join(), contains(' i$_nb'));
      expect(
        _text(events.line(events.inYear(1870, everyone).single)),
        endsWith('(ok. 1870)'),
      );
      expect(
        events.line(events.inYear(1870, everyone).single).last.text,
        ' (ok.${_nb}1870)',
      );
    },
  );

  test(
    'D68 — "razem" before the wedding and the wedding in its own year; "razem" alone without one; the woman first',
    () {
      expect(
        lines(1982, everyone),
        contains('Razem: Ewa Wymyślona i Marek Wymyślony'),
      );
      expect(
        lines(1985, everyone),
        contains('Ślub: Ewa Wymyślona i Marek Wymyślony'),
      );
      expect(
        lines(2014, everyone),
        contains('Razem: Natalia Zmyślewicz i Michał Wymyślony'),
      );
    },
  );

  test(
    'element 6a, K1 — 1955 on "Linia krwi": the wedding first, then the births by name; the wedding of two people of '
    'another level is not there, with everyone it is (D59)',
    () {
      expect(lines(1955, bloodLine), [
        'Ślub: Krystyna Zmyślona i Henryk Zmyślony',
        'Urodziła się Grażyna Testowiak',
        'Urodził się Marek Wymyślony',
        'Urodził się Roman Zmyślony',
        'Urodził się Wojciech Testowski',
      ]);
      expect(
        lines(1955, everyone),
        contains('Ślub: Wanda Przykładowa i Edmund Przykładowy'),
      );
      expect(events.inYear(1955, bloodLine).length, greaterThan(captionPage));
    },
  );

  test(
    'F1 — without a sex written: "Urodził(a) się …", "Zmarł(a) …"; without a name: "Osoba bez imienia"; a set '
    'without any date has no year to go to (D71)',
    () {
      final FamilyTreeData small = FamilyTreeData(
        people: {
          1: TreePerson(
            id: 1,
            givenNames: 'Kamila',
            surname: 'Testowa',
            birth: _y(1950),
            death: _y(2001),
            dead: true,
          ),
          2: TreePerson(id: 2, sex: Sex.male, birth: _y(1960)),
          3: const TreePerson(id: 3, givenNames: 'Bez', surname: 'Dat'),
        },
        unions: const [],
      );
      final TreeEvents few = TreeEvents(small);
      String one(int year) =>
          _text(few.line(few.inYear(year, {1, 2, 3}).single));
      expect(one(1950), 'Urodził(a) się Kamila Testowa');
      expect(one(2001), 'Zmarł(a) Kamila Testowa');
      expect(one(1960), 'Urodził się Osoba bez imienia');
      expect(few.yearsOf({3}, start: 1880, now: 2026), isEmpty);
    },
  );

  test(
    'D60 — a union with an uncertain date says so too: "Ślub: … i … (przed 1920)", "Razem: … i … (ok. 1922)" (ui review, '
    'MAJOR)',
    () {
      final FamilyTreeData small = FamilyTreeData(
        people: {
          1: const TreePerson(
            id: 1,
            givenNames: 'Jan',
            surname: 'Wymyślony',
            sex: Sex.male,
          ),
          2: const TreePerson(
            id: 2,
            givenNames: 'Maria',
            surname: 'Zmyślona',
            sex: Sex.female,
          ),
          3: const TreePerson(
            id: 3,
            givenNames: 'Anna',
            surname: 'Testowa',
            sex: Sex.female,
          ),
        },
        unions: const [
          TreeUnion(
            familyId: 1,
            partners: [1, 2],
            children: [],
            married: true,
            marriage: QualifiedDate(DateQualifier.before, PartialDate(1920)),
          ),
          TreeUnion(
            familyId: 2,
            partners: [1, 3],
            children: [],
            married: true,
            together: QualifiedDate(DateQualifier.about, PartialDate(1922)),
            marriage: QualifiedDate(DateQualifier.exact, PartialDate(1925)),
          ),
        ],
      );
      final TreeEvents few = TreeEvents(small);
      List<String> of(int year) => [
        for (final TreeEvent e in few.inYear(year, {1, 2, 3}))
          _text(few.line(e)),
      ];
      expect(of(1920), ['Ślub: Maria Zmyślona i Jan Wymyślony (przed 1920)']);
      expect(of(1922), ['Razem: Anna Testowa i Jan Wymyślony (ok. 1922)']);
      expect(of(1925), ['Ślub: Anna Testowa i Jan Wymyślony']);
    },
  );
}
