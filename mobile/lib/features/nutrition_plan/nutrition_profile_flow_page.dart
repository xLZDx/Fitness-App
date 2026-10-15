import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/background/hud_sky.dart';
import '../../core/theme/hud_tokens.dart';
import '../../core/theme/hud_typography.dart';
import '../../shared/widgets/hud/hud_surface.dart';
import '../auth/state/auth_providers.dart';
import '../onboarding/state/questionnaire_notifier.dart';
import '../onboarding/widgets/inputs.dart';
import '../onboarding/widgets/measure_ruler.dart';
import '../onboarding/widgets/nutrition_inputs.dart';
import '../profile/data/profile_models.dart';
import 'data/missing_inputs.dart';

/// The three sheets of the "complete your nutrition profile" flow
/// (design s16.3). `safety` asks the two safety questions, `body` the missing
/// body and goal inputs, `food` food and activity preferences.
enum NutritionProfileSheet { safety, body, food }

/// Which sheets a profile needs, given what it still lacks. Pure so it can be
/// asserted without pumping the page.
///
/// `safety` appears only while at least one safety question is unanswered, and
/// `body` only while a body or goal input is missing; `food` is always last
/// because every field on it is optional and the flow ends there. The list is
/// computed ONCE per visit, from the profile as it was on entry, so a field the
/// user has just filled does not vanish from under them mid-sheet.
List<NutritionProfileSheet> nutritionProfileSheets(
    List<NutritionInput> missing) {
  const safety = {
    NutritionInput.nutritionGuidance,
    NutritionInput.professionalGuidance,
  };
  const body = {
    NutritionInput.birthYear,
    NutritionInput.height,
    NutritionInput.weight,
    NutritionInput.sexBasis,
    NutritionInput.activity,
    NutritionInput.goal,
  };
  return [
    if (missing.any(safety.contains)) NutritionProfileSheet.safety,
    if (missing.any(body.contains)) NutritionProfileSheet.body,
    NutritionProfileSheet.food,
  ];
}

/// Reached from the Plan screen and Home card (`/nutrition/profile`), never
/// forced: a user who finished onboarding is not routed back to `/onboarding`,
/// and nothing is written until they act. It edits the same
/// `questionnaireDraftProvider` the onboarding step does and saves through the
/// existing profile repository, which keeps the profile's own `completedAt`
/// (the draft is a copy of the cached profile).
class NutritionProfileFlowPage extends ConsumerStatefulWidget {
  const NutritionProfileFlowPage({super.key});

  @override
  ConsumerState<NutritionProfileFlowPage> createState() =>
      _NutritionProfileFlowPageState();
}

class _NutritionProfileFlowPageState
    extends ConsumerState<NutritionProfileFlowPage> {
  bool _refreshed = false;
  bool _saving = false;
  int _index = 0;

  /// Fixed on the first build with a resolved profile; see
  /// [nutritionProfileSheets].
  List<NutritionInput>? _missing;
  List<NutritionProfileSheet>? _sheets;

  @override
  void initState() {
    super.initState();
    // The draft notifier may have been built earlier (onboarding, edit
    // answers) and hold stale answers; rebuild it from the cached profile once
    // the first frame is done, then let `build` fix the sheet list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(questionnaireDraftProvider);
      setState(() => _refreshed = true);
    });
  }

  Future<bool> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(questionnaireDraftProvider.notifier).saveDraft();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context).onboardingCouldNotSaveProfile(e))),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _next() async {
    final sheets = _sheets!;
    final isLast = _index == sheets.length - 1;
    if (isLast) {
      ref.read(questionnaireDraftProvider.notifier).markNutritionCompleted();
    }
    if (!await _save() || !mounted) return;
    if (isLast) {
      _leave();
    } else {
      setState(() => _index++);
    }
  }

  Future<void> _back() async {
    if (_index == 0 || _saving) return;
    await _save();
    if (mounted) setState(() => _index--);
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final ready = _refreshed && ref.watch(authUserProvider).hasValue;
    final draft = ref.watch(questionnaireDraftProvider);
    if (ready && _sheets == null) {
      _missing = missingNutritionInputs(draft);
      _sheets = nutritionProfileSheets(_missing!);
    }
    final sheets = _sheets;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: HudSkyBackground(
        selection: HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: sheets == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: _index == 0
                                ? null
                                : IconButton(
                                    key: const Key('nutProfile.back'),
                                    tooltip: l10n.onboardingBack,
                                    onPressed: _saving ? null : _back,
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                          ),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                l10n.nutProfileTitle,
                                textAlign: TextAlign.center,
                                style: HudType.label(t, size: 11).overPhoto(t),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: IconButton(
                              key: const Key('nutProfile.close'),
                              tooltip: l10n.commonClose,
                              onPressed: _saving ? null : _leave,
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.nutProfileStepOf(_index + 1, sheets.length),
                          key: const Key('nutProfile.progress'),
                          textAlign: TextAlign.center,
                          style: HudType.body(t, size: 12).overPhoto(t),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey('nutProfile.sheet.${sheets[_index].name}'),
                          physics: const BouncingScrollPhysics(),
                          child: _SheetBody(
                            sheet: sheets[_index],
                            missing: _missing!,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      HudButton(
                        key: const Key('nutProfile.cta'),
                        label: _index == sheets.length - 1
                            ? l10n.commonSave
                            : l10n.commonNext,
                        tone: HudButtonTone.accent,
                        centered: true,
                        enabled: !_saving,
                        onPressed: _saving ? null : _next,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody({required this.sheet, required this.missing});

  final NutritionProfileSheet sheet;
  final List<NutritionInput> missing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final draft = ref.watch(questionnaireDraftProvider);
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final personal = draft.personal;
    // Live, so answering "reported" on the first sheet locks the next two at
    // once instead of after a reload (D-75).
    final clear = nutritionSafetyClear(draft.health.flags);

    switch (sheet) {
      case NutritionProfileSheet.safety:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepTitle(
              title: l10n.nutProfileSafetyTitle,
              subtitle: l10n.nutProfileSafetyIntro,
            ),
            if (missing.contains(NutritionInput.professionalGuidance))
              const ProfessionalGuidanceQuestion(),
            if (missing.contains(NutritionInput.nutritionGuidance))
              const NutritionGuidanceQuestion(),
          ],
        );
      case NutritionProfileSheet.body:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepTitle(title: l10n.nutProfileBodyTitle),
            if (!clear)
              const NutritionLockedNotice()
            else ...[
              if (missing.contains(NutritionInput.birthYear)) ...[
                FieldLabel(l10n.onbBirthYear),
                MeasureRuler(
                  key: const Key('nutProfile.birthYearRuler'),
                  value: personal.birthYear?.toDouble(),
                  min: 1930,
                  max: (DateTime.now().year - 12).toDouble(),
                  majorEvery: 10,
                  onChanged: (v) => notifier
                      .updatePersonal((p) => p.copyWith(birthYear: v.round())),
                ),
              ],
              if (missing.contains(NutritionInput.height)) ...[
                FieldLabel(l10n.onbHeightCm),
                MeasureRuler(
                  key: const Key('nutProfile.heightRuler'),
                  value: personal.heightCm?.toDouble(),
                  min: 120,
                  max: 220,
                  unit: l10n.onbUnitCm,
                  onChanged: (v) => notifier
                      .updatePersonal((p) => p.copyWith(heightCm: v.round())),
                ),
              ],
              if (missing.contains(NutritionInput.weight)) ...[
                FieldLabel(l10n.onbWeightCurrent),
                MeasureRuler(
                  key: const Key('nutProfile.weightRuler'),
                  value: personal.weightCurrentKg,
                  min: 35,
                  max: 200,
                  step: 0.5,
                  majorEvery: 10,
                  unit: l10n.onbUnitKg,
                  onChanged: (v) => notifier
                      .updatePersonal((p) => p.copyWith(weightCurrentKg: v)),
                ),
              ],
              if (missing.contains(NutritionInput.sexBasis))
                const NutritionSexAtBirthField(),
              if (missing.contains(NutritionInput.activity)) ...[
                FieldLabel(l10n.onbActivityLevel),
                SingleChoiceChips<ActivityLevel>(
                  key: const Key('nutProfile.activity'),
                  options: const [
                    ActivityLevel.sedentary,
                    ActivityLevel.moderatelyActive,
                    ActivityLevel.active,
                    ActivityLevel.veryActive,
                  ],
                  labelOf: (a) => switch (a) {
                    ActivityLevel.sedentary => l10n.onbActivitySedentary,
                    ActivityLevel.moderatelyActive => l10n.onbActivityModerate,
                    ActivityLevel.active => l10n.onbActivityActive,
                    ActivityLevel.veryActive => l10n.onbActivityVery,
                  },
                  value: personal.activityLevel,
                  onChanged: (a) => notifier
                      .updatePersonal((p) => p.copyWith(activityLevel: a)),
                ),
              ],
              if (missing.contains(NutritionInput.goal))
                const NutritionGoalField(),
            ],
            const SizedBox(height: 16),
          ],
        );
      case NutritionProfileSheet.food:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepTitle(
              title: l10n.onbNutritionTitle,
              subtitle: l10n.onbNutritionSubtitle,
            ),
            if (!clear)
              const NutritionLockedNotice()
            else
              const NutritionStepsField(),
            const NutritionAllergensField(),
            const NutritionExcludedFoodsField(),
            const NutritionMealsField(),
            if (clear) const NutritionOwnershipField(),
            const SizedBox(height: 16),
          ],
        );
    }
  }
}
