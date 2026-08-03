import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';

/// Stretching, mobility and Pilates can be asked for.
///
/// They were in the catalog the whole time — 65 rows carrying `isStretch` —
/// and the Train tab had thirteen chips, none of which was this one. Operator:
/// *"не вижу новые упражнения на растяжку егу и пилатес в списке категорий"*.
void main() {
  late List<ExerciseItem> catalog;

  setUpAll(() {
    catalog = (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
            as List)
        .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  test('the flag survives the trip from JSON into the model', () {
    // It did not before: `isStretch` was parsed by nothing, so every exercise
    // arrived in the app as not-a-stretch and the filter would have been
    // permanently empty.
    final stretches = catalog.where((e) => e.isStretch).toList();
    expect(stretches.length, greaterThanOrEqualTo(65));
  });

  test('there is a chip for it', () {
    expect(WorkoutsFilter.values, contains(WorkoutsFilter.stretching));
  });

  test('yoga and Pilates are inside it, not left out', () {
    // The three Pilates rows and one older stretch were flagged by
    // `widen_stretch_flag.py` rather than by a name list in the widget.
    final ids = catalog.where((e) => e.isStretch).map((e) => e.id).toSet();
    expect(ids, contains('vid_stretching_butterfly_yoga_pose'));
    expect(ids, containsAll([
      'vid_corkscrew_pilates',
      'vid_hundred_pilates',
      'vid_jackknife_pilates',
      'all_fours_quad_stretch',
    ]));
  });

  test('the flag is narrow — it has not swallowed the strength catalog', () {
    // The widening rule matched on id substrings, which is the kind of thing
    // that quietly grows. A third of the catalog turning into "stretching"
    // would make the chip useless without breaking anything visibly.
    final share = catalog.where((e) => e.isStretch).length / catalog.length;
    expect(share, lessThan(0.20));
    expect(catalog.firstWhere((e) => e.id == 'barbell_squat').isStretch, isFalse);
  });

  test('a translation does not lose it', () {
    // `withText` rebuilds the object field by field; a new field forgotten
    // there disappears the moment the app runs in Russian.
    final s = catalog.firstWhere((e) => e.isStretch);
    final ru = s.withText(title: 'Растяжка', summary: '', steps: const []);
    expect(ru.isStretch, isTrue);
    expect(ru.poster, s.poster, reason: 'the poster must survive too');
  });

  test('a fair share of them can still show a clip', () {
    // Was >85%, and that WAS the reason this chip was worth having: the
    // mobility set came from the video library. It came from the UNLICENSED
    // half of it -- the Drive scaffold that predates the purchased pack -- so
    // removing that on 2026-08-03 took it to 43%.
    //
    // Kept as a floor rather than deleted: a rebuild that drops the stretching
    // clips entirely is still a defect this notices, and the number goes back
    // up as the rest are re-matched against the vendor library.
    final st = catalog.where((e) => e.isStretch).toList();
    final withVideo = st.where((e) => e.hasVideo).length;
    expect(withVideo / st.length, greaterThan(0.60));
  });
}
