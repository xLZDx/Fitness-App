import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// What S1b turned out to be.
///
/// The plan scoped it as a one-way backfill of stored health data, and named
/// it the riskiest step in the remediation for exactly that reason. S1a's
/// shape removed the need: `region` is additive, `bodyPart` is never
/// overwritten, `Injury.fromJson` reads the old shape by field absence, and
/// both the filter and the honesty gate fall back to `suggestRegion` at read
/// time. An untouched account is already screened and already told the truth.
///
/// A migration would have mutated medical records to produce a result the app
/// already computes. What was actually missing is the nudge for the injuries
/// nothing can name, because those are screened by nothing and only the user
/// can resolve them.
class _Repo implements ProfileRepository {
  _Repo(this.profile);
  final UserProfile? profile;

  @override
  Stream<UserProfile?> watch(String uid) => Stream.value(profile);
  @override
  UserProfile? cached(String uid) => profile;
  @override
  Future<UserProfile?> load(String uid) async => profile;
  @override
  Future<void> save(UserProfile p) async {}
  @override
  Future<void> delete(String uid) async {}
}

Future<int> countFor(List<Injury> injuries) async {
  final container = ProviderContainer(overrides: [
    authUserProvider
        .overrideWith((ref) => Stream.value(const AuthUser(uid: 'u', displayName: 'U'))),
    profileRepositoryProvider.overrideWithValue(
      _Repo(UserProfile(uid: 'u', health: HealthHistory(injuries: injuries))),
    ),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(currentProfileProvider, (_, __) {});
  addTearDown(sub.close);
  await container.read(currentProfileProvider.future);
  return container.read(unresolvedInjuryCountProvider);
}

void main() {
  test('an injury a rule can name does not nag', () async {
    // "left knee" resolves to knee without anyone typing anything, so the
    // screen pre-answers it. Counting it would nag about a solved problem.
    expect(await countFor(const [Injury(bodyPart: 'left knee', type: 'x')]), 0);
  });

  test('an injury nothing can name is counted', () async {
    // A rib is screened by nothing at all, and only the user can say what to
    // do about it.
    expect(await countFor(const [Injury(bodyPart: 'rib', type: 'x')]), 1);
  });

  test('a declined injury stops counting', () async {
    expect(
      await countFor(
        const [Injury(bodyPart: 'rib', type: 'x', confirmed: true)],
      ),
      0,
    );
  });

  test('a mapped injury does not count', () async {
    expect(
      await countFor(
        const [Injury(bodyPart: 'anything', type: 'x', region: InjuryRegion.hip)],
      ),
      0,
    );
  });

  test('no profile is not a nag', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(unresolvedInjuryCountProvider), 0);
  });

  test('only the unnameable ones are counted, in a mixed list', () async {
    expect(
      await countFor(const [
        Injury(bodyPart: 'left knee', type: 'x'),
        Injury(bodyPart: 'rib', type: 'x'),
        Injury(bodyPart: 'jaw', type: 'x'),
      ]),
      2,
    );
  });
}
