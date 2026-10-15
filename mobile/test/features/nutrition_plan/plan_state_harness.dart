// Riverpod harness of the C18 state tests (not a test file itself): the real
// providers over the in-memory repositories, a fixed clock and an injected
// profile, so a test drives the REAL scheduler, actions and providers.
import 'dart:async';

import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/nutrition_plan/data/in_memory_nutrition_repositories.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_providers.dart';
import 'package:fitness_app/features/nutrition_plan/state/weight_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_state_fixtures.dart';

const HealthFlags kClearFlags = HealthFlags(
  nutritionGuidance: NutritionGuidanceNeed.none,
  professionalGuidance: ProfessionalGuidanceNeed.none,
);

/// An eligible adult (born 1985, male, 180 cm, 80 kg, lose goal).
UserProfile eligibleProfile({
  HealthFlags flags = kClearFlags,
  int? birthYear = 1985,
  int? heightCm = 180,
  double? weightKg = 80,
  GoalDirection goal = GoalDirection.lose,
  PlanOwnership? ownership,
  double? targetBodyFatPct,
  ActivityLevel? activity = ActivityLevel.moderatelyActive,
}) =>
    UserProfile(
      uid: kUid,
      personal: PersonalInfo(
        birthYear: birthYear,
        gender: Gender.male,
        heightCm: heightCm,
        weightCurrentKg: weightKg,
        activityLevel: activity,
      ),
      health: HealthHistory(flags: flags),
      nutrition: NutritionPrefs(
          goalDirection: goal,
          planOwnership: ownership,
          targetBodyFatPct: targetBodyFatPct),
    );

class PlanHarness {
  PlanHarness._(this.plans, this.weights, this.now);

  final InMemoryPlanRepository plans;
  final InMemoryWeightRepository weights;
  DateTime now;
  late ProviderContainer container;

  Future<void> settle() async {
    await container.read(authUserProvider.future);
    await container.read(currentProfileProvider.future);
    await container.read(weightLogItemsProvider.future);
    await pumpEventQueue();
  }

  void dispose() {
    container.dispose();
    plans.dispose();
    weights.dispose();
  }
}

/// Builds a harness. [uid] null means signed out; [profile] null means no
/// profile loaded yet.
Future<PlanHarness> makeHarness({
  UserProfile? profile,
  String? uid = kUid,
  bool noticeAcknowledged = true,
  String? deletingUid,
  DateTime? now,
  bool seedEligibleDefaultProfile = true,
  InMemoryPlanRepository? planRepository,
  List<Override> extra = const [],
}) async {
  final clockNow = now ?? kNow;
  late PlanHarness h;
  final plans = planRepository ?? InMemoryPlanRepository();
  final weights = InMemoryWeightRepository(clock: () => h.now);
  h = PlanHarness._(plans, weights, clockNow);
  final effectiveProfile =
      profile ?? (seedEligibleDefaultProfile ? eligibleProfile() : null);
  h.container = ProviderContainer(overrides: [
    authUserProvider.overrideWith((ref) => Stream.value(
        uid == null ? null : AuthUser(uid: uid, displayName: 'Tester'))),
    currentProfileProvider
        .overrideWith((ref) => Stream.value(effectiveProfile)),
    nutritionClockProvider.overrideWithValue(() => h.now),
    dataNoticeAcknowledgedProvider
        .overrideWith((ref) async => noticeAcknowledged),
    nutritionPlanRepositoryProvider.overrideWithValue(plans),
    weightRepositoryProvider.overrideWithValue(weights),
    ...extra,
  ]);
  if (deletingUid != null) {
    h.container.read(accountBeingDeletedUidProvider.notifier).state =
        deletingUid;
  }
  await h.settle();
  return h;
}
