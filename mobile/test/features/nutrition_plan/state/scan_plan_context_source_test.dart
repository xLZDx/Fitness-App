// C18 scan_plan_context_source_test. The real ScanPlanContextSource: the surface
// mode follows the device-local verdict, and the decision and target body fat
// reach the scan surfaces ONLY for an eligible user (D-55, D-71, D-74). An
// unknown or refused verdict must yield measurement only, with no figures.
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_providers.dart';
import 'package:fitness_app/features/nutrition_plan/state/scan_plan_context_source.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';
import '../plan_state_harness.dart';

final _decision = decisionOf(
  kind: ReviewDecisionKind.keep,
  reasons: const [ReviewReason.onTrack],
  deltaKcal: 0,
);

ScanPlanContext _eligibleContext() => ScanPlanContext(
      surfaceMode: ScanSurfaceMode.full,
      decision: _decision,
      targetBodyFatPct: 18,
    );

ScanPlanContext _from(NutritionEligibility? v) =>
    NutritionScanPlanContextSource.from(
      verdict: v,
      eligibleContext: _eligibleContext(),
    ).current();

void main() {
  group('surfaceModeFor', () {
    test('full only for eligible and needsProfile', () {
      expect(surfaceModeFor(const Eligible()), ScanSurfaceMode.full);
      expect(surfaceModeFor(const NeedsProfile([NutritionInput.height])),
          ScanSurfaceMode.full);
    });

    test('measurement only for referProfessional (every reason) and needsAnswer',
        () {
      for (final r in ReferReason.values) {
        expect(surfaceModeFor(ReferProfessional(r)),
            ScanSurfaceMode.measurementOnly,
            reason: r.name);
      }
      for (final q in NutritionQuestion.values) {
        expect(surfaceModeFor(NeedsAnswer(q)), ScanSurfaceMode.measurementOnly,
            reason: q.name);
      }
    });
  });

  group('NutritionScanPlanContextSource.from (pure)', () {
    test('eligible: the full context with decision and target is passed on', () {
      final c = _from(const Eligible());
      expect(c.surfaceMode, ScanSurfaceMode.full);
      expect(c.decision, same(_decision));
      expect(c.targetBodyFatPct, 18);
    });

    test('unknown verdict (null): measurement only, no figures', () {
      final c = _from(null);
      expect(c.surfaceMode, ScanSurfaceMode.measurementOnly);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });

    test('needsProfile: full surface but NO decision and NO target', () {
      final c = _from(const NeedsProfile([NutritionInput.weight]));
      expect(c.surfaceMode, ScanSurfaceMode.full);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });

    test('referProfessional: measurement only, no decision, no target', () {
      for (final r in ReferReason.values) {
        final c = _from(ReferProfessional(r));
        expect(c.surfaceMode, ScanSurfaceMode.measurementOnly, reason: r.name);
        expect(c.decision, isNull, reason: r.name);
        expect(c.targetBodyFatPct, isNull, reason: r.name);
      }
    });

    test('needsAnswer: measurement only, no decision, no target', () {
      final c = _from(const NeedsAnswer(NutritionQuestion.nutritionGuidance));
      expect(c.surfaceMode, ScanSurfaceMode.measurementOnly);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });
  });

  group('nutritionScanPlanContextSourceProvider (live)', () {
    late PlanHarness h;
    tearDown(() => h.dispose());

    Future<ScanPlanContext> context() async {
      await h.container.read(storedNutritionPlanProvider.future);
      await h.container.read(nutritionReviewsProvider.future);
      await pumpEventQueue();
      return h.container.read(nutritionScanPlanContextSourceProvider).current();
    }

    test('eligible with a plan: full mode, the live decision and the target',
        () async {
      h = await makeHarness(profile: eligibleProfile(targetBodyFatPct: 18));
      h.plans.seedPlan(kUid, storedPlan());
      final c = await context();
      expect(c.surfaceMode, ScanSurfaceMode.full);
      expect(c.targetBodyFatPct, 18);
      expect(c.decision, isNotNull);
      expect(c.decision!.kind, ReviewDecisionKind.needMoreData);
      expect(c.decision!.basePlanVersion, 3);
    });

    test('eligible without a plan: full mode, target given, no decision',
        () async {
      h = await makeHarness(profile: eligibleProfile(targetBodyFatPct: 18));
      final c = await context();
      expect(c.surfaceMode, ScanSurfaceMode.full);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, 18);
    });

    test('referProfessional with a plan and a target: measurement only, nothing',
        () async {
      h = await makeHarness(
        profile: eligibleProfile(
          targetBodyFatPct: 18,
          flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none,
          ),
        ),
      );
      h.plans.seedPlan(kUid, storedPlan());
      final c = await context();
      expect(c.surfaceMode, ScanSurfaceMode.measurementOnly);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });

    test('needsAnswer (unanswered): measurement only, nothing', () async {
      h = await makeHarness(
          profile: eligibleProfile(
              targetBodyFatPct: 18, flags: const HealthFlags()));
      h.plans.seedPlan(kUid, storedPlan());
      final c = await context();
      expect(c.surfaceMode, ScanSurfaceMode.measurementOnly);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });

    test('needsProfile (no height): full surface, no figures', () async {
      h = await makeHarness(
          profile: eligibleProfile(targetBodyFatPct: 18, heightCm: null));
      h.plans.seedPlan(kUid, storedPlan());
      final c = await context();
      expect(c.surfaceMode, ScanSurfaceMode.full);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });

    test('profile not loaded (unknown verdict): measurement only', () async {
      h = await makeHarness(seedEligibleDefaultProfile: false);
      final c = await context();
      expect(c.surfaceMode, ScanSurfaceMode.measurementOnly);
      expect(c.decision, isNull);
      expect(c.targetBodyFatPct, isNull);
    });

    test('the context follows the verdict when the profile answer changes',
        () async {
      h = await makeHarness(profile: eligibleProfile(targetBodyFatPct: 18));
      h.plans.seedPlan(kUid, storedPlan());
      expect((await context()).surfaceMode, ScanSurfaceMode.full);
      final other = await makeHarness(
        profile: eligibleProfile(
          targetBodyFatPct: 18,
          flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none,
          ),
        ),
      );
      other.plans.seedPlan(kUid, storedPlan());
      await other.container.read(storedNutritionPlanProvider.future);
      await pumpEventQueue();
      expect(
          other.container
              .read(nutritionScanPlanContextSourceProvider)
              .current()
              .surfaceMode,
          ScanSurfaceMode.measurementOnly);
      other.dispose();
    });
  });
}
