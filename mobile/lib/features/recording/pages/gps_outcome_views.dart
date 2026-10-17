/// Outcome screens of the GPS recording (S04-D 9, 11, 12, 13):
/// S4-4 saved / save failed, S4-5 recovery offer and unreadable recording,
/// S4-6 permission revoked. No Export anywhere (X3). Automatic swaps move
/// focus to the new headline and make no duplicate announcement (one rule).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permissions/permission_providers.dart';
import '../state/recorder_providers.dart';
import '../state/recording_journal_port.dart';
import '../widgets/gps_common_widgets.dart';
import '../widgets/gps_format.dart';
import '../widgets/gps_live_widgets.dart';
import '../widgets/gps_start_flow.dart';
import '../widgets/gps_start_panels.dart';

// ======================================================================
// S4-4 Finish screen
// ======================================================================

class GpsFinishedView extends ConsumerWidget {
  const GpsFinishedView({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(recorderControllerProvider);
    final m = s.metrics;
    final reason = gpsStopReasonLine(l10n, s.stopReason);
    final useSpeed = gpsUsesSpeed(s.sport);
    return GpsScreenFrame(
      scaffoldKey: const ValueKey<String>('gps.finish.screen'),
      body: <Widget>[
        // The title takes focus and is read by focus (no separate announce).
        GpsPanelCard(
          title: l10n.gpsSavedTitle,
          body: reason,
        ),
        const SizedBox(height: 12),
        GpsSummaryPanel(
          movingTimeMs: s.totalMovingTimeMs,
          elapsedMs: m?.elapsedMs,
          distanceM: s.totalDistanceM,
          pace: m?.averagePaceSecPerKm,
          speed: m?.averageSpeedMps,
          useSpeed: useSpeed,
          ascentM: m?.ascentM,
          descentM: m?.descentM,
        ),
        const SizedBox(height: 12),
        GpsBodyText(l10n.gpsSavedOnDevice, secondary: true),
      ],
      bottom: KeyedSubtree(
        key: const ValueKey<String>('gps.finish.done'),
        child: GpsButton(
          label: l10n.gpsDone,
          primary: true,
          onPressed: () {
            ref.read(recorderControllerProvider.notifier).acknowledgeFinished();
            onDone();
          },
        ),
      ),
    );
  }
}

/// The hand-off failed: the recording is kept and offered at the next start.
class GpsSaveFailedView extends ConsumerWidget {
  const GpsSaveFailedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ref.read(recorderControllerProvider.notifier);
    return GpsScreenFrame(
      scaffoldKey: const ValueKey<String>('gps.saveFailed.screen'),
      body: <Widget>[
        GpsPanelCard(
          title: l10n.gpsRecoveryTitle,
          body: l10n.gpsSaveFailed,
          buttons: <Widget>[
            // Try again re-reads the journal; the kept recording is then
            // offered for Save as finished (the controller has no retry call).
            GpsButton(
                label: l10n.gpsTryAgain,
                primary: true,
                onPressed: () => unawaited(c.checkUnfinished())),
            GpsButton(label: l10n.gpsNotNow, onPressed: onClose),
          ],
        ),
      ],
    );
  }
}

// ======================================================================
// S4-5 Recovery offer
// ======================================================================

UnfinishedRecording? _firstWithStatus(
    List<UnfinishedRecording> list, UnfinishedStatus status) {
  for (final u in list) {
    if (u.status == status) return u;
  }
  return null;
}

class GpsRecoveryView extends ConsumerStatefulWidget {
  const GpsRecoveryView({
    super.key,
    required this.onClose,
    required this.onAddManually,
    this.onOpenPrivacySettings,
  });

  final VoidCallback onClose;
  final VoidCallback onAddManually;
  final VoidCallback? onOpenPrivacySettings;

  @override
  ConsumerState<GpsRecoveryView> createState() => _GpsRecoveryViewState();
}

class _GpsRecoveryViewState extends ConsumerState<GpsRecoveryView> {
  bool _confirmDiscard = false;
  final FocusNode _confirmFocus = FocusNode(debugLabel: 'gps.recovery.confirm');

  @override
  void dispose() {
    _confirmFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(recorderControllerProvider);
    final flow = ref.watch(gpsStartFlowProvider);
    final c = ref.read(recorderControllerProvider.notifier);
    final item = _firstWithStatus(s.unfinished, UnfinishedStatus.readable);

    if (item == null) {
      // Static loading text while the journal is read (no spinner).
      return GpsScreenFrame(
        scaffoldKey: const ValueKey<String>('gps.recovery.screen'),
        back: GpsBackButton(onPressed: widget.onClose),
        body: <Widget>[GpsPanelCard(title: l10n.gpsRestoringLoading, autofocus: false)],
      );
    }

    int? lastMs = item.lastOffsetMs;
    String? age;
    if (item.startUtcMs != null && lastMs != null) {
      try {
        final now = ref.read(recorderEnvironmentProvider).nowUtcMs();
        age = l10n.gpsRecoveryAge(
            gpsSpokenAge(l10n, now - (item.startUtcMs! + lastMs)));
      } catch (_) {
        age = null;
      }
    }
    // TODO(R5): UnfinishedRecording carries no distance or moving time, so the
    // kept distance reads "No data" here; time is the last journaled offset.
    final body = l10n.gpsRecoveryBody(
      lastMs == null ? l10n.gpsNoData : gpsFormatDuration(lastMs),
      l10n.gpsNoData,
    );
    final panelId = flow.panel;

    return GpsScreenFrame(
      scaffoldKey: const ValueKey<String>('gps.recovery.screen'),
      back: GpsBackButton(onPressed: widget.onClose),
      body: <Widget>[
        GpsPanelCard(
          key: const ValueKey<String>('gps.recovery.offer'),
          title: l10n.gpsRecoveryTitle,
          body: body,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (age != null) GpsBodyText(age, secondary: true, size: 13),
              GpsBodyText(l10n.gpsRecoveryCaveat, secondary: true, size: 13),
              GpsBodyText(l10n.gpsResumeGapNote, secondary: true, size: 13),
            ],
          ),
          buttons: _confirmDiscard
              ? const <Widget>[]
              : <Widget>[
                  GpsButton(
                    label: l10n.gpsRecoveryResume,
                    primary: true,
                    enabled: !flow.working,
                    onPressed: () => unawaited(ref
                        .read(gpsStartFlowProvider.notifier)
                        .resume(item.recordingId)),
                  ),
                  GpsButton(
                    label: l10n.gpsRecoverySaveFinished,
                    onPressed: () => unawaited(c.saveRecoveredAsFinished(item.recordingId)),
                  ),
                  GpsButton(
                    label: l10n.gpsDiscard,
                    onPressed: () {
                      setState(() => _confirmDiscard = true);
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _confirmFocus.requestFocus());
                    },
                  ),
                ],
        ),
        if (panelId != GpsStartPanelId.none) ...<Widget>[
          const SizedBox(height: 12),
          // Resume needs permission and services (S04-D 12); the same panels
          // as the Start screen explain what is missing.
          GpsStartPanelView(
            panel: panelId,
            resumeMode: true,
            onAddManually: widget.onAddManually,
            onOpenPrivacySettings: widget.onOpenPrivacySettings,
          ),
        ],
        if (_confirmDiscard) ...<Widget>[
          const SizedBox(height: 12),
          GpsDiscardConfirm(
            headerFocusNode: _confirmFocus,
            distanceM: 0,
            movingTimeMs: lastMs ?? 0,
            onKeep: () => setState(() => _confirmDiscard = false),
            onDelete: () => unawaited(c.discardRecovered(item.recordingId)),
          ),
        ],
      ],
    );
  }
}

/// `recoveryFailed`: Keep (quarantine) or Delete file. No Export (X3).
class GpsRecoveryFailedView extends ConsumerStatefulWidget {
  const GpsRecoveryFailedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<GpsRecoveryFailedView> createState() =>
      _GpsRecoveryFailedViewState();
}

class _GpsRecoveryFailedViewState extends ConsumerState<GpsRecoveryFailedView> {
  bool _confirm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        gpsAnnounce(context, AppLocalizations.of(context).gpsAnnRecoveryFailed,
            assertive: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(recorderControllerProvider);
    final c = ref.read(recorderControllerProvider.notifier);
    final item = _firstWithStatus(s.unfinished, UnfinishedStatus.unreadable);
    final id = item?.recordingId;
    return GpsScreenFrame(
      scaffoldKey: const ValueKey<String>('gps.recoveryFailed.screen'),
      back: GpsBackButton(onPressed: widget.onClose),
      body: <Widget>[
        GpsPanelCard(
          key: const ValueKey<String>('gps.recoveryFailed.panel'),
          title: l10n.gpsRecoveryFailedTitle,
          body: l10n.gpsRecoveryFailedBody,
          buttons: _confirm || id == null
              ? const <Widget>[]
              : <Widget>[
                  GpsButton(
                    label: l10n.gpsKeepFile,
                    primary: true,
                    onPressed: () => unawaited(c.keepUnreadable(id)),
                  ),
                  GpsButton(
                    label: l10n.gpsDeleteFile,
                    onPressed: () => setState(() => _confirm = true),
                  ),
                ],
        ),
        if (_confirm && id != null) ...<Widget>[
          const SizedBox(height: 12),
          GpsPanelCard(
            key: const ValueKey<String>('gps.recoveryFailed.confirm'),
            title: l10n.gpsDeleteFile,
            body: l10n.gpsRecoveryFailedBody,
            buttons: <Widget>[
              GpsButton(
                  label: l10n.gpsDelete,
                  onPressed: () => unawaited(c.deleteUnreadable(id))),
              GpsButton(
                  label: l10n.gpsKeepFile,
                  primary: true,
                  onPressed: () => setState(() => _confirm = false)),
            ],
          ),
        ],
      ],
    );
  }
}

// ======================================================================
// S4-6 Permission revoked
// ======================================================================

class GpsRevokedView extends ConsumerStatefulWidget {
  const GpsRevokedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<GpsRevokedView> createState() => _GpsRevokedViewState();
}

class _GpsRevokedViewState extends ConsumerState<GpsRevokedView> {
  bool _confirmDelete = false;
  bool _busy = false;
  final FocusNode _confirmFocus = FocusNode(debugLabel: 'gps.revoked.confirm');

  @override
  void dispose() {
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(recorderControllerProvider);
    final c = ref.read(recorderControllerProvider.notifier);
    final savedAt = s.startUtcMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
                s.startUtcMs! + (s.metrics?.elapsedMs ?? s.totalMovingTimeMs),
                isUtc: true)
            .toLocal();
    final body = l10n.gpsRevokedBody(
      savedAt == null ? l10n.gpsNoData : gpsFormatClock(savedAt),
      gpsFormatDuration(s.totalMovingTimeMs),
      s.totalDistanceM > 0 ? gpsFormatDistance(s.totalDistanceM) : l10n.gpsNoData,
    );
    return GpsScreenFrame(
      scaffoldKey: const ValueKey<String>('gps.revoked.screen'),
      body: <Widget>[
        // Focus moves here and the title is read by focus (no announce).
        GpsPanelCard(
          key: const ValueKey<String>('gps.revoked.panel'),
          title: l10n.gpsRevokedTitle,
          body: body,
          buttons: _confirmDelete
              ? const <Widget>[]
              : <Widget>[
                  GpsButton(
                    label: l10n.gpsKeep,
                    primary: true,
                    enabled: !_busy,
                    onPressed: () => _run(c.keepRevoked),
                  ),
                  GpsButton(
                    label: l10n.gpsDelete,
                    enabled: !_busy,
                    onPressed: () {
                      setState(() => _confirmDelete = true);
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _confirmFocus.requestFocus());
                    },
                  ),
                  // A link to system settings, never a permission request.
                  GpsButton(
                    label: l10n.gpsOpenSettings,
                    minHeight: 48,
                    onPressed: () => unawaited(
                        ref.read(permissionServiceProvider).openSettings()),
                  ),
                ],
        ),
        if (_confirmDelete) ...<Widget>[
          const SizedBox(height: 12),
          GpsDiscardConfirm(
            headerFocusNode: _confirmFocus,
            busy: _busy,
            distanceM: s.totalDistanceM,
            movingTimeMs: s.totalMovingTimeMs,
            onKeep: () => setState(() => _confirmDelete = false),
            onDelete: () => _run(c.deleteRevoked),
          ),
        ],
      ],
    );
  }
}
