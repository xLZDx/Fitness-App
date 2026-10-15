/// "Body check-in" entry card (D-76) for the Progress page and, in its compact
/// form, the Home page. Carries the provisional label (D-73), follows the
/// surface mode (D-74: no goal figures in `measurementOnly`), and on Progress
/// also mounts the resume / failure card for an unfinished scan (D-78) and the
/// history / privacy links.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/hud/hud_surface.dart';
import '../../progress_photos/scan/scan_access.dart';
import '../../progress_photos/scan/scan_models.dart';
import '../../progress_photos/scan/scan_repository.dart';
import '../../progress_photos/scan/ui/scan_gate_view.dart';
import '../data/body_scan_job.dart';
import '../data/scan_plan_context.dart';
import '../state/body_scan_providers.dart';
import '../state/scan_history_actions.dart';
import '../state/scan_history_rows.dart';
import '../state/scan_plan_context_provider.dart';
import 'resume_scan_card.dart';

class BodyScanEntryCard extends ConsumerWidget {
  const BodyScanEntryCard({super.key, this.compact = false});

  /// Home form: title, last check-in and one action only.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(scanAccessProvider);
    if (access == ScanAccess.signedOut) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final history = ref.watch(scanHistoryProvider).valueOrNull ?? const <ScanRecord>[];
    final measurementOnly = ref.watch(scanPlanContextValueProvider).surfaceMode ==
        ScanSurfaceMode.measurementOnly;

    DateTime? newest;
    for (final r in history) {
      if (newest == null || r.createdAt.isAfter(newest)) newest = r.createdAt;
    }
    final now = DateTime.now();
    final days = newest == null ? null : now.difference(newest).inDays;
    final last = days == null
        ? l10n.bodyCheckInNever
        : l10n.bodyCheckInLast(days < 0 ? 0 : days);

    final allowed = access == ScanAccess.allowed;
    VoidCallback? start;
    if (allowed) {
      start = () => GoRouter.of(context).push('/body-scan');
    } else if (access == ScanAccess.needsConsent) {
      start = () async {
        if (await runScanConsent(context, ref) && context.mounted) {
          GoRouter.of(context).push('/body-scan');
        }
      };
    } else if (access == ScanAccess.needsSupporter) {
      start = () => GoRouter.of(context).push('/subscription');
    } else if (access == ScanAccess.ageUnknown) {
      start = () => GoRouter.of(context).push('/profile');
    }
    final canStart = allowed || access == ScanAccess.needsConsent;

    final card = HudPanel(
      key: Key('bodyCheckIn.card.${compact ? 'home' : 'progress'}'),
      padding: const EdgeInsets.all(16),
      onTap: compact ? start : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.bodyCheckInTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          if (canStart || compact) ...[
            Text(l10n.bodyScanRoughLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(last, style: theme.textTheme.bodyMedium),
            if (measurementOnly) ...[
              const SizedBox(height: 4),
              Text(l10n.bodyScanMeasurementOnlyNote,
                  style: theme.textTheme.bodySmall),
            ],
          ] else
            Text(scanAccessMessage(l10n, access),
                style: theme.textTheme.bodySmall),
          if (start != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('bodyCheckIn.start'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: start,
              child: Text(compact && canStart
                  ? l10n.bodyCheckInHomeAction
                  : l10n.bodyCheckInStart),
            ),
          ],
          if (!compact && allowed) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('bodyCheckIn.history'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => GoRouter.of(context).push('/body-scan/history'),
                  child: Text(l10n.bodyScanHistoryTitle),
                ),
                TextButton(
                  key: const Key('bodyCheckIn.privacy'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => GoRouter.of(context).push('/body-scan/privacy'),
                  child: Text(l10n.bodyScanPrivacyTitle),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (compact || !allowed) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnfinishedScan(history: history),
        card,
      ],
    );
  }
}

/// The resume / terminal-failure card of the newest unfinished scan (D-78).
class _UnfinishedScan extends ConsumerStatefulWidget {
  const _UnfinishedScan({required this.history});
  final List<ScanRecord> history;

  @override
  ConsumerState<_UnfinishedScan> createState() => _UnfinishedScanState();
}

class _UnfinishedScanState extends ConsumerState<_UnfinishedScan> {
  bool _hidden = false;

  /// Cancel / Delete: the remote-delete-aware path. The cloud copy goes first;
  /// offline, the delete is owed (`pendingRemoteDelete`) and the runner
  /// finishes it, so a cancelled scan never leaves an orphan on the server.
  Future<void> _delete(ScanRecord r) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    DeletePhotosOutcome outcome;
    try {
      outcome = await ref.read(scanHistoryActionsProvider).deletePhotos(
            ScanHistoryRow(
              id: r.id,
              takenAt: r.createdAt,
              weightKg: r.weightKg,
              record: r,
            ),
          );
    } catch (e) {
      debugPrint('body scan: delete failed (${e.runtimeType})');
      outcome = DeletePhotosOutcome.failed;
    }
    final text = switch (outcome) {
      DeletePhotosOutcome.deleted => l10n.bodyScanDeletePhotosDone,
      DeletePhotosOutcome.queuedOffline => l10n.bodyScanDeletePhotosQueued,
      DeletePhotosOutcome.failed => l10n.bodyScanDeletePhotosFailed,
    };
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Resume / Retry: wake the runner, then open the flow with the scan id.
  Future<void> _open(ScanRecord r, {required bool retry}) async {
    final runner = ref.read(bodyScanRunnerProvider);
    try {
      if (retry) {
        await runner?.retry(r.id);
      } else {
        // Not awaited: the flow page follows the record; errors are observed.
        unawaited(runner?.resume().catchError((Object e) {
              debugPrint('body scan: resume failed (${e.runtimeType})');
            }) ??
            Future<void>.value());
      }
    } catch (e) {
      debugPrint('body scan: resume failed (${e.runtimeType})');
    }
    if (!mounted) return;
    GoRouter.of(context).push('/body-scan?scanId=${Uri.encodeQueryComponent(r.id)}');
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    ScanRecord? target;
    for (final r in widget.history) {
      final a = r.analysis;
      if (a == null || a.status == JobStatus.done || a.status == JobStatus.cancelled) {
        continue;
      }
      if (target == null || r.createdAt.isAfter(target.createdAt)) target = r;
    }
    if (target == null) return const SizedBox.shrink();
    final rec = target;
    final card = rec.analysis!.status == JobStatus.failed
        ? ResumeScanCard.failed(
            onRetry: () => _open(rec, retry: true),
            onKeep: () => setState(() => _hidden = true),
            onDelete: () => _delete(rec),
          )
        : ResumeScanCard.pending(
            onResume: () => _open(rec, retry: false),
            onCancel: () => _delete(rec),
          );
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: card);
  }
}
