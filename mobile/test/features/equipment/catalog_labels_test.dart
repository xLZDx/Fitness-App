import 'dart:ui' show Locale;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/catalog_labels.dart';

/// `CatalogLabels.contraindication` -- added because
/// `ExerciseCautionCard` (`exercise_reference.dart`) was showing raw catalog
/// tags like `shoulder_injury` as "shoulder injury" regardless of app
/// locale, bypassing this file entirely. This pins the fix: a tag that maps
/// to one of the eight screened regions must translate the same way
/// `injuries_page.dart` already labels the user's own injuries.
void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  group('CatalogLabels.contraindication', () {
    test('a region-matching tag translates, not underscore-stripped', () {
      expect(CatalogLabels.contraindication(en, 'shoulder_injury'),
          'Shoulder');
      expect(CatalogLabels.contraindication(ru, 'shoulder_injury'), 'Плечо');
    });

    test('every synonym across all eight regions resolves to a real label',
        () {
      const samples = {
        'neck': 'Neck',
        'rotator_cuff': 'Shoulder',
        'tennis_elbow': 'Elbow',
        'carpal': 'Wrist',
        'lumbar': 'Lower back',
        'groin_hip': 'Hip',
        'meniscus': 'Knee',
        'achilles': 'Ankle',
      };
      for (final entry in samples.entries) {
        expect(CatalogLabels.contraindication(en, entry.key), entry.value,
            reason: 'tag "${entry.key}" should resolve to a region label');
      }
    });

    test('an unmapped tag falls back to underscore-stripped text, same as '
        'CatalogLabels.muscle/category do for their own unknown tags', () {
      expect(CatalogLabels.contraindication(en, 'pregnancy_third_trimester'),
          'pregnancy third trimester');
    });
  });
}
