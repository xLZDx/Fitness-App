/// Weigh-in state (design s21, D-72): the weight entries, the ONE
/// `currentWeightProvider` and the add/edit/delete actions of the weight log.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_deletion/state/account_deletion_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../data/in_memory_nutrition_repositories.dart';
import '../data/nutrition_inputs.dart';
import '../data/weight_entry.dart';
import '../data/weight_repository.dart';

/// "Now" for the nutrition state; overridden in tests.
final nutritionClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

/// Backend-agnostic weigh-in storage. Default is the in-memory fake;
/// `main.dart` overrides it with the Firestore implementation.
final weightRepositoryProvider = Provider<WeightEntriesRepository>((ref) {
  final repo = InMemoryWeightRepository(clock: ref.watch(nutritionClockProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// The last 60 days of weigh-ins with their document ids, oldest first. Empty
/// while signed out.
final weightLogItemsProvider =
    StreamProvider<List<WeightLogItem>>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(weightRepositoryProvider).watchLog(user.uid);
});

/// The weigh-ins without ids, oldest first (what the maths reads).
final weightEntriesProvider = Provider<AsyncValue<List<WeightEntry>>>((ref) {
  return ref
      .watch(weightLogItemsProvider)
      .whenData((items) => [for (final i in items) i.entry]);
});

/// THE current weight (D-72): the newest weigh-in within 14 days, else the
/// profile weight flagged stale, else null. Every consumer (eligibility,
/// inputs, plan, scan weight prompt) reads this one definition.
///
/// Evaluated at the time the inputs last changed; a plain rebuild is not
/// scheduled for the day a weigh-in turns 14 days old, the next weigh-in,
/// profile change or screen open recomputes it.
final currentWeightProvider = Provider<ResolvedWeight?>((ref) {
  final entries = ref.watch(weightEntriesProvider).valueOrNull ?? const [];
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  return resolveCurrentWeight(
    entries: entries,
    profileWeightKg: profile?.personal.weightCurrentKg,
    now: ref.watch(nutritionClockProvider)(),
  );
});

/// What a weight write did.
enum WeightWriteStatus {
  saved,

  /// The weight is outside 30..300 kg; nothing written.
  invalid,

  /// Signed out, or the account is being deleted; nothing written.
  unavailable,

  /// A scan weight equal to the same day's manual entry; the manual entry is
  /// kept untouched.
  keptManual,
}

/// Add / edit / delete of weigh-ins. The data-notice acknowledgement (D-79) is
/// the caller's job: the UI calls `ensureDataNoticeAcknowledged` before it
/// calls these, so a declined notice defers the write and nothing is lost.
class WeightLogActions {
  WeightLogActions(this._ref);

  final Ref _ref;

  String? _uid() {
    final uid = _ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) return null;
    // The deletion fence: no write while this account is being deleted.
    if (_ref.read(accountBeingDeletedUidProvider) == uid) return null;
    return uid;
  }

  /// Adds (or overwrites the same local day's) manual weigh-in.
  Future<WeightWriteStatus> add(double kg, {DateTime? at}) async {
    final uid = _uid();
    if (uid == null) return WeightWriteStatus.unavailable;
    if (!WeightEntry.isValidKg(kg)) return WeightWriteStatus.invalid;
    final when = at ?? _ref.read(nutritionClockProvider)();
    await _ref
        .read(weightRepositoryProvider)
        .put(uid, WeightEntry(at: when, kg: kg));
    return WeightWriteStatus.saved;
  }

  /// A weight confirmed in the scan weight prompt. Never silently replaces a
  /// same-day manual entry: an equal value leaves it untouched, a changed
  /// value is the user's explicit edit and is written with `source: scan`.
  Future<WeightWriteStatus> saveScanWeight(double kg, {DateTime? at}) async {
    final uid = _uid();
    if (uid == null) return WeightWriteStatus.unavailable;
    if (!WeightEntry.isValidKg(kg)) return WeightWriteStatus.invalid;
    final when = at ?? _ref.read(nutritionClockProvider)();
    final entry = WeightEntry(at: when, kg: kg, source: WeightSource.scan);
    final repo = _ref.read(weightRepositoryProvider);
    final existing = await repo.entryForDay(uid, entry.dayKey);
    if (existing != null &&
        existing.entry.source == WeightSource.manual &&
        existing.entry.kg == kg) {
      return WeightWriteStatus.keptManual;
    }
    await repo.put(uid, entry);
    return WeightWriteStatus.saved;
  }

  /// Edits [item] (new weight and/or date); a changed day moves the entry.
  Future<WeightWriteStatus> edit(
    WeightLogItem item, {
    required double kg,
    DateTime? at,
  }) async {
    final uid = _uid();
    if (uid == null) return WeightWriteStatus.unavailable;
    if (!WeightEntry.isValidKg(kg)) return WeightWriteStatus.invalid;
    await _ref.read(weightRepositoryProvider).replace(
          uid,
          oldId: item.id,
          entry: WeightEntry(at: at ?? item.entry.at, kg: kg),
        );
    return WeightWriteStatus.saved;
  }

  Future<WeightWriteStatus> delete(WeightLogItem item) async {
    final uid = _uid();
    if (uid == null) return WeightWriteStatus.unavailable;
    await _ref.read(weightRepositoryProvider).delete(uid, item.id);
    return WeightWriteStatus.saved;
  }
}

final weightLogActionsProvider =
    Provider<WeightLogActions>((ref) => WeightLogActions(ref));
