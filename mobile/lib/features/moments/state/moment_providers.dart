import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/moment.dart';
import '../data/moment_repository.dart';

final momentRepositoryProvider = Provider<MomentRepository>((ref) {
  return MockMomentRepository();
});

/// Whether Home may show the Day-3 welcome modal. Off in v1: the modal is
/// entirely a Supporter-subscription ask, which is outside the v1 scope.
/// Launch counting and the "settled" hand-off to the mode chooser still run.
/// Tests override this to true to exercise the modal.
final day3WelcomeModalEnabledProvider = Provider<bool>((ref) => false);

/// Tiny notifier that triggers a moment-bookkeeping op (mark shown,
/// bump counter) and exposes a simple `AsyncValue<void>` for the UI.
class MomentController extends StateNotifier<AsyncValue<void>> {
  MomentController(this._repo) : super(const AsyncData(null));

  final MomentRepository _repo;

  Future<void> markShown(MomentId id) async {
    state = const AsyncLoading();
    try {
      await _repo.markShown(id);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> bumpLaunchCount() => _repo.bumpLaunchCount();
  Future<void> bumpInjuryFilterUses() => _repo.bumpInjuryFilterUses();
}

final momentControllerProvider =
    StateNotifierProvider<MomentController, AsyncValue<void>>((ref) {
  return MomentController(ref.watch(momentRepositoryProvider));
});

final launchCountProvider = FutureProvider<int>((ref) {
  return ref.watch(momentRepositoryProvider).launchCount();
});

final injuryFilterUsesProvider = FutureProvider<int>((ref) {
  return ref.watch(momentRepositoryProvider).injuryFilterUses();
});

final hasShownProvider =
    FutureProvider.family<bool, MomentId>((ref, id) {
  return ref.watch(momentRepositoryProvider).hasShown(id);
});
