/// The per-mode first-run questions S-2 (design 2.3, contract S-2; S03-09).
///
/// A separate full-screen route (`/mode-questions/:mode`), NOT a step of the
/// onboarding flow. It reuses the onboarding look: `ObProgressHeader`,
/// `StepTitle` and `ChoiceCard`. At most three questions, one per screen, each
/// skippable. The list of questions is fixed once, when the saved state is
/// known, so the counter "Question n of N" never changes while answers arrive.
///
/// Answers are written through the mode notifier ([ModeNotifier.answerQuestion],
/// [ModeNotifier.skipQuestion]); the TRAIN answer is mirrored into the existing
/// `TrainingContext` answer. A failed save shows an inline error with Try again;
/// Skip and Back stay enabled (F-26).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/background/hud_sky.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../../shared/widgets/shell_back_button.dart';
import '../../onboarding/widgets/inputs.dart' show ChoiceCard, StepTitle;
import '../../onboarding/widgets/ob_shell.dart' show ObProgressHeader;
import '../../progress_photos/scan/scan_access.dart'
    show ScanAccess, scanAccessProvider;
import '../../progress_photos/scan/ui/scan_gate_view.dart'
    show scanAccessMessage;
import '../../training_context/data/training_context.dart';
import '../../training_context/state/training_context_providers.dart';
import '../data/mode_models.dart';
import '../state/mode_providers.dart';
import '../widgets/mode_question_plan.dart';

/// Minimum time the "Saving" feedback stays visible (contract S-2).
const Duration kModeQuestionSavingMinimum = Duration(milliseconds: 300);

class ModeQuestionPage extends ConsumerStatefulWidget {
  const ModeQuestionPage({super.key, required this.mode});

  /// The mode whose questions are asked. The route guarantees an available mode.
  final AppMode mode;

  @override
  ConsumerState<ModeQuestionPage> createState() => _ModeQuestionPageState();
}

class _ModeQuestionPageState extends ConsumerState<ModeQuestionPage> {
  /// Fixed once the saved state is known (see the library comment).
  List<ModeQuestionId>? _plan;
  int _index = 0;
  String? _chosenId;
  bool _saving = false;
  bool _failed = false;
  bool _finished = false;

  void _leave() {
    if (!mounted || _finished) return;
    _finished = true;
    final NavigatorState? nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      context.go('/home');
    }
  }

  void _advance() {
    final List<ModeQuestionId> plan = _plan ?? const <ModeQuestionId>[];
    if (_index + 1 < plan.length) {
      setState(() {
        _index += 1;
        _chosenId = null;
        _saving = false;
        _failed = false;
      });
    } else {
      _leave();
    }
  }

  /// Back chevron and system Back: the previous question, or leave without
  /// writing anything.
  void _back() {
    if (_saving) return;
    if (_index > 0) {
      setState(() {
        _index -= 1;
        _chosenId = null;
        _failed = false;
      });
    } else {
      _leave();
    }
  }

  Future<bool> _writeAnswer(ModeQuestionOption option) async {
    try {
      final ModeSaveResult r = await ref
          .read(modeStateProvider.notifier)
          .answerQuestion(widget.mode, ModeAnswer.answered(option.id));
      final bool ok =
          r == ModeSaveResult.saved || r == ModeSaveResult.unchanged;
      final TrainingContext? tc = option.trainingContext;
      if (ok && tc != null) {
        await ref.read(trainingContextProvider.notifier).choose(tc);
      }
      return ok;
    } catch (e) {
      debugPrint('mode question: save threw (${e.runtimeType})');
      return false;
    }
  }

  Future<void> _choose(ModeQuestionOption option) async {
    if (_saving || _finished) return;
    setState(() {
      _saving = true;
      _failed = false;
      _chosenId = option.id;
    });
    final Future<bool> write = _writeAnswer(option);
    await Future<void>.delayed(kModeQuestionSavingMinimum);
    final bool ok = await write;
    if (!mounted) return;
    if (ok) {
      _advance();
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  /// Skip stores `skipped` and never asks again. Failures are logged and
  /// ignored: Skip always works (F-26).
  Future<void> _skip() async {
    if (_saving || _finished) return;
    setState(() => _saving = true);
    try {
      await ref.read(modeStateProvider.notifier).skipQuestion(widget.mode);
      if (widget.mode == AppMode.train) {
        await ref.read(trainingContextProvider.notifier).skip();
      }
    } catch (e) {
      debugPrint('mode question: skip threw (${e.runtimeType})');
    }
    if (!mounted) return;
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;

    final AsyncValue<ModeState> modeAsync = ref.watch(modeStateProvider);
    final AsyncValue<TrainingContextAnswer> tcAsync =
        ref.watch(trainingContextProvider);
    final bool ready = !modeAsync.isLoading && !tcAsync.isLoading;

    if (ready && _plan == null) {
      // A failed training-context read is treated as "answered": never block
      // or nag on a read error.
      final TrainingContextAnswer tc = tcAsync.hasError
          ? TrainingContextAnswer.skipped
          : (tcAsync.valueOrNull ?? TrainingContextAnswer.unanswered);
      _plan = unansweredQuestionsFor(
        widget.mode,
        modeState: modeAsync.valueOrNull ?? ModeState.initial(),
        trainingContext: tc,
      );
      if (_plan!.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
      }
    }

    final List<ModeQuestionId>? plan = _plan;
    final bool hasQuestion = plan != null && plan.isNotEmpty;

    Widget content = const SizedBox.shrink();
    if (hasQuestion && !_finished) {
      content = _buildQuestion(context, l10n, t, plan[_index], plan.length);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: HudSkyBackground(
          selection:
              HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    AppLocalizations l10n,
    HudTokens t,
    ModeQuestionId question,
    int total,
  ) {
    final String title = switch (question) {
      ModeQuestionId.trainWhere => l10n.modeQuestionTrainWhere,
      ModeQuestionId.bodyStart => l10n.modeQuestionBodyStart,
    };
    final String changes = l10n.modeQuestionWhatChanges(
        question == ModeQuestionId.bodyStart ? 'body' : 'train');
    final List<ModeQuestionOption> options = optionsOfQuestion(question);
    // Only the BODY question consults the existing access gate.
    final ScanAccess access = question == ModeQuestionId.bodyStart
        ? ref.watch(scanAccessProvider)
        : ScanAccess.allowed;

    final List<Widget> optionWidgets = <Widget>[];
    for (final ModeQuestionOption o in options) {
      final String label = _optionLabel(l10n, question, o.id);
      final Key key = Key('modeQuestion.option.${o.id}');
      if (isQuestionOptionRefused(access, o.id)) {
        final String reason = scanAccessMessage(l10n, access);
        optionWidgets.add(
          Semantics(
            key: key,
            container: true,
            button: true,
            enabled: false,
            label: label,
            hint: reason,
            excludeSemantics: true,
            child: ExcludeFocus(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.5,
                  child: ChoiceCard(
                    title: label,
                    subtitle: reason,
                    selected: false,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        optionWidgets.add(
          ChoiceCard(
            key: key,
            title: label,
            selected: _chosenId == o.id,
            onTap: () => unawaited(_choose(o)),
          ),
        );
      }
      optionWidgets.add(const SizedBox(height: 10));
    }

    ModeQuestionOption? chosen;
    for (final ModeQuestionOption o in options) {
      if (o.id == _chosenId) chosen = o;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Visible on Apple desktop only; takes no space elsewhere.
        ShellBackButton(onPressed: _back),
        // Polite announcement on step change (contract S-2).
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.modeQuestionProgress(_index + 1, total),
            key: const Key('modeQuestion.progress'),
            style: HudType.label(t, size: 11).overPhoto(t),
          ),
        ),
        const SizedBox(height: 10),
        ObProgressHeader(
          step: _index + 1,
          total: total,
          onBack: _saving ? null : _back,
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                StepTitle(title: title, subtitle: changes),
                const SizedBox(height: 18),
                ...optionWidgets,
                if (_saving && chosen != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.modeQuestionSaving,
                      key: const Key('modeQuestion.saving'),
                      style: HudType.body(t, size: 13).overPhoto(t),
                    ),
                  ),
                if (_failed) ...<Widget>[
                  Text(
                    l10n.modeQuestionSaveError,
                    key: const Key('modeQuestion.error'),
                    style: HudType.body(t, size: 13).overPhoto(t),
                  ),
                  const SizedBox(height: 10),
                  HudButton(
                    key: const Key('modeQuestion.retry'),
                    label: l10n.modeQuestionRetry,
                    centered: true,
                    enabled: chosen != null,
                    onPressed: chosen == null
                        ? null
                        : () => unawaited(_choose(chosen!)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        HudButton(
          key: const Key('modeQuestion.skip'),
          label: l10n.modeQuestionSkip,
          centered: true,
          enabled: !_saving,
          onPressed: _saving ? null : () => unawaited(_skip()),
        ),
      ],
    );
  }

  String _optionLabel(
      AppLocalizations l10n, ModeQuestionId question, String optionId) {
    switch (question) {
      case ModeQuestionId.trainWhere:
        return switch (optionId) {
          kTrainWhereGym => l10n.modeQuestionTrainOptionGym,
          kTrainWhereAtHome => l10n.modeQuestionTrainOptionAtHome,
          kTrainWhereOutdoors => l10n.modeQuestionTrainOptionOutdoors,
          _ => l10n.modeQuestionTrainOptionYoga,
        };
      case ModeQuestionId.bodyStart:
        return switch (optionId) {
          kBodyStartPhotos => l10n.modeQuestionBodyOptionPhotos,
          kBodyStartFood => l10n.modeQuestionBodyOptionFood,
          _ => l10n.modeQuestionBodyOptionWeight,
        };
    }
  }
}
