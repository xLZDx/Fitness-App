import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../workouts/data/equipment_type_history.dart';
import '../../workouts/data/workout_log.dart' show WorkoutLogEntry;
import '../../workouts/state/workout_session_providers.dart';
import '../state/equipment_providers.dart';

/// Level-1 equipment memory: the most recent logged workout for any exercise
/// mapped to this equipment TYPE — never a specific gym or physical unit,
/// which the equipment detail page does not know about (it is keyed by
/// `equipmentId`, a catalog type id, e.g. `leg_press`, shared by every gym
/// that owns one). Copy below is deliberately type-scoped ("this equipment",
/// never "this machine you scanned") because that is genuinely all the data
/// underneath it means — see
/// `core/product/GATE_D_EQUIPMENT_TYPE_HISTORY_D0_NOTE_2026-08-19.md`.
///
/// Reuses [workoutSessionHistoryProvider] / [workoutSessionTotalsProvider] —
/// the same providers Progress and the suggested-weight chip already watch
/// — rather than any new Firestore query, and matches client-side against
/// [equipmentExerciseIdsProvider]'s raw exercise-id set. Renders nothing
/// while either is still loading; a card popping in after the rest of the
/// page is a smaller cost than a loading spinner for an optional fact.
class LastSessionCard extends ConsumerWidget {
  const LastSessionCard({super.key, required this.equipmentId});
  final String equipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final exerciseIds =
        ref.watch(equipmentExerciseIdsProvider(equipmentId)).valueOrNull;
    if (exerciseIds == null || exerciseIds.isEmpty) {
      return const SizedBox.shrink();
    }
    // Gated on the session stream's own AsyncValue, not just on
    // `workoutSessionHistoryProvider`'s already-collapsed list: that
    // provider folds "still loading" into an empty list
    // (`.valueOrNull ?? const []`), which is indistinguishable from "no
    // history". Without this check, `workoutSessionTotalsProvider`
    // resolving before the session stream delivers its first snapshot
    // would read as `0 sessions in the window, N total` -- a truncated
    // miss -- and flash "not found in your recent workouts" before the
    // real (possibly matching) history has even arrived (Gate D review,
    // 2026-08-19).
    if (!ref.watch(workoutSessionsProvider).hasValue) {
      return const SizedBox.shrink();
    }
    final history = ref.watch(workoutSessionHistoryProvider);
    final totals = ref.watch(workoutSessionTotalsProvider).valueOrNull;
    if (totals == null) return const SizedBox.shrink();

    final summary = summarizeEquipmentTypeHistory(
      equipmentId: equipmentId,
      windowedHistory: history,
      exerciseIdsForEquipment: exerciseIds,
      allTimeTotal: totals.total,
    );

    // A confirmed "never done this" is not worth a card — same restraint
    // `_SuitabilityCard` uses for "nothing to say yet" in
    // `equipment_detail_page.dart`. Only a genuine find, or the
    // truncated-window case D3 forbids reporting as "no history", earns
    // screen space here.
    if (summary.isConfirmedNoHistory) return const SizedBox.shrink();

    return HudPanel(
      key: const Key('equipment.lastSession'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.equipmentLastSessionHeadline,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (summary.hasHistory)
            _LastSessionDetail(entry: summary.lastEntry!, l10n: l10n, theme: theme)
          else
            Text(
              l10n.equipmentLastSessionNotFoundRecent,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _LastSessionDetail extends StatelessWidget {
  const _LastSessionDetail({
    required this.entry,
    required this.l10n,
    required this.theme,
  });

  final WorkoutLogEntry entry;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final metric = formatLastSessionMetric(
      l10n,
      weightKg: entry.weightKg,
      repsCompleted: entry.repsCompleted,
    );
    final date = DateFormat.MMMd(l10n.localeName).format(entry.completedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (metric != null)
          Text(metric,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        Text(date,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colors.textSecondary)),
      ],
    );
  }
}
