import 'celebrity_plan.dart';

abstract class CelebrityPlanRepository {
  Future<List<CelebrityPlan>> list();
  Future<CelebrityPlan?> byId(String id);
}

/// Placeholder plans shipped so the screen renders before any real donated
/// plan exists. Every one is marked `isSample: true` and the coach name carries
/// no invented credential — the previous seed claimed a "US-certified
/// strength coach" and a "DPT", which is a fabricated professional
/// qualification presented to the user as fact. Titles and bios are
/// localized at render time (see CelebrityPlansPage), so they read in the
/// interface language without the invented credentials coming back.
class MockCelebrityPlanRepository implements CelebrityPlanRepository {
  static final List<CelebrityPlan> _seed = [
    const CelebrityPlan(
      id: 'starter-strength-4w',
      title: 'Starter Strength · 4 weeks',
      coachName: '—',
      coachBio: '',
      weeks: 4,
      heroImageUrl: '',
      equipmentNeeded: ['barbell', 'squat_rack', 'bench_press'],
      dailyWorkouts: {
        0: ['squat', 'bench_press', 'plank'],
        2: ['deadlift', 'row_barbell', 'plank'],
        4: ['squat', 'overhead_press', 'plank'],
      },
      isSample: true,
    ),
    const CelebrityPlan(
      id: 'low-back-friendly-6w',
      title: 'Low-Back-Friendly · 6 weeks',
      coachName: '—',
      coachBio: '',
      weeks: 6,
      heroImageUrl: '',
      equipmentNeeded: ['kettlebell'],
      dailyWorkouts: {
        0: ['glute_bridge', 'plank', 'birddog'],
        2: ['kb_deadlift', 'plank'],
        4: ['glute_bridge', 'birddog'],
      },
      isSample: true,
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
