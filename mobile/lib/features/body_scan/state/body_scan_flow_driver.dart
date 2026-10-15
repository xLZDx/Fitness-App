/// Drives the pure scan flow (`ScanFlowController`) from the real job runner.
///
/// The controller executes no effect itself. The guided capture screen already
/// writes the photos and the queued scan record, and the job runner
/// (`BodyScanJobRunner`) performs the upload, estimate and verification, so the
/// driver only:
///
///  * keeps the flow context in step with the weight log, the flags and the
///    consent (`FlowContext`);
///  * after the capture screen returns a scan id, replays the capture events so
///    the machine reaches `savingLocal`, then answers its `saveLocal` effect;
///  * starts the runner when the machine asks for the analysis;
///  * forwards cancel and retry to the runner;
///  * follows the persisted scan record (written by the runner) and advances
///    the machine to `done`, or to `failed` with the scrubbed slug.
///
/// body_scan only: nothing here imports the nutrition review state.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/body_scan_flags.dart';
import '../../nutrition_plan/state/weight_providers.dart';
import '../../progress_photos/scan/scan_models.dart';
import '../../progress_photos/scan/scan_repository.dart';
import '../body_scan_flow_page.dart' show bodyScanActiveScanIdProvider;
import '../data/body_scan_flow_machine.dart';
import 'body_scan_providers.dart';
import 'body_scan_settings.dart';
import 'scan_flow_controller.dart';

/// The flow context for the current flags, consent and weight log.
FlowContext flowContextFor({
  required BodyScanFlags flags,
  required BodyScanSettings settings,
  required DateTime now,
  required DateTime? latestWeightAt,
}) {
  final cloud = flags.cloudPhotos && settings.hasCurrentConsent;
  return FlowContext(
    latestWeightAge: latestWeightAt == null ? null : now.difference(latestWeightAt),
    localOnly: !cloud,
    providerRequiresPhotos: flags.cloudPhotos,
    online: true,
  );
}

/// Watch it from the flow page. It lives exactly as long as the page (the
/// controller it drives is auto-disposed too).
final bodyScanFlowDriverProvider = Provider.autoDispose<BodyScanFlowDriver>(
  (ref) {
    final driver = BodyScanFlowDriver(ref);
    driver._start();
    ref.onDispose(driver._dispose);
    return driver;
  },
);

class BodyScanFlowDriver {
  BodyScanFlowDriver(this._ref);

  final Ref _ref;
  bool _disposed = false;
  int _lastRevision = -1;
  FlowStage? _lastStage;
  bool _cancelSent = false;

  ScanFlowController get _ctl => _ref.read(scanFlowControllerProvider.notifier);
  ScanFlowSnapshot get _snap => _ref.read(scanFlowControllerProvider);

  void _start() {
    _ref.listen<ScanFlowSnapshot>(scanFlowControllerProvider, (_, next) {
      _onSnapshot(next);
    });
    _ref.listen(scanHistoryProvider, (_, next) {
      _followRecord(next.valueOrNull);
    });
    // Context inputs; a change pushes a fresh context (never during build).
    _ref.listen(bodyScanFlagsProvider, (_, __) => _pushContext());
    _ref.listen(bodyScanSettingsProvider, (_, __) => _pushContext());
    _ref.listen(weightEntriesProvider, (_, __) => _pushContext());
    Future.microtask(_pushContext);
  }

  void _dispose() => _disposed = true;

  void _pushContext() {
    if (_disposed) return;
    final entries =
        _ref.read(weightEntriesProvider).valueOrNull ?? const [];
    DateTime? latest;
    for (final e in entries) {
      if (latest == null || e.at.isAfter(latest)) latest = e.at;
    }
    _ctl.updateContext(flowContextFor(
      flags: _ref.read(bodyScanFlagsProvider),
      settings:
          _ref.read(bodyScanSettingsProvider).valueOrNull ?? const BodyScanSettings(),
      now: _ref.read(nutritionClockProvider)(),
      latestWeightAt: latest,
    ));
  }

  /// Called by the flow page when the capture route returned. A null id means
  /// the user left the capture without saving.
  void captureReturned(String? scanId) {
    if (_disposed) return;
    if (scanId == null) {
      if (_snap.state.stage == FlowStage.capturing) {
        _ctl.dispatch(const FlowEvent(FlowEventKind.cancel));
      }
      return;
    }
    _ref.read(bodyScanActiveScanIdProvider.notifier).state = scanId;
    // The capture screen has taken every pose and written the record.
    for (var i = 0; i < ScanPose.ordered.length + 1; i++) {
      final s = _snap.state;
      if (s.stage != FlowStage.capturing) break;
      _ctl.dispatch(FlowEvent(FlowEventKind.captured, pose: s.pose));
    }
    if (_snap.state.stage == FlowStage.reviewing) {
      _ctl.dispatch(const FlowEvent(FlowEventKind.confirm));
    }
  }

  // ---- effects ----------------------------------------------------------

  void _onSnapshot(ScanFlowSnapshot snap) {
    if (_disposed || snap.revision == _lastRevision) return;
    _lastRevision = snap.revision;
    final stage = snap.state.stage;
    final previous = _lastStage;
    _lastStage = stage;

    for (final effect in snap.effects) {
      switch (effect.kind) {
        case FlowEffectKind.saveLocal:
          // The capture screen wrote the photos and the record already.
          Future.microtask(() {
            if (_disposed) return;
            if (_ref.read(bodyScanActiveScanIdProvider) == null) {
              _ctl.dispatch(const FlowEvent(FlowEventKind.error,
                  retriable: false, errorSlug: 'save-failed'));
            } else {
              _ctl.dispatch(const FlowEvent(FlowEventKind.saved));
            }
          });
        case FlowEffectKind.computeLocalEstimate:
          _resume();
        case FlowEffectKind.syncReminder:
          // The scan is queued for the cloud path; the runner takes it from here.
          Future.microtask(() {
            if (_disposed || _snap.state.stage != FlowStage.queued) return;
            _ctl.dispatch(const FlowEvent(FlowEventKind.online));
            _resume();
          });
        case FlowEffectKind.abortInFlight:
        case FlowEffectKind.deleteBodyScan:
        case FlowEffectKind.markPendingRemoteDelete:
          _cancelRunner();
        // The runner owns these steps (or the weight sheet / capture screen
        // already did them): nothing to execute here.
        case FlowEffectKind.checkAccess:
        case FlowEffectKind.writeWeight:
        case FlowEffectKind.recordManualOverride:
        case FlowEffectKind.createBodyScan:
        case FlowEffectKind.uploadPose:
        case FlowEffectKind.estimateBodyScan:
        case FlowEffectKind.runVerification:
        case FlowEffectKind.scheduleRetry:
          break;
      }
    }
    // Cancel without an in-flight step still has to stop a queued scan.
    if (stage == FlowStage.cancelled && previous != FlowStage.cancelled) {
      _cancelRunner();
    }
    // Retry from `failed`: the machine goes back to queued with no effect.
    if (previous == FlowStage.failed && stage == FlowStage.queued) {
      final id = _ref.read(bodyScanActiveScanIdProvider);
      if (id != null) {
        _cancelSent = false;
        _ref.read(bodyScanRunnerProvider)?.retry(id);
      }
    }
  }

  void _resume() {
    try {
      final r = _ref.read(bodyScanRunnerProvider);
      if (r != null) r.resume();
    } catch (e) {
      debugPrint('body scan: resume skipped (${e.runtimeType})');
    }
  }

  void _cancelRunner() {
    final id = _ref.read(bodyScanActiveScanIdProvider);
    if (id == null || _cancelSent) return;
    _cancelSent = true;
    _ref.read(bodyScanRunnerProvider)?.cancel(id);
  }

  // ---- follow the persisted record --------------------------------------

  void _followRecord(List<ScanRecord>? records) {
    if (_disposed || records == null) return;
    final id = _ref.read(bodyScanActiveScanIdProvider);
    if (id == null) return;
    ScanRecord? rec;
    for (final r in records) {
      if (r.id == id) rec = r;
    }
    final a = rec?.analysis;
    if (a == null) return;
    final stage = _snap.state.stage;
    if (!_snap.state.isActive) return;
    switch (a.status) {
      case JobStatus.done:
        _advanceToDone();
      case JobStatus.failed:
        if (stage != FlowStage.savingLocal) {
          _ctl.dispatch(FlowEvent(FlowEventKind.error,
              retriable: false, errorSlug: a.lastError ?? 'failed'));
        }
      default:
        break;
    }
  }

  void _advanceToDone() {
    for (var i = 0; i < 12; i++) {
      final s = _snap.state;
      switch (s.stage) {
        case FlowStage.queued:
          _ctl.dispatch(const FlowEvent(FlowEventKind.online));
        case FlowStage.uploading:
          _ctl.dispatch(FlowEvent(FlowEventKind.uploaded, pose: s.pose));
        case FlowStage.analysing:
          _ctl.dispatch(const FlowEvent(FlowEventKind.estimated));
        case FlowStage.verifying:
          _ctl.dispatch(const FlowEvent(FlowEventKind.verified));
        default:
          return;
      }
    }
  }
}
