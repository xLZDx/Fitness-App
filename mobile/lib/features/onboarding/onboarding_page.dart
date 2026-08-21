import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/background/hud_sky.dart';
import '../../core/theme/hud_tokens.dart';
import '../../core/theme/hud_typography.dart';
import '../../shared/widgets/hud/hud_surface.dart';
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
import 'steps/step_health_flags.dart';
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
      case OnboardingStep.healthFlags:
        return l10n.healthStepTitle;
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
      case OnboardingStep.healthFlags:
        return const StepHealthFlags();
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
    // Read before the `await` below, not after: `context` is only safe to
    // touch synchronously, and `Duration.zero` makes `PageController`'s own
    // `animateTo` jump straight to the next page instead of sliding -- reduce
    // motion skips the page-turn, not the step change itself.
    final Duration duration =
        context.hudMotionDuration(const Duration(milliseconds: 320));
    // Persist whatever the user has so far before advancing or finishing.
    await ref.read(questionnaireDraftProvider.notifier).saveDraft();
    if (_index < _stepCount - 1) {
      await _ctrl.nextPage(duration: duration, curve: Curves.easeOutCubic);
    } else {
      await _submit();
    }
  }

  Future<void> _back() async {
    final Duration duration =
        context.hudMotionDuration(const Duration(milliseconds: 280));
    await ref.read(questionnaireDraftProvider.notifier).saveDraft();
    if (_index == 0) return;
    await _ctrl.previousPage(duration: duration, curve: Curves.easeOutCubic);
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

    final HudTokens t = context.hud;

    // A full-screen route pushed above `MainShell` (never one of its five
    // tabs), so it mounts its own sky rather than relying on an ancestor —
    // the same reason Session and the form coach each do the same. The phase
    // is the real clock, exactly like `MainShell`'s: onboarding has no reason
    // to show a different time of day than the rest of the app a moment
    // later.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: HudSkyBackground(
        selection: HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The counter lives in `ObProgressHeader`; printing "Step N of
                // M" again here would say it twice on every screen.
                Text(
                  _titleFor(kOnboardingOrder[_index], l10n),
                  style: HudType.label(t, size: 11).overPhoto(t),
                ),
                const SizedBox(height: 10),
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
    final HudTokens t = context.hud;
    final Color ink = answered ? t.onAccent : t.textPrimary;
    // Спиннер подменяет текст, поэтому под ним у элемента не остаётся никакой
    // метки — скринридер молчал бы ровно тогда, когда человек ждёт ответа. В
    // обычном состоянии метку даёт сам Text, и второй label превратил бы
    // объявление в «Далее Далее».
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? label : null,
      child: HudKeyboardActivation(
        onActivate: busy ? null : onTap,
        child: GestureDetector(
          key: const Key('onboarding.cta'),
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: HudSurface(
              // The same accent recipe every other primary action in the app
              // uses (`HudButton`'s `accent` tone) rather than a bespoke
              // gradient — R9's brand CTA lives in one token set now, not a
              // literal lime/lime-deep pair repeated per screen.
              glass: t.button,
              overlay: answered ? t.accentChipGradient : null,
              border: answered ? t.accentChipBorder : null,
              topHighlight: answered ? t.accentChipTopHighlight : null,
              borderRadius: BorderRadius.circular(20),
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(ink),
                        ),
                      )
                    : Text(
                        label,
                        style: HudType.panelTitle(t)
                            .copyWith(fontSize: 16, color: ink),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
