import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';

/// Holds the in-progress draft profile while the user moves through the
/// questionnaire. Backed by the auth provider so we always have a uid.
/// Hydrates from any cached profile on first build, so partial answers
/// survive app restarts (or refreshes from the in-memory mock).
final questionnaireDraftProvider =
    NotifierProvider<QuestionnaireDraft, UserProfile>(QuestionnaireDraft.new);

class QuestionnaireDraft extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final user = ref.watch(authUserProvider).valueOrNull;
    final uid = user?.uid ?? 'anonymous';
    final repo = ref.read(profileRepositoryProvider);
    final cached = repo.cached(uid);
    if (cached != null) return cached;
    return UserProfile.empty(uid);
  }

  /// Persist the current draft (no `completedAt`) so the user's answers
  /// survive losing the screen.
  Future<void> saveDraft() async {
    await ref.read(profileRepositoryProvider).save(state);
  }

  void updatePersonal(PersonalInfo Function(PersonalInfo) update) =>
      state = state.copyWith(personal: update(state.personal));

  void updateHealth(HealthHistory Function(HealthHistory) update) =>
      state = state.copyWith(health: update(state.health));

  void updateGoals(FitnessGoals Function(FitnessGoals) update) =>
      state = state.copyWith(goals: update(state.goals));

  void updateLevel(FitnessLevel Function(FitnessLevel) update) =>
      state = state.copyWith(level: update(state.level));

  void updateLifestyle(Lifestyle Function(Lifestyle) update) =>
      state = state.copyWith(lifestyle: update(state.lifestyle));

  void updateEquipment(EquipmentAccess Function(EquipmentAccess) update) =>
      state = state.copyWith(equipment: update(state.equipment));

  void updateMotivation(MotivationPrefs Function(MotivationPrefs) update) =>
      state = state.copyWith(motivation: update(state.motivation));

  /// O5. Writes the schedule AND keeps [MotivationPrefs.preferredDuration] in
  /// step with it.
  ///
  /// Session length is asked once, in minutes, on the schedule screen. The
  /// coarse bucket is still read elsewhere (`suggestion_builder.dart:135`), so
  /// it is derived here rather than asked a second time. Two controls for one
  /// fact is how they end up disagreeing — the same reasoning that made
  /// `hasGymAccess` derived in O4.
  ///
  /// The sync lives in the notifier, not in the widget, so it holds for every
  /// caller and can be asserted without pumping a screen.
  void updateSchedule(TrainingSchedule Function(TrainingSchedule) update) {
    final next = update(state.schedule);
    state = state.copyWith(
      schedule: next,
      motivation: next.sessionMinutes == null
          // Nothing to derive from: leave whatever a pre-O5 profile already
          // had rather than blanking a real answer.
          ? state.motivation
          : state.motivation.copyWith(preferredDuration: next.durationBucket),
    );
  }

  void reset() {
    final user = ref.read(authUserProvider).valueOrNull;
    state = UserProfile.empty(user?.uid ?? 'anonymous');
  }
}
