import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../profile/state/profile_providers.dart';
import 'state/questionnaire_notifier.dart';
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
    final theme = Theme.of(context);
    final submitState = ref.watch(profileSubmitProvider);
    final isSubmitting = submitState.isLoading;
    final isLast = _index == _stepCount - 1;

    return FrostedScaffold(
      appBar: GlassAppBar(
        title: AppLocalizations.of(context)
            .onboardingStepOf(_index + 1, _stepCount, _titles(l10n)[_index]),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 88, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressBar(value: (_index + 1) / _stepCount),
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
              Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmitting ? null : _back,
                        child:
                            Text(AppLocalizations.of(context).onboardingBack),
                      ),
                    ),
                  if (_index > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: isSubmitting ? null : _next,
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(colors: [
                            AppPalette.auroraPink,
                            AppPalette.auroraViolet,
                          ]),
                          boxShadow: [
                            BoxShadow(
                              color: AppPalette.auroraViolet
                                  .withValues(alpha: 0.40),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                        AppSemanticColors.onGradientInk),
                                  ),
                                )
                              : Text(
                                  isLast
                                      ? AppLocalizations.of(context).commonDone
                                      : AppLocalizations.of(context).commonNext,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppSemanticColors.onGradientInk,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.30)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppPalette.auroraPink,
                    AppPalette.auroraViolet,
                    AppPalette.auroraBlue,
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
