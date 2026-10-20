/// The body-scan history list (C16): one row per scan with date, weight, body
/// fat, the trend label, the baseline marker, the provisional label and the
/// "new estimator" marker (D-54, D-73). Every number and date goes through
/// `NumberFormat` / `DateFormat` with the active locale (D-85).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../data/scan_trend.dart' show ChangeLabel;
import '../state/scan_history_rows.dart';
import 'scan_row_actions.dart';

enum _RowAction { open, editWeight, deletePhotos }

class ScanHistoryList extends ConsumerWidget {
  const ScanHistoryList({super.key, required this.rows});

  /// Newest first.
  final List<ScanHistoryRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.bodyScanHistoryEmpty,
            key: const Key('bodyScan.history.empty'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: hud.textSecondary),
          ),
        ),
      );
    }
    final withPhotos = rows.where((r) => r.hasLocalPhotos).length;
    return ListView(
      padding: const EdgeInsets.all(HudTokens.screenGutter),
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.bodyScanHistoryCount(rows.length),
            key: const Key('bodyScan.history.count'),
            style: theme.textTheme.titleMedium?.copyWith(color: hud.textPrimary),
          ),
        ),
        const SizedBox(height: 8),
        if (withPhotos >= 2)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(
                key: const Key('bodyScan.history.compareBaseline'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => context.push('/photos/compare?mode=baseline'),
                child: Text(l10n.bodyScanHistoryCompareBaseline),
              ),
              OutlinedButton(
                key: const Key('bodyScan.history.comparePrevious'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => context.push('/photos/compare?mode=previous'),
                child: Text(l10n.bodyScanHistoryComparePrevious),
              ),
            ],
          )
        else if (withPhotos == 1)
          Text(
            l10n.bodyScanCompareBaselineOnly,
            key: const Key('bodyScan.history.secondScan'),
            style: theme.textTheme.bodyMedium?.copyWith(color: hud.textSecondary),
          ),
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _HistoryRow(key: ValueKey('bodyScan.history.row.${row.id}'), row: row),
          ),
      ],
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({super.key, required this.row});

  final ScanHistoryRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final locale = l10n.localeName;
    final date = DateFormat.yMMMd(locale).format(row.takenAt);
    final pct = NumberFormat('0.0', locale);
    final kg = NumberFormat('0.0#', locale);

    final fat = row.estimate == null
        ? l10n.bodyScanHistoryPhotosOnly
        : l10n.bodyScanHistoryBodyFat(pct.format(row.estimate!.value));
    final weight = row.weightKg == null
        ? null
        : l10n.bodyScanHistoryWeight(kg.format(row.weightKg!));
    final change = switch (row.change) {
      ChangeLabel.noMeaningfulChange => l10n.bodyScanHistoryChangeNone,
      ChangeLabel.down => l10n.bodyScanHistoryChangeDown,
      ChangeLabel.up => l10n.bodyScanHistoryChangeUp,
      null => null,
    };
    final notes = <String>[
      if (row.isBaseline) l10n.bodyScanHistoryBaseline,
      if (row.startsNewEstimator) l10n.bodyScanHistoryNewEstimator,
      if (row.provisional) l10n.bodyScanRoughLabel,
      if (change != null) change,
      if (row.deletePending) l10n.bodyScanHistoryDeletePending,
    ];
    final parts = <String>[date, fat, if (weight != null) weight, ...notes];

    return GlassCard(
          key: Key('bodyScan.history.card.${row.id}'),
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          onTap: row.estimate == null
              ? null
              : () => context.push('/body-scan/result/${row.id}'),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: parts.join(', '),
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(date,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: hud.textPrimary)),
                      Text(
                        weight == null ? fat : '$fat · $weight',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: hud.textPrimary),
                      ),
                      for (final n in notes)
                        Text(n,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: hud.textSecondary)),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_RowAction>(
                key: Key('bodyScan.history.menu.${row.id}'),
                tooltip: l10n.bodyScanHistoryMenu,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onSelected: (a) {
                  switch (a) {
                    case _RowAction.open:
                      context.push('/body-scan/result/${row.id}');
                    case _RowAction.editWeight:
                      editScanWeightFlow(context, ref, row);
                    case _RowAction.deletePhotos:
                      deleteScanPhotosFlow(context, ref, row);
                  }
                },
                itemBuilder: (_) => [
                  if (row.estimate != null)
                    PopupMenuItem(
                      value: _RowAction.open,
                      child: Text(l10n.bodyScanHistoryActionOpen),
                    ),
                  if (row.estimate != null)
                    PopupMenuItem(
                      value: _RowAction.editWeight,
                      child: Text(l10n.bodyScanHistoryActionEditWeight),
                    ),
                  if (row.hasLocalPhotos || row.mayHaveServerPhotos)
                    PopupMenuItem(
                      value: _RowAction.deletePhotos,
                      child: Text(l10n.bodyScanHistoryActionDeletePhotos),
                    ),
                ],
              ),
            ],
          ),
    );
  }
}
