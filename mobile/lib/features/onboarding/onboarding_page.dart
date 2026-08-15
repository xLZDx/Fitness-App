import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../auth/state/auth_providers.dart';
import '../profile/data/profile_models.dart';
import '../profile/state/profile_providers.dart';
import 'data/step_answered.dart';
import 'state/questionnaire_notifier.dart';
import 'widgets/ob_shell.dart';
import 'steps/step_equipment.dart';
import 'steps/step_goal_and_level.dart';
import 'steps/step_body.dart';
import 'steps/step_lifestyle.dart';
import 'steps/step_barriers.dart';
import 'steps/step_personal.dart';
import 'steps/step_preview.dart';
import 'steps/step_screening.dart';
import 'steps/step_schedule.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _ctrl = PageController();

  /// O2 turned three parallel lists — titles, widgets, answeredness — into one
  /// keyed on [OnboardingStep]. They used to be a switch over an int and a list
  /// in the same order, which is a shape that stays correct exactly until
  /// somebody reorders one of them.
  static String _titleFor(OnboardingStep step, AppLocalizations l10n) {
    switch (step) {
      case OnboardingStep.personal:
        return l10n.onbStepPersonal;
      case OnboardingStep.body:
        return l10n.onbStepBody;
      case OnboardingStep.goalAndLevel:
        return l10n.onbStepGoalAndLevel;
      case OnboardingStep.lifestyle:
        return l10n.onbStepLifestyle;
      case OnboardingStep.equipment:
        return l10n.onbStepEquipment;
      case OnboardingStep.schedule:
        return l10n.onbStepSchedule;
      case OnboardingStep.barriers:
        return l10n.onbStepBarriers;
      case OnboardingStep.screening:
        return l10n.safetyScreeningTitle;
      case OnboardingStep.preview:
        return l10n.onbStepPreview;
    }
  }

  static Widget _widgetFor(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.personal:
        return const StepPersonal();
      case OnboardingStep.body:
        return const StepBody();
      case OnboardingStep.goalAndLevel:
        return const StepGoalAndLevel();
      case OnboardingStep.lifestyle:
        return const StepLifestyle();
      case OnboardingStep.equipment:
        return const StepEquipment();
      case OnboardingStep.schedule:
        return const StepSchedule();
      case OnboardingStep.barriers:
        return const StepBarriers();
      case OnboardingStep.screening:
        return const StepScreening();
      case OnboardingStep.preview:
        return const StepPreview();
    }
  }

  int get _stepCount => kOnboardingOrder.length;

  int _index = 0;

  /// Resume happens exactly once, the moment the draft is known to be real.
  ///
  /// `questionnaireDraftProvider` builds from an empty profile and rehydrates a
  /// frame later, when `authUserProvider` resolves and the cached profile is
  /// read. Deciding in `initState` would therefore always decide against an
  /// empty draft and always land on screen one — the bug this gate removes.
  ///
  /// The latch is on **auth resolving**, not on the target being non-zero, and
  /// the difference is not academic. Latching on "target moved off zero" would
  /// leave this armed while the user sat on screen one — so the moment they
  /// answered the question in front of them, the page would decide they had
  /// finished it and jump them to screen two mid-typing. Auth resolves once and
  /// never again; the user is driving from that frame on.
  bool _resumed = false;

  void _maybeResume(UserProfile draft) {
    if (_resumed) return;
    if (!ref.watch(authUserProvider).hasValue) return;
    _resumed = true;
    final target = onboardingResumeIndex(draft);
    if (target == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      _ctrl.jumpToPage(target);
      setState(() => _index = target);
    });
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
    final draft = ref.watch(questionnaireDraftProvider);
    _maybeResume(draft);

    // The button reads "Skip" and goes quiet on a step nothing has been put
    // into, per the design (`App.tsx:1598`). It still advances either way --
    // every question here is optional and `_submit` sends whatever the draft
    // holds -- so this is a statement about what the user has done, not a gate.
    final answered =
        isOnboardingStepAnswered(kOnboardingOrder[_index], draft);

    return FrostedScaffold(
      // The counter moved into `ObProgressHeader`; leaving "Step N of M" here
      // as well would print it twice on every screen.
      appBar: GlassAppBar(title: _titleFor(kOnboardingOrder[_index], l10n)),
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
                    child: _widgetFor(kOnboardingOrder[i]),
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
