/// The one pushed page behind `/record/gps` (S04-D 4.1: S4-1 to S4-6). It
/// switches in place on the recorder phase, so the strip, the notification and
/// a process restart all open the same route. Routes and wiring belong to lane
/// R9; this file only exposes [GpsRecordingPage].
///
/// Phase to view: idle/preparing -> start (S4-1); acquiring, recording, paused,
/// stopping -> live (S4-2, S4-3); finished -> saved (S4-4); restoring ->
/// recovery offer (S4-5); recoveryFailed -> unreadable (S4-5); permissionRevoked
/// -> revoked (S4-6). `resumeMode` is `/record/gps?mode=resume` (RS-8).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../activity/data/sport_type.dart';
import '../pipeline/recording_constants.dart';
import '../state/recorder_display.dart';
import '../state/recorder_phase.dart';
import '../state/recorder_providers.dart';
import '../state/recorder_state.dart';
import '../widgets/gps_common_widgets.dart';
import '../widgets/gps_format.dart';
import '../widgets/gps_live_widgets.dart';
import '../widgets/gps_start_flow.dart';
import '../widgets/gps_start_panels.dart';
import 'gps_outcome_views.dart';

/// Route name of manual entry (S4-7, PROPOSED); used only as the default of
/// [GpsRecordingPage.onAddManually].
const String kGpsManualEntryRoute = '/record/manual';

/// Marks [gpsRecordingPageOpenProvider] while mounted (U5).
class _PageOpenMarker extends ConsumerStatefulWidget {
  const _PageOpenMarker({required this.child});
  final Widget child;

  @override
  ConsumerState<_PageOpenMarker> createState() => _PageOpenMarkerState();
}

class _PageOpenMarkerState extends ConsumerState<_PageOpenMarker> {
  StateController<bool>? _flag;

  @override
  void initState() {
    super.initState();
    final flag = ref.read(gpsRecordingPageOpenProvider.notifier);
    _flag = flag;
    Future<void>.microtask(() {
      if (mounted) flag.state = true;
    });
  }

  @override
  void dispose() {
    final flag = _flag;
    Future<void>.microtask(() {
      try {
        flag?.state = false;
      } catch (_) {
        // The container is already gone.
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class GpsRecordingPage extends ConsumerWidget {
  const GpsRecordingPage({
    super.key,
    this.resumeMode = false,
    this.onAddManually,
    this.onOpenWorkout,
    this.onOpenPrivacySettings,
    this.onClose,
  });

  /// `?mode=resume`: the Start screen in resume mode (RS-8).
  final bool resumeMode;

  /// Opens manual entry. Default: push [kGpsManualEntryRoute].
  final VoidCallback? onAddManually;

  /// Opens the running workout; the gym-timer row shows only when set.
  final VoidCallback? onOpenWorkout;

  /// Opens the Settings privacy section (consent withdrawn panel).
  final VoidCallback? onOpenPrivacySettings;

  /// Leaves the screen (Done, completed Discard, Back). Default: pop, else go
  /// to `/home` (S04-D 9 destinations).
  final VoidCallback? onClose;

  void _close(BuildContext context) {
    final cb = onClose;
    if (cb != null) return cb();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/home');
    }
  }

  void _manual(BuildContext context) {
    final cb = onAddManually;
    if (cb != null) return cb();
    context.push(kGpsManualEntryRoute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PageOpenMarker(child: _body(context, ref));
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(recorderPhaseProvider);
    final handOffFailed =
        ref.watch(recorderControllerProvider.select((s) => s.handOffFailed));
    final saveFailedDismissed = ref.watch(gpsSaveFailedDismissedProvider);
    ref.listen<bool>(
        recorderControllerProvider.select((s) => s.handOffFailed), (p, n) {
      if (n && p != true) {
        ref.read(gpsSaveFailedDismissedProvider.notifier).state = false;
      }
    });
    void close() => _close(context);
    void manual() => _manual(context);

    switch (phase) {
      case RecorderPhase.acquiring:
      case RecorderPhase.recording:
      case RecorderPhase.pausedManual:
      case RecorderPhase.pausedAuto:
      case RecorderPhase.stopping:
        return GpsLiveView(onClose: close, onOpenWorkout: onOpenWorkout);
      case RecorderPhase.finished:
        return GpsFinishedView(onDone: close);
      case RecorderPhase.restoring:
        return resumeMode
            ? GpsStartView(
                resumeMode: true,
                onClose: close,
                onAddManually: manual,
                onOpenPrivacySettings: onOpenPrivacySettings)
            : GpsRecoveryView(
                onClose: close,
                onAddManually: manual,
                onOpenPrivacySettings: onOpenPrivacySettings);
      case RecorderPhase.recoveryFailed:
        return GpsRecoveryFailedView(onClose: close);
      case RecorderPhase.permissionRevoked:
        return GpsRevokedView(onClose: close);
      case RecorderPhase.idle:
      case RecorderPhase.preparing:
        if (handOffFailed && !saveFailedDismissed) {
          return GpsSaveFailedView(onClose: close);
        }
        return GpsStartView(
          resumeMode: false,
          onClose: close,
          onAddManually: manual,
          onOpenPrivacySettings: onOpenPrivacySettings,
          onReview: () => ref.read(recorderControllerProvider.notifier).checkUnfinished(),
        );
    }
  }
}

// ======================================================================
// S4-1 Start screen
// ======================================================================

class GpsStartView extends ConsumerStatefulWidget {
  const GpsStartView({
    super.key,
    required this.resumeMode,
    required this.onClose,
    required this.onAddManually,
    this.onOpenPrivacySettings,
    this.onReview,
  });

  final bool resumeMode;
  final VoidCallback onClose;
  final VoidCallback onAddManually;
  final VoidCallback? onOpenPrivacySettings;

  /// "Review" on `blockedByJournal`: asks the recorder to load the offer.
  final VoidCallback? onReview;

  @override
  ConsumerState<GpsStartView> createState() => _GpsStartViewState();
}

class _GpsStartViewState extends ConsumerState<GpsStartView>
    with WidgetsBindingObserver {
  SportType _sport = SportType.walking;
  bool? _autoPauseOverride;

  bool get _autoPause => _autoPauseOverride ?? autoPauseDefaultOn(_sport);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(gpsStartFlowProvider.notifier).recheck());
    }
  }

  String? _resumeId() {
    final list = ref.read(recorderControllerProvider).unfinished;
    for (final u in list) {
      if (u.status.name == 'readable') return u.recordingId;
    }
    return list.isEmpty ? null : list.first.recordingId;
  }

  void _go() {
    final flow = ref.read(gpsStartFlowProvider.notifier);
    ref.read(gpsNothingRecordedProvider.notifier).state = false;
    ref.read(gpsSaveFailedDismissedProvider.notifier).state = false;
    if (widget.resumeMode) {
      final id = _resumeId();
      if (id != null) unawaited(flow.resume(id));
    } else {
      unawaited(flow.start(sport: _sport, autoPause: _autoPause));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flow = ref.watch(gpsStartFlowProvider);
    final recorder = ref.watch(recorderControllerProvider);
    final panel = gpsEffectivePanel(flow, recorder.startPanel);
    final busy = flow.working || recorder.isBusy ||
        recorder.startPanel == StartPanel.preparing;
    final nothing = ref.watch(gpsNothingRecordedProvider);

    ref.listen<GpsStartFlowState>(gpsStartFlowProvider, (prev, next) {
      if (prev?.panel == next.panel) return;
      if (next.panel == GpsStartPanelId.startFailed) {
        gpsAnnounce(context, l10n.gpsAnnStartFailed);
      } else if (next.panel == GpsStartPanelId.restricted) {
        gpsAnnounce(context, l10n.gpsAnnRestricted);
      }
    });
    ref.listen<bool>(gpsStartFlowProvider.select((s) => s.working), (p, n) {
      if (n && p != true) gpsAnnounce(context, l10n.gpsAnnStarting);
    });

    final showForm = !widget.resumeMode;
    return PopScope(
      canPop: true,
      child: GpsScreenFrame(
        scaffoldKey: const ValueKey<String>('gps.start.screen'),
        back: GpsBackButton(onPressed: widget.onClose),
        title: widget.resumeMode ? l10n.gpsResumeModeTitle : l10n.gpsStartTitle,
        body: <Widget>[
          if (nothing) GpsNoteLine(l10n.gpsNothingRecorded),
          if (showForm) ...<Widget>[
            GpsSportRow(
              selected: _sport,
              onChanged: (s) => setState(() {
                _sport = s;
                _autoPauseOverride = null;
              }),
            ),
            const SizedBox(height: 12),
            GpsAutoPauseRow(
              value: _autoPause,
              onChanged: (v) => setState(() => _autoPauseOverride = v),
            ),
            const SizedBox(height: 12),
          ],
          GpsStartPanelView(
            panel: panel,
            resumeMode: widget.resumeMode,
            onAddManually: widget.onAddManually,
            onReview: widget.onReview,
            onOpenPrivacySettings: widget.onOpenPrivacySettings,
          ),
          if (panel != GpsStartPanelId.none) const SizedBox(height: 12),
          const GpsPrivacyLine(),
          const GpsBatteryStartNote(),
          const GpsSafetyGapNote(),
        ],
        bottom: KeyedSubtree(
          key: const ValueKey<String>('gps.start.button'),
          child: GpsButton(
            label: busy
                ? l10n.gpsStarting
                : (widget.resumeMode ? l10n.gpsRecoveryResume : l10n.gpsStartButton),
            primary: true,
            enabled: !busy,
            onPressed: _go,
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// S4-2 Recording screen and S4-3 stop panel
// ======================================================================

enum _LiveStep { controls, stopPanel, discardConfirm }

class GpsLiveView extends ConsumerStatefulWidget {
  const GpsLiveView({super.key, required this.onClose, this.onOpenWorkout});

  final VoidCallback onClose;
  final VoidCallback? onOpenWorkout;

  @override
  ConsumerState<GpsLiveView> createState() => _GpsLiveViewState();
}

class _GpsLiveViewState extends ConsumerState<GpsLiveView>
    with WidgetsBindingObserver {
  _LiveStep _step = _LiveStep.controls;
  bool _details = false;
  bool _returnChip = false;
  bool _wasHidden = false;
  Timer? _tick;
  Timer? _chipTimer;
  int? _poorSinceMs;

  /// The recorder's own clock (RecorderEnvironment), so the 30 s rules follow
  /// the same time as the recording and can be driven by a fake clock.
  int _nowMs() => ref.read(recorderEnvironmentProvider).nowUtcMs();

  DateTime _nowForGate() =>
      DateTime.fromMillisecondsSinceEpoch(_nowMs(), isUtc: true);
  final GpsAnnounceGate _gate = GpsAnnounceGate();
  final FocusNode _stopFocus = FocusNode(debugLabel: 'gps.stop');
  final FocusNode _panelFocus = FocusNode(debugLabel: 'gps.panel');
  bool _offlineAnnounced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _chipTimer?.cancel();
    _stopFocus.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = ref.read(recorderControllerProvider.notifier);
    if (s == AppLifecycleState.resumed) {
      c.setBackground(false);
      if (_wasHidden) {
        _wasHidden = false;
        setState(() => _returnChip = true);
        _chipTimer?.cancel();
        _chipTimer = Timer(const Duration(seconds: 10), () {
          if (mounted) setState(() => _returnChip = false);
        });
        gpsAnnounce(context, AppLocalizations.of(context).gpsAnnBackgroundReturn);
      }
    } else {
      _wasHidden = true;
      c.setBackground(true);
    }
  }

  void _setStep(_LiveStep step, {FocusNode? returnTo}) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (step == _LiveStep.controls ? returnTo ?? _stopFocus : _panelFocus)
          .requestFocus();
    });
  }

  void _onState(RecorderState? prev, RecorderState next) {
    final l10n = AppLocalizations.of(context);
    final from = prev?.phase;
    final to = next.phase;
    if (from != to) {
      if (to == RecorderPhase.recording && from == RecorderPhase.acquiring) {
        gpsAnnounce(context,
            next.hasRecoveredData ? l10n.gpsAnnResumedRecovered : l10n.gpsAnnStarted);
      } else if (to == RecorderPhase.pausedManual) {
        gpsAnnounce(context, l10n.gpsAnnPaused);
      } else if (to == RecorderPhase.recording && from == RecorderPhase.pausedManual) {
        gpsAnnounce(context, l10n.gpsAnnResumed);
      } else if (to == RecorderPhase.pausedAuto && _gate.allow('autoPaused', now: _nowForGate())) {
        gpsAnnounce(context, l10n.gpsAnnAutoPaused);
      } else if (to == RecorderPhase.recording &&
          from == RecorderPhase.pausedAuto &&
          _gate.allow('autoResumed', now: _nowForGate())) {
        gpsAnnounce(context, l10n.gpsAnnAutoResumed);
      } else if (to == RecorderPhase.acquiring && from == null) {
        gpsAnnounce(context, l10n.gpsAnnAcquiring);
      }
    }
    if (next.flags.poorAccuracy != (prev?.flags.poorAccuracy ?? false)) {
      _poorSinceMs = next.flags.poorAccuracy ? _nowMs() : null;
      if (_gate.allow(next.flags.poorAccuracy ? 'weak' : 'signalBack',
          now: _nowForGate())) {
        gpsAnnounce(context,
            next.flags.poorAccuracy ? l10n.gpsAnnWeak : l10n.gpsAnnSignalBack);
      }
    }
    if (next.flags.batteryCritical && !(prev?.flags.batteryCritical ?? false)) {
      // Read the percentage after the frame: the live battery stream delivers
      // the same reading just after the recorder reacted to it, and the
      // announcement must name that reading, not the previous one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pct = ref.read(gpsLiveBatteryProvider).valueOrNull?.percent ??
            kBatteryDisplayFallbackPercent;
        gpsAnnounce(context, l10n.gpsAnnBattery(pct), assertive: true);
      });
    }
    if (next.stopReason == StopReason.battery &&
        prev?.stopReason != StopReason.battery &&
        next.phase == RecorderPhase.stopping) {
      gpsAnnounce(context, l10n.gpsAnnBatteryFinish, assertive: true);
    }
    if (next.flags.offline && !_offlineAnnounced) {
      _offlineAnnounced = true;
      gpsAnnounce(context, l10n.gpsAnnOffline);
    }
    if (next.pausePromptDue && !(prev?.pausePromptDue ?? false)) {
      gpsAnnounce(context, l10n.gpsAnnPausedLong);
    }
  }

  void _pauseResume(RecorderPhase phase) {
    final c = ref.read(recorderControllerProvider.notifier);
    if (phase == RecorderPhase.pausedManual) {
      c.resume();
    } else if (phase == RecorderPhase.pausedAuto) {
      // Resume forces recording (S04-D 8.3). The controller exposes resume()
      // for manual pause only, so pause first (legal from pausedAuto), resume.
      c.pause();
      c.resume();
    } else {
      c.pause();
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _stopTapped(RecorderState s) async {
    HapticFeedback.lightImpact();
    final c = ref.read(recorderControllerProvider.notifier);
    if (s.phase == RecorderPhase.acquiring && !s.hasRecoveredData) {
      // Nothing recorded: the controller drops the empty recording.
      ref.read(gpsNothingRecordedProvider.notifier).state = true;
      await c.stop();
      return;
    }
    _setStep(_LiveStep.stopPanel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(recorderControllerProvider);
    final display = ref.watch(recorderDisplayProvider);
    ref.listen<RecorderState>(recorderControllerProvider, _onState);

    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.scale(10) / 10;
    final stepInBody = scale > 1.3 || mq.size.height < 480;
    final phase = s.phase;
    final m = s.metrics;
    final stopping = phase == RecorderPhase.stopping;
    final paused = phase == RecorderPhase.pausedManual || phase == RecorderPhase.pausedAuto;

    // Headline, icon, hint.
    final head = switch (display.headline) {
      RecorderDisplayState.acquiring => l10n.gpsHeadAcquiring,
      RecorderDisplayState.poorAccuracy => l10n.gpsHeadWeak,
      RecorderDisplayState.pausedManual => l10n.gpsHeadPaused,
      RecorderDisplayState.pausedAuto => l10n.gpsHeadAutoPaused,
      _ => l10n.gpsHeadRecording,
    };
    final icon = switch (display.headline) {
      RecorderDisplayState.acquiring => Icons.gps_not_fixed,
      RecorderDisplayState.poorAccuracy => Icons.gps_off,
      RecorderDisplayState.pausedManual ||
      RecorderDisplayState.pausedAuto =>
        Icons.pause_circle_outline,
      _ => Icons.fiber_manual_record,
    };
    final level = display.headline == RecorderDisplayState.poorAccuracy
        ? GpsSignalLevel.none
        : (phase == RecorderPhase.acquiring ? GpsSignalLevel.weak : GpsSignalLevel.good);

    // Banner: one item (storage, battery, long pause).
    final battery = ref.watch(gpsLiveBatteryProvider).valueOrNull?.percent ??
        kBatteryDisplayFallbackPercent;
    String? banner;
    var bannerIcon = Icons.info_outline;
    if (display.banner == RecorderBanner.storageWriteFailing) {
      banner = l10n.gpsStorageBanner;
      bannerIcon = Icons.sd_storage_outlined;
    } else if (display.banner == RecorderBanner.batteryCritical) {
      banner = l10n.gpsBatteryBanner(battery);
      bannerIcon = Icons.battery_alert;
    } else if (s.pausePromptDue) {
      banner = l10n.gpsPausedLongBanner;
      bannerIcon = Icons.hourglass_bottom;
    }

    // Hint line (hidden in acquiring while a banner shows).
    String? hint;
    var weakLink = false;
    switch (phase) {
      case RecorderPhase.acquiring:
        if (s.hasRecoveredData) {
          hint = l10n.gpsResumeGapNote;
        } else {
          final env = ref.read(recorderEnvironmentProvider);
          final waited = env.nowUtcMs() - (s.startUtcMs ?? env.nowUtcMs());
          hint = waited >= 60000 ? l10n.gpsAcquiringLong : l10n.gpsAcquiringHint;
        }
      case RecorderPhase.recording:
        if (display.headline == RecorderDisplayState.poorAccuracy) {
          final since = _poorSinceMs;
          final long = since != null && _nowMs() - since >= 30000;
          hint = long ? l10n.gpsWeakLongHint : l10n.gpsWeakHint;
          weakLink = long;
        }
      case RecorderPhase.pausedManual:
        hint = l10n.gpsPausedHint;
      case RecorderPhase.pausedAuto:
        hint = l10n.gpsAutoPausedHint;
      default:
        break;
    }
    final hintMovedToDetails = phase == RecorderPhase.acquiring && banner != null;

    // Chips.
    final chips = <String>[
      if (display.chips.contains(RecorderChip.offline)) l10n.gpsChipOffline,
      if (_returnChip || display.chips.contains(RecorderChip.background))
        l10n.gpsChipBackground,
    ];

    bool gymRow = false;
    if (widget.onOpenWorkout != null) {
      try {
        gymRow = ref.read(recorderEnvironmentProvider).gymTimerRunning;
      } catch (_) {
        gymRow = false;
      }
    }

    final useSpeed = gpsUsesSpeed(s.sport);
    // Time starts at the first signal (S04-D 8.2): while acquiring only a
    // recovered recording's earlier time shows, a fresh one reads 0:00.
    final shownMovingMs = phase == RecorderPhase.acquiring
        ? s.recoveredMovingTimeMs
        : s.totalMovingTimeMs;
    final stepWidget = switch (_step) {
      _LiveStep.controls => null,
      _LiveStep.stopPanel => GpsStopPanel(
          busy: stopping,
          headerFocusNode: _panelFocus,
          onFinish: () => ref.read(recorderControllerProvider.notifier).stop(),
          onKeepRecording: () => _setStep(_LiveStep.controls),
          onDiscard: () => _setStep(_LiveStep.discardConfirm),
        ),
      _LiveStep.discardConfirm => GpsDiscardConfirm(
          busy: stopping,
          headerFocusNode: _panelFocus,
          distanceM: s.totalDistanceM,
          movingTimeMs: s.totalMovingTimeMs,
          onKeep: () => _setStep(_LiveStep.stopPanel),
          onDelete: () async {
            await ref.read(recorderControllerProvider.notifier).discard();
            if (!mounted) return;
            gpsAnnounce(context, l10n.gpsAnnDiscarded);
            widget.onClose();
          },
        ),
    };

    final controls = GpsLiveControls(
      paused: paused,
      pauseEnabled: !stopping && phase != RecorderPhase.acquiring,
      onPauseResume: () => _pauseResume(phase),
      onStop: () => _stopTapped(s),
      stopFocusNode: _stopFocus,
    );

    final detailLines = <String>[
      head,
      if (hint != null) hint,
      if (banner != null) banner,
      ...chips,
    ];

    return PopScope(
      canPop: _step == _LiveStep.controls,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _setStep(_step == _LiveStep.discardConfirm
            ? _LiveStep.stopPanel
            : _LiveStep.controls);
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_step == _LiveStep.discardConfirm) {
              _setStep(_LiveStep.stopPanel);
            } else if (_step == _LiveStep.stopPanel) {
              _setStep(_LiveStep.controls);
            }
          },
        },
        child: GpsScreenFrame(
          scaffoldKey: const ValueKey<String>('gps.rec.screen'),
          back: GpsBackButton(
            spokenLabel: l10n.gpsBackLabel,
            onPressed: widget.onClose,
          ),
          body: <Widget>[
            Row(
              children: <Widget>[
                ExcludeSemantics(child: Icon(icon, size: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      head,
                      key: const ValueKey<String>('gps.rec.headline'),
                      style: HudType.panelHeading(context.hud).copyWith(fontSize: 22),
                    ),
                  ),
                ),
                if (scale <= 1.3) GpsSignalIndicator(level: level),
              ],
            ),
            if (scale > 1.3) ...<Widget>[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: GpsSignalIndicator(level: level),
              ),
            ],
            const SizedBox(height: 10),
            if (banner != null) ...<Widget>[
              GpsBannerView(text: banner, icon: bannerIcon),
              const SizedBox(height: 10),
            ],
            GpsMetricBlock(
              movingTimeMs: shownMovingMs,
              distanceM: s.totalDistanceM,
              pace: m?.currentPaceSecPerKm,
              speed: m?.currentSpeedMps,
              useSpeed: useSpeed,
              stacked: scale > 1.3,
            ),
            if (hint != null && !hintMovedToDetails) ...<Widget>[
              const SizedBox(height: 10),
              GpsBodyText(hint, secondary: true),
              if (weakLink)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GpsButton(
                    label: l10n.gpsOpenLocationSettings,
                    minHeight: 48,
                    onPressed: () => ref
                        .read(gpsStartFlowProvider.notifier)
                        .openLocationSettings(),
                  ),
                ),
            ],
            if (chips.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              GpsChipRow(labels: chips),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GpsButton(
                label: l10n.gpsDetails,
                minHeight: 48,
                onPressed: () => setState(() => _details = !_details),
              ),
            ),
            if (_details)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final line in detailLines) GpsBodyText(line, size: 13),
                  ],
                ),
              ),
            if (gymRow) ...<Widget>[
              const SizedBox(height: 10),
              GpsButton(
                label: l10n.gpsGymTimerRow,
                minHeight: 48,
                onPressed: widget.onOpenWorkout,
              ),
            ],
            if (stepWidget != null && stepInBody) ...<Widget>[
              const SizedBox(height: 12),
              stepWidget,
            ],
          ],
          bottom: stepInBody
              ? (_step == _LiveStep.controls ? controls : null)
              : (stepWidget ?? controls),
        ),
      ),
    );
  }
}

/// Used when the battery stream has no reading yet; the banner then names the
/// entry threshold of S04-R-030 instead of a made-up level.
const int kBatteryDisplayFallbackPercent = 10;
