import '../../data/database.dart' show Sex;
import '../../data/kinship.dart';

/// The word for one step of the chain (05_DESIGN/osoba.md element 7, D13'): what the person in the row
/// is to the one above — from their sex; for a partner, from whether the pair married. Without a sex,
/// the neutral word. The compound names ("babcia", "stryj", "siostra cioteczna") are the tree's, when it
/// joins two people (drzewo.md D6) — not the person's view.
String stepWord(KinEdge edge, Sex? sex, {bool married = false}) =>
    switch ((edge, sex)) {
      (KinEdge.parent, Sex.female) => 'mama',
      (KinEdge.parent, Sex.male) => 'tata',
      (KinEdge.parent, null) => 'rodzic',
      (KinEdge.child, Sex.female) => 'córka',
      (KinEdge.child, Sex.male) => 'syn',
      (KinEdge.child, null) => 'dziecko',
      (KinEdge.sibling, Sex.female) => 'siostra',
      (KinEdge.sibling, Sex.male) => 'brat',
      (KinEdge.sibling, null) => 'rodzeństwo',
      (KinEdge.partner, Sex.female) => married ? 'żona' : 'partnerka',
      (KinEdge.partner, Sex.male) => married ? 'mąż' : 'partner',
      (KinEdge.partner, null) => married ? 'małżonek' : 'partner',
    };

/// The words that take "jej": the feminine ones. Every other word — the masculine and the neutral
/// "rodzic", "dziecko", "rodzeństwo", "partner", "małżonek" — takes "jego", by the word's gender, not the
/// person's (osoba.md element 7), so a step after someone without a sex still says whose it is.
const Set<String> _feminine = {'mama', 'córka', 'siostra', 'żona', 'partnerka'};

/// One person of the chain as their row is labelled: the step's word and the first name.
class ChainPerson {
  const ChainPerson({
    required this.edge,
    this.sex,
    this.married = false,
    required this.name,
  });

  final KinEdge edge;
  final Sex? sex;
  final bool married;

  /// The first name — or what there is.
  final String name;
}

/// The labels of the chain's rows after "Ja", as the path card in R3 spells it: "Mama Anna", "Jej mama
/// Maria"; "Żona Kasia", "Jej tata Marek", "Jego siostra Ewa". The first row is to "Ja" and has no
/// pronoun; every next one has the pronoun of the word in the row above.
List<String> chainLabels(List<ChainPerson> people) {
  final List<String> labels = [];
  String? before;
  for (final ChainPerson p in people) {
    final String word = stepWord(p.edge, p.sex, married: p.married);
    final String phrase = before == null
        ? word
        : '${_feminine.contains(before) ? 'jej' : 'jego'} $word';
    labels.add('${phrase[0].toUpperCase()}${phrase.substring(1)} ${p.name}');
    before = word;
  }
  return labels;
}

// ---------------------------------------------------------------------------------------------------------
// The tree's card: what the person at the end of a path is to "ja" (05_DESIGN/drzewo.md v1.6 element 5, D12,
// D13, G1; ISSUE-033). The words are the dictionary of ISSUE-025 D2 (SJPD, via Frąckiewicz 2013); a farther
// relation is told in segments, each a word of the dictionary, the nearer ones in the genitive: "Siostra
// cioteczna babci Twojej żony". The segments are counted from the other person (D12): the longest known
// segment that ends at them, then the next one towards "ja" — counted from "ja", "teściowa" would take the
// first two steps and give "Siostrzenica babci Twojej teściowej". The app speaks to the author (G1):
// "Twoja babcia".

enum _Gender { feminine, masculine, neuter }

/// One segment's word: the nominative, the genitive, the word's grammatical gender (for "Twoja" / "Twój" /
/// "Twoje" — the word's, not the person's), and the bracket of the dictionary (D13: "ciotka (siostra taty)").
class _Word {
  const _Word(this.nominative, this.genitive, this.gender, [this.bracket]);

  final String nominative;
  final String genitive;
  final _Gender gender;
  final String? bracket;
}

/// The genitive of each word and its gender — the regular declension; the less common forms checked in
/// Wikisłownik's declension tables on 2026-10-13: szwagra, siostrzeńca, zięcia, teścia, wuja. A prefix
/// "pra" is taken off and put back: "prapradziadek" → "prapradziadka".
const Map<String, (String, _Gender)> _forms = {
  'mama': ('mamy', _Gender.feminine),
  'tata': ('taty', _Gender.masculine),
  'rodzic': ('rodzica', _Gender.masculine),
  'babcia': ('babci', _Gender.feminine),
  'dziadek': ('dziadka', _Gender.masculine),
  'córka': ('córki', _Gender.feminine),
  'syn': ('syna', _Gender.masculine),
  'dziecko': ('dziecka', _Gender.neuter),
  'wnuczka': ('wnuczki', _Gender.feminine),
  'wnuk': ('wnuka', _Gender.masculine),
  'siostra': ('siostry', _Gender.feminine),
  'brat': ('brata', _Gender.masculine),
  'rodzeństwo': ('rodzeństwa', _Gender.neuter),
  'żona': ('żony', _Gender.feminine),
  'mąż': ('męża', _Gender.masculine),
  'małżonek': ('małżonka', _Gender.masculine),
  'partnerka': ('partnerki', _Gender.feminine),
  'partner': ('partnera', _Gender.masculine),
  'ciotka': ('ciotki', _Gender.feminine),
  'stryj': ('stryja', _Gender.masculine),
  'wuj': ('wuja', _Gender.masculine),
  'stryjenka': ('stryjenki', _Gender.feminine),
  'wujenka': ('wujenki', _Gender.feminine),
  'siostra stryjeczna': ('siostry stryjecznej', _Gender.feminine),
  'brat stryjeczny': ('brata stryjecznego', _Gender.masculine),
  'siostra wujeczna': ('siostry wujecznej', _Gender.feminine),
  'brat wujeczny': ('brata wujecznego', _Gender.masculine),
  'siostra cioteczna': ('siostry ciotecznej', _Gender.feminine),
  'brat cioteczny': ('brata ciotecznego', _Gender.masculine),
  'bratanica': ('bratanicy', _Gender.feminine),
  'bratanek': ('bratanka', _Gender.masculine),
  'siostrzenica': ('siostrzenicy', _Gender.feminine),
  'siostrzeniec': ('siostrzeńca', _Gender.masculine),
  'teściowa': ('teściowej', _Gender.feminine),
  'teść': ('teścia', _Gender.masculine),
  'synowa': ('synowej', _Gender.feminine),
  'zięć': ('zięcia', _Gender.masculine),
  'bratowa': ('bratowej', _Gender.feminine),
  'szwagier': ('szwagra', _Gender.masculine),
  'szwagierka': ('szwagierki', _Gender.feminine),
};

_Word _word(String nominative, [String? bracket]) {
  String prefix = '', base = nominative;
  while (base.startsWith('pra') && !_forms.containsKey(base)) {
    prefix += 'pra';
    base = base.substring(3);
  }
  final (String genitive, _Gender gender) = _forms[base]!;
  return _Word(nominative, '$prefix$genitive', gender, bracket);
}

/// "taty", "mamy", or without a sex "rodzica" — the side in a bracket.
String _ofParent(Sex? s) => switch (s) {
  Sex.male => 'taty',
  Sex.female => 'mamy',
  null => 'rodzica',
};

/// "żony", "męża", or without a sex "małżonka".
String _ofSpouse(Sex? s) => switch (s) {
  Sex.female => 'żony',
  Sex.male => 'męża',
  null => 'małżonka',
};

/// The word for one segment of a path — null when the dictionary has none, or when it needs a sex that is
/// not written (ISSUE-025 D2: then the segments go neutral, one step at a time). One step always has a word.
_Word? _segment(List<KinStep> st, Sex? Function(int) sexOf) {
  final String kinds = [
    for (final KinStep s in st)
      switch (s.edge) {
        KinEdge.parent => 'P',
        KinEdge.child => 'C',
        KinEdge.sibling => 'B',
        KinEdge.partner => 'S',
      },
  ].join();
  Sex? sex(int i) => sexOf(st[i].personId);
  final Sex? k = sex(st.length - 1);
  _Word? pick(String female, String male, [String? bracket]) => switch (k) {
    Sex.female => _word(female, bracket),
    Sex.male => _word(male, bracket),
    null => null,
  };

  if (RegExp(r'^P+$').hasMatch(kinds)) {
    if (kinds.length == 1) return _word(_parentWord(k));
    final String pra = 'pra' * (kinds.length - 2);
    return pick('${pra}babcia', '${pra}dziadek');
  }
  if (RegExp(r'^C+$').hasMatch(kinds)) {
    if (kinds.length == 1) return _word(_childWord(k));
    final String pra = 'pra' * (kinds.length - 2);
    return pick('${pra}wnuczka', '${pra}wnuk');
  }
  switch (kinds) {
    case 'B':
      return _word(switch (k) {
        Sex.female => 'siostra',
        Sex.male => 'brat',
        null => 'rodzeństwo',
      });
    case 'S':
      return _word(switch ((st.single.married, k)) {
        (true, Sex.female) => 'żona',
        (true, Sex.male) => 'mąż',
        (true, null) => 'małżonek',
        (false, Sex.female) => 'partnerka',
        (false, _) => 'partner',
      });
    case 'PB':
      final Sex? parent = sex(0);
      if (k == Sex.female) {
        return _word('ciotka', 'siostra ${_ofParent(parent)}');
      }
      if (k == Sex.male && parent != null) {
        return parent == Sex.male
            ? _word('stryj', 'brat taty')
            : _word('wuj', 'brat mamy');
      }
      return null;
    case 'PBS':
      if (!st[2].married) return null;
      final Sex? parent = sex(0), sibling = sex(1);
      if (sibling == Sex.male && k == Sex.female && parent != null) {
        return parent == Sex.male
            ? _word('stryjenka', 'żona brata taty')
            : _word('wujenka', 'żona brata mamy');
      }
      if (sibling == Sex.female && k == Sex.male) {
        return _word('wuj', 'mąż siostry ${_ofParent(parent)}');
      }
      return null;
    case 'PBC':
      final Sex? parent = sex(0), sibling = sex(1);
      if (k == null || sibling == null) return null;
      final String? kind = sibling == Sex.female
          ? 'cioteczn'
          : switch (parent) {
              Sex.male => 'stryjeczn',
              Sex.female => 'wujeczn',
              null => null,
            };
      if (kind == null) return null;
      final String bracket =
          '${k == Sex.female ? 'córka' : 'syn'} '
          '${sibling == Sex.female ? 'siostry' : 'brata'} ${_ofParent(parent)}';
      return pick('siostra ${kind}a', 'brat ${kind}y', bracket);
    case 'BC':
      final Sex? sibling = sex(0);
      if (sibling == null) return null;
      final String bracket =
          '${k == Sex.female ? 'córka' : 'syn'} '
          '${sibling == Sex.female ? 'siostry' : 'brata'}';
      return sibling == Sex.male
          ? pick('bratanica', 'bratanek', bracket)
          : pick('siostrzenica', 'siostrzeniec', bracket);
    case 'SP':
      if (!st[0].married) return null;
      return pick(
        'teściowa',
        'teść',
        '${k == Sex.female ? 'mama' : 'tata'} ${_ofSpouse(sex(0))}',
      );
    case 'CS':
      if (!st[1].married) return null;
      final Sex? child = sex(0);
      if (child == Sex.male && k == Sex.female) {
        return _word('synowa', 'żona syna');
      }
      if (child == Sex.female && k == Sex.male) {
        return _word('zięć', 'mąż córki');
      }
      return null;
    case 'BS':
      if (!st[1].married) return null;
      final Sex? sibling = sex(0);
      if (sibling == Sex.male && k == Sex.female) {
        return _word('bratowa', 'żona brata');
      }
      if (sibling == Sex.female && k == Sex.male) {
        return _word('szwagier', 'mąż siostry');
      }
      return null;
    case 'SB':
      if (!st[0].married) return null;
      return pick(
        'szwagierka',
        'szwagier',
        '${k == Sex.female ? 'siostra' : 'brat'} ${_ofSpouse(sex(0))}',
      );
  }
  return null;
}

String _parentWord(Sex? s) => switch (s) {
  Sex.female => 'mama',
  Sex.male => 'tata',
  null => 'rodzic',
};

String _childWord(Sex? s) => switch (s) {
  Sex.female => 'córka',
  Sex.male => 'syn',
  null => 'dziecko',
};

/// What the last person of [steps] — a path from "ja" (`KinGraph.path`) — is to "ja", for the tree's card:
/// "Twoja babcia", "Twój stryj (brat taty)", "Siostra cioteczna babci Twojej żony". Null for "ja" themselves
/// (no steps). [sexOf] gives each person's sex; null where it is not written.
String? kinshipName(List<KinStep> steps, Sex? Function(int personId) sexOf) {
  if (steps.isEmpty) return null;
  final List<_Word> segments = [];
  int end = steps.length;
  while (end > 0) {
    // The longest known segment ending at [end]; one step always has a word, so the loop always moves.
    for (int start = 0; start < end; start++) {
      final _Word? w = _segment(steps.sublist(start, end), sexOf);
      if (w != null) {
        segments.insert(0, w);
        end = start;
        break;
      }
    }
  }
  final String text;
  if (segments.length == 1) {
    final _Word w = segments.single;
    final String your = switch (w.gender) {
      _Gender.feminine => 'Twoja',
      _Gender.masculine => 'Twój',
      _Gender.neuter => 'Twoje',
    };
    text = '$your ${w.nominative}${w.bracket == null ? '' : ' (${w.bracket})'}';
  } else {
    final String your = segments.first.gender == _Gender.feminine
        ? 'Twojej'
        : 'Twojego';
    text = [
      segments.last.nominative,
      for (int i = segments.length - 2; i >= 1; i--) segments[i].genitive,
      '$your ${segments.first.genitive}',
    ].join(' ');
  }
  return '${text[0].toUpperCase()}${text.substring(1)}';
}
