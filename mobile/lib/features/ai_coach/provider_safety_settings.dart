import 'package:firebase_ai/firebase_ai.dart';

/// The provider-side content filter applied to every Gemini call this app
/// makes.
///
/// # This is NOT the app's fitness safety layer
///
/// Read this before using it, because the two are easy to conflate and the
/// conflation is the actual hazard:
///
/// * **Provider moderation** (this file) is Google's general-purpose filter
///   for harassment, hate speech, sexually explicit material and dangerous
///   content. It knows nothing about this user, their injuries, their PAR-Q+
///   answers, or what a squat is.
/// * **SPTR domain safety** (`features/safety/`) decides whether a specific
///   person may be prescribed a specific movement right now. It is
///   deterministic, it reads the user's own answers, and it is the only thing
///   in this codebase entitled to that decision.
///
/// A model answer that clears provider moderation has cleared NOTHING about
/// exercise safety. "Do heavy barbell squats through the knee pain" is not
/// dangerous content by any provider's definition; it is dangerous advice by
/// this product's. Provider moderation cannot close a single finding in the
/// injury/eligibility/programme space and must never be cited as if it had.
///
/// # Why configure it at all, then
///
/// F026. Leaving it unset does not mean "no filtering" — it means the
/// defaults, whatever they are on the day, changing when the provider changes
/// them, with nothing in the repository recording what this app asked for.
/// Declaring it makes the request explicit and reviewable, and it is the half
/// of the problem that IS the provider's to solve.
///
/// # Why `medium` and not `low`
///
/// Fitness content sits closer to these categories than most product copy
/// does. "Blast your chest", "kill your legs", "destroy this set" are ordinary
/// gym register; anatomical and injury discussion is unavoidably clinical and
/// bodily. `low` blocks at the lowest probability of harm and would refuse
/// legitimate answers about, say, pelvic-floor work or a groin strain —
/// producing a coach that goes silent exactly where a user most needs it, and
/// silence reads as a broken feature rather than as a safety decision.
///
/// `medium` is the provider's own balanced setting. It is a
/// `PRODUCT_HEURISTIC` with no named owner, recorded here rather than inline
/// so that stays visible, and it is the direction that can be tightened
/// without the app losing the ability to discuss the body.
///
/// `HarmBlockThreshold.none` and `.off` are deliberately not used anywhere.
final List<SafetySetting> kProviderSafetySettings = [
  for (final category in const [
    HarmCategory.harassment,
    HarmCategory.hateSpeech,
    HarmCategory.sexuallyExplicit,
    HarmCategory.dangerousContent,
  ])
    SafetySetting(category, HarmBlockThreshold.medium, null),
];
