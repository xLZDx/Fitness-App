/// The mode switcher S-3 (design 2.3, 6.2; contract S-3; S03-10).
///
/// Opened through [AdaptiveSurface] (bottom sheet on Compact and Medium, popover
/// under the Home mode chip on Expanded). Tapping an available row applies the
/// mode at once and closes the sheet; the current mode's row changes nothing.
/// Ride and Explore rows open the Coming-later sheet and never write. Dismissal
/// writes nothing. A running session is not read or touched here (R-M1).
///
/// Wiring: the app root provides [openModeSwitcher] as the value of
/// `modeSwitcherOpenerProvider`. Home (lane L7) attaches [kHomeModeChipKey] to
/// its `home.modeChip` so the popover has an anchor.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/adaptive_surface.dart';
import '../../../shared/widgets/hud/hud_metric.dart' show HudSettingRow;
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../training_context/data/training_context.dart';
import '../../training_context/state/training_context_providers.dart';
import '../data/mode_models.dart';
import '../state/mode_providers.dart';
import '../../../shared/widgets/window_size.dart' show windowWidthShare;
import 'coming_later_sheet.dart';
import 'mode_question_plan.dart';
import 'mode_text.dart';

/// Anchor of the switcher popover: the Home mode chip (`home.modeChip`).
/// Lane L7 puts this key on the chip; without a mounted anchor the surface
/// falls back to a centred dialog (contract 10.6).
final GlobalKey kHomeModeChipKey = GlobalKey(debugLabel: 'home.modeChip');

bool _switcherOpen = false;

/// Opens the switcher. Matches `ModeSwitcherOpener`. Opening twice is a no-op
/// (AC-SW-4).
void openModeSwitcher(BuildContext context, {GlobalKey? anchorKey}) {
  if (_switcherOpen) return;
  _switcherOpen = true;
  try {
    final String label = AppLocalizations.of(context).modeSwitcherTitle;
    unawaited(
      AdaptiveSurface.show<void>(
        context,
        (BuildContext ctx) => const ModeSwitcherSheet(),
        anchorKey: anchorKey ?? kHomeModeChipKey,
        semanticLabel: label,
      ).whenComplete(() => _switcherOpen = false),
    );
  } catch (_) {
    _switcherOpen = false;
    rethrow;
  }
}

class ModeSwitcherSheet extends ConsumerWidget {
  const ModeSwitcherSheet({super.key});

  /// Applies [mode]; failures show the save-error snackbar, nothing else.
  Future<void> _apply(
    ModeNotifier notifier,
    ScaffoldMessengerState? messenger,
    AppLocalizations l10n,
    TextDirection direction,
    AppMode mode,
  ) async {
    ModeSaveResult r;
    try {
      r = await notifier.selectMode(mode);
    } catch (_) {
      r = ModeSaveResult.saveFailed;
    }
    if (r == ModeSaveResult.saved || r == ModeSaveResult.saveFailed) {
      // ignore: deprecated_member_use
      unawaited(SemanticsService.announce(
          l10n.modeChangedAnnouncement(mode.name), direction));
    }
    if (r == ModeSaveResult.saveFailed || r == ModeSaveResult.notReady) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.modeSwitchSaveError)));
    }
  }

  Future<void> _onRowTap(
      BuildContext context, WidgetRef ref, AppMode mode, bool available) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ModeNotifier notifier = ref.read(modeStateProvider.notifier);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    final TextDirection direction = Directionality.of(context);
    if (!available) {
      // Coming later: never writes here. "Choose Train for now" applies Train.
      final bool chose = await showComingLaterSheet(context, mode);
      if (chose && context.mounted) {
        Navigator.of(context).pop();
        await _apply(notifier, messenger, l10n, direction, AppMode.train);
      }
      return;
    }
    Navigator.of(context).pop();
    await _apply(notifier, messenger, l10n, direction, mode);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    // Null while the state reloads: no row is marked current.
    final AppMode? selectedMode = ref.watch(selectedModeProvider);
    final AsyncValue<ModeState> modeAsync = ref.watch(modeStateProvider);
    final ModeState state =
        modeAsync.isLoading ? ModeState.initial() : (modeAsync.valueOrNull ?? ModeState.initial());
    final Map<AppMode, ModeAvailability> table =
        ref.watch(modeFlagsProvider).availabilityTable;
    // Still loading counts as answered: never show a count that may be wrong.
    final TrainingContextAnswer tc = ref.watch(trainingContextProvider).valueOrNull ??
        TrainingContextAnswer.skipped;

    final double chipMaxWidth = windowWidthShare(context, 0.4);

    final List<Widget> rows = <Widget>[];
    for (final AppMode m in AppMode.values) {
      final bool available =
          availabilityOfMode(m, table: table) == ModeAvailability.available;
      final bool current = available && selectedMode == m;
      final int questions = available
          ? unansweredQuestionsFor(m, modeState: state, trainingContext: tc)
              .length
          : 0;
      rows.add(
        Semantics(
          inMutuallyExclusiveGroup: true,
          child: HudSettingRow(
            key: Key('modeSwitcher.row.${m.name}'),
            icon: modeIconOf(m),
            title: modeNameOf(l10n, m),
            subtitle: modeBlurbOf(l10n, m),
            mergeSemantics: true,
            selected: current,
            trailingLabel: available
                ? (current ? l10n.modeSelected : null)
                : l10n.modeComingLater,
            trailing: available
                ? (current
                    ? Icon(Icons.check_rounded, color: t.accent)
                    : const SizedBox.shrink())
                // Badge text scale is bounded: the full meaning is in the row's
                // semantics label.
                : ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: chipMaxWidth),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.3)),
                      child: HudChip(
                        label: l10n.modeComingLater,
                        selected: false,
                        minHeight: 24,
                        maxLines: 2,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                      ),
                    ),
                  ),
            showFocusRing: true,
            hoverStyle: true,
            cursor: true,
            onTap: () => unawaited(_onRowTap(context, ref, m, available)),
          ),
        ),
      );
      if (questions > 0) {
        rows.add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: Key('modeSwitcher.questions.${m.name}'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: t.textSecondary,
              ),
              onPressed: () {
                final GoRouter router = GoRouter.of(context);
                Navigator.of(context).pop();
                unawaited(router.push<void>('/mode-questions/${m.name}'));
              },
              child: Text(l10n.modeSwitcherQuestions(questions)),
            ),
          ),
        );
      }
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          key: const Key('modeSwitcher.sheet'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Focus(
                autofocus: true,
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.modeSwitcherTitle,
                    style: HudType.rowTitle(t, strong: true)
                        .copyWith(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...rows,
              const SizedBox(height: 4),
              TextButton(
                key: const Key('modeSwitcher.seeAll'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: t.textPrimary,
                ),
                onPressed: () {
                  final GoRouter router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  unawaited(router.push<void>('/mode-chooser'));
                },
                child: Text(l10n.modeSwitcherSeeAll),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
