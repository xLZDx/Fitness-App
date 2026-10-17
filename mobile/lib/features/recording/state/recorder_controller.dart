/// The recorder controller: the one entry for start, pause, resume, stop,
/// discard, recovery and the automatic stops (S04 design 5.2 to 5.6, 8.1;
/// S04-03, S04-22, S04-34, S04-35, S04-36, S04-37).
///
/// Rules kept here:
/// - Exactly one phase; every change goes through `_go` and the table in
///   `recorder_phase.dart`.
/// - One `_releaseAll()` ends every collection path (stop, discard, permission
///   loss, battery finish, engine detach, account change): it cancels the
///   subscription, the service, the timers and flushes the journal.
/// - No file API, no clock other than `RecorderEnvironment.nowUtcMs`, no
///   location plugin type. Errors are swallowed content-free (S04-R-052).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/sport_type.dart';
import '../location/fix.dart';
import '../location/location_providers.dart';
import '../location/location_source.dart';
import '../permissions/permission_providers.dart';
import '../permissions/permission_revocation_watcher.dart';
import '../pipeline/pipeline_types.dart';
import '../pipeline/recorder_pipeline.dart';
import '../pipeline/recording_constants.dart';
import 'battery_monitor.dart';
import 'recorder_environment.dart';
import 'recorder_phase.dart';
import 'recorder_ports.dart';
import 'recorder_state.dart';
import 'recorder_state_constants.dart';
import 'recording_journal_port.dart';

class RecorderController extends Notifier<RecorderState> {
  RecorderPipeline? _pipeline;
  LocationSource? _location;
  RecordingJournalPort? _journalPort;
  PermissionRevocationWatcher? _watcher;
  RecordingMeta? _meta;

  StreamSubscription<Fix>? _locationSub;
  StreamSubscription<void>? _detachSub;
  StreamSubscription<void>? _revokedSub;
  StreamSubscription<BatteryReading>? _batterySub;
  StreamSubscription<JournalFault>? _faultSub;
  Timer? _tick;
  Timer? _preparingTimer;
  Timer? _graceTimer;

  /// Bumped by every start attempt and by `_releaseAll`; a stale async
  /// continuation compares and stops.
  int _epoch = 0;

  /// True while a multi-step operation runs; public operations are ignored so
  /// two actions cannot interleave.
  bool _locked = false;

  List<UnfinishedRecording> _pendingUnfinished = const [];

  @override
  RecorderState build() {
    ref.onDispose(_disposeNow);
    return RecorderState.initial;
  }

  // ---------------------------------------------------------------- start

  /// The one Start entry (design 5.4, 7.3). Proceeds only when every
  /// precondition holds; any failure leaves phase `idle` with a visible
  /// [RecorderState.refusal] (no silent no-op).
  Future<void> requestStart({
    required SportType sport,
    bool? autoPauseEnabled,
  }) async {
    if (_locked || state.phase != RecorderPhase.idle) return;
    final env = ref.read(recorderEnvironmentProvider);
    final epoch = ++_epoch;
    _go(RecorderPhase.preparing,
        (s) => _cleared(s, panel: StartPanel.preparing));
    _preparingTimer?.cancel();
    _preparingTimer = Timer(const Duration(milliseconds: kPreparingTimeoutMs),
        () {
      if (epoch != _epoch || state.phase != RecorderPhase.preparing) return;
      _epoch++;
      _failStart(StartPanel.cannotStart, StartRefusal.checkIncomplete);
    });

    final StartRefusal? refusal = await _preconditions(env);
    if (epoch != _epoch) return;
    _preparingTimer?.cancel();
    if (refusal != null) {
      _failStart(_panelFor(refusal), refusal, unfinished: _pendingUnfinished);
      return;
    }

    final ownerUid = env.openJournalOwnerUid;
    if (ownerUid == null) {
      _failStart(StartPanel.cannotStart, StartRefusal.journalNotOpen);
      return;
    }
    final meta = RecordingMeta(
      recordingId: env.newRecordingId(),
      startUtcMs: env.nowUtcMs(),
      utcOffsetMinutes: env.utcOffsetMinutes(),
      sport: sport,
      autoPauseEnabled: autoPauseEnabled ?? autoPauseDefaultOn(sport),
      ownerUid: ownerUid,
    );
    final journal = ref.read(recordingJournalPortProvider);
    try {
      await journal
          .begin(meta)
          .timeout(const Duration(milliseconds: kStartFailedTimeoutMs));
    } on TimeoutException {
      if (epoch == _epoch) {
        _epoch++;
        _failStart(StartPanel.startFailed, StartRefusal.serviceStartFailed);
      }
      return;
    } catch (_) {
      if (epoch == _epoch) {
        _failStart(StartPanel.cannotStart, StartRefusal.beginFailed);
      }
      return;
    }
    if (epoch != _epoch) return;
    if (!_startCollection(meta)) {
      await _releaseAll();
      _failStart(StartPanel.startFailed, StartRefusal.serviceStartFailed);
      return;
    }
    _go(
      RecorderPhase.acquiring,
      (s) => s.copyWith(
        startPanel: StartPanel.none,
        refusal: null,
        recordingId: meta.recordingId,
        sport: meta.sport,
        startUtcMs: meta.startUtcMs,
      ),
    );
    unawaited(_primeBattery(epoch));
  }

  /// Hides a `cannotStart` / `startFailed` panel (Try again calls
  /// [requestStart], Add manually leaves the recorder).
  void dismissStartPanel() {
    if (state.phase != RecorderPhase.idle) return;
    state = state.copyWith(startPanel: StartPanel.none, refusal: null);
  }

  StartPanel _panelFor(StartRefusal r) => switch (r) {
        StartRefusal.journalNotOpen ||
        StartRefusal.checkIncomplete ||
        StartRefusal.beginFailed =>
          StartPanel.cannotStart,
        StartRefusal.serviceStartFailed => StartPanel.startFailed,
        _ => StartPanel.none,
      };

  void _failStart(StartPanel panel, StartRefusal refusal,
      {List<UnfinishedRecording> unfinished = const []}) {
    _preparingTimer?.cancel();
    if (state.phase != RecorderPhase.preparing) return;
    _go(
      RecorderPhase.idle,
      (s) => _cleared(s,
          panel: panel, refusal: refusal, unfinished: unfinished),
    );
  }

  /// The checks of design 5.4 in order; null when all pass.
  Future<StartRefusal?> _preconditions(RecorderEnvironment env,
      {bool checkUnfinished = true}) async {
    _pendingUnfinished = const [];
    try {
      if (env.openJournalOwnerUid == null) return StartRefusal.journalNotOpen;
      if (env.gymTimerRunning) return StartRefusal.gymTimerRunning;
      if (env.foreignSessionRunning) return StartRefusal.foreignSession;
      if (!env.locationConsentGranted) return StartRefusal.consentMissing;
      final perms = ref.read(permissionServiceProvider);
      if (!(await perms.locationStatus()).allowsRecording) {
        return StartRefusal.permissionNotGranted;
      }
      if (env.requireNotificationPermission &&
          !(await perms.notificationStatus()).isGranted) {
        return StartRefusal.notificationDenied;
      }
      if (checkUnfinished) {
        final journal = ref.read(recordingJournalPortProvider);
        final list = await journal.listUnfinished();
        if (list.any((u) => u.blocksStart)) {
          _pendingUnfinished = list;
          return StartRefusal.unfinishedRecording;
        }
      }
      return null;
    } catch (_) {
      return StartRefusal.checkIncomplete;
    }
  }

  /// Opens the subscription and all collection plumbing. Returns false when
  /// something threw (the caller releases and shows `startFailed`).
  bool _startCollection(RecordingMeta meta, {RecoveredRecording? recovered}) {
    try {
      final env = ref.read(recorderEnvironmentProvider);
      final location = _location = ref.read(locationSourceProvider);
      final journal = _journalPort = ref.read(recordingJournalPortProvider);
      final watcher = _watcher = ref.read(permissionRevocationWatcherProvider);
      final battery = ref.read(batteryMonitorProvider);

      final pipeline = RecorderPipeline(autoPauseEnabled: meta.autoPauseEnabled);
      if (recovered != null) {
        // The interruption is a pause interval: no distance, no moving time.
        pipeline.pauseManual(recovered.lastOffsetMs);
        pipeline.resumeManual(
            math.max(env.nowUtcMs() - meta.startUtcMs, recovered.lastOffsetMs));
      }
      _pipeline = pipeline;
      _meta = meta;

      journal.setFlushIntervalMs(kFlushIntervalMs);
      _locationSub = location
          .start(LocationRequest(
            intervalSeconds: kSamplingIntervalMs ~/ 1000,
            notificationTitle: env.notificationTitle,
            notificationText: env.notificationText,
          ))
          .listen(_onFix, onError: _onLocationError);
      _detachSub = location.engineDetached.listen((_) => _onEngineDetached());
      _revokedSub = watcher.onRevoked.listen((_) => unawaited(_onRevoked()));
      watcher.start();
      _batterySub = battery.readings.listen(_onBattery);
      _faultSub = journal.faults.listen(_onFault);
      _tick = Timer.periodic(
          const Duration(milliseconds: kRecorderTickMs), (_) => _onTick());
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------- pause and resume

  /// Manual pause (S04-03 AC-3/AC-4, S04-36). The service and the single
  /// subscription stay; the request rate drops to 10 s and no sample reaches
  /// the track.
  void pause() {
    final p = _pipeline;
    final phase = state.phase;
    if (_locked || p == null || state.engineDetached) return;
    if (phase != RecorderPhase.recording && phase != RecorderPhase.pausedAuto) {
      return;
    }
    final off = _offset();
    _journalEvents(p.pauseManual(off), p);
    _event(JournalEventKind.pause, off);
    _go(
      RecorderPhase.pausedManual,
      (s) => s.copyWith(
        flags: s.flags.copyWith(poorAccuracy: false),
        manualPauseSinceMs: off,
        pausePromptDue: false,
        metrics: p.metrics,
      ),
    );
    _applyInterval();
  }

  /// Resume from a manual pause: back to `recording` (the pipeline restores the
  /// prior moving state; a new auto-pause follows from new fixes).
  void resume() {
    final p = _pipeline;
    if (_locked || p == null || state.phase != RecorderPhase.pausedManual) {
      return;
    }
    final off = _offset();
    p.resumeManual(off);
    _event(JournalEventKind.resume, off);
    _go(
      RecorderPhase.recording,
      (s) => s.copyWith(
        manualPauseSinceMs: null,
        pausePromptDue: false,
        metrics: p.metrics,
      ),
    );
    _applyInterval();
  }

  /// The UI lane reports app visibility (chip `background`).
  void setBackground(bool background) {
    if (state.flags.background == background) return;
    state = state.copyWith(flags: state.flags.copyWith(background: background));
  }

  // ------------------------------------------------------- stop & discard

  /// The user finishes: flush, seal, hand off (S04-R-018).
  Future<void> stop() => _stopAndSave(StopReason.user);

  /// An automatic stop: battery, storage, sampleCap, consentWithdrawn, account
  /// (S04-22, S04-35). Callers outside the controller: the consent lane
  /// (`consentWithdrawn`) and the account hook (`account`).
  Future<void> stopAutomatically(StopReason reason) => _stopAndSave(reason);

  Future<void> _stopAndSave(StopReason reason) async {
    if (_locked || !state.phase.isCollecting) return;
    final s = state;
    final nothingRecorded = s.phase == RecorderPhase.acquiring &&
        !s.hasRecoveredData &&
        (s.metrics?.keptCount ?? 0) == 0;
    if (nothingRecorded) {
      await _discardRunning(reason: reason == StopReason.user ? null : reason);
      return;
    }
    _locked = true;
    try {
      _publish();
      final off = _offset();
      final notice = reason.postsAutoStopNotification
          ? AutoStopNotice(
              reason: reason,
              movingTimeMs: state.totalMovingTimeMs,
              distanceM: state.totalDistanceM)
          : null;
      final id = state.recordingId!;
      if (!_go(RecorderPhase.stopping,
          (s) => s.copyWith(stopReason: reason, pausePromptDue: false))) {
        return;
      }
      await _releaseAll(finishOffset: off);
      await _sealAndHandOff(id, reason, off, notice);
    } finally {
      _locked = false;
    }
  }

  Future<void> _sealAndHandOff(
      String id, StopReason reason, int? off, AutoStopNotice? notice) async {
    final journal = _journalPort ?? ref.read(recordingJournalPortProvider);
    try {
      final stopEvent = journalStopEventFor(reason);
      if (stopEvent != null && off != null) {
        await journal.appendEvent(JournalEvent(stopEvent, off));
      }
      await journal.seal(id, SealRequest(reason: reason, lastOffsetMs: off));
      final result = await journal.handOff(id);
      if (result == HandOffResult.done) {
        _go(RecorderPhase.finished, (s) => s.copyWith(autoStopNotice: notice));
      } else {
        _go(
          RecorderPhase.idle,
          (s) => _cleared(s, stopReason: reason, handOffFailed: true),
        );
      }
    } catch (_) {
      _go(
        RecorderPhase.idle,
        (s) => _cleared(s, stopReason: reason, handOffFailed: true),
      );
    }
  }

  /// Discards the running recording (confirmed by the UI): releases, then the
  /// ordered delete (S04 design 4.5). Nothing is saved.
  Future<void> discard() async {
    if (_locked || !state.phase.isCollecting) return;
    await _discardRunning();
  }

  Future<void> _discardRunning({StopReason? reason}) async {
    _locked = true;
    try {
      final id = state.recordingId;
      await _releaseAll(finishOffset: _offsetOrNull());
      if (id != null) {
        try {
          await (_journalPort ?? ref.read(recordingJournalPortProvider))
              .decideDelete(id);
        } catch (_) {
          // The recording stays on disk and is offered by the next check.
        }
      }
      _go(RecorderPhase.idle, (s) => _cleared(s, stopReason: reason));
    } finally {
      _locked = false;
    }
  }

  /// `finished` is left when the screen is left.
  void acknowledgeFinished() {
    if (state.phase != RecorderPhase.finished) return;
    _go(RecorderPhase.idle, (s) => _cleared(s));
  }

  // ------------------------------------------------- permission revoked

  Future<void> _onRevoked() async {
    if (_locked || !state.phase.isCollecting) return;
    await _enterRevoked();
  }

  Future<void> _enterRevoked() async {
    _locked = true;
    try {
      _publish();
      final id = state.recordingId;
      final off = _offset();
      if (!_go(
        RecorderPhase.permissionRevoked,
        (s) => s.copyWith(
          stopReason: StopReason.permissionRevoked,
          flags: s.flags.copyWith(poorAccuracy: false),
          pausePromptDue: false,
        ),
      )) {
        return;
      }
      await _releaseAll(finishOffset: off);
      if (id == null) return;
      final journal = _journalPort ?? ref.read(recordingJournalPortProvider);
      try {
        await journal.appendEvent(
            JournalEvent(JournalEventKind.permissionRevoked, off));
        // Durably SEALED before the user chooses (design 4.3, Y1).
        await journal.seal(
            id, SealRequest(reason: StopReason.permissionRevoked, lastOffsetMs: off));
      } catch (_) {
        // The choice below still works on the unsealed log; recovery covers it.
      }
    } finally {
      _locked = false;
    }
  }

  /// Keep after a permission loss: durable KEEP, then hand off as a finished
  /// partial activity (design 5.2, Y1).
  Future<void> keepRevoked() async {
    if (_locked || state.phase != RecorderPhase.permissionRevoked) return;
    final id = state.recordingId;
    if (id == null) return;
    _locked = true;
    try {
      final outcome =
          await ref.read(recordingJournalPortProvider).decideKeep(id);
      if (outcome == DecisionOutcome.alreadyDecided) return;
      if (!_go(RecorderPhase.stopping)) return;
      await _sealAndHandOff(id, StopReason.permissionRevoked, null, null);
    } catch (_) {
      // Stays in permissionRevoked; the user can choose again.
    } finally {
      _locked = false;
    }
  }

  /// Delete after a permission loss: durable DELETE, then the ordered delete.
  Future<void> deleteRevoked() async {
    if (_locked || state.phase != RecorderPhase.permissionRevoked) return;
    final id = state.recordingId;
    if (id == null) return;
    _locked = true;
    try {
      final outcome =
          await ref.read(recordingJournalPortProvider).decideDelete(id);
      if (outcome == DecisionOutcome.alreadyDecided) return;
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in permissionRevoked; the user can choose again.
    } finally {
      _locked = false;
    }
  }

  // ------------------------------------------------------------ recovery

  /// Looks for unfinished recordings after the journal is bound (design 4.5).
  /// `idle -> restoring -> (idle | recoveryFailed | stays restoring with the
  /// offer in [RecorderState.unfinished])`.
  Future<void> checkUnfinished() async {
    if (_locked || state.phase != RecorderPhase.idle) return;
    if (ref.read(recorderEnvironmentProvider).openJournalOwnerUid == null) {
      return;
    }
    _locked = true;
    try {
      if (!_go(RecorderPhase.restoring)) return;
      List<UnfinishedRecording> list;
      try {
        list = await ref.read(recordingJournalPortProvider).listUnfinished();
      } catch (_) {
        _go(RecorderPhase.idle, (s) => _cleared(s));
        return;
      }
      final open =
          list.where((u) => u.status != UnfinishedStatus.quarantined).toList();
      if (open.isEmpty) {
        _go(RecorderPhase.idle, (s) => _cleared(s));
      } else if (open.any((u) => u.status == UnfinishedStatus.unreadable)) {
        _go(RecorderPhase.recoveryFailed,
            (s) => s.copyWith(unfinished: open));
      } else {
        state = state.copyWith(unfinished: open);
      }
    } finally {
      _locked = false;
    }
  }

  /// Resume a recovered recording: needs the Start preconditions without the
  /// unfinished check (design 4.5, 5.2). Enters `acquiring` for every origin.
  Future<void> resumeRecovered(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.restoring) return;
    _locked = true;
    try {
      final env = ref.read(recorderEnvironmentProvider);
      final refusal = await _preconditions(env, checkUnfinished: false);
      if (refusal != null) {
        state = state.copyWith(refusal: refusal);
        return;
      }
      final epoch = ++_epoch;
      RecoveredRecording rec;
      try {
        rec = await ref
            .read(recordingJournalPortProvider)
            .openForResume(recordingId)
            .timeout(const Duration(milliseconds: kStartFailedTimeoutMs));
      } catch (_) {
        state = state.copyWith(refusal: StartRefusal.beginFailed);
        return;
      }
      if (epoch != _epoch) return;
      if (!_startCollection(rec.meta, recovered: rec)) {
        await _releaseAll();
        state = state.copyWith(refusal: StartRefusal.serviceStartFailed);
        return;
      }
      _go(
        RecorderPhase.acquiring,
        (s) => s.copyWith(
          refusal: null,
          recordingId: rec.meta.recordingId,
          sport: rec.meta.sport,
          startUtcMs: rec.meta.startUtcMs,
          hasRecoveredData: true,
          recoveredDistanceM: rec.distanceM,
          recoveredMovingTimeMs: rec.movingTimeMs,
          metrics: null,
          unfinished: const [],
        ),
      );
      unawaited(_primeBattery(epoch));
    } finally {
      _locked = false;
    }
  }

  /// Save as finished: seal and hand off the recovered data (design 4.5).
  Future<void> saveRecoveredAsFinished(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.restoring) return;
    _locked = true;
    try {
      if (!_go(
        RecorderPhase.stopping,
        (s) => s.copyWith(
            recordingId: recordingId,
            stopReason: StopReason.user,
            unfinished: const []),
      )) {
        return;
      }
      await _sealAndHandOff(recordingId, StopReason.user, null, null);
    } finally {
      _locked = false;
    }
  }

  /// Discard a recovered recording (durable DELETE, ordered delete).
  Future<void> discardRecovered(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.restoring) return;
    _locked = true;
    try {
      final outcome = await ref
          .read(recordingJournalPortProvider)
          .decideDelete(recordingId);
      if (outcome == DecisionOutcome.alreadyDecided) return;
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in restoring; the offer is shown again.
    } finally {
      _locked = false;
    }
  }

  /// `recoveryFailed`: Keep = quarantine (X3: no Export).
  Future<void> keepUnreadable(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.recoveryFailed) return;
    _locked = true;
    try {
      await ref.read(recordingJournalPortProvider).quarantine(recordingId);
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in recoveryFailed.
    } finally {
      _locked = false;
    }
  }

  /// `recoveryFailed`: Delete the unreadable recording.
  Future<void> deleteUnreadable(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.recoveryFailed) return;
    _locked = true;
    try {
      final outcome = await ref
          .read(recordingJournalPortProvider)
          .decideDelete(recordingId);
      if (outcome == DecisionOutcome.alreadyDecided) return;
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in recoveryFailed.
    } finally {
      _locked = false;
    }
  }

  // ------------------------------------------------- input from the seams

  void _onFix(Fix f) {
    final p = _pipeline;
    final start = state.startUtcMs;
    if (p == null || start == null || _locked || state.engineDetached) return;
    if (!state.phase.isCollecting) return;
    _handle(
      p,
      p.addSample(PipelineSample(
        offsetMs: f.timeUtcMs - start,
        lat: f.latitude,
        lon: f.longitude,
        accuracyM: f.accuracyMeters,
        altitudeM: f.altitudeMeters,
        speedMps: f.speedMps,
      )),
    );
  }

  void _onLocationError(Object _) {
    // A stream error may be a permission loss; the check decides. Anything else
    // is transient and changes nothing (no gap is invented here).
    final watcher = _watcher;
    if (watcher == null) return;
    unawaited(watcher.check().then((r) async {
      if (r == RevocationCheck.revoked) await _onRevoked();
    }));
  }

  void _onTick() {
    final p = _pipeline;
    if (p == null || _locked || !state.phase.isCollecting) return;
    final off = _offset();
    _handle(p, state.engineDetached ? const [] : p.advanceTo(off));
    final since = state.manualPauseSinceMs;
    if (state.phase == RecorderPhase.pausedManual &&
        since != null &&
        !state.pausePromptDue &&
        off - since >= kManualPausePromptAfterMs) {
      state = state.copyWith(pausePromptDue: true);
    }
    if (p.metrics.keptCount >= kSampleCap) {
      unawaited(stopAutomatically(StopReason.sampleCap));
    }
  }

  void _onBattery(BatteryReading r) {
    if (_locked || !state.phase.isCollecting) return;
    if (BatteryPolicy.finishes(r)) {
      unawaited(stopAutomatically(StopReason.battery));
      return;
    }
    final critical = state.flags.batteryCritical;
    if (!critical && BatteryPolicy.entersCritical(r)) {
      state = state.copyWith(flags: state.flags.copyWith(batteryCritical: true));
      _journalPort?.setFlushIntervalMs(kBatteryCriticalFlushIntervalMs);
      _applyInterval();
      _event(JournalEventKind.batteryCritical, _offset());
    } else if (critical && BatteryPolicy.leavesCritical(r)) {
      state =
          state.copyWith(flags: state.flags.copyWith(batteryCritical: false));
      _journalPort?.setFlushIntervalMs(kFlushIntervalMs);
      _applyInterval();
    }
  }

  Future<void> _primeBattery(int epoch) async {
    try {
      final r = await ref.read(batteryMonitorProvider).current();
      if (r != null && epoch == _epoch) _onBattery(r);
    } catch (_) {
      // No reading: the stream may still deliver one.
    }
  }

  void _onFault(JournalFault fault) {
    if (!state.phase.isCollecting) return;
    switch (fault) {
      case JournalFault.storageFailing:
        state =
            state.copyWith(flags: state.flags.copyWith(storageWriteFailing: true));
      case JournalFault.storageRecovered:
        state = state.copyWith(
            flags: state.flags.copyWith(storageWriteFailing: false));
      case JournalFault.storageGaveUp:
        unawaited(stopAutomatically(StopReason.storage));
      case JournalFault.ownerScopeLost:
        unawaited(stopAutomatically(StopReason.account));
    }
  }

  /// S04-37. Nothing is journaled while detached and the notification must not
  /// say Recording ([RecorderState.claimsRecording]).
  void _onEngineDetached() {
    if (_locked || !state.phase.isCollecting) return;
    switch (ref.read(engineDetachPolicyProvider)) {
      case EngineDetachPolicy.stopImmediately:
        unawaited(_haltForDetach());
      case EngineDetachPolicy.graceThenStop:
        state = state.copyWith(engineDetached: true);
        _graceTimer?.cancel();
        _graceTimer = Timer(const Duration(milliseconds: kEngineDetachGraceMs),
            () => unawaited(_haltForDetach()));
    }
  }

  /// Stops collection without sealing: the log stays unfinished and the next
  /// start offers recovery with a marked gap (S04-37 AC-2).
  Future<void> _haltForDetach() async {
    if (_locked || !state.phase.isCollecting) return;
    _locked = true;
    try {
      await _releaseAll();
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } finally {
      _locked = false;
    }
  }

  // ------------------------------------------------------------- helpers

  /// Journals the pipeline events, then moves the phase for them.
  void _handle(RecorderPipeline p, List<PipelineEvent> events) {
    _journalEvents(events, p);
    for (final e in events) {
      switch (e) {
        case FirstFixAcquired() || FixKept():
          if (state.phase == RecorderPhase.acquiring) {
            _go(RecorderPhase.recording);
          }
        case AutoPaused():
          // Manual pause wins: the pipeline suppresses auto rules, and the
          // phase never leaves pausedManual because of one (S04-03 AC-3).
          if (state.phase == RecorderPhase.recording) {
            _go(RecorderPhase.pausedAuto);
          }
        case AutoResumed():
          if (state.phase == RecorderPhase.pausedAuto) {
            _go(RecorderPhase.recording);
          }
        case FixRejected() || GapStarted() || GapEnded():
          break;
      }
    }
    _publish();
  }

  void _journalEvents(List<PipelineEvent> events, RecorderPipeline p) {
    final journal = _journalPort;
    if (journal == null) return;
    for (final e in events) {
      switch (e) {
        case FixKept():
          journal.enqueueSample(e.sample, p.counters);
        case GapStarted():
          _event(JournalEventKind.gapStart, e.offsetMs);
        case GapEnded():
          _event(JournalEventKind.gapEnd, e.offsetMs);
        case AutoPaused():
          _event(JournalEventKind.autoPause, e.offsetMs);
        case AutoResumed():
          _event(JournalEventKind.autoResume, e.offsetMs);
        case FirstFixAcquired() || FixRejected():
          break;
      }
    }
  }

  void _event(JournalEventKind kind, int offsetMs) {
    final journal = _journalPort;
    if (journal == null) return;
    unawaited(journal
        .appendEvent(JournalEvent(kind, offsetMs))
        .catchError((Object _) {}));
  }

  void _publish() {
    final p = _pipeline;
    if (p == null || !state.phase.isCollecting) return;
    final m = p.metrics;
    state = state.copyWith(
      metrics: m,
      flags: state.flags.copyWith(
        poorAccuracy: state.phase == RecorderPhase.recording && m.poorAccuracy,
      ),
    );
  }

  /// Request rate: manual pause 10 s, battery critical 5 s, else 1 s. One
  /// subscription throughout (S04-03 AC-4, S04-36 AC-1).
  void _applyInterval() {
    final location = _location;
    if (location == null) return;
    final ms = state.phase == RecorderPhase.pausedManual
        ? kManualPauseIntervalMs
        : (state.flags.batteryCritical
            ? kBatteryCriticalIntervalMs
            : kSamplingIntervalMs);
    unawaited(location.setInterval(ms ~/ 1000).catchError((Object _) {}));
  }

  int _offset() => ref.read(recorderEnvironmentProvider).nowUtcMs() -
      (state.startUtcMs ?? _meta?.startUtcMs ?? 0);

  int? _offsetOrNull() =>
      state.startUtcMs == null && _meta == null ? null : _offset();

  /// The single release path (design 5.3): cancel subscription, service,
  /// timers, then flush. Idempotent; every step is isolated.
  Future<void> _releaseAll({int? finishOffset}) async {
    _epoch++;
    _tick?.cancel();
    _tick = null;
    _preparingTimer?.cancel();
    _preparingTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _watcher?.stop();
    final subs = <StreamSubscription<Object?>?>[
      _locationSub,
      _detachSub,
      _revokedSub,
      _batterySub,
      _faultSub,
    ];
    _locationSub = null;
    _detachSub = null;
    _revokedSub = null;
    _batterySub = null;
    _faultSub = null;
    for (final s in subs) {
      try {
        await s?.cancel();
      } catch (_) {}
    }
    try {
      await _location?.stop();
    } catch (_) {}
    if (finishOffset != null) {
      try {
        _pipeline?.finish(finishOffset);
      } catch (_) {}
    }
    try {
      await _journalPort?.flush();
    } catch (_) {}
  }

  void _disposeNow() {
    _epoch++;
    _tick?.cancel();
    _preparingTimer?.cancel();
    _graceTimer?.cancel();
    _watcher?.stop();
    _locationSub?.cancel();
    _detachSub?.cancel();
    _revokedSub?.cancel();
    _batterySub?.cancel();
    _faultSub?.cancel();
    final location = _location;
    if (location != null) {
      unawaited(location.stop().catchError((Object _) {}));
    }
  }

  /// The one place that changes the phase. An illegal pair is ignored (and
  /// fails in debug builds) so the table in `recorder_phase.dart` stays the
  /// only authority.
  bool _go(RecorderPhase to, [RecorderState Function(RecorderState)? edit]) {
    final from = state.phase;
    if (!isLegalTransition(from, to)) {
      assert(false, 'illegal recorder transition $from -> $to');
      return false;
    }
    final next = state.copyWith(phase: to);
    state = edit == null ? next : edit(next);
    return true;
  }

  /// A state with the run fields cleared (phase kept), for every return to
  /// `idle`. Background visibility survives.
  RecorderState _cleared(
    RecorderState s, {
    StartPanel panel = StartPanel.none,
    StartRefusal? refusal,
    StopReason? stopReason,
    bool handOffFailed = false,
    List<UnfinishedRecording> unfinished = const [],
  }) =>
      RecorderState(
        phase: s.phase,
        flags: RecorderFlags(background: s.flags.background),
        startPanel: panel,
        refusal: refusal,
        stopReason: stopReason,
        handOffFailed: handOffFailed,
        unfinished: unfinished,
      );
}
