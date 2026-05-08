import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';

/// Holds the in-progress draft profile while the user moves through the
/// questionnaire. Backed by the auth provider so we always have a uid.
/// Hydrates from any cached profile on first build, so partial answers
/// survive app restarts (or refreshes from the in-memory mock).
final questionnaireDraftProvider =
    NotifierProvider<QuestionnaireDraft, UserProfile>(
        QuestionnaireDraft.new);

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

  void reset() {
    final user = ref.read(authUserProvider).valueOrNull;
    state = UserProfile.empty(user?.uid ?? 'anonymous');
  }
}
