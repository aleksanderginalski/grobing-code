import '../../data/database.dart' show DateQualifier, Sex;
import '../../data/family_tree.dart';
import '../../data/graves.dart' show QualifiedDate;
import '../dates.dart' show formatDate;
import '../polish.dart' show personName, polishCompare;

// "Następne" (05_DESIGN/drzewo.md v1.26, element 6a; ISSUE-050): what happened in a year of the tree — births,
// deaths, "razem" and weddings — for ⏭ and the caption of the year. Pure Dart, worked out once for the family, as
// TreeTime: ⏭ then only asks.
//
// An event stands in the year its date names (N1 — D60): "ok. 1870" in 1870, "między 1895 a 1900" in 1895, and the
// caption says the qualifier. A date without a year is no event — the windows of D31, D32 are for the dashed outline
// only, the app does not guess dates (D22).

/// What happened (D68), in the order of a year's caption: unions, births, deaths (element 6a). An end of a union
/// is no event of the caption, nor a burial.
enum TreeEventKind { together, marriage, birth, death }

/// One event: its date and its people — one, or the pair, the woman first (as in ISSUE-050 AC-1).
class TreeEvent {
  const TreeEvent(this.kind, this.date, this.people);

  final TreeEventKind kind;
  final QualifiedDate date;
  final List<int> people;

  int get year => date.from.year;

  /// The order inside a year: unions, then births, then deaths.
  int get _rank => switch (kind) {
    TreeEventKind.together || TreeEventKind.marriage => 0,
    TreeEventKind.birth => 1,
    TreeEventKind.death => 2,
  };
}

/// A piece of a caption's line: words, or a name — semibold on the screen (element 6a, style-b.md rule 4).
class CaptionPart {
  const CaptionPart(this.text, {this.name = false});

  final String text;
  final bool name;
}

/// At most this many events of a year at once; the next ⏭ shows the rest of the year (D66).
const int captionPage = 4;

/// A person's name in a caption: as in the card, without "z d." (D61), held together by hard spaces, so a line
/// breaks between people, not inside a name (style-b.md rule 6).
String captionName(TreePerson? person) =>
    personName(person?.givenNames, person?.surname).replaceAll(' ', '\u00A0');

/// A qualified date as a caption's postscript: " (ok.\u00A01870)" — nothing for a plain date.
String captionQualifier(QualifiedDate date) =>
    date.qualifier == DateQualifier.exact
    ? ''
    : ' (${formatDate(date).replaceAll(' ', '\u00A0')})';

/// The family's events, worked out once.
class TreeEvents {
  TreeEvents._(this._people, this._events);

  factory TreeEvents(FamilyTreeData data) {
    final List<TreeEvent> events = [];
    for (final TreePerson p in data.people.values) {
      if (p.birth case final QualifiedDate b) {
        events.add(TreeEvent(TreeEventKind.birth, b, [p.id]));
      }
      if (p.death case final QualifiedDate d) {
        events.add(TreeEvent(TreeEventKind.death, d, [p.id]));
      }
    }
    for (final TreeUnion u in data.unions) {
      if (u.partners.length < 2) continue;
      // The woman first, as in AC-1 ("Maria Zmyślona i Piotr Wymyślony"); else as written.
      final List<int> pair = [...u.partners]
        ..sort(
          (a, b) =>
              (data.people[a]?.sex == Sex.female ? 0 : 1) -
              (data.people[b]?.sex == Sex.female ? 0 : 1),
        );
      final QualifiedDate? wedding = u.married ? u.marriage : null;
      // "Razem" when the pair is not married, or was together before the wedding's year (D68).
      if (u.together case final QualifiedDate t
          when wedding == null || t.from.year < wedding.from.year) {
        events.add(TreeEvent(TreeEventKind.together, t, pair));
      }
      if (wedding != null) {
        events.add(TreeEvent(TreeEventKind.marriage, wedding, pair));
      }
    }
    return TreeEvents._(data.people, events);
  }

  final Map<int, TreePerson> _people;
  final List<TreeEvent> _events;

  /// [e] is about the people shown: all its people among [people] — a union only with both (K1 — D59).
  static bool _of(TreeEvent e, Set<int> people) =>
      e.people.every(people.contains);

  /// The years with an event of [people], from [start] and before [now] — this year is "dziś", where the tree is
  /// whole anyway — in order.
  List<int> yearsOf(Set<int> people, {required int start, required int now}) {
    final Set<int> years = {
      for (final TreeEvent e in _events)
        if (e.year >= start && e.year < now && _of(e, people)) e.year,
    };
    return years.toList()..sort();
  }

  /// The events of [people] in [year], in the caption's order: unions, births, deaths; inside each by the date's
  /// month and day, then by the name (element 6a).
  List<TreeEvent> inYear(int year, Set<int> people) {
    final List<TreeEvent> found = [
      for (final TreeEvent e in _events)
        if (e.year == year && _of(e, people)) e,
    ];
    int order(TreeEvent a, TreeEvent b) {
      final int byKind = a._rank - b._rank;
      if (byKind != 0) return byKind;
      final int byMonth = (a.date.from.month ?? 13) - (b.date.from.month ?? 13);
      if (byMonth != 0) return byMonth;
      final int byDay = (a.date.from.day ?? 32) - (b.date.from.day ?? 32);
      if (byDay != 0) return byDay;
      return polishCompare(
        captionName(_people[a.people.first]),
        captionName(_people[b.people.first]),
      );
    }

    return found..sort(order);
  }

  /// The words of [e] (F1 — D61): "Urodził się / Urodziła się / Urodził(a) się …" by the sex written, "Zmarł …",
  /// "Ślub: … i …", "Razem: … i …"; an uncertain date ends with its qualifier — "(ok. 1870)".
  List<CaptionPart> line(TreeEvent e) {
    final TreePerson? first = _people[e.people.first];
    String bySex(String male, String female, String unknown) =>
        switch (first?.sex) {
          Sex.male => male,
          Sex.female => female,
          null => unknown,
        };
    final CaptionPart name = CaptionPart(captionName(first), name: true);
    final String postscript = captionQualifier(e.date);
    return switch (e.kind) {
      TreeEventKind.birth => [
        CaptionPart('${bySex('Urodził', 'Urodziła', 'Urodził(a)')}\u00A0się '),
        name,
        if (postscript.isNotEmpty) CaptionPart(postscript),
      ],
      TreeEventKind.death => [
        CaptionPart('${bySex('Zmarł', 'Zmarła', 'Zmarł(a)')} '),
        name,
        if (postscript.isNotEmpty) CaptionPart(postscript),
      ],
      TreeEventKind.marriage || TreeEventKind.together => [
        CaptionPart(e.kind == TreeEventKind.marriage ? 'Ślub: ' : 'Razem: '),
        name,
        // The one-letter "i" holds the next name (style-b.md rule 6).
        const CaptionPart(' i\u00A0'),
        CaptionPart(captionName(_people[e.people.last]), name: true),
        // A union's date may be uncertain too ("ślub przed 1920"): the line says so, as a birth's (ui review, MAJOR).
        if (postscript.isNotEmpty) CaptionPart(postscript),
      ],
    };
  }
}
