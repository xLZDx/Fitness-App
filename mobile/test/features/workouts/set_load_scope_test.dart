import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

/// The weight/reps a person typed for an exercise belong to THEIR session. A
/// sign-out / account switch in the same process used to leave the value in an
/// app-scoped provider, so the next account's first set was logged with the
/// previous person's load.
AuthUser _u(String uid) => AuthUser(uid: uid, displayName: uid);

void main() {
  test('a captured load does not survive an account switch', () async {
    final auth = StreamController<AuthUser?>();
    addTearDown(auth.close);
    final c = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    addTearDown(c.dispose);
    // Keep the family entry alive the way a mounted screen would.
    final sub = c.listen(setLoadProvider('squat'), (_, __) {});
    addTearDown(sub.close);
    final authSub = c.listen(authUserProvider, (_, __) {});
    addTearDown(authSub.close);

    auth.add(_u('A'));
    await Future<void>.delayed(Duration.zero);
    c.read(setLoadProvider('squat').notifier).state =
        (weightKg: 80, reps: 5);
    expect(c.read(setLoadProvider('squat')), isNotNull);

    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    auth.add(_u('B'));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(setLoadProvider('squat')), isNull,
        reason: "B must not inherit A's weight and reps");
  });

  test('re-emitting the same uid does not wipe the person\'s own answer',
      () async {
    final auth = StreamController<AuthUser?>();
    addTearDown(auth.close);
    final c = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(setLoadProvider('squat'), (_, __) {});
    addTearDown(sub.close);
    final authSub = c.listen(authUserProvider, (_, __) {});
    addTearDown(authSub.close);

    auth.add(_u('A'));
    await Future<void>.delayed(Duration.zero);
    c.read(setLoadProvider('squat').notifier).state =
        (weightKg: 80, reps: 5);
    // A profile refresh re-emits the same identity with a new display name.
    auth.add(const AuthUser(uid: 'A', displayName: 'Alice'));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(setLoadProvider('squat')), isNotNull);
  });
}
