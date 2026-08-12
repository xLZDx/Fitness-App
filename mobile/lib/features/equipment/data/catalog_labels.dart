import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../profile/data/injury_regions.dart';
import '../../profile/data/profile_models.dart';
import 'equipment_models.dart';

/// Localized display names for catalog vocabulary — muscle tags, difficulty
/// tiers and equipment categories.
///
/// The catalog stores these as stable English keys ('quads', 'beginner',
/// 'free_weights') because they drive filtering, the muscle map and the
/// injury filter; only the label shown to the user is translated. Kept in
/// one file so a Russian UI cannot end up with 'beginner' or 'core' leaking
/// through in one screen and translated in another — which is exactly what
/// the operator's screenshots showed.
class CatalogLabels {
  const CatalogLabels._();

  /// Falls back to the raw tag with underscores spaced out. Not defensive
  /// padding: an AI-generated exercise or a future catalog entry can carry a
  /// tag this table has not learned yet, and showing 'lower back' beats
  /// showing nothing.
  static String muscle(AppLocalizations l, String tag) {
    switch (tag) {
      case 'chest':
        return l.muscleChest;
      case 'back':
        return l.muscleBack;
      case 'lats':
        return l.muscleLats;
      case 'traps':
        return l.muscleTraps;
      case 'lower_back':
        return l.muscleLowerBack;
      case 'quads':
        return l.muscleQuads;
      case 'hamstrings':
        return l.muscleHamstrings;
      case 'calves':
        return l.muscleCalves;
      case 'glutes':
        return l.muscleGlutes;
      case 'adductors':
        return l.muscleAdductors;
      case 'shoulders':
        return l.muscleShoulders;
      case 'biceps':
        return l.muscleBiceps;
      case 'triceps':
        return l.muscleTriceps;
      case 'forearms':
        return l.muscleForearms;
      case 'core':
        return l.muscleCore;
      default:
        return tag.replaceAll('_', ' ');
    }
  }

  static String difficulty(AppLocalizations l, ExerciseDifficulty d) {
    switch (d) {
      case ExerciseDifficulty.beginner:
        return l.exerciseDifficultyBeginner;
      case ExerciseDifficulty.intermediate:
        return l.exerciseDifficultyIntermediate;
      case ExerciseDifficulty.advanced:
        return l.exerciseDifficultyAdvanced;
    }
  }

  static String category(AppLocalizations l, String category) {
    switch (category) {
      case 'strength':
        return l.equipmentCategoryStrength;
      case 'cardio':
        return l.equipmentCategoryCardio;
      case 'free_weights':
        return l.equipmentCategoryFreeWeights;
      case 'functional':
        return l.equipmentCategoryFunctional;
      case 'bodyweight':
        return l.equipmentCategoryBodyweight;
      default:
        return category.replaceAll('_', ' ');
    }
  }

  /// The catalog stores 'Any' as the manufacturer for every generic machine
  /// — it is a placeholder, not a brand, so it needs translating too.
  static String manufacturer(AppLocalizations l, String manufacturer) =>
      manufacturer == 'Any' ? l.equipmentAnyBrand : manufacturer;

  /// A contraindication tag (`ExerciseItem.contraindications`), translated
  /// via the same eight-region vocabulary `injuries_page.dart` already
  /// labels the user's own injuries with -- so "shoulder_injury" on an
  /// exercise and "Shoulder" on the injuries screen read as the same body
  /// part, not two different vocabularies that happen to overlap.
  ///
  /// [suggestRegion] is normally reserved for proposing a match to a human
  /// for confirmation, never for a screening decision on its own
  /// (`injury_regions.dart`'s own doc comment). Using it here is safe: this
  /// only chooses a display label, nothing is filtered or blocked by the
  /// result.
  static String contraindication(AppLocalizations l, String tag) {
    final region = suggestRegion(tag);
    if (region == null) return tag.replaceAll('_', ' ');
    return switch (region) {
      InjuryRegion.neck => l.injuryRegionNeck,
      InjuryRegion.upperBack => l.injuryRegionUpperBack,
      InjuryRegion.shoulder => l.injuryRegionShoulder,
      InjuryRegion.elbow => l.injuryRegionElbow,
      InjuryRegion.wrist => l.injuryRegionWrist,
      InjuryRegion.lowerBack => l.injuryRegionLowerBack,
      InjuryRegion.hip => l.injuryRegionHip,
      InjuryRegion.knee => l.injuryRegionKnee,
      InjuryRegion.ankle => l.injuryRegionAnkle,
    };
  }
}
