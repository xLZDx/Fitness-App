import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/health/widgets/health_sync_card.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../nutrition_plan/data/energy_math.dart';
import '../../nutrition_plan/data/missing_inputs.dart';
import '../../nutrition_plan/data/plan_calculator.dart';
import '../../profile/data/profile_models.dart';
import '../../safety/data/health_flags.dart';
import '../state/questionnaire_notifier.dart';
import 'inputs.dart';
import 'measure_ruler.dart';

/// The nutrition inputs shared by the onboarding step (`step_nutrition.dart`)
/// and the "complete your nutrition profile" flow (design s16.2-16.3).
///
/// Every widget reads and writes `questionnaireDraftProvider`, so the step and
/// the flow cannot disagree about where an answer lives. None of them persists
/// anything: the caller decides when to `saveDraft`.
///
/// The two safety questions come first in both places (D-75). A pace, a default
/// goal or any target text is only ever rendered when [nutritionSafetyClear] is
/// true; otherwise the caller shows [NutritionLockedNotice] and no numbers.

/// True only when BOTH safety questions were answered "none". Unanswered is not
/// clear, and `reported` is not clear: the same doctrine as the eligibility
/// gate, so a screen never shows target text the gate would refuse.
bool nutritionSafetyClear(HealthFlags flags) =>
    flags.professionalGuidance == ProfessionalGuidanceNeed.none &&
    flags.nutritionGuidance == NutritionGuidanceNeed.none;

/// Midpoints of the five typical-daily-steps buckets (design s16.2).
const List<int> kStepsBucketMidpoints = [2500, 4000, 6500, 9500, 12500];

/// Index into [kStepsBucketMidpoints] whose bucket contains [steps]
/// (<3k, 3-5k, 5-8k, 8-11k, 11k+).
int stepsBucketIndex(int steps) {
  if (steps < 3000) return 0;
  if (steps < 5000) return 1;
  if (steps < 8000) return 2;
  if (steps < 11000) return 3;
  return 4;
}

/// Display label of one allergen of the closed EU-14 list.
String foodAllergenLabel(AppLocalizations l10n, FoodAllergen a) => switch (a) {
      FoodAllergen.gluten => l10n.onbNutritionAllergenGluten,
      FoodAllergen.crustaceans => l10n.onbNutritionAllergenCrustaceans,
      FoodAllergen.eggs => l10n.onbNutritionAllergenEggs,
      FoodAllergen.fish => l10n.onbNutritionAllergenFish,
      FoodAllergen.peanuts => l10n.onbNutritionAllergenPeanuts,
      FoodAllergen.soy => l10n.onbNutritionAllergenSoy,
      FoodAllergen.milk => l10n.onbNutritionAllergenMilk,
      FoodAllergen.treeNuts => l10n.onbNutritionAllergenTreeNuts,
      FoodAllergen.celery => l10n.onbNutritionAllergenCelery,
      FoodAllergen.mustard => l10n.onbNutritionAllergenMustard,
      FoodAllergen.sesame => l10n.onbNutritionAllergenSesame,
      FoodAllergen.sulphites => l10n.onbNutritionAllergenSulphites,
      FoodAllergen.lupin => l10n.onbNutritionAllergenLupin,
      FoodAllergen.molluscs => l10n.onbNutritionAllergenMolluscs,
    };

/// F014. The pregnancy / breastfeeding question, a plain yes/no, because it is
/// the only question here whose answer does not describe a limitation the user
/// lives with -- it describes a limitation of THIS APP. Offering "unsure" would
/// be asking someone to be uncertain about something they are not uncertain
/// about, and offering more granularity would collect a medical detail nothing
/// acts on. See `ProfessionalGuidanceNeed`.
///
/// Extracted from `step_health_flags.dart` so the profile flow asks the exact
/// same question with the exact same wording and key.
class ProfessionalGuidanceQuestion extends ConsumerWidget {
  const ProfessionalGuidanceQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final flags = ref.watch(questionnaireDraftProvider).health.flags;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.healthStepProfessionalGuidance),
        SingleChoiceChips<ProfessionalGuidanceNeed>(
          key: const Key('onb.flags.guidance'),
          options: ProfessionalGuidanceNeed.values,
          labelOf: (v) => switch (v) {
            ProfessionalGuidanceNeed.none => l10n.guidanceNeedNone,
            ProfessionalGuidanceNeed.reported => l10n.guidanceNeedReported,
          },
          value: flags.professionalGuidance,
          onChanged: (v) => notifier.updateHealth(
            (h) => h.copyWith(
              flags: h.flags.copyWith(professionalGuidance: v),
            ),
          ),
        ),
      ],
    );
  }
}

/// The nutrition safety question (D-75, design s16.2). The wording is product
/// content and deliberately names no diagnosis: the stored value is only
/// `none` / `reported`, and there is no "prefer not to say" because that would
/// be indistinguishable from unanswered, which already locks the coach.
class NutritionGuidanceQuestion extends ConsumerWidget {
  const NutritionGuidanceQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final flags = ref.watch(questionnaireDraftProvider).health.flags;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final body = HudType.body(t, size: 13).overPhoto(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Semantics(
            header: true,
            child: Text(
              l10n.onbNutritionGuidanceTitle,
              style: HudType.body(t, size: 15)
                  .copyWith(fontWeight: FontWeight.w700)
                  .overPhoto(t),
            ),
          ),
        ),
        Text(l10n.onbNutritionGuidancePrompt, style: body),
        const SizedBox(height: 8),
        _Bullet(text: l10n.onbNutritionGuidanceOptionSupervised),
        _Bullet(text: l10n.onbNutritionGuidanceOptionRelationship),
        const SizedBox(height: 12),
        SingleChoiceChips<NutritionGuidanceNeed>(
          key: const Key('onb.flags.nutritionGuidance'),
          options: NutritionGuidanceNeed.values,
          labelOf: (v) => switch (v) {
            NutritionGuidanceNeed.none => l10n.onbNutritionGuidanceNone,
            NutritionGuidanceNeed.reported =>
              l10n.onbNutritionGuidanceReported,
          },
          value: flags.nutritionGuidance,
          onChanged: (v) => notifier.updateHealth(
            (h) => h.copyWith(
              flags: h.flags.copyWith(nutritionGuidance: v),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(l10n.onbNutritionGuidanceWhy,
            key: const Key('onb.nutritionGuidance.why'),
            style: HudType.body(t, size: 12).overPhoto(t)),
        const SizedBox(height: 6),
        Text(l10n.onbNutritionGuidanceConsequence,
            key: const Key('onb.nutritionGuidance.consequence'),
            style: HudType.body(t, size: 12).overPhoto(t)),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('•  ', style: HudType.body(t, size: 13).overPhoto(t)),
          ),
          Expanded(
            child: Text(text, style: HudType.body(t, size: 13).overPhoto(t)),
          ),
        ],
      ),
    );
  }
}

/// Neutral lock-out copy shown instead of every goal, pace and target element
/// while either safety answer is `reported` or missing. It names no reason and
/// shows no number (D-75, design s14).
class NutritionLockedNotice extends StatelessWidget {
  const NutritionLockedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: HudPanel(
        child: Semantics(
          liveRegion: true,
          child: Text(
            l10n.onbNutritionLockedNotice,
            key: const Key('onb.nutrition.locked'),
            style: HudType.body(t, size: 13).overPhoto(t),
          ),
        ),
      ),
    );
  }
}

/// Sex at birth, for the energy formula only. Shows the value derived from
/// `gender` as selected when nothing was chosen, without writing it: reading
/// falls back the same way (`resolveSexBasis`).
class NutritionSexAtBirthField extends ConsumerWidget {
  const NutritionSexAtBirthField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final draft = ref.watch(questionnaireDraftProvider);
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final derived = switch (draft.personal.gender) {
      Gender.male => SexAtBirth.male,
      Gender.female => SexAtBirth.female,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionSexAtBirth),
        SingleChoiceChips<SexAtBirth>(
          key: const Key('onb.nutrition.sex'),
          options: SexAtBirth.values,
          labelOf: (s) => switch (s) {
            SexAtBirth.female => l10n.onbNutritionSexFemale,
            SexAtBirth.male => l10n.onbNutritionSexMale,
            SexAtBirth.unspecified => l10n.onbNutritionSexNeutral,
          },
          value: draft.nutrition.sexAtBirth ?? derived,
          onChanged: (s) =>
              notifier.updateNutrition((n) => n.copyWith(sexAtBirth: s)),
        ),
        const SizedBox(height: 6),
        Text(l10n.onbNutritionSexHint,
            style: HudType.body(t, size: 12).overPhoto(t)),
      ],
    );
  }
}

/// The goal direction. A default is shown as selected only when the
/// questionnaire goals let one be derived (`weightLoss` -> lose, `muscleGain`
/// -> gain), and only the caller's safety check allows this widget to render at
/// all (D-75).
class NutritionGoalField extends ConsumerWidget {
  const NutritionGoalField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(questionnaireDraftProvider);
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionGoal),
        SingleChoiceChips<GoalDirection>(
          key: const Key('onb.nutrition.goal'),
          options: GoalDirection.values,
          labelOf: (g) => switch (g) {
            GoalDirection.lose => l10n.onbNutritionGoalLose,
            GoalDirection.maintain => l10n.onbNutritionGoalMaintain,
            GoalDirection.gain => l10n.onbNutritionGoalGain,
          },
          value: hasGoalSignal(draft) ? deriveGoalDirection(draft) : null,
          onChanged: (g) =>
              notifier.updateNutrition((n) => n.copyWith(goalDirection: g)),
        ),
      ],
    );
  }
}

/// Read-only target-weight line, with a link back to the personal screen, and
/// the realistic-pace message from the same calculator the plan uses. The
/// target WEIGHT is never asked twice (`step_personal` owns it).
class NutritionPaceMessage extends ConsumerWidget {
  const NutritionPaceMessage({super.key, this.onEditTarget});

  /// Jumps to the screen that owns the target weight; null hides the link.
  final VoidCallback? onEditTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final draft = ref.watch(questionnaireDraftProvider);
    final p = draft.personal;
    final locale = Localizations.localeOf(context).toString();

    String? message;
    final weight = p.weightCurrentKg;
    final height = p.heightCm;
    final target = p.weightTargetKg;
    if (weight != null && height != null && target != null) {
      final pace = realisticPace(
        weightKg: weight,
        heightCm: height.toDouble(),
        targetWeightKg: target,
        goal: hasGoalSignal(draft) ? deriveGoalDirection(draft) : null,
      );
      if (pace.targetBelowHealthyRange) {
        message = l10n.onbNutritionPaceBelowRange;
      } else if (pace.underweightNoDeficit) {
        message = l10n.onbNutritionPaceUnderweight;
      } else if (pace.kgPerWeek != null && pace.weeks != null) {
        message = l10n.onbNutritionPaceMessage(
          NumberFormat('0.0#', locale).format(pace.kgPerWeek),
          pace.weeks!,
        );
      }
    }

    final targetLine = target == null
        ? l10n.onbNutritionTargetMissing
        : l10n.onbNutritionTargetLine(
            NumberFormat('0.#', locale).format(target));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(targetLine,
                  key: const Key('onb.nutrition.targetLine'),
                  style: HudType.body(t, size: 13).overPhoto(t)),
            ),
            if (onEditTarget != null)
              TextButton(
                key: const Key('onb.nutrition.editTarget'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onEditTarget,
                child: Text(l10n.onbNutritionTargetChange),
              ),
          ],
        ),
        if (message != null)
          Semantics(
            liveRegion: true,
            child: Text(message,
                key: const Key('onb.nutrition.pace'),
                style: HudType.body(t, size: 13).overPhoto(t)),
          ),
      ],
    );
  }
}

/// Optional body-fat target. Clamped to the safe band for the resolved sex
/// basis (10-40 % male, 16-40 % otherwise) at the moment it is written, so the
/// draft can never hold a value the plan would refuse.
class NutritionTargetBodyFatField extends ConsumerWidget {
  const NutritionTargetBodyFatField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(questionnaireDraftProvider);
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final basis = resolveSexBasis(draft) ?? SexBasis.unspecified;
    final min = basis == SexBasis.male ? 10.0 : 16.0;
    final current = draft.nutrition.targetBodyFatPct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionTargetBodyFat),
        MeasureRuler(
          key: const Key('onb.nutrition.bodyFatRuler'),
          value: current == null ? null : current.clamp(min, 40.0).toDouble(),
          min: min,
          max: 40,
          step: 0.5,
          majorEvery: 10,
          unit: '%',
          onChanged: (v) => notifier.updateNutrition(
            (n) => n.copyWith(targetBodyFatPct: clampTargetBodyFatPct(v, basis)),
          ),
        ),
        if (current != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: HudChip(
                key: const Key('onb.nutrition.bodyFatClear'),
                label: l10n.onbNutritionTargetBodyFatClear,
                selected: false,
                onTap: () => notifier
                    .updateNutrition((n) => n.copyWith(clearTargetBodyFat: true)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Typical daily steps bucket, with the existing Health Connect card as an
/// optional alternative. Picking a bucket records `manual`; the connection
/// itself stays with the existing health seam.
class NutritionStepsField extends ConsumerWidget {
  const NutritionStepsField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final nutrition = ref.watch(questionnaireDraftProvider).nutrition;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final labels = [
      l10n.onbNutritionSteps0,
      l10n.onbNutritionSteps1,
      l10n.onbNutritionSteps2,
      l10n.onbNutritionSteps3,
      l10n.onbNutritionSteps4,
    ];
    final steps = nutrition.typicalDailySteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionSteps),
        const HealthSyncCard(),
        const SizedBox(height: 8),
        Text(l10n.onbNutritionStepsHint,
            style: HudType.body(t, size: 12).overPhoto(t)),
        const SizedBox(height: 10),
        SingleChoiceChips<int>(
          key: const Key('onb.nutrition.steps'),
          options: const [0, 1, 2, 3, 4],
          labelOf: (i) => labels[i],
          value: steps == null ? null : stepsBucketIndex(steps),
          onChanged: (i) => notifier.updateNutrition(
            (n) => n.copyWith(
              typicalDailySteps: kStepsBucketMidpoints[i],
              healthConnectChoice:
                  n.healthConnectChoice == HealthConnectChoice.connected
                      ? null
                      : HealthConnectChoice.manual,
            ),
          ),
        ),
      ],
    );
  }
}

/// Allergen chips (closed EU-14 list). Stored in `HealthFlags` through the same
/// `copyWith` path as every other health answer, so it stays device-only.
class NutritionAllergensField extends ConsumerWidget {
  const NutritionAllergensField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final flags = ref.watch(questionnaireDraftProvider).health.flags;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionAllergens),
        MultiChoiceChips<FoodAllergen>(
          key: const Key('onb.nutrition.allergens'),
          options: FoodAllergen.values,
          labelOf: (a) => foodAllergenLabel(l10n, a),
          values: flags.foodAllergens,
          onChanged: (next) => notifier.updateHealth(
            (h) => h.copyWith(flags: h.flags.copyWith(foodAllergens: next)),
          ),
        ),
        const SizedBox(height: 6),
        Text(l10n.onbNutritionDeviceOnly,
            style: HudType.body(t, size: 12).overPhoto(t)),
      ],
    );
  }
}

/// Foods the user does not eat: at most [NutritionPrefs.maxExcludedFoods]
/// entries of at most [NutritionPrefs.maxExcludedFoodChars] characters.
/// DEVICE-ONLY (free text can name an intolerance or a condition).
class NutritionExcludedFoodsField extends ConsumerStatefulWidget {
  const NutritionExcludedFoodsField({super.key});

  @override
  ConsumerState<NutritionExcludedFoodsField> createState() =>
      _NutritionExcludedFoodsFieldState();
}

class _NutritionExcludedFoodsFieldState
    extends ConsumerState<NutritionExcludedFoodsField> {
  String _pending = '';

  void _onChanged(String v) {
    // Over-long input is cut rather than rejected on submit, so the text the
    // user sees is always the text that would be saved.
    final cut = v.length > NutritionPrefs.maxExcludedFoodChars
        ? v.substring(0, NutritionPrefs.maxExcludedFoodChars)
        : v;
    setState(() => _pending = cut);
  }

  void _add() {
    final foods = ref.read(questionnaireDraftProvider).nutrition.excludedFoods;
    final text = _pending.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return;
    final dup = foods.any((f) => f.toLowerCase() == text.toLowerCase());
    if (!dup && foods.length < NutritionPrefs.maxExcludedFoods) {
      ref
          .read(questionnaireDraftProvider.notifier)
          .updateNutrition((n) => n.copyWith(excludedFoods: [...foods, text]));
    }
    setState(() => _pending = '');
  }

  void _remove(String food) => ref
      .read(questionnaireDraftProvider.notifier)
      .updateNutrition((n) => n.copyWith(
            excludedFoods: [
              for (final f in n.excludedFoods)
                if (f != food) f
            ],
          ));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final foods = ref.watch(questionnaireDraftProvider).nutrition.excludedFoods;
    final full = foods.length >= NutritionPrefs.maxExcludedFoods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionExcluded),
        if (foods.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              key: const Key('onb.nutrition.excludedList'),
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final food in foods)
                  Semantics(
                    button: true,
                    label: l10n.onbNutritionExcludedRemove(food),
                    excludeSemantics: true,
                    onTap: () => _remove(food),
                    child: HudChip(
                      label: '$food  ✕',
                      selected: true,
                      onTap: () => _remove(food),
                    ),
                  ),
              ],
            ),
          ),
        if (full)
          Text(
            l10n.onbNutritionExcludedLimit(NutritionPrefs.maxExcludedFoods),
            key: const Key('onb.nutrition.excludedLimit'),
            style: HudType.body(t, size: 12).overPhoto(t),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: GlassTextField(
                  key: const Key('onb.nutrition.excludedInput'),
                  value: _pending,
                  hint: l10n.onbNutritionExcludedHint,
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Center(
                  child: HudChip(
                    key: const Key('onb.nutrition.excludedAdd'),
                    label: l10n.onbNutritionExcludedAdd,
                    selected: _pending.trim().isNotEmpty,
                    onTap: _add,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        Text(l10n.onbNutritionDeviceOnly,
            style: HudType.body(t, size: 12).overPhoto(t)),
      ],
    );
  }
}

/// Meals per day, 2-6. Nothing is pre-selected: an unanswered question is not a
/// default answer, and the plan assumes 3 when this is left blank.
class NutritionMealsField extends ConsumerWidget {
  const NutritionMealsField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final nutrition = ref.watch(questionnaireDraftProvider).nutrition;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionMeals),
        SingleChoiceChips<int>(
          key: const Key('onb.nutrition.meals'),
          options: [
            for (var i = NutritionPrefs.minMealsPerDay;
                i <= NutritionPrefs.maxMealsPerDay;
                i++)
              i
          ],
          labelOf: (i) => '$i',
          value: nutrition.mealsPerDay,
          onChanged: (i) =>
              notifier.updateNutrition((n) => n.copyWith(mealsPerDay: i)),
        ),
        const SizedBox(height: 6),
        Text(l10n.onbNutritionMealsDefault,
            style: HudType.body(t, size: 12).overPhoto(t)),
      ],
    );
  }
}

/// Who owns the plan numbers (design s18). Coached is the default when blank;
/// the safety clamps bind every mode.
class NutritionOwnershipField extends ConsumerWidget {
  const NutritionOwnershipField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final nutrition = ref.watch(questionnaireDraftProvider).nutrition;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final entries = <(PlanOwnership, String, String)>[
      (
        PlanOwnership.coached,
        l10n.onbNutritionOwnershipCoached,
        l10n.onbNutritionOwnershipCoachedHint
      ),
      (
        PlanOwnership.shared,
        l10n.onbNutritionOwnershipShared,
        l10n.onbNutritionOwnershipSharedHint
      ),
      (
        PlanOwnership.manual,
        l10n.onbNutritionOwnershipManual,
        l10n.onbNutritionOwnershipManualHint
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.onbNutritionOwnership),
        for (final e in entries) ...[
          ChoiceCard(
            key: Key('onb.nutrition.ownership.${e.$1.name}'),
            title: e.$2,
            subtitle: e.$3,
            selected: nutrition.planOwnership == e.$1,
            onTap: () => notifier
                .updateNutrition((n) => n.copyWith(planOwnership: e.$1)),
          ),
          const SizedBox(height: 8),
        ],
        Text(l10n.onbNutritionOwnershipDefault,
            style: HudType.body(t, size: 12).overPhoto(t)),
      ],
    );
  }
}
