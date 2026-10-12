import '../../data/database.dart' show Sex;

/// What someone is to the person whose family is shown (05_DESIGN/rodzina.md → Role names).
enum FamilyRole { parent, partner, child }

/// "Matka", "Mąż", "Partnerka", "Syn" — from [sex] and, for a partner, whether there was a wedding; the
/// neutral name without a sex ("Rodzic", "Małżonek", "Partner", "Dziecko"). One list for the form's
/// "Rodzina" (wpis-osoby.md 9a) and the person's mini tree (osoba.md element 6).
String roleName(FamilyRole role, Sex? sex, {bool married = false}) =>
    switch ((role, sex)) {
      (FamilyRole.parent, Sex.female) => 'Matka',
      (FamilyRole.parent, Sex.male) => 'Ojciec',
      (FamilyRole.parent, null) => 'Rodzic',
      (FamilyRole.partner, Sex.female) => married ? 'Żona' : 'Partnerka',
      (FamilyRole.partner, Sex.male) => married ? 'Mąż' : 'Partner',
      (FamilyRole.partner, null) => married ? 'Małżonek' : 'Partner',
      (FamilyRole.child, Sex.female) => 'Córka',
      (FamilyRole.child, Sex.male) => 'Syn',
      (FamilyRole.child, null) => 'Dziecko',
    };
