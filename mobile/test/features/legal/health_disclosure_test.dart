import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart' as h;

import 'package:fitness_app/core/health/platform_health_service.dart';

/// The privacy policy must name every health metric the app actually reads.
///
/// Two release blockers were found on 2026-08-15 and both were disclosure
/// failures rather than code failures. The app reads resting heart rate, heart
/// rate variability and sleep from Health Connect and Apple Health, and no
/// legal document in either locale mentioned any of it — `legal_text.py`, the
/// single source of both the in-app pages and the public URLs Google Play
/// links to, contained zero occurrences. Separately the manifest declared
/// `READ_HEART_RATE`, a permission granting continuous heart-rate history that
/// no code path has ever requested.
///
/// Neither could be caught by review, because both are absences. A reviewer
/// reading the health service sees correct code; a reviewer reading the policy
/// sees a coherent document. Only holding the two against each other shows the
/// gap, which is what this file does.
///
/// The assertions run against the generated `.arb`, not against
/// `legal_text.py`, on purpose: the .arb is what the app renders and what the
/// build publishes, so a change made to the source and never rebuilt fails
/// here rather than shipping.

/// Every health metric, and the words the policy has to use for it.
///
/// Keyed by the type so a metric added to `healthReadTypes` without a
/// corresponding entry fails the coverage assertion below rather than passing
/// silently — the failure mode that produced the blocker.
const Map<h.HealthDataType, List<String>> _mustBeNamed = {
  h.HealthDataType.STEPS: ['steps', 'шаг'],
  h.HealthDataType.ACTIVE_ENERGY_BURNED: ['calories', 'калори'],
  h.HealthDataType.RESTING_HEART_RATE: ['resting heart rate', 'пульс покоя'],
  h.HealthDataType.SLEEP_ASLEEP: ['sleep', 'сон'],
  h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD: [
    'heart rate variability',
    'вариабельность',
  ],
  h.HealthDataType.HEART_RATE_VARIABILITY_SDNN: [
    'heart rate variability',
    'вариабельность',
  ],
  h.HealthDataType.WORKOUT: ['workout', 'тренировк'],
};

String _arb(String lang) =>
    File('lib/l10n/app_$lang.arb').readAsStringSync().toLowerCase();

void main() {
  group('the privacy policy names what the app reads', () {
    test('every read and write type appears in both locales', () {
      final types = <h.HealthDataType>{
        ...healthReadTypes(android: true),
        ...healthReadTypes(android: false),
        ...healthWriteTypes,
      };

      for (final (lang, index) in const [('en', 0), ('ru', 1)]) {
        final body = _arb(lang);
        for (final type in types) {
          final words = _mustBeNamed[type];
          expect(words, isNotNull,
              reason: 'health type $type is requested by the app but this test '
                  'does not know what the policy must call it — add it to '
                  '_mustBeNamed and to legal_text.py, then rebuild');
          expect(body, contains(words![index]),
              reason: 'the $lang privacy text never mentions $type. It is '
                  'read from the user\'s device; a policy that omits it is the '
                  'blocker this file exists to prevent');
        }
      }
    });

    test('and it says the readings stay on the device', () {
      // The disclosure is only adequate because the data does not leave the
      // phone. If that ever changes, this sentence becomes false and the
      // section needs rewriting rather than extending.
      expect(_arb('en'), contains('never leave your phone'));
      expect(_arb('ru'), contains('не покидают телефон'));
    });
  });

  /// R4. The policy said "You get everything, in a machine-readable file" /
  /// «Вы получаете всё», while `data_export.dart` deliberately excludes the
  /// encrypted progress-photo bytes and prints a line inside the export saying
  /// so. A promise about a data-subject right is not a place to round up.
  /// R5 of the Gate J review — the device-local claim was absolute in the
  /// notice and conditional in the code.
  ///
  /// Gate J deferred it as needing a production Firestore query nobody could
  /// run. Reading the code settles it without one, which is why it is closed
  /// here rather than left open on an access request:
  ///
  /// * `DeviceHealthProfileRepository.save` calls `stripSensitive` before it
  ///   writes, so the CURRENT app cannot put a health block on the server. The
  ///   present-tense claim is true, and
  ///   `device_health_profile_repository_test.dart` is what keeps it true.
  /// * `firestore_profile_repository.dart:74` still PARSES one, because a
  ///   document written before the 2026-08-06 split may carry it.
  /// * `_resolve` moves that block down and clears it upstream on the owner's
  ///   next read, and `deleteAccount`'s `recursiveDelete` of `users/{uid}`
  ///   removes it with the account.
  /// * Only an account nobody opens again keeps a copy — which is exactly the
  ///   population the absolute sentence was silently speaking for.
  ///
  /// So the notice is now specific about the one case it cannot promise, and
  /// tells that reader the one action that resolves it.
  group('the device-local health claim covers the accounts it cannot promise for',
      () {
    test('both locales name the historical exception', () {
      expect(_arb('en'), contains('before 6 august 2026'));
      expect(_arb('ru'), contains('до 6 августа 2026'));
    });

    test('and tell the reader what resolves it', () {
      // A disclosure that names a residue and offers no action is worse than
      // one that names nothing: it worries the reader without helping them.
      expect(_arb('en'), contains('opening the app once is enough'));
      expect(_arb('ru'), contains('достаточно один раз открыть приложение'));
    });

    test('CONTROL: the absolute present-tense claim is still made', () {
      // The fix must not be "soften it until it says nothing". The app really
      // does not send these answers, and that is the sentence a user needs.
      expect(_arb('en'), contains("is not sent to this app's servers"));
      expect(_arb('ru'), contains('не отправляется на серверы этого'));
    });
  });

  group('the export promise matches what the export produces', () {
    test('neither locale promises the file contains everything', () {
      expect(_arb('en'), isNot(contains('you get everything')));
      expect(_arb('ru'), isNot(contains('вы получаете всё')));
    });

    test('and both name the exclusion', () {
      // The words the exclusion has to reach the user in. `data_export.dart`
      // says "Progress photo image data is not included in this export."
      expect(_arb('en'), contains('does not '));
      expect(_arb('en'), contains('progress-photo images'));
      expect(_arb('ru'), contains('сами изображения'));
    });
  });

  test('every declared health permission is a type the app requests', () {
    // `READ_HEART_RATE` sat here unused. Play's Health Connect access review
    // rejects a declaration for a data type with no demonstrated in-app use,
    // and the permission grants continuous heart-rate history the app never
    // reads — a data-minimisation problem as well as a store one.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final declared = RegExp(r'android\.permission\.health\.(READ|WRITE)_(\w+)')
        .allMatches(manifest)
        .map((m) => m.group(2)!)
        .toSet();

    // The plugin's Android names, which is what the manifest has to match.
    const known = {
      'STEPS': h.HealthDataType.STEPS,
      'ACTIVE_CALORIES_BURNED': h.HealthDataType.ACTIVE_ENERGY_BURNED,
      'RESTING_HEART_RATE': h.HealthDataType.RESTING_HEART_RATE,
      'SLEEP': h.HealthDataType.SLEEP_ASLEEP,
      'HEART_RATE_VARIABILITY': h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      'EXERCISE': h.HealthDataType.WORKOUT,
    };
    final requested = <h.HealthDataType>{
      ...healthReadTypes(android: true),
      ...healthWriteTypes,
    };

    for (final name in declared) {
      final type = known[name];
      expect(type, isNotNull,
          reason: 'the manifest declares health permission $name, which this '
              'test does not recognise. Either the app gained a metric and '
              'this map needs it, or the permission is unused and must go');
      expect(requested, contains(type),
          reason: 'the manifest declares $name but no code path requests it');
    }
  });

  group('the app does not claim a therapeutic grade', () {
    test('no user-facing string offers rehabilitation', () {
      // "rehab-grade" shipped on the About page in both locales while the
      // Terms in the same corpus said the library "has not been reviewed by a
      // physiotherapist". Rehabilitation is an explicit medical purpose under
      // MDR 2017/745 Art. 2(1); the app's own catalogue tagger states in its
      // header that nobody with a licence has looked at the tags.
      //
      // Matched narrowly. This forbids claiming to PROVIDE rehabilitation, not
      // mentioning that a user might be in it — a disclaimer that says "this
      // is not a rehabilitation programme" must stay legal to write.
      for (final (lang, banned) in const [
        ('en', ['rehab-grade', 'rehabilitation-grade', 'clinical-grade']),
        ('ru', ['реабилитационного уровня', 'клинического уровня']),
      ]) {
        final body = _arb(lang);
        for (final phrase in banned) {
          expect(body, isNot(contains(phrase)),
              reason: '$lang carries the therapeutic-quality claim "$phrase"');
        }
      }
    });

    test('CONTROL: the Terms still say the library is unreviewed', () {
      // Without this, the assertion above could pass because the whole corpus
      // was emptied. The contradiction was only visible because BOTH halves
      // were present; this keeps the honest half pinned.
      expect(_arb('en'), contains('not been reviewed by a physiotherapist'));
    });
  });
}
