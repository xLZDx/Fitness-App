import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/steps/step_health.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// O8 (birth year replaces a stored age) and P4-lite (the injuries box stops
/// throwing away what it cannot parse).
///
/// Both are migrations of data that already exists on real devices, which is
/// the class of change that fails silently: nothing crashes, an answer just
/// quietly stops being there.
void main() {
  group('O8 — a profile written before the birth year existed', () {
    test('keeps the age it already had', () {
      const legacy = PersonalInfo(age: 31);
      expect(legacy.birthYear, isNull);
      expect(legacy.ageAt(2026), 31,
          reason: 'dropping the stored age would un-answer this silently');
    });

    test('is still distinguishable from a profile that answered nothing', () {
      expect(const PersonalInfo().ageAt(2026), isNull);
    });

    test('an unrelated edit does not freeze a derived age as a stored one', () {
      // The trap in `copyWith`: passing the `age` GETTER through would turn
      // "born 1990" into "aged 36 forever" the first time the user changed
      // their weight.
      const p = PersonalInfo(birthYear: 1990);
      final edited = p.copyWith(weightCurrentKg: 80);
      expect(edited.birthYear, 1990);
      expect(edited.ageAt(2030), 40,
          reason: 'age must still follow the year, not a snapshot of it');
    });
  });

  group('O8 — a birth year answers the age', () {
    test('and wins over any stored legacy value', () {
      const p = PersonalInfo(age: 20, birthYear: 1990);
      expect(p.ageAt(2026), 36);
    });

    test('the same profile reads a year older next year', () {
      const p = PersonalInfo(birthYear: 1990);
      expect(p.ageAt(2026), 36);
      expect(p.ageAt(2027), 37);
    });

    test('serialisation writes the derived age, not the stored one', () {
      const profile =
          UserProfile(uid: 'u', personal: PersonalInfo(age: 20, birthYear: 1990));
      final json = profile.toJson()['personal'] as Map<String, dynamic>;
      expect(json['birthYear'], 1990);
      // Readers that predate O8 keep getting a true answer rather than the
      // stale 20 sitting in the document.
      expect(json['age'], profile.personal.age);
    });

    test('either field marks the personal step answered', () {
      expect(
        isOnboardingStepAnswered(OnboardingStep.personal,
            const UserProfile(uid: 'u', personal: PersonalInfo(birthYear: 1990))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(OnboardingStep.personal,
            const UserProfile(uid: 'u', personal: PersonalInfo(age: 31))),
        isTrue,
      );
    });
  });

  group('P4-lite — the injuries box keeps what it cannot parse', () {
    test('an entry with no colon is kept, not discarded', () {
      // The whole defect: "колено болит" used to vanish between the keyboard
      // and the profile, leaving a filled-looking field and an empty list.
      final parsed = parseInjuryInput('колено болит');
      expect(parsed, hasLength(1));
      expect(parsed.single.bodyPart, 'колено болит');
      expect(parsed.single.type, isEmpty);
    });

    test('the documented format still parses into part and type', () {
      final parsed = parseInjuryInput('колено: растяжение');
      expect(parsed.single.bodyPart, 'колено');
      expect(parsed.single.type, 'растяжение');
    });

    test('parsed and unparsed entries survive together', () {
      final parsed = parseInjuryInput('колено: растяжение, плечо ноет');
      expect(parsed.map((i) => i.bodyPart), ['колено', 'плечо ноет']);
      expect(parsed.map((i) => i.type), ['растяжение', '']);
    });

    test('an unparsed entry is not passed off as screened', () {
      // `region == null && !confirmed` is the state that means "still needs a
      // human". Inventing a region here would claim a screening that never ran.
      final parsed = parseInjuryInput('рёбра');
      expect(parsed.single.region, isNull);
      expect(parsed.single.confirmed, isFalse);
      expect(parsed.single.isResolved, isFalse);
    });

    test('blank input clears the list rather than storing an empty injury', () {
      expect(parseInjuryInput('   ,  '), isEmpty);
    });

    test('typing in the box does not strip a region set on the body map', () {
      // O6 writes injuries whose region came from a tap, not from the text. A
      // parse that rebuilt purely from the string would erase that region the
      // first time the user typed anything here — and the body map would show
      // the zone deselected without ever being touched.
      const previous = [
        Injury(bodyPart: 'Колено', type: '', region: InjuryRegion.knee),
      ];
      final parsed = parseInjuryInput('Колено, плечо ноет', previous);
      expect(parsed.first.region, InjuryRegion.knee);
      expect(parsed.last.region, isNull);
    });

    test('the box round-trips its own rendering', () {
      // What the field shows must parse back to what it was showing, or the
      // next keystroke rewrites the user's words.
      const injuries = [
        Injury(bodyPart: 'колено', type: 'растяжение'),
        Injury(bodyPart: 'плечо ноет', type: ''),
      ];
      final text = formatInjuryInput(injuries);
      expect(text, 'колено: растяжение, плечо ноет');
      final parsed = parseInjuryInput(text, injuries);
      expect(parsed.map((i) => i.bodyPart), injuries.map((i) => i.bodyPart));
      expect(parsed.map((i) => i.type), injuries.map((i) => i.type));
    });
  });
}
