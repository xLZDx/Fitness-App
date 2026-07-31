# -*- coding: utf-8 -*-
"""Localise the profile page.

Two things here are not plain substitution.

The activity label was DERIVED from the enum name: `moderatelyActive` was
turned into "moderately active" by inserting spaces before capitals. That is a
clever way to never need a label, and it hard-codes English into the shape of
an identifier -- rename the enum and the interface changes. It now looks the
value up like every other label.

The six goal names already exist, authored for onboarding. They are reused
rather than re-translated: two spellings of "Набор мышечной массы" in one app
is exactly the drift a shared key prevents.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path('D:/test 2/Fitness App/mobile')
PAGE = ROOT / 'lib' / 'features' / 'profile' / 'profile_page.dart'
ARB_EN = ROOT / 'lib' / 'l10n' / 'app_en.arb'
ARB_RU = ROOT / 'lib' / 'l10n' / 'app_ru.arb'

NEW = {
    'profileGuest': ('Guest', 'Гость'),
    'profileComplete': ('Profile complete', 'Профиль заполнен'),
    'profileSignInToSync': ('Sign in to sync progress',
                            'Войдите, чтобы синхронизировать прогресс'),
    'profileFinishOnboarding': ('Finish onboarding to unlock plans',
                                'Заполните анкету, чтобы открыть планы'),
    'profileHealthQuestionnaire': ('Health questionnaire', 'Анкета о здоровье'),
    'profileCompleteQuestionnaire': ('Complete questionnaire', 'Заполнить анкету'),
    'profileFreeStartTrial': ('Free · start a 14-day trial',
                              'Бесплатно · 14 дней пробного периода'),
    'profileTierFree': ('Free', 'Бесплатный'),
    'profileTierStandard': ('Standard', 'Стандартный'),
    'profileTierCelebrity': ('Celebrity trainer', 'Тренер-звезда'),
    'profileSubTrial': ('Trial', 'Пробный период'),
    'profileSubActive': ('Active', 'Активна'),
    'profileSubCancelling': ('Cancelling', 'Отменяется'),
    'profileSubExpired': ('Expired', 'Истекла'),
    'profileSubNone': ('Free', 'Бесплатно'),
    'profileRowAge': ('Age', 'Возраст'),
    'profileRowHeight': ('Height', 'Рост'),
    'profileRowWeight': ('Weight', 'Вес'),
    'profileRowActivity': ('Activity', 'Активность'),
    'profileRowGoals': ('Goals', 'Цели'),
}

MEASURE = {
    'commonCentimetres': ('{value} cm', '{value} см', 'int'),
    'commonKilograms': ('{value} kg', '{value} кг', 'String'),
}

# Substitutions applied in order. Written out rather than pattern-matched:
# every one of them changes surrounding structure, and a regex that could do
# them all would also match things it should not.
EDITS = [
    ("final displayName = user?.displayName ?? 'Guest';",
     'final displayName = user?.displayName ?? l10n.profileGuest;'),
    ("""    final subtitle = onboarded
        ? 'Profile complete'
        : (user == null ? 'Sign in to sync progress' : 'Finish onboarding to unlock plans');""",
     """    final subtitle = onboarded
        ? l10n.profileComplete
        : (user == null
            ? l10n.profileSignInToSync
            : l10n.profileFinishOnboarding);"""),
    ("""                  title:
                      onboarded ? 'Health questionnaire' : 'Complete questionnaire',""",
     """                  title: onboarded
                      ? l10n.profileHealthQuestionnaire
                      : l10n.profileCompleteQuestionnaire,"""),
    ("""  String _subscriptionSubtitle(Subscription? sub, SubscriptionTier tier) {
    if (sub == null || sub.status == SubscriptionStatus.none) {
      return 'Free · start a 14-day trial';
    }
    final tierLabel = switch (tier) {
      SubscriptionTier.free => 'Free',
      SubscriptionTier.standard => 'Standard',
      SubscriptionTier.celebrityTrainer => 'Celebrity trainer',
    };
    final statusLabel = switch (sub.status) {
      SubscriptionStatus.trial => 'Trial',
      SubscriptionStatus.active => 'Active',
      SubscriptionStatus.cancelled => 'Cancelling',
      SubscriptionStatus.expired => 'Expired',
      SubscriptionStatus.none => 'Free',
    };
    return '$tierLabel · $statusLabel';
  }""",
     """  String _subscriptionSubtitle(
      AppLocalizations l10n, Subscription? sub, SubscriptionTier tier) {
    if (sub == null || sub.status == SubscriptionStatus.none) {
      return l10n.profileFreeStartTrial;
    }
    final tierLabel = switch (tier) {
      SubscriptionTier.free => l10n.profileTierFree,
      SubscriptionTier.standard => l10n.profileTierStandard,
      SubscriptionTier.celebrityTrainer => l10n.profileTierCelebrity,
    };
    final statusLabel = switch (sub.status) {
      SubscriptionStatus.trial => l10n.profileSubTrial,
      SubscriptionStatus.active => l10n.profileSubActive,
      SubscriptionStatus.cancelled => l10n.profileSubCancelling,
      SubscriptionStatus.expired => l10n.profileSubExpired,
      SubscriptionStatus.none => l10n.profileSubNone,
    };
    return '$tierLabel · $statusLabel';
  }"""),
    ('_subscriptionSubtitle(sub, tier)', '_subscriptionSubtitle(l10n, sub, tier)'),
    ("""  String _activityLabel() {
    final a = profile.personal.activityLevel;
    if (a == null) return '—';
    return a.name.replaceAllMapped(
        RegExp(r'([A-Z])'), (m) => ' ${m.group(0)!.toLowerCase()}');
  }""",
     """  /// The activity level, looked up rather than derived.
  ///
  /// This used to build the label out of the enum's own name by inserting a
  /// space before every capital, which produced "moderately active" for free
  /// and produced it in English only -- and tied the interface to an
  /// identifier, so renaming the enum would have renamed what the user reads.
  String _activityLabel(AppLocalizations l10n) => switch (
          profile.personal.activityLevel) {
        null => '—',
        ActivityLevel.sedentary => l10n.onbActivitySedentary,
        ActivityLevel.moderatelyActive => l10n.onbActivityModerate,
        ActivityLevel.active => l10n.onbActivityActive,
        ActivityLevel.veryActive => l10n.onbActivityVery,
      };"""),
    ("""    final goalsList = <String>[
      if (profile.goals.weightLoss) 'Weight loss',
      if (profile.goals.muscleGain) 'Muscle gain',
      if (profile.goals.endurance) 'Endurance',
      if (profile.goals.strength) 'Strength',
      if (profile.goals.flexibility) 'Flexibility',
      if (profile.goals.generalFitness) 'General fitness',
    ];""",
     """    // The same six keys the onboarding chips use. A second translation of
    // "Muscle gain" would drift from the first the moment either is edited.
    final goalsList = <String>[
      if (profile.goals.weightLoss) l10n.onbGoalWeightLoss,
      if (profile.goals.muscleGain) l10n.onbGoalMuscleGain,
      if (profile.goals.endurance) l10n.onbGoalEndurance,
      if (profile.goals.strength) l10n.onbGoalStrength,
      if (profile.goals.flexibility) l10n.onbGoalFlexibility,
      if (profile.goals.generalFitness) l10n.onbGoalGeneral,
    ];"""),
    ("""          _row(context, 'Age', p.age?.toString() ?? '—'),
          _row(context, 'Height',
              p.heightCm != null ? '${p.heightCm} cm' : '—'),
          _row(context, 'Weight',
              p.weightCurrentKg != null ? '${p.weightCurrentKg} kg' : '—'),
          _row(context, 'Activity', _activityLabel()),
          _row(context, 'Goals',
              goalsList.isEmpty ? '—' : goalsList.join(', ')),""",
     """          _row(context, l10n.profileRowAge, p.age?.toString() ?? '—'),
          _row(
              context,
              l10n.profileRowHeight,
              p.heightCm != null
                  ? l10n.commonCentimetres(p.heightCm!)
                  : '—'),
          _row(
              context,
              l10n.profileRowWeight,
              p.weightCurrentKg != null
                  ? l10n.commonKilograms('${p.weightCurrentKg}')
                  : '—'),
          _row(context, l10n.profileRowActivity, _activityLabel(l10n)),
          _row(context, l10n.profileRowGoals,
              goalsList.isEmpty ? '—' : goalsList.join(', ')),"""),
]


def main() -> None:
    en = json.loads(ARB_EN.read_text('utf-8'))
    ru = json.loads(ARB_RU.read_text('utf-8'))
    for key, (e, r) in NEW.items():
        en[key], ru[key] = e, r
    for key, (e, r, t) in MEASURE.items():
        en[key], ru[key] = e, r
        en[f'@{key}'] = {'placeholders': {'value': {'type': t}}}
    ARB_EN.write_text(json.dumps(en, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    ARB_RU.write_text(json.dumps(ru, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(f'arb keys added: {len(NEW) + len(MEASURE)}')

    src = PAGE.read_text('utf-8')
    for old, new in EDITS:
        if old not in src:
            raise SystemExit(f'edit did not match:\n{old[:90]}')
        src = src.replace(old, new)
    # Both build() methods need the local.
    src = re.sub(r'(Widget build\(BuildContext context(?:, WidgetRef ref)?\) \{\n)',
                 r'\1    final l10n = AppLocalizations.of(context);\n', src)
    PAGE.write_text(src, 'utf-8')
    print('profile_page.dart rewritten')


if __name__ == '__main__':
    main()
