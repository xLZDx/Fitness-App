import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../profile/state/profile_providers.dart';
import 'data/step_answered.dart';
import 'state/questionnaire_notifier.dart';
import 'widgets/ob_shell.dart';
import 'steps/step_equipment.dart';
import 'steps/step_goals.dart';
import 'steps/step_health.dart';
import 'steps/step_level.dart';
import 'steps/step_lifestyle.dart';
import 'steps/step_motivation.dart';
import 'steps/step_personal.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _ctrl = PageController();

  /// The seven step names, in order. A function rather than a `static const`
  /// list: a translated string is a method call on the localizations object,
  /// and a const list cannot hold one.
  static List<String> _titles(AppLocalizations l10n) => [
        l10n.onbStepPersonal,
        l10n.onbStepHealth,
        l10n.onbStepGoals,
        l10n.onbStepLevel,
        l10n.onbStepLifestyle,
        l10n.onbStepEquipment,
        l10n.onbStepMotivation,
      ];

  static const _stepCount = 7;

  int _index = 0;

  Widget _stepFor(int i) {
    switch (i) {
      case 0:
        return const StepPersonal();
      case 1:
        return const StepHealth();
      case 2:
        return const StepGoals();
      case 3:
        return const StepLevel();
      case 4:
        return const StepLifestyle();
      case 5:
        return const StepEquipment();
      default:
        return const StepMotivation();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    // Persist whatever the user has so far before advancing or finishing.
    await ref.read(questionnaireDraftProvider.notifier).saveDraft();
    if (_index < _stepCount - 1) {
      await _ctrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _submit();
    }
  }

  Future<void> _back() async {
    await ref.read(questionnaireDraftProvider.notifier).saveDraft();
    if (_index == 0) return;
    await _ctrl.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _submit() async {
    final draft = ref.read(questionnaireDraftProvider);
    await ref.read(profileSubmitProvider.notifier).submit(draft);
    if (!mounted) return;
    final state = ref.read(profileSubmitProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .onboardingCouldNotSaveProfile(state.error ?? ''))),
      );
      return;
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final submitState = ref.watch(profileSubmitProvider);
    final isSubmitting = submitState.isLoading;
    final isLast = _index == _stepCount - 1;

    // The button reads "Skip" and goes quiet on a step nothing has been put
    // into, per the design (`App.tsx:1598`). It still advances either way --
    // every question here is optional and `_submit` sends whatever the draft
    // holds -- so this is a statement about what the user has done, not a gate.
    final answered =
        isOnboardingStepAnswered(_index, ref.watch(questionnaireDraftProvider));

    return FrostedScaffold(
      // The counter moved into `ObProgressHeader`; leaving "Step N of M" here
      // as well would print it twice on every screen.
      appBar: GlassAppBar(title: _titles(l10n)[_index]),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 88, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ObProgressHeader(
                step: _index + 1,
                total: _stepCount,
                onBack: (_index == 0 || isSubmitting) ? null : _back,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemCount: _stepCount,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, i) => SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: _stepFor(i),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PrimaryCta(
                label: !answered
                    ? l10n.onboardingSkipStep
                    : (isLast ? l10n.commonDone : l10n.commonNext),
                answered: answered,
                busy: isSubmitting,
                onTap: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single bottom control.
///
/// One button, not two. The design ships both patterns and they contradict
/// each other: most steps put a ghost "Пропустить этот шаг" *under* an
/// always-enabled primary, where both call the same handler
/// (`App.tsx:1565`), while step 5 uses one button whose label and variant
/// follow whether anything was answered (`App.tsx:1598`). The second is the
/// one implemented here — two controls that do the identical thing is a fork
/// in the prototype, not an affordance.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.answered,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool answered;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colors;
    // Спиннер подменяет текст, поэтому под ним у элемента не остаётся никакой
    // метки — скринридер молчал бы ровно тогда, когда человек ждёт ответа. В
    // обычном состоянии метку даёт сам Text, и второй label превратил бы
    // объявление в «Далее Далее».
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? label : null,
      child: GestureDetector(
        key: const Key('onboarding.cta'),
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // R9: brand CTA, moved off the pre-R9 pink/violet pair.
            gradient: answered
                ? const LinearGradient(colors: [
                    AppPalette.auroraLime,
                    AppPalette.auroraLimeDeep,
                  ])
                : null,
            color: answered ? null : colors.surfaceInteractive,
            boxShadow: answered
                ? [
                    BoxShadow(
                      color: AppPalette.auroraLime.withValues(alpha: 0.40),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(AppSemanticColors.onGradientInk),
                    ),
                  )
                : Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: answered
                          ? AppSemanticColors.onGradientInk
                          : colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
