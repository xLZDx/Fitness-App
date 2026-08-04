import 'profile_models.dart';

/// Proposes an [InjuryRegion] for text a user typed.
///
/// ## What this is for, and what it deliberately is not
///
/// It is a *proposal*, shown to the user for confirmation, never applied
/// silently. Nothing in the screening path calls it: an injury is screened by
/// [Injury.region] or not at all. That separation is the whole point — a
/// guess that becomes a safety decision without anyone seeing it is exactly
/// how "knee" ended up matching "ship" in the substring matcher this replaces.
///
/// ## Why exact tokens rather than substrings
///
/// `_injuryHits` in `exercise_filter.dart` matches symmetrically and
/// substring-wise, so "back" hits "lower_back" and vice versa. That is a
/// reasonable compensation for free text and a bad rule for a closed set: it
/// cannot say no. Here a word either is in the table or it is not, and "not"
/// means the user is asked rather than guessed at.
///
/// Bilingual because the app ships English and Russian, and a Russian user
/// typing "колено" who got no proposal would make [Injury.confirmed]
/// meaningless — they would be declining a match the app never offered.
const Map<InjuryRegion, List<String>> kInjurySynonyms = {
  InjuryRegion.neck: ['neck', 'cervical', 'шея', 'шейный'],
  InjuryRegion.shoulder: [
    'shoulder',
    'rotator',
    'rotator_cuff',
    'deltoid',
    'плечо',
    'плечи',
    'ротаторная_манжета',
  ],
  InjuryRegion.elbow: ['elbow', 'tennis_elbow', 'локоть', 'локти'],
  InjuryRegion.wrist: ['wrist', 'carpal', 'hand', 'запястье', 'кисть'],
  InjuryRegion.lowerBack: [
    'lower_back',
    'lowback',
    'low_back',
    'back',
    'lumbar',
    'spine',
    'поясница',
    'спина',
    'поясничный',
  ],
  InjuryRegion.hip: ['hip', 'hips', 'groin_hip', 'бедро', 'таз', 'тазобедренный'],
  InjuryRegion.knee: ['knee', 'knees', 'acl', 'meniscus', 'колено', 'колени'],
  InjuryRegion.ankle: [
    'ankle',
    'achilles',
    'foot',
    'лодыжка',
    'голеностоп',
    'стопа',
  ],
};

/// Same normalisation as the exercise filter's, so "Knee (Right)" and "knee"
/// collapse identically on both sides of the app.
String normaliseInjuryText(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-zа-яё0-9_\s]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');

/// The region [raw] most likely names, or null when nothing in the table
/// matches.
///
/// Null is a real answer, not a failure: "rib", "jaw" and "groin" are none of
/// the eight, and the honest response is to ask the user rather than to force
/// the nearest region onto a body part it does not describe.
InjuryRegion? suggestRegion(String raw) {
  final text = normaliseInjuryText(raw);
  if (text.isEmpty) return null;

  // Whole-token match first: "left_knee" contains the token "knee".
  final tokens = text.split('_').where((t) => t.isNotEmpty).toSet();
  for (final entry in kInjurySynonyms.entries) {
    for (final synonym in entry.value) {
      if (text == synonym || tokens.contains(synonym)) return entry.key;
    }
  }

  // Then multi-word synonyms, which cannot appear as a single token.
  for (final entry in kInjurySynonyms.entries) {
    for (final synonym in entry.value) {
      if (synonym.contains('_') && text.contains(synonym)) return entry.key;
    }
  }
  return null;
}

/// Injuries that still need a human decision: unmapped and not yet declined.
List<Injury> unresolvedInjuries(Iterable<Injury> injuries) =>
    injuries.where((i) => !i.isResolved).toList(growable: false);
