import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';

/// §18 — the Dart model and the Firestore rule, held in step structurally.
///
/// ## The defect this is built from
///
/// N-02: `HealthHistory.toJson` emitted ten fields and `healthIsStripped`
/// inspected eight. The two missing ones were `screening` — the PAR-Q answers
/// — and `flags`, which carries every normalised health answer the app has.
/// A client could write both to the server, and the rule that exists to keep
/// medical content off the server would have allowed it.
///
/// That was fixed by hand. Fixing it by hand is exactly the thing that failed:
/// three times in this programme a field has reached the model and the
/// serialiser and not the guard, each time invisibly, because nothing in the
/// repository connects the two. This is that connection.
///
/// ## Why it reads the SERIALISER rather than a list of names
///
/// A hardcoded list is a third place to forget. The keys come from calling
/// `toJson()` on a real instance, so a field added to the model appears here
/// the moment it is serialised — which is the moment it can reach the server,
/// and therefore the moment the rule has to know about it.
///
/// ## What it does not claim
///
/// That the rule is CORRECT — only that it mentions every key that can be
/// written. A rule naming a field and testing the wrong thing about it passes
/// here and is caught by the emulator suite in `functions/`, which exercises
/// the rule against a real Firestore. The two are complementary: this one
/// cannot be forgotten, that one cannot be satisfied by a mention.
void main() {
  final rulesFile = File('../firestore.rules');

  /// The rules source with comments removed.
  ///
  /// Not fastidiousness. `healthIsStripped`'s own comment block names
  /// `HealthFlags` and talks about keys and values; a raw `contains` over the
  /// file would be satisfied by prose describing the very field that had been
  /// dropped from the check. Fifth instance of this class in this programme.
  String liveRules() {
    final raw = rulesFile.readAsStringSync();
    final withoutBlocks = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return withoutBlocks
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  }

  /// The body of `function <name>(...)`, by brace balance.
  ///
  /// Balanced rather than sliced to the next `function`, because a slice takes
  /// whatever follows — which is how the field-coverage fence in this same
  /// directory ended up matching a neighbouring member's doc comment and
  /// certifying a defect it was written to catch (R-01).
  String ruleFunction(String name) {
    final src = liveRules();
    final at = src.indexOf('function $name(');
    if (at < 0) {
      throw StateError(
        'firestore.rules no longer declares function $name(). If it was '
        'renamed, update this test deliberately — do not delete the lookup to '
        'make it pass.',
      );
    }
    final open = src.indexOf('{', at);
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(open + 1, i);
      }
    }
    throw StateError('unbalanced braces after function $name');
  }

  bool names(String body, String key) =>
      RegExp('\\b${RegExp.escape(key)}\\b').hasMatch(body);

  test('the rules file is where this test thinks it is', () {
    // The guard on the guard. A source-scanning test whose subject has moved
    // reports success while checking nothing, and this one reads across the
    // mobile/ boundary, which is exactly the path that breaks silently.
    expect(rulesFile.existsSync(), isTrue,
        reason: 'expected the rules at ${rulesFile.absolute.path}');
    expect(liveRules(), contains('function healthIsStripped('));
    expect(liveRules(), contains('function flagsAreStripped('));
  });

  test('every key HealthHistory can write is named by healthIsStripped', () {
    // A populated instance, not `const HealthHistory()`: a serialiser that
    // omits null or empty values would emit fewer keys from an empty one, and
    // the field that gets dropped is precisely the one nobody set.
    final keys = HealthHistory(
      conditions: const ['x'],
      allergies: const ['x'],
      medications: const ['x'],
      injuries: const [Injury(bodyPart: 'knee', type: 'strain')],
      physicalLimitations: const ['x'],
      recentSurgeries: const ['x'],
      bloodPressure: BloodPressure.high,
      otherConcerns: 'x',
      screening: const {},
      flags: const HealthFlags(
        restrictions: {MovementRestriction.overhead},
        bloodPressure: BloodPressureStatus.diagnosedHigh,
        surgery: SurgeryStatus.underRestrictions,
        clinicianAdvice: ClinicianExerciseAdvice.limitsGiven,
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      ),
    ).toJson().keys.toList();

    expect(keys, isNotEmpty,
        reason: 'toJson emitted nothing, so this test would police nothing');
    expect(keys.length, greaterThanOrEqualTo(10),
        reason: 'N-02 was found against a ten-key block. Fewer keys than that '
            'means the serialiser lost fields, which is its own defect: $keys');

    final body = ruleFunction('healthIsStripped');
    expect(body.trim(), isNotEmpty);
    for (final key in keys) {
      expect(names(body, key), isTrue,
          reason: 'HealthHistory.toJson writes "$key" and healthIsStripped '
              'does not inspect it. A client can therefore put it on the '
              'server. This is N-02 exactly: the block emitted ten fields and '
              'the rule read eight, so the PAR-Q answers and every normalised '
              'health flag were writable.\n'
              'Add the field to the rule — do not remove it from this test.');
    }
  });

  test('every key HealthFlags can write is named by flagsAreStripped', () {
    final keys = const HealthFlags(
      restrictions: {MovementRestriction.overhead},
      bloodPressure: BloodPressureStatus.diagnosedHigh,
      surgery: SurgeryStatus.underRestrictions,
      clinicianAdvice: ClinicianExerciseAdvice.limitsGiven,
      professionalGuidance: ProfessionalGuidanceNeed.reported,
    ).toJson().keys.toList();

    expect(keys, isNotEmpty);
    expect(keys.length, greaterThanOrEqualTo(5),
        reason: 'HealthFlags carries five answers; $keys is fewer');

    final body = ruleFunction('flagsAreStripped');
    expect(body.trim(), isNotEmpty);
    for (final key in keys) {
      expect(names(body, key), isTrue,
          reason: 'HealthFlags.toJson writes "$key" and flagsAreStripped does '
              'not inspect it. F014 was lost twice by exactly this shape — a '
              'field that reaches the model and the serialiser and not the '
              'guard.');
    }
  });

  test('healthIsStripped actually delegates to flagsAreStripped', () {
    // Otherwise the two tests above are each satisfied while the rule never
    // reaches the second function: `healthIsStripped` naming `flags` proves it
    // mentions the key, not that it inspects what is inside it.
    expect(names(ruleFunction('healthIsStripped'), 'flagsAreStripped'), isTrue,
        reason: 'healthIsStripped names the `flags` key without checking its '
            'contents, so every HealthFlags answer is writable through it');
  });

  // ---- E1 additions: nutrition fields (RULES-18, ONB-16, PRIV-16) ----

  test('E1: with the nutrition answers set, every HealthFlags key is named by flagsAreStripped', () {
    // The serializer omits null/empty answers, so the populated instance above
    // does not emit the two new keys. This one does.
    final keys = const HealthFlags(
      restrictions: {MovementRestriction.overhead},
      bloodPressure: BloodPressureStatus.diagnosedHigh,
      surgery: SurgeryStatus.underRestrictions,
      clinicianAdvice: ClinicianExerciseAdvice.limitsGiven,
      professionalGuidance: ProfessionalGuidanceNeed.reported,
      nutritionGuidance: NutritionGuidanceNeed.reported,
      foodAllergens: {FoodAllergen.peanuts},
    ).toJson().keys.toSet();
    expect(keys, {
      'restrictions',
      'bloodPressure',
      'surgery',
      'clinicianAdvice',
      'professionalGuidance',
      'nutritionGuidance',
      'foodAllergens',
    });
    final body = ruleFunction('flagsAreStripped');
    for (final key in keys) {
      expect(names(body, key), isTrue,
          reason: 'HealthFlags.toJson can write "$key" and flagsAreStripped '
              'does not name it (the F014 failure class).');
    }
  });

  test('E1 RULES-18: empty flags serialise to NO nutrition keys; unset answers are never explicit null', () {
    final json = HealthFlags.empty.toJson();
    expect(json.containsKey('nutritionGuidance'), isFalse);
    expect(json.containsKey('foodAllergens'), isFalse);
    final partial = const HealthFlags(
      professionalGuidance: ProfessionalGuidanceNeed.none,
    ).toJson();
    expect(partial.containsKey('nutritionGuidance'), isFalse);
    expect(partial.containsKey('foodAllergens'), isFalse);
    expect(partial['professionalGuidance'], 'none');
  });

  test('E1 ONB-16: every NutritionPrefs key except excludedFoods is allowed by nutritionOk; excludedFoods is NOT', () {
    final prefs = NutritionPrefs(
      sexAtBirth: SexAtBirth.female,
      goalDirection: GoalDirection.lose,
      targetBodyFatPct: 20,
      typicalDailySteps: 6500,
      mealsPerDay: 3,
      excludedFoods: const ['peanut butter'],
      planOwnership: PlanOwnership.coached,
      healthConnectChoice: HealthConnectChoice.manual,
      completedAt: DateTime.utc(2026, 10, 15),
    );
    final keys = prefs.toJson().keys.toSet();
    expect(keys, contains('excludedFoods'));
    expect(keys.length, 10, reason: 'schema + nine answers: $keys');
    final body = ruleFunction('nutritionOk');
    for (final key in keys.difference({'excludedFoods'})) {
      expect(names(body, key), isTrue,
          reason: 'NutritionPrefs.toJson writes "$key" but nutritionOk does '
              'not allow it, so a normal profile save would be refused.');
    }
    expect(names(body, 'excludedFoods'), isFalse,
        reason: 'excludedFoods is device-only free text (D-55); the rules '
            'allowlist must refuse it');
  });
}
