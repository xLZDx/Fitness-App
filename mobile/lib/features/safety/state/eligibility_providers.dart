import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/state/equipment_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../personalisation/data/recommendation_hints.dart';
import '../../equipment/data/equipment_models.dart' show ExerciseDifficulty;
import '../data/age_policy.dart';
import '../data/eligibility.dart';
import '../data/par_q.dart';

/// The user's safety context, assembled once.
///
/// Every recommending surface reads THIS and hands it to
/// `eligibleExercises` / `evaluateExercise`. Before it existed each surface
/// assembled its own subset — the planner took injuries, the programme builder
/// took equipment, the home feed took injuries again, and the Gate M screening
/// reached three of them. A rule added to one was absent from the others with
/// no symptom.
///
/// ## Fail-closed while loading
///
/// `screeningProfileProvider` awaits BOTH auth and the profile, so this stays
/// `AsyncLoading` until the answer is real rather than resolving to a
/// permissive default. A profile that has not arrived is not a profile with no
/// restrictions, and the difference is a user being shown work their injuries
/// screen out for as long as the read takes.
///
/// A genuinely absent profile — signed out, or never onboarded — yields
/// [kUnscreened], which blocks.
///
/// N08. `safety_providers.dart` once held a `safetyVerdictProvider` that
/// answered the same question from `currentProfileProvider` and returned only
/// the `SafetyVerdict` — the screening half, without the injuries, flags or
/// equipment every caller also needs. It had no consumer and was deleted:
/// two providers answering "is this person screened?" with different amounts
/// of information is a second authority waiting to be reached for, and one
/// safety truth is the point of this file.
final safetyContextProvider = FutureProvider<SafetyContext>((ref) async {
  final profile = await ref.watch(screeningProfileProvider.future);
  if (profile == null) {
    return SafetyContext(screening: kUnscreened);
  }
  return safetyContextFor(profile);
});

/// The same context built from the in-progress questionnaire draft.
///
/// Onboarding has no saved profile yet, so reading the stored one would screen
/// the user as they were BEFORE they answered — which on a first run means
/// screening an empty profile and refusing the preview to someone who has just
/// filled the whole form in.
///
/// N08. This is what `onboardingPlanPreviewProvider` actually calls, and it is
/// why the deleted `draftSafetyVerdictProvider` had no consumer: the draft
/// path was already served, by the version that carries the whole context
/// rather than the verdict alone.
///
/// Also carries the age band and the gentle-selection switch, so every surface
/// that reads this context applies the same cautious policy. [now] exists for
/// tests; the age is computed from the calendar year.
SafetyContext safetyContextFor(UserProfile profile, {DateTime? now}) =>
    SafetyContext(
      screening: screen(profile.health.screening),
      injuries: profile.health.injuries,
      health: profile.health.flags,
      equipment: profile.equipment,
      ageBand: ageBandFor(
          profile.personal.ageAt((now ?? DateTime.now()).year)),
      gentleSelection: gentleSelectionFor(profile),
      maxDifficulty: switch (profile.level.tier) {
        FitnessTier.never || FitnessTier.beginner => ExerciseDifficulty.beginner,
        _ => null,
      },
    );
