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
