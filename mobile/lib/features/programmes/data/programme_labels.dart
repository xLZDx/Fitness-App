import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'programme_templates.dart';

/// Localized display names for the programme catalogue.
///
/// Same shape and same reason as [CatalogLabels] (`equipment/data/catalog_labels.dart`):
/// the data layer keeps a stable English id, only the label shown to the user
/// is translated. `programme_templates.dart` used to carry the title as a
/// Russian string literal, so an English UI showed "Силовая база" under the
/// header "Current programme" — the operator's screenshot of 2026-08-13.
///
/// [id] is [ProgrammeTemplate.id]. Falls back to [stored] — the title as it
/// was written into Firestore at enrolment time — so a programme whose
/// template has since been renamed or removed still has a name to show
/// instead of a blank card.
class ProgrammeLabels {
  const ProgrammeLabels._();

  static String title(AppLocalizations l, String id, {String? stored}) {
    switch (id) {
      case 'strength_base':
        return l.programmeStrengthBase;
      case 'hypertrophy':
        return l.programmeHypertrophy;
      case 'gym_start':
        return l.programmeGymStart;
      case 'shred_endurance':
        return l.programmeShredEndurance;
      case 'injury_comeback':
        return l.programmeInjuryComeback;
      case 'shoulders_arms':
        return l.programmeShouldersArms;
      // B5d-2. Not a template — a programme built from the questionnaire
      // itself (`kProfileProgrammeId`). It reaches here through the same
      // `Programme.templateId` field, so it needs a name the same way.
      case kProfileProgrammeId:
        return l.programmeFromAnswers;
    }
    return stored ?? id;
  }
}
