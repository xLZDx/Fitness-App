import 'celebrity_plan.dart';

abstract class CelebrityPlanRepository {
  Future<List<CelebrityPlan>> list();
  Future<CelebrityPlan?> byId(String id);
}

class MockCelebrityPlanRepository implements CelebrityPlanRepository {
  static final List<CelebrityPlan> _seed = [
    const CelebrityPlan(
      id: 'starter-strength-4w',
      title: 'Starter Strength · 4 weeks',
      coachName: 'Coach Alex',
      coachBio:
          'In-kind donation by a US-certified strength coach. 4-week '
          'beginner-friendly compound lift programme.',
      weeks: 4,
      heroImageUrl: '',
      equipmentNeeded: ['barbell', 'squat_rack', 'bench_press'],
      dailyWorkouts: {
        0: ['squat', 'bench_press', 'plank'],
        2: ['deadlift', 'row_barbell', 'plank'],
        4: ['squat', 'overhead_press', 'plank'],
      },
    ),
    const CelebrityPlan(
      id: 'low-back-friendly-6w',
      title: 'Low-Back-Friendly · 6 weeks',
      coachName: 'Dr. Maria, DPT',
      coachBio:
          'Pro-bono review of a hinge-pattern programme that respects '
          'the lumbar-strain return-to-load protocol.',
      weeks: 6,
      heroImageUrl: '',
      equipmentNeeded: ['kettlebell'],
      dailyWorkouts: {
        0: ['glute_bridge', 'plank', 'birddog'],
        2: ['kb_deadlift', 'plank'],
        4: ['glute_bridge', 'birddog'],
      },
    ),
  ];

  @override
  Future<List<CelebrityPlan>> list() async => List.unmodifiable(_seed);

  @override
  Future<CelebrityPlan?> byId(String id) async {
    for (final p in _seed) {
      if (p.id == id) return p;
    }
    return null;
  }
}
