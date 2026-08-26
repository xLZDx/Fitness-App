import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_coach/provider_safety_settings.dart';

/// F026 — the provider content filter, tested SEPARATELY from domain safety.
///
/// The separation is the point of the finding, so it is the shape of this
/// file too. Nothing here asserts anything about injuries, eligibility or
/// programmes, and nothing in the domain-safety suites asserts anything about
/// `HarmCategory`. A test that mixed them would be the first place someone
/// later read "provider moderation is configured" as "the coach is safe".
void main() {
  group('what this app asks the provider for', () {
    test('all four harm categories are declared', () {
      // An unset category is not "no filtering" — it is the provider's default
      // of the day, changing when they change it, with nothing in the
      // repository recording what this app asked for. Naming all four is what
      // makes the request reviewable.
      expect(
        kProviderSafetySettings.map((s) => s.category).toSet(),
        {
          HarmCategory.harassment,
          HarmCategory.hateSpeech,
          HarmCategory.sexuallyExplicit,
          HarmCategory.dangerousContent,
        },
      );
    });

    test('nothing is switched off', () {
      // `none` and `off` are the two values that would make declaring the
      // settings worse than not declaring them: an explicit request for less
      // filtering than the default.
      for (final s in kProviderSafetySettings) {
        expect(s.threshold, isNot(HarmBlockThreshold.none), reason: '${s.category}');
        expect(s.threshold, isNot(HarmBlockThreshold.off), reason: '${s.category}');
      }
    });

    test('the threshold is the balanced one, deliberately not the strictest',
        () {
      // `low` would refuse legitimate answers about pelvic-floor work or a
      // groin strain, producing a coach that goes silent exactly where a user
      // most needs it — and silence reads as a broken feature, not a safety
      // decision. Pinned so a later change to `low` is a decision someone
      // makes on purpose rather than a tightening that quietly breaks the
      // clinical half of the product.
      for (final s in kProviderSafetySettings) {
        expect(s.threshold, HarmBlockThreshold.medium, reason: '${s.category}');
      }
    });
  });

  group('every direct Gemini call site actually passes them', () {
    // The finding is that no call site configured this. Three existed; G1
    // moved one of them (`ai_coach_service.dart`) behind the `aiCoachAdvice`
    // Cloud Function, so it no longer calls `generativeModel(` at all — its
    // safety settings now live server-side in `functions/src/ai_gateway.ts`'s
    // own `SAFETY_SETTINGS` (same four categories, same `medium` threshold,
    // ported deliberately rather than re-derived; see that file). This group
    // only has jurisdiction over what still calls the SDK directly from the
    // phone. A fourth direct call site added later without the settings is
    // the regression, and it is invisible to any behavioural test because it
    // only shows up in a network request.
    const sites = [
      'lib/features/ai_coach/ai_exercise_generator.dart',
      'lib/features/visual_equipment/data/gemini_equipment_service.dart',
    ];

    for (final path in sites) {
      test('$path passes kProviderSafetySettings', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('generativeModel('),
            reason: 'the call site moved; re-point this test');
        expect(src, contains('safetySettings: kProviderSafetySettings'));
      });
    }

    test('ai_coach_service.dart no longer calls Gemini directly', () {
      // The mirror of the "moved" case above: if this ever starts matching
      // `generativeModel(` again, either G1's migration was reverted or a
      // second, undocumented direct call was added alongside the callable —
      // both need this suite's attention, not a silent pass.
      final src =
          File('lib/features/ai_coach/ai_coach_service.dart').readAsStringSync();
      expect(src, isNot(contains('generativeModel(')));
      expect(src, contains("httpsCallable('aiCoachAdvice')"));
    });

    test('there are exactly two direct call sites, so the list above is complete',
        () {
      final found = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('generativeModel(')) {
          found.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(found.toSet(), sites.toSet(),
          reason: 'a Gemini call site appeared or moved. It needs '
              'safetySettings, and it needs the same question asked of it that '
              'F016 asked of MachineDescriber: can its output become an '
              'actionable exercise? A call site that moved server-side needs '
              'the equivalent question asked of ai_gateway.ts instead.');
    });
  });

  test('the file says, in the file, that this is not fitness safety', () {
    // Not decoration. The whole finding is one sentence away from being
    // misread as "the AI coach is now safe", and the only durable place to
    // stop that is beside the declaration itself.
    final doc =
        File('lib/features/ai_coach/provider_safety_settings.dart').readAsStringSync();
    expect(doc, contains('NOT the app'));
    expect(doc, contains('features/safety/'));
  });
}
