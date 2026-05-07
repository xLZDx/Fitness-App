import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../profile/data/profile_models.dart';

/// Holds the in-progress draft profile while the user moves through the
/// questionnaire. Backed by the auth provider so we always have a uid.
final questionnaireDraftProvider =
    NotifierProvider<QuestionnaireDraft, UserProfile>(
        QuestionnaireDraft.new);

class QuestionnaireDraft extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final user = ref.watch(authUserProvider).valueOrNull;
    return UserProfile.empty(user?.uid ?? 'anonymous');
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
