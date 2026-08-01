import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_silhouette.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// The coach asks for the answers it is about to use.
///
/// Operator: *"если етих данных нет в анкете то как только кто то заходит к
/// тренеру тот должен предложить дозаполнить нехватающих деталей"*. Tested
/// through the providers rather than the page, because the page opens a camera.
UserProfile _profile(PersonalInfo personal) =>
    UserProfile(uid: 'u1', personal: personal);

ProviderContainer _containerFor(UserProfile? profile) {
  final c = ProviderContainer(overrides: [
    currentProfileProvider.overrideWith((ref) => Stream.value(profile)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a blank intake is asked for all three', () async {
    final c = _containerFor(_profile(PersonalInfo.empty));
    await c.read(currentProfileProvider.future);
    expect(
      c.read(missingBodyAnswersProvider),
      {BodyAnswer.gender, BodyAnswer.height, BodyAnswer.weight},
    );
  });

  test('only what is actually missing is asked for', () async {
    final c = _containerFor(_profile(
      const PersonalInfo(gender: Gender.female, heightCm: 165),
    ));
    await c.read(currentProfileProvider.future);
    expect(c.read(missingBodyAnswersProvider), {BodyAnswer.weight});
  });

  test('a complete intake is not nagged', () async {
    final c = _containerFor(_profile(
      const PersonalInfo(
          gender: Gender.male, heightCm: 183, weightCurrentKg: 84),
    ));
    await c.read(currentProfileProvider.future);
    expect(c.read(missingBodyAnswersProvider), isEmpty);
  });

  test('"prefer not to say" is an answer and is not asked again', () async {
    // The failure this pins: treating the neutral choice as absence would put
    // the card back on the screen every visit, which reads as not having been
    // heard.
    final c = _containerFor(_profile(
      const PersonalInfo(
        gender: Gender.preferNotToSay,
        heightCm: 170,
        weightCurrentKg: 70,
      ),
    ));
    await c.read(currentProfileProvider.future);
    expect(c.read(missingBodyAnswersProvider), isEmpty);
    // ...and it still draws the neutral build rather than guessing a sex.
    expect(c.read(silhouetteBuildProvider).shoulderHalfWidth,
        BodyBuild.forBody(heightCm: 170, weightKg: 70).shoulderHalfWidth);
  });

  test('no profile at all still yields a drawable build', () async {
    final c = _containerFor(null);
    await c.read(currentProfileProvider.future);
    expect(c.read(silhouetteBuildProvider), BodyBuild.unknown);
  });

  test('the intake reaches the outline', () async {
    final woman = _containerFor(_profile(const PersonalInfo(
        gender: Gender.female, heightCm: 150, weightCurrentKg: 48)));
    final man = _containerFor(_profile(const PersonalInfo(
        gender: Gender.male, heightCm: 200, weightCurrentKg: 95)));
    await woman.read(currentProfileProvider.future);
    await man.read(currentProfileProvider.future);

    final w = woman.read(silhouetteBuildProvider);
    final m = man.read(silhouetteBuildProvider);
    expect(m.shoulderHalfWidth, greaterThan(w.shoulderHalfWidth));
    expect(m.hipHalfWidth, lessThan(w.hipHalfWidth));
  });
}
