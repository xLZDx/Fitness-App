import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/state/questionnaire_notifier.dart';
import '../../profile/state/profile_providers.dart';
import '../data/par_q.dart';

/// The screening verdict for the SAVED profile.
///
/// Two properties are deliberate and both are the fail-closed direction:
///
///  - a signed-out user, or one whose profile has not loaded, gets
///    [kUnscreened], which is `blocked`. Not "clear pending load" — a plan
///    built while the answers are still in flight is a plan built from no
///    answers, and it would render before the real verdict arrived.
///  - the map comes straight from `HealthHistory.screening` with no
///    normalisation. `screen()` is the only thing that interprets it.
final safetyVerdictProvider = FutureProvider<SafetyVerdict>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return kUnscreened;
  return screen(profile.health.screening);
});

/// The screening verdict for the IN-PROGRESS questionnaire draft.
///
/// Distinct from [safetyVerdictProvider] for the same reason
/// `onboardingPlanPreviewProvider` is distinct from `generatedPlanProvider`:
/// during onboarding nothing has been saved, so reading the stored profile
/// would screen the user as they were before they answered — which for a first
/// run means screening an empty profile and refusing the preview to someone
/// who has just answered every question truthfully.
final draftSafetyVerdictProvider = Provider<SafetyVerdict>((ref) {
  final draft = ref.watch(questionnaireDraftProvider);
  return screen(draft.health.screening);
});
