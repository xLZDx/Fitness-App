import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/celebrity_plan.dart';
import '../data/celebrity_plan_repository.dart';

final celebrityPlanRepositoryProvider =
    Provider<CelebrityPlanRepository>((_) => MockCelebrityPlanRepository());

final celebrityPlansProvider = FutureProvider<List<CelebrityPlan>>((ref) {
  return ref.watch(celebrityPlanRepositoryProvider).list();
});
