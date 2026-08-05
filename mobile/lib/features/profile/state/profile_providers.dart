import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../workouts/state/session_screening_providers.dart';
import '../data/injury_regions.dart';
import '../data/local_sensitive_store.dart';
import '../data/mock_profile_repository.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';

/// Backend-agnostic profile provider. Default wires up the in-memory mock;
/// override in tests or for the Firebase-backed implementation.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repo = MockProfileRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Where the device-only half of the profile lives (H1a).
///
/// A provider rather than a value `main.dart` keeps to itself, because restore
/// (H2b) has to write into the same store the repository reads from. Two
/// instances would restore a backup into a store nobody consults -- the import
/// would report success and change nothing, which is the failure mode this
/// indirection exists to make impossible.
final localSensitiveStoreProvider =
    Provider<LocalSensitiveStore>((_) => InMemorySensitiveStore());

/// The current user's profile (or null if signed out / not yet created).
final currentProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  final repo = ref.watch(profileRepositoryProvider);
  return repo.watch(user.uid);
});

/// How many of the user's stored injuries still need an area chosen.
///
/// ## Why this is what S1b turned out to be
///
/// The plan scoped S1b as a one-way backfill of stored health data: read every
/// user's free-text injuries, map them to regions, write them back. It also
/// said, correctly, that this was the riskiest step in the whole remediation —
/// the only one that mutates already-stored medical data.
///
/// S1a's shape removed the need for it. `region` is additive and `bodyPart` is
/// never overwritten, `Injury.fromJson` reads the old shape by field absence,
/// and both the screening filter and the honesty gate fall back to
/// `suggestRegion` on unmapped text at read time. An untouched account is
/// already screened and already told the truth about it. A migration would
/// therefore mutate health records to produce a result the app already
/// computes — strictly more risk for no behaviour change.
///
/// What is genuinely missing is the nudge: an injury nothing can name is
/// screened by nothing, and only the user can resolve it. So this counts them
/// and the profile tile says so. Silent inference was rejected in S1a for the
/// same reason it is rejected here — a safety decision nobody saw.
final unresolvedInjuryCountProvider = Provider<int>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) return 0;
  return unresolvedInjuries(
    // Proposals are not resolutions, but an injury a rule CAN name is one the
    // user only has to confirm, not puzzle over. Counting it as unresolved
    // would nag about something the screen pre-answers.
    profile.health.injuries
        .map((i) => i.region == null && !i.confirmed
            ? i.copyWith(region: suggestRegion(i.bodyPart))
            : i)
        .toList(),
  ).length;
});

/// True when the signed-in user has completed onboarding. Used by the router.
final isOnboardedProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  return profile?.hasCompletedOnboarding ?? false;
});

/// Submit a finalized profile (sets `completedAt`).
final profileSubmitProvider =
    NotifierProvider<ProfileSubmit, AsyncValue<void>>(ProfileSubmit.new);

class ProfileSubmit extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> submit(UserProfile draft) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.save(draft.copyWith(completedAt: DateTime.now()));
      // The injury list may have just changed, and a reminder scheduled
      // before it fires from the OS with no render pass to screen it. This is
      // the only save path in the app, so it is the only place that can catch
      // that. Best-effort: the profile is saved either way, and failing the
      // submit because a notification could not be cancelled would be worse
      // than the stale reminder.
      try {
        await ref.read(sessionReminderReconcilerProvider).reconcile();
      } catch (e) {
        debugPrint('reminder reconcile after profile save failed: $e');
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveDraft(UserProfile draft) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.save(draft);
  }

  /// Saves an edited injury list. The only save path outside onboarding.
  ///
  /// Before this, `ProfileRepository.save()` had exactly two call sites, both
  /// inside `features/onboarding/`, and the one affordance meant to reach them
  /// — "Edit your answers" (`profile_page.dart`) — routes to `/onboarding`,
  /// which `app_router.dart` bounces straight back to `/home` for anyone who
  /// has onboarded. There was no way to change a stored injury at all, which
  /// made the structured region below undeliverable to every existing user.
  ///
  /// It reconciles reminders afterwards for the same reason `submit` does: a
  /// newly-added injury can contraindicate a session whose notification is
  /// already armed in the OS, and this is now the path that can actually
  /// happen.
  Future<void> saveInjuries(List<Injury> injuries) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot edit injuries while signed out');
      }
      final repo = ref.read(profileRepositoryProvider);
      final current = ref.read(currentProfileProvider).valueOrNull ??
          await repo.load(user.uid) ??
          UserProfile.empty(user.uid);
      await repo.save(
        current.copyWith(
          health: current.health.copyWith(injuries: injuries),
        ),
      );
      try {
        await ref.read(sessionReminderReconcilerProvider).reconcile();
      } catch (e) {
        debugPrint('reminder reconcile after injury edit failed: $e');
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
