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

  /// Completes when the running multi-step operation ends (an account change
  /// awaits an in-flight stop through it, review C4).
  Completer<void>? _idle;

  /// An automatic stop that arrived while the controller was locked; retried
  /// when the lock is released (review C16).
  StopReason? _pendingAutoStop;

  bool _accountKnown = false;
  String? _accountUid;
  bool _resetAfterUnlock = false;
  bool _disposed = false;
  Timer? _recoveryRetry;
  int _recoveryRetries = 0;

  @override
  RecorderState build() {
    ref.onDispose(_disposeNow);
    return RecorderState.initial;
  }

  void _lock() {
    _locked = true;
    _idle ??= Completer<void>();
  }

  void _unlock() {
    _locked = false;
    final c = _idle;
    _idle = null;
    if (c != null && !c.isCompleted) c.complete();
    if (_disposed) return;
    if (_resetAfterUnlock) {
      _resetAfterUnlock = false;
      _resetForAccount();
    }
    final pending = _pendingAutoStop;
    _pendingAutoStop = null;
    if (pending != null && state.phase.isCollecting) {
      scheduleMicrotask(() => unawaited(_stopAndSave(pending)));
    }
  }

  void _beginAction() {
    if (state.lastActionResult != RecorderActionResult.none) {
      state = state.copyWith(lastActionResult: RecorderActionResult.none);
    }
  }

  Future<void> _abandon(String? id) async {
    if (id == null) return;
    try {
      await (_journalPort ??
              ref.read<RecordingJournalPort>(recordingJournalPortProvider))
          .abandonActive(id);
    } catch (_) {}
  }

  // ------------------------------------------------------------- account

  /// The confirmed account changed (called by the app wiring AFTER the
  /// pre-unbind hook, review C7). Every non-collecting phase resets to idle so a
  /// stale `finished`, `permissionRevoked`, `restoring` or `recoveryFailed`
  /// cannot block the next account. A running or stopping recording is left to
  /// the hook; the reset follows once it ends.
  void onAccountChanged(String? uid) {
    if (_accountKnown && uid == _accountUid) return;
    final first = !_accountKnown;
    _accountKnown = true;
    _accountUid = uid;
    if (first) return;
    if (_locked || state.phase.isActive) {
      _resetAfterUnlock = true;
      if (!_locked) _resetForAccount();
      return;
    }
    _resetForAccount();
  }

  void _resetForAccount() {
    if (state.phase.isCollecting) return;
    _epoch++;
    _recoveryRetry?.cancel();
    _recoveryRetry = null;
    _recoveryRetries = 0;
    _pendingAutoStop = null;
    _clearRun();
    state = RecorderState(flags: RecorderFlags(background: state.flags.background));
  }

  void _clearRun() {
    _pipeline = null;
    _meta = null;
  }

  /// The pre-unbind recorder shutdown: waits for an in-flight operation (an
  /// ongoing stop), then stops a still-collecting recording (review C4).
  Future<void> shutdownForAccountChange() async {
    for (var i = 0; _locked && i < 100; i++) {
      final c = _idle;
      if (c == null) break;
      await c.future;
    }
    if (state.phase.isCollecting) await _stopAndSave(StopReason.account);
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

    // Consent can be withdrawn while the checks ran (review C16).
    if (!ref.read(recorderEnvironmentProvider).locationConsentGranted) {
      _failStart(StartPanel.none, StartRefusal.consentMissing);
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
    final beginFuture = journal.begin(meta);
    try {
      await beginFuture
          .timeout(const Duration(milliseconds: kStartFailedTimeoutMs));
    } on TimeoutException {
      // The begin may still complete later: whatever it opens is released
      // (review C1).
      unawaited(beginFuture.then((_) => _abandon(meta.recordingId),
          onError: (Object _) {}));
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
    if (epoch != _epoch) {
      await _abandon(meta.recordingId);
      return;
    }
    if (!ref.read(recorderEnvironmentProvider).locationConsentGranted) {
      await _discardNew(meta.recordingId);
      _failStart(StartPanel.none, StartRefusal.consentMissing);
      return;
    }
    if (!_startCollection(meta)) {
      await _releaseAll();
      await _abandon(meta.recordingId);
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

  /// A recording that was begun but never collected: ordered delete, or at
  /// least release the journal.
  Future<void> _discardNew(String id) async {
    try {
      await ref.read(recordingJournalPortProvider).decideDelete(id);
    } catch (_) {
      await _abandon(id);
    }
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
      final LocationSource location = ref.read(locationSourceProvider);
      final RecordingJournalPort journal = ref.read(recordingJournalPortProvider);
      final PermissionRevocationWatcher watcher =
          ref.read(permissionRevocationWatcherProvider);
      _location = location;
      _journalPort = journal;
      _watcher = watcher;
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
      // A failing battery source must never kill the recording (S04-22).
      _batterySub = battery.readings.listen(_onBattery, onError: (Object _) {});
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
    if (_locked) {
      // Not dropped: retried when the lock is released (review C16).
      if (reason.isAutomatic) _pendingAutoStop ??= reason;
      return;
    }
    if (!state.phase.isCollecting) return;
    final s = state;
    final nothingRecorded = s.phase == RecorderPhase.acquiring &&
        !s.hasRecoveredData &&
        (s.metrics?.keptCount ?? 0) == 0;
    if (nothingRecorded) {
      await _discardRunning(reason: reason == StopReason.user ? null : reason);
      return;
    }
    _lock();
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
      _unlock();
    }
  }

  Future<void> _sealAndHandOff(
      String id, StopReason reason, int? off, AutoStopNotice? notice,
      {RecorderActionResult result = RecorderActionResult.none}) async {
    final RecordingJournalPort journal =
        _journalPort ?? ref.read<RecordingJournalPort>(recordingJournalPortProvider);
    try {
      final stopEvent = journalStopEventFor(reason);
      if (stopEvent != null && off != null) {
        await journal.appendEvent(JournalEvent(stopEvent, off));
      }
      await journal.seal(id, SealRequest(reason: reason, lastOffsetMs: off));
      final handOff = await journal.handOff(id);
      if (handOff == HandOffResult.done) {
        _go(
            RecorderPhase.finished,
            (s) => s.copyWith(
                autoStopNotice: notice, lastActionResult: result));
      } else if (handOff == HandOffResult.tombstoned) {
        // Deleted by the user meanwhile: nothing was saved, no "saved" screen.
        _go(RecorderPhase.idle,
            (s) => _cleared(s, stopReason: reason, actionResult: result));
      } else {
        _go(
          RecorderPhase.idle,
          (s) => _cleared(s,
              stopReason: reason, handOffFailed: true, actionResult: result),
        );
      }
    } catch (_) {
      // Seal or hand-off threw: the recording stays on disk and is offered
      // again; the journal must not stay active (review C1).
      await _abandon(id);
      _go(
        RecorderPhase.idle,
        (s) => _cleared(s,
            stopReason: reason, handOffFailed: true, actionResult: result),
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
    _lock();
    try {
      _beginAction();
      final id = state.recordingId;
      var result = RecorderActionResult.none;
      await _releaseAll(finishOffset: _offsetOrNull());
      if (id != null) {
        try {
          await (_journalPort ??
                  ref.read<RecordingJournalPort>(recordingJournalPortProvider))
              .decideDelete(id);
        } catch (_) {
          // The recording stays on disk and is offered by the next check; the
          // journal is released so Start is not blocked (review C1, C8).
          result = RecorderActionResult.failed;
          await _abandon(id);
        }
      }
      _go(RecorderPhase.idle,
          (s) => _cleared(s, stopReason: reason, actionResult: result));
    } finally {
      _unlock();
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
    _lock();
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
      final RecordingJournalPort journal =
        _journalPort ?? ref.read<RecordingJournalPort>(recordingJournalPortProvider);
      try {
        await journal.appendEvent(
            JournalEvent(JournalEventKind.permissionRevoked, off));
        // Durably SEALED before the user chooses (design 4.3, Y1).
        await journal.seal(
            id, SealRequest(reason: StopReason.permissionRevoked, lastOffsetMs: off));
      } catch (_) {
        // The choice below still works on the unsealed log; recovery covers it.
      }
      // Never leave the journal active (a successful seal already detached it).
      await _abandon(id);
    } finally {
      _unlock();
    }
  }

  /// Keep after a permission loss: durable KEEP, then hand off as a finished
  /// partial activity (design 5.2, Y1). When DELETE had already won, the delete
  /// is completed and the result says so (review C8).
  Future<void> keepRevoked() async {
    if (_locked || state.phase != RecorderPhase.permissionRevoked) return;
    final id = state.recordingId;
    if (id == null) return;
    _lock();
    try {
      _beginAction();
      final journal = ref.read(recordingJournalPortProvider);
      final outcome = await journal.decideKeep(id);
      if (outcome == DecisionOutcome.alreadyDecided) {
        await journal.decideDelete(id);
        _go(RecorderPhase.idle,
            (s) => _cleared(s, actionResult: RecorderActionResult.alreadyDecided));
        return;
      }
      if (!_go(RecorderPhase.stopping)) return;
      await _sealAndHandOff(id, StopReason.permissionRevoked, null, null);
    } catch (_) {
      // Stays in permissionRevoked; the user can choose again.
      state = state.copyWith(lastActionResult: RecorderActionResult.failed);
    } finally {
      _unlock();
    }
  }

  /// Delete after a permission loss: durable DELETE, then the ordered delete.
  /// When KEEP had already won, the hand-off is completed instead.
  Future<void> deleteRevoked() async {
    if (_locked || state.phase != RecorderPhase.permissionRevoked) return;
    final id = state.recordingId;
    if (id == null) return;
    _lock();
    try {
      _beginAction();
      final journal = ref.read(recordingJournalPortProvider);
      final outcome = await journal.decideDelete(id);
      if (outcome == DecisionOutcome.alreadyDecided) {
        await journal.decideKeep(id);
        if (!_go(RecorderPhase.stopping)) return;
        await _sealAndHandOff(id, StopReason.permissionRevoked, null, null,
            result: RecorderActionResult.alreadyDecided);
        return;
      }
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in permissionRevoked; the user can choose again.
      state = state.copyWith(lastActionResult: RecorderActionResult.failed);
    } finally {
      _unlock();
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
    _lock();
    try {
      if (!_go(RecorderPhase.restoring)) return;
      List<UnfinishedRecording> list;
      try {
        list = await ref.read(recordingJournalPortProvider).listUnfinished();
      } catch (_) {
        // Visible and retried (review C16).
        _go(RecorderPhase.idle, (s) => _cleared(s, recoveryCheckFailed: true));
        _scheduleRecoveryRetry();
        return;
      }
      final open =
          list.where((u) => u.status != UnfinishedStatus.quarantined).toList();
      final hasUnavailable =
          open.any((u) => u.status == UnfinishedStatus.unavailable);
      if (hasUnavailable) {
        _scheduleRecoveryRetry();
      } else {
        _recoveryRetry?.cancel();
        _recoveryRetries = 0;
      }
      if (open.isEmpty) {
        _go(RecorderPhase.idle, (s) => _cleared(s));
      } else if (open.any((u) => u.status == UnfinishedStatus.unreadable)) {
        _go(RecorderPhase.recoveryFailed,
            (s) => s.copyWith(unfinished: open, recoveryCheckFailed: false));
      } else if (!open.any((u) => u.status == UnfinishedStatus.readable)) {
        // Only temporarily unreadable recordings: not an offer, not damage.
        _go(RecorderPhase.idle,
            (s) => _cleared(s, unfinished: open, recoveryCheckFailed: true));
      } else {
        state = state.copyWith(
            unfinished: open, recoveryCheckFailed: hasUnavailable);
      }
    } finally {
      _unlock();
    }
  }

  void _scheduleRecoveryRetry() {
    if (_disposed || _recoveryRetries >= 3) return;
    _recoveryRetries++;
    _recoveryRetry?.cancel();
    _recoveryRetry = Timer(const Duration(seconds: 15), () {
      _recoveryRetry = null;
      if (!_disposed) unawaited(checkUnfinished());
    });
  }

  /// Resume a recovered recording: needs the Start preconditions without the
  /// unfinished check (design 4.5, 5.2). Enters `acquiring` for every origin.
  Future<void> resumeRecovered(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.restoring) return;
    _lock();
    try {
      final env = ref.read(recorderEnvironmentProvider);
      final refusal = await _preconditions(env, checkUnfinished: false);
      if (refusal != null) {
        state = state.copyWith(refusal: refusal);
        return;
      }
      final epoch = ++_epoch;
      RecoveredRecording rec;
      final openFuture =
          ref.read(recordingJournalPortProvider).openForResume(recordingId);
      try {
        rec = await openFuture
            .timeout(const Duration(milliseconds: kStartFailedTimeoutMs));
      } on TimeoutException {
        unawaited(openFuture.then((_) => _abandon(recordingId),
            onError: (Object _) {}));
        state = state.copyWith(refusal: StartRefusal.beginFailed);
        return;
      } catch (_) {
        await _abandon(recordingId);
        state = state.copyWith(refusal: StartRefusal.beginFailed);
        return;
      }
      if (epoch != _epoch) {
        await _abandon(recordingId);
        return;
      }
      if (!_startCollection(rec.meta, recovered: rec)) {
        await _releaseAll();
        await _abandon(recordingId);
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
      _unlock();
    }
  }

  /// Save as finished: seal and hand off the recovered data (design 4.5).
  Future<void> saveRecoveredAsFinished(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.restoring) return;
    _lock();
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
      _unlock();
    }
  }

  /// Discard a recovered recording (durable DELETE, ordered delete). When KEEP
  /// had already won, the hand-off is completed (review C8).
  Future<void> discardRecovered(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.restoring) return;
    _lock();
    try {
      _beginAction();
      final journal = ref.read(recordingJournalPortProvider);
      final outcome = await journal.decideDelete(recordingId);
      if (outcome == DecisionOutcome.alreadyDecided) {
        await journal.decideKeep(recordingId);
        if (!_go(
          RecorderPhase.stopping,
          (s) => s.copyWith(
              recordingId: recordingId,
              stopReason: StopReason.user,
              unfinished: const []),
        )) {
          return;
        }
        await _sealAndHandOff(recordingId, StopReason.user, null, null,
            result: RecorderActionResult.alreadyDecided);
        return;
      }
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in restoring; the offer is shown again.
      state = state.copyWith(lastActionResult: RecorderActionResult.failed);
    } finally {
      _unlock();
    }
  }

  /// `recoveryFailed`: Keep = quarantine (X3: no Export).
  Future<void> keepUnreadable(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.recoveryFailed) return;
    _lock();
    try {
      _beginAction();
      await ref.read(recordingJournalPortProvider).quarantine(recordingId);
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in recoveryFailed.
      state = state.copyWith(lastActionResult: RecorderActionResult.failed);
    } finally {
      _unlock();
    }
  }

  /// `recoveryFailed`: Delete the unreadable recording.
  Future<void> deleteUnreadable(String recordingId) async {
    if (_locked || state.phase != RecorderPhase.recoveryFailed) return;
    _lock();
    try {
      _beginAction();
      final outcome = await ref
          .read(recordingJournalPortProvider)
          .decideDelete(recordingId);
      if (outcome == DecisionOutcome.alreadyDecided) {
        // KEEP won: the next recovery check completes it.
        _go(RecorderPhase.idle,
            (s) => _cleared(s, actionResult: RecorderActionResult.alreadyDecided));
        return;
      }
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } catch (_) {
      // Stays in recoveryFailed.
      state = state.copyWith(lastActionResult: RecorderActionResult.failed);
    } finally {
      _unlock();
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
    _lock();
    try {
      final id = state.recordingId;
      await _releaseAll();
      // Unsealed on purpose, but the journal must be freed (review C1).
      await _abandon(id);
      _go(RecorderPhase.idle, (s) => _cleared(s));
    } finally {
      _unlock();
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
    _disposed = true;
    _recoveryRetry?.cancel();
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
    if (to == RecorderPhase.idle || to == RecorderPhase.finished) _clearRun();
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
    RecorderActionResult actionResult = RecorderActionResult.none,
    bool recoveryCheckFailed = false,
  }) =>
      RecorderState(
        phase: s.phase,
        flags: RecorderFlags(background: s.flags.background),
        startPanel: panel,
        refusal: refusal,
        stopReason: stopReason,
        handOffFailed: handOffFailed,
        unfinished: unfinished,
        lastActionResult: actionResult,
        recoveryCheckFailed: recoveryCheckFailed,
      );
}
