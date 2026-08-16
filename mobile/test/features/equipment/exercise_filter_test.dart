import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

ExerciseItem _ex({
  required String id,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
  List<String> contraindications = const [],
}) {
  return ExerciseItem(
    id: id,
    title: id,
    equipmentId: 'eq',
    muscles: const [],
    difficulty: difficulty,
    durationMinutes: 10,
    summary: '',
    steps: const [],
    contraindications: contraindications,
  );
}

void main() {
  group('filterContraindicated', () {
    test('returns the input unchanged when injuries are empty', () {
      final list = [_ex(id: 'a', contraindications: ['knee'])];
      final out = filterContraindicated(list, const []);
      expect(out, hasLength(1));
      expect(out.first.id, 'a');
    });

    test('removes exercises whose contraindication matches an injury', () {
      final list = [
        _ex(id: 'safe'),
        _ex(id: 'knee_risk', contraindications: ['knee']),
        _ex(id: 'back_risk', contraindications: ['lower_back']),
      ];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'knee', type: 'sprain')],
      );
      expect(out.map((e) => e.id), ['safe', 'back_risk']);
    });

    test('matches "left knee" against "knee" contraindication', () {
      final list = [_ex(id: 'risk', contraindications: ['knee'])];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'Left Knee', type: 'tear')],
      );
      expect(out, isEmpty);
    });

    test('matches "lower_back" injury against "back" tag and vice versa', () {
      final list = [
        _ex(id: 'a', contraindications: ['back']),
        _ex(id: 'b', contraindications: ['lower_back']),
        _ex(id: 'c', contraindications: ['knee']),
      ];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'lower back', type: 'strain')],
      );
      // a and b both match "lower back" via substring; c is unrelated.
      expect(out.map((e) => e.id), ['c']);
    });

    test('does not collide unrelated tags', () {
      final list = [_ex(id: 'shoulder', contraindications: ['shoulder'])];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'ankle', type: 'sprain')],
      );
      expect(out, hasLength(1));
    });

    test('keeps exercises with no contraindications regardless of injuries',
        () {
      final list = [_ex(id: 'free')];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'knee', type: 'sprain')],
      );
      expect(out, hasLength(1));
    });
  });

  group('sortByTierFit', () {
    final beginner = _ex(id: 'b', difficulty: ExerciseDifficulty.beginner);
    final intermediate =
        _ex(id: 'i', difficulty: ExerciseDifficulty.intermediate);
    final advanced = _ex(id: 'a', difficulty: ExerciseDifficulty.advanced);

    test('returns a copy, not the original list reference', () {
      final input = [advanced, beginner, intermediate];
      final out = sortByTierFit(input, FitnessTier.beginner);
      expect(identical(input, out), isFalse);
    });

    test('beginner user surfaces beginner exercises first', () {
      final out =
          sortByTierFit([advanced, beginner, intermediate], FitnessTier.beginner);
      expect(out.map((e) => e.id), ['b', 'i', 'a']);
    });

    test('advanced user surfaces advanced exercises first', () {
      final out =
          sortByTierFit([beginner, advanced, intermediate], FitnessTier.advanced);
      expect(out.map((e) => e.id), ['a', 'i', 'b']);
    });

    test('intermediate user surfaces intermediate first', () {
      final out =
          sortByTierFit([beginner, advanced, intermediate], FitnessTier.intermediate);
      expect(out.first.id, 'i');
    });

    test('null tier preserves order', () {
      final out = sortByTierFit([advanced, beginner, intermediate], null);
      expect(out.map((e) => e.id), ['a', 'b', 'i']);
    });

    /// F024 — the doc says "stable-sorts" and `List.sort` is not stable.
    ///
    /// Ties are the common case, not the edge: the comparator returns 0 for
    /// two exercises of the SAME difficulty, and a beginner's list is mostly
    /// beginner exercises. So the order the user sees among equally-suitable
    /// exercises was whatever the sort happened to leave behind, and it could
    /// differ between two builds of the same list.
    ///
    /// Small lists hide it — Dart's sort is insertion-based below a threshold
    /// and incidentally stable there — which is why this uses a realistic
    /// number of rows rather than three.
    test('F024: equally-suitable exercises keep the order they came in', () {
      final input = [
        for (var i = 0; i < 60; i++)
          _ex(id: 'e$i', difficulty: ExerciseDifficulty.beginner),
      ];
      final out = sortByTierFit(input, FitnessTier.beginner);
      expect(out.map((e) => e.id).toList(), input.map((e) => e.id).toList());
    });

    test('F024: a tie inside a mixed list is broken by input order too', () {
      // The same property where the comparator is actually doing work: the
      // distance ranking still decides, and only the ties fall back to input
      // order.
      final input = [
        for (var i = 0; i < 30; i++) ...[
          _ex(id: 'a$i', difficulty: ExerciseDifficulty.advanced),
          _ex(id: 'b$i', difficulty: ExerciseDifficulty.beginner),
        ],
      ];
      final out = sortByTierFit(input, FitnessTier.beginner);
      expect(out.take(30).map((e) => e.id).toList(),
          [for (var i = 0; i < 30; i++) 'b$i']);
      expect(out.skip(30).map((e) => e.id).toList(),
          [for (var i = 0; i < 30; i++) 'a$i']);
    });
  });

  group('recommended (full pipeline)', () {
    test('null profile passes through unchanged', () {
      final list = [
        _ex(id: 'a', contraindications: ['knee']),
        _ex(id: 'b'),
      ];
      expect(recommended(list, null).map((e) => e.id), ['a', 'b']);
    });

    test('filters contraindicated then sorts by tier', () {
      final list = [
        _ex(id: 'beg_safe', difficulty: ExerciseDifficulty.beginner),
        _ex(id: 'adv_risk',
            difficulty: ExerciseDifficulty.advanced,
            contraindications: ['knee']),
        _ex(id: 'adv_safe', difficulty: ExerciseDifficulty.advanced),
      ];
      final profile = UserProfile(
        uid: 'u1',
        health: const HealthHistory(injuries: [
          Injury(bodyPart: 'knee', type: 'sprain'),
        ]),
        level: const FitnessLevel(tier: FitnessTier.advanced),
      );
      final out = recommended(list, profile);
      expect(out.map((e) => e.id), ['adv_safe', 'beg_safe']);
    });
  });

  group('safety without ranking', () {
    // `recommended` fused screening and tier-sorting with no way to take one
    // without the other, so every caller that had its own idea of order --
    // the For-you ranker, the offline prefetch list, a single deep-linked
    // exercise -- was choosing between ranking twice and not screening at
    // all. More than one of them chose the second.
    final profile = UserProfile(
      uid: 'u1',
      health: const HealthHistory(injuries: [
        Injury(bodyPart: 'knee', type: 'sprain'),
      ]),
      level: const FitnessLevel(tier: FitnessTier.advanced),
    );

    test('safeFor screens and leaves the order alone', () {
      final list = [
        _ex(id: 'adv_safe', difficulty: ExerciseDifficulty.advanced),
        _ex(id: 'adv_risk',
            difficulty: ExerciseDifficulty.advanced,
            contraindications: ['knee']),
        _ex(id: 'beg_safe', difficulty: ExerciseDifficulty.beginner),
      ];
      expect(safeFor(list, profile).map((e) => e.id), ['adv_safe', 'beg_safe']);
    });

    test('recommended is safeFor plus the ranking, not a second rule', () {
      final list = [
        _ex(id: 'beg_safe', difficulty: ExerciseDifficulty.beginner),
        _ex(id: 'adv_risk',
            difficulty: ExerciseDifficulty.advanced,
            contraindications: ['knee']),
        _ex(id: 'adv_safe', difficulty: ExerciseDifficulty.advanced),
      ];
      expect(
        recommended(list, profile).map((e) => e.id).toSet(),
        safeFor(list, profile).map((e) => e.id).toSet(),
      );
    });

    test('a null profile is left untouched by both', () {
      final list = [_ex(id: 'a', contraindications: ['knee'])];
      expect(safeFor(list, null).map((e) => e.id), ['a']);
      expect(recommended(list, null).map((e) => e.id), ['a']);
    });
  });

  group('one exercise at a time', () {
    // A deep link, a scheduled session and a reminder each arrive holding one
    // id. Before this the only way to ask was to build a one-element list and
    // see whether it came back empty, which is why all three ended up not
    // asking.
    const injuries = [Injury(bodyPart: 'knee', type: 'sprain')];

    test('a conflicting tag is caught', () {
      expect(
        isContraindicated(_ex(id: 'a', contraindications: ['knee']), injuries),
        isTrue,
      );
    });

    test('an untagged exercise is not', () {
      expect(isContraindicated(_ex(id: 'a'), injuries), isFalse);
    });

    test('an unrelated tag is not', () {
      expect(
        isContraindicated(
            _ex(id: 'a', contraindications: ['shoulder']), injuries),
        isFalse,
      );
    });

    test('it agrees with the list form, which is built on it', () {
      final list = [
        _ex(id: 'risk', contraindications: ['knee']),
        _ex(id: 'safe'),
      ];
      final kept = filterContraindicated(list, injuries).map((e) => e.id);
      expect(kept,
          list.where((e) => !isContraindicated(e, injuries)).map((e) => e.id));
    });
  });

  group('focusZoneMuscles', () {
    test('fullBody is the absence of a restriction, not a muscle', () {
      expect(focusZoneMuscles(FocusZone.fullBody), isEmpty);
    });

    test('a zone can stand for several catalogue tokens', () {
      expect(focusZoneMuscles(FocusZone.arms),
          {'biceps', 'triceps', 'forearms'});
    });

    test('every zone resolves only to tokens the shipped catalogue uses', () {
      // The 15 tokens measured across `assets/data/exercises_vendor.json`.
      // A zone mapping to anything outside this set would filter to nothing
      // while looking like it worked.
      const catalogueTokens = {
        'shoulders', 'quads', 'glutes', 'hamstrings', 'lower_back', 'core',
        'traps', 'triceps', 'biceps', 'chest', 'forearms', 'calves', 'lats',
        'back', 'adductors',
      };
      for (final zone in FocusZone.values) {
        expect(focusZoneMuscles(zone), everyElement(isIn(catalogueTokens)),
            reason: 'zone $zone maps outside the catalogue vocabulary');
      }
    });

    test('every zone except fullBody resolves to at least one token', () {
      for (final zone in FocusZone.values) {
        if (zone == FocusZone.fullBody) continue;
        expect(focusZoneMuscles(zone), isNotEmpty, reason: 'zone $zone');
      }
    });
  });

  group('availableWith', () {
    test('an unanswered equipment section filters nothing', () {
      final list = [_kit('barbell_row', label: 'Barbell')];
      expect(availableWith(list, EquipmentAccess.empty).map((e) => e.id),
          ['barbell_row']);
    });

    test('a gym answer allows everything, including machines', () {
      final list = [
        _kit('press', label: 'Chest Press Machine'),
        _kit('row', label: 'Barbell'),
      ];
      const access = EquipmentAccess(location: TrainingLocation.gym);
      expect(availableWith(list, access), hasLength(2));
    });

    test('a mixed answer counts as gym access', () {
      final list = [_kit('press', label: 'Chest Press Machine')];
      const access = EquipmentAccess(
        location: TrainingLocation.mixed,
        available: [EquipmentKind.bodyweight],
      );
      expect(availableWith(list, access), hasLength(1));
    });

    test('the fullGym chip allows everything even from home', () {
      final list = [_kit('press', label: 'Chest Press Machine')];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.fullGym],
      );
      expect(availableWith(list, access), hasLength(1));
    });

    test('a bodyweight-only answer keeps push-ups and drops the barbell', () {
      final list = [
        _kit('pushup', label: 'None (Bodyweight)'),
        _kit('plank', label: 'none'),
        _kit('squat', label: 'Barbell'),
      ];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.bodyweight],
      );
      expect(availableWith(list, access).map((e) => e.id), ['pushup', 'plank']);
    });

    test('an exercise needing nothing is kept whatever the user ticked', () {
      final list = [_kit('pushup', label: 'None (Bodyweight)')];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.kettlebells],
      );
      expect(availableWith(list, access), hasLength(1));
    });

    test('a chip admits its own kit and nothing else', () {
      final list = [
        _kit('curl', label: 'Dumbbells'),
        _kit('swing', label: 'Kettlebells'),
        _kit('press', label: 'Barbell'),
      ];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.dumbbells],
      );
      expect(availableWith(list, access).map((e) => e.id), ['curl']);
    });

    test('matching is exact, so "barbell" never admits a pull-up bar', () {
      // The substring trap `_furnitureNotEquipment` was written to avoid: "bar"
      // inside "Pull Up Bar" would promise a home user kit they never claimed.
      final list = [_kit('pullup', label: 'Pull Up Bar')];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.barbell],
      );
      expect(availableWith(list, access), isEmpty);
    });

    test('the machines chip covers any label naming a machine, in any case',
        () {
      final list = [
        _kit('lat', label: 'Lat Pull Down Machine (Cable)'),
        _kit('smith', label: 'Smith machine'),
        _kit('mill', label: 'Treadmill'),
      ];
      const access = EquipmentAccess(available: [EquipmentKind.machines]);
      expect(availableWith(list, access), hasLength(3));
    });

    test('a composite label needs every part, not any part', () {
      final list = [
        _kit('a', label: 'Barbell, Box'),
        _kit('b', label: 'Barbell'),
      ];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.barbell],
      );
      expect(availableWith(list, access).map((e) => e.id), ['b']);
    });

    test('cameraScan alone is an intention, not kit, so it names nothing', () {
      final list = [
        _kit('press', label: 'Barbell'),
        _kit('pushup', label: 'None (Bodyweight)'),
      ];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.cameraScan],
      );
      expect(availableWith(list, access).map((e) => e.id), ['pushup']);
    });

    test('with nothing answered at all, cameraScan still filters nothing', () {
      final list = [_kit('press', label: 'Barbell')];
      const access = EquipmentAccess(available: [EquipmentKind.cameraScan]);
      expect(availableWith(list, access), hasLength(1));
    });

    test('"at home" with no chips ticked means no equipment, not no answer',
        () {
      // The commonest real path: `step_answered.dart:157` marks the onboarding
      // step answered as soon as a location is tapped, so a user can reach the
      // end of onboarding having said "Home" and touched no chip at all. Reading
      // that as "has not answered" scheduled barbell work for them.
      final list = [
        _kit('press', label: 'Barbell'),
        _kit('pushup', label: 'None (Bodyweight)'),
      ];
      const access = EquipmentAccess(location: TrainingLocation.home);
      expect(availableWith(list, access).map((e) => e.id), ['pushup']);
    });

    test('"outdoors" with no chips ticked means no equipment either', () {
      final list = [
        _kit('press', label: 'Barbell'),
        _kit('pushup', label: 'None (Bodyweight)'),
      ];
      const access = EquipmentAccess(location: TrainingLocation.outdoor);
      expect(availableWith(list, access).map((e) => e.id), ['pushup']);
    });

    test('cameraScan does not widen a real answer', () {
      final list = [_kit('press', label: 'Barbell')];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.bodyweight, EquipmentKind.cameraScan],
      );
      expect(availableWith(list, access), isEmpty);
    });

    test('a row whose label says "None" while naming a machine is dropped', () {
      // 89 shipped rows contradict themselves this way (27 of them
      // `bench_press`). The id is believed, so a home user is not handed one.
      final list = [
        _kit('bench', label: 'None', equipmentId: 'bench_press'),
        _kit('pushup', label: 'None'),
      ];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.bodyweight],
      );
      expect(availableWith(list, access).map((e) => e.id), ['pushup']);
    });

    test('a bodyweight answer can never empty a real catalogue', () {
      // The property the schedule generator depends on: it is handed this list
      // and cannot fall back past it, so an empty result would mean an
      // enrolment with no sessions at all.
      final list = [
        _kit('pushup', label: 'None (Bodyweight)'),
        _kit('press', label: 'Barbell'),
      ];
      const access = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.bodyweight],
      );
      expect(availableWith(list, access), isNotEmpty);
    });
  });
}

ExerciseItem _kit(String id, {String? label, String? equipmentId}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      equipmentLabel: label,
      muscles: const [],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
    );
