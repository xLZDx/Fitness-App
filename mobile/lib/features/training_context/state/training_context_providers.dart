import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart' show sortByTierFit;
import '../../equipment/state/equipment_providers.dart';
import '../../safety/state/eligibility_providers.dart';
import '../data/training_context.dart';

/// SharedPreferences key for one account's answer. Per uid and NOT part of the
/// health blob: it is a session preference, not health data. The account
/// deletion wipe removes this exact key (`local_data_wipe.dart`).
String trainingContextKeyFor(String uid) => 'training_context.v1.$uid';

const _skippedToken = 'skipped';

/// Decodes a stored value. Anything unrecognised reads as unanswered, so the
/// user is asked again rather than silently given a default.
TrainingContextAnswer decodeTrainingContext(String? raw) {
  if (raw == null) return TrainingContextAnswer.unanswered;
  if (raw == _skippedToken) return TrainingContextAnswer.skipped;
  for (final c in TrainingContext.values) {
    if (c.name == raw) return TrainingContextAnswer.chosen(c);
  }
  return TrainingContextAnswer.unanswered;
}

String encodeTrainingContext(TrainingContextAnswer a) =>
    a.context?.name ?? _skippedToken;

/// Optional injection point for tests; production reads the platform store.
final trainingContextPrefsProvider = Provider<Future<SharedPreferences>>(
    (ref) => SharedPreferences.getInstance());

/// The signed-in user's stored training-context answer.
///
/// Loading until the uid and the stored value are both known, so no surface
/// can generate against a half-known answer. Signed out reads as unanswered.
final trainingContextProvider =
    AsyncNotifierProvider<TrainingContextNotifier, TrainingContextAnswer>(
        TrainingContextNotifier.new);

class TrainingContextNotifier extends AsyncNotifier<TrainingContextAnswer> {
  /// The uid the current state was loaded for. Cleared at the start of every
  /// reload: while an account switch is loading, Riverpod keeps the previous
  /// AsyncData, so a stale uid here would write account B's tap under A's key.
  String? _uid;

  @override
  Future<TrainingContextAnswer> build() async {
    _uid = null;
    final user = await ref.watch(authUserProvider.future);
    if (user == null) return TrainingContextAnswer.unanswered;
    final prefs = await ref.watch(trainingContextPrefsProvider);
    final answer =
        decodeTrainingContext(prefs.getString(trainingContextKeyFor(user.uid)));
    _uid = user.uid;
    return answer;
  }

  /// Stores [answer] and updates state, which regenerates every surface that
  /// watches it. State changes first: a failed write costs one repeated
  /// question next launch, not an ignored tap. A failed write is logged, not
  /// thrown. Refused while the signed-in account differs from the one the
  /// state was loaded for (an account switch is still loading).
  Future<void> select(TrainingContextAnswer answer) async {
    if (!answer.answered) return;
    final uid = _uid;
    final current = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || current == null || current != uid) return;
    state = AsyncData(answer);
    final prefs = await ref.read(trainingContextPrefsProvider);
    final ok = await prefs.setString(
        trainingContextKeyFor(uid), encodeTrainingContext(answer));
    if (!ok) debugPrint('training context answer was not persisted');
  }

  Future<void> choose(TrainingContext c) =>
      select(TrainingContextAnswer.chosen(c));

  Future<void> skip() => select(TrainingContextAnswer.skipped);
}

/// The context recommendations should use: the chosen one, or null (skipped
/// or still loading handled by callers via [trainingContextProvider]).
/// While a reload is in flight (an account switch) the previous account's
/// answer is still the held value, so it reads as null: the plain feed.
final activeTrainingContextProvider = Provider<TrainingContext?>((ref) {
  final a = ref.watch(trainingContextProvider);
  if (a.isLoading || a.isRefreshing) return null;
  return a.valueOrNull?.context;
});

/// `forYouExercisesProvider` under a training context: the injury-screened
/// catalogue, narrowed to the context and run through the same eligibility
/// layer (injuries, age policy, screening), then tier-sorted exactly as the
/// plain feed is. A null context is the plain feed itself.
final forYouExercisesInContextProvider =
    FutureProvider.family<List<ExerciseItem>, TrainingContext?>(
        (ref, context) async {
  if (context == null) return ref.watch(forYouExercisesProvider.future);
  final safe = await ref.watch(safeCatalogProvider.future);
  final profile = await ref.watch(screeningProfileProvider.future);
  final safety = await ref.watch(safetyContextProvider.future);
  return sortByTierFit(
    eligibleForTrainingContext(safe, safety, context),
    profile?.level.tier,
  );
});
