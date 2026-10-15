/// The pure scan flow state machine (design s10). Pure Dart, no Flutter
/// imports: `nextFlow(state, event, context)` returns the next state plus the
/// effects the job runner must execute; it performs none itself.
///
/// An event that is illegal in the current state leaves the state unchanged
/// and returns no effects.
library;

import '../../progress_photos/scan/scan_pose.dart';
import 'body_scan_job.dart';

enum FlowStage {
  idle,
  intro,
  weightPrompt,
  capturing,
  reviewing,
  savingLocal,
  queued,
  uploading,
  analysing,
  verifying,
  done,
  failed,
  cancelled,
}

class FlowState {
  const FlowState(
    this.stage, {
    this.pose,
    this.retake = false,
    this.attempt = 0,
    this.retriable = true,
    this.failReason,
  });

  const FlowState.idle() : this(FlowStage.idle);

  final FlowStage stage;

  /// The pose being captured or uploaded.
  final ScanPose? pose;

  /// True while a single pose is being retaken from the review screen: after
  /// the shot the flow returns to review instead of moving to the next pose.
  final bool retake;

  /// Failed attempts so far (`queued` after an error carries `attempt + 1`).
  final int attempt;
  final bool retriable;
  final String? failReason;

  /// Stages the user can cancel from.
  bool get isActive => switch (stage) {
        FlowStage.intro ||
        FlowStage.weightPrompt ||
        FlowStage.capturing ||
        FlowStage.reviewing ||
        FlowStage.savingLocal ||
        FlowStage.queued ||
        FlowStage.uploading ||
        FlowStage.analysing ||
        FlowStage.verifying =>
          true,
        _ => false,
      };

  /// True when objects may already be on the server.
  bool get mayHaveUploaded =>
      stage == FlowStage.uploading ||
      stage == FlowStage.analysing ||
      stage == FlowStage.verifying;

  @override
  bool operator ==(Object other) =>
      other is FlowState &&
      other.stage == stage &&
      other.pose == pose &&
      other.retake == retake &&
      other.attempt == attempt &&
      other.retriable == retriable &&
      other.failReason == failReason;

  @override
  int get hashCode =>
      Object.hash(stage, pose, retake, attempt, retriable, failReason);

  @override
  String toString() => 'FlowState(${stage.name}, ${pose?.name}, attempt: $attempt)';
}

enum FlowEventKind {
  open,
  start,
  weightLogged,
  skipWeight,
  captured,
  retakePose,
  confirm,
  saved,
  online,
  uploaded,
  estimated,
  verified,
  cancel,
  error,
  retry,
}

class FlowEvent {
  const FlowEvent(
    this.kind, {
    this.pose,
    this.manualOverride = false,
    this.retriable = true,
    this.errorSlug,
  });

  final FlowEventKind kind;
  final ScanPose? pose;

  /// For `captured`: the manual shutter fired while readiness was not green.
  final bool manualOverride;

  /// For `error`.
  final bool retriable;
  final String? errorSlug;
}

enum FlowEffectKind {
  checkAccess,
  writeWeight,
  recordManualOverride,
  saveLocal,
  computeLocalEstimate,
  syncReminder,
  createBodyScan,
  uploadPose,
  estimateBodyScan,
  runVerification,
  abortInFlight,
  deleteBodyScan,
  markPendingRemoteDelete,
  scheduleRetry,
}

class FlowEffect {
  const FlowEffect(this.kind, {this.pose, this.seconds});

  final FlowEffectKind kind;
  final ScanPose? pose;
  final int? seconds;

  @override
  bool operator ==(Object other) =>
      other is FlowEffect &&
      other.kind == kind &&
      other.pose == pose &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(kind, pose, seconds);

  @override
  String toString() => 'FlowEffect(${kind.name}, ${pose?.name}, $seconds)';
}

/// Facts the pure machine needs but does not own.
class FlowContext {
  const FlowContext({
    this.latestWeightAge,
    this.localOnly = true,
    this.providerRequiresPhotos = false,
    this.online = true,
  });

  /// Age of the latest weight entry; null when there is none.
  final Duration? latestWeightAge;

  /// The provisional provider with the cloud flag off: computed on the device,
  /// no callable, no upload, works offline (D-52).
  final bool localOnly;

  /// The active provider needs photos (cloud path only).
  final bool providerRequiresPhotos;

  /// Connectivity, for the cancel effect (`deleteBodyScan` vs a pending
  /// remote delete).
  final bool online;
}

class FlowTransition {
  const FlowTransition(this.state, [this.effects = const []]);

  final FlowState state;
  final List<FlowEffect> effects;
}

/// A weight entry at least this old makes the flow ask for a weight first.
const Duration kWeightPromptAfter = Duration(days: 3);

ScanPose? _nextPose(ScanPose p) {
  final i = ScanPose.ordered.indexOf(p);
  return i + 1 < ScanPose.ordered.length ? ScanPose.ordered[i + 1] : null;
}

FlowTransition nextFlow(FlowState s, FlowEvent e, FlowContext c) {
  FlowTransition illegal() => FlowTransition(s);

  switch (e.kind) {
    case FlowEventKind.open:
      if (s.stage != FlowStage.idle) return illegal();
      return const FlowTransition(
        FlowState(FlowStage.intro),
        [FlowEffect(FlowEffectKind.checkAccess)],
      );

    case FlowEventKind.start:
      if (s.stage != FlowStage.intro) return illegal();
      final age = c.latestWeightAge;
      if (age == null || age >= kWeightPromptAfter) {
        return const FlowTransition(FlowState(FlowStage.weightPrompt));
      }
      return const FlowTransition(
          FlowState(FlowStage.capturing, pose: ScanPose.front));

    case FlowEventKind.weightLogged:
      if (s.stage != FlowStage.weightPrompt) return illegal();
      return const FlowTransition(
        FlowState(FlowStage.capturing, pose: ScanPose.front),
        [FlowEffect(FlowEffectKind.writeWeight)],
      );

    case FlowEventKind.skipWeight:
      if (s.stage != FlowStage.weightPrompt) return illegal();
      return const FlowTransition(
          FlowState(FlowStage.capturing, pose: ScanPose.front));

    case FlowEventKind.captured:
      if (s.stage != FlowStage.capturing || e.pose != s.pose) return illegal();
      final effects = [
        if (e.manualOverride)
          FlowEffect(FlowEffectKind.recordManualOverride, pose: s.pose),
      ];
      final next = _nextPose(s.pose!);
      if (s.retake || next == null) {
        return FlowTransition(FlowState(FlowStage.reviewing), effects);
      }
      return FlowTransition(FlowState(FlowStage.capturing, pose: next), effects);

    case FlowEventKind.retakePose:
      if (s.stage != FlowStage.reviewing || e.pose == null) return illegal();
      return FlowTransition(
          FlowState(FlowStage.capturing, pose: e.pose, retake: true));

    case FlowEventKind.confirm:
      if (s.stage != FlowStage.reviewing) return illegal();
      return const FlowTransition(
        FlowState(FlowStage.savingLocal),
        [FlowEffect(FlowEffectKind.saveLocal)],
      );

    case FlowEventKind.saved:
      if (s.stage != FlowStage.savingLocal) return illegal();
      if (c.localOnly) {
        return const FlowTransition(
          FlowState(FlowStage.verifying),
          [FlowEffect(FlowEffectKind.computeLocalEstimate)],
        );
      }
      return const FlowTransition(
        FlowState(FlowStage.queued),
        [FlowEffect(FlowEffectKind.syncReminder)],
      );

    case FlowEventKind.online:
      if (s.stage != FlowStage.queued) return illegal();
      if (c.providerRequiresPhotos) {
        return const FlowTransition(
          FlowState(FlowStage.uploading, pose: ScanPose.front),
          [
            FlowEffect(FlowEffectKind.createBodyScan),
            FlowEffect(FlowEffectKind.uploadPose, pose: ScanPose.front),
          ],
        );
      }
      return const FlowTransition(
        FlowState(FlowStage.analysing),
        [
          FlowEffect(FlowEffectKind.createBodyScan),
          FlowEffect(FlowEffectKind.estimateBodyScan),
        ],
      );

    case FlowEventKind.uploaded:
      if (s.stage != FlowStage.uploading || e.pose != s.pose) return illegal();
      final nextUp = _nextPose(s.pose!);
      if (nextUp == null) {
        return const FlowTransition(
          FlowState(FlowStage.analysing),
          [FlowEffect(FlowEffectKind.estimateBodyScan)],
        );
      }
      return FlowTransition(
        FlowState(FlowStage.uploading, pose: nextUp),
        [FlowEffect(FlowEffectKind.uploadPose, pose: nextUp)],
      );

    case FlowEventKind.estimated:
      if (s.stage != FlowStage.analysing) return illegal();
      return const FlowTransition(
        FlowState(FlowStage.verifying),
        [FlowEffect(FlowEffectKind.runVerification)],
      );

    case FlowEventKind.verified:
      if (s.stage != FlowStage.verifying) return illegal();
      return const FlowTransition(FlowState(FlowStage.done));

    case FlowEventKind.cancel:
      if (!s.isActive) return illegal();
      return FlowTransition(
        const FlowState(FlowStage.cancelled),
        [
          if (s.stage == FlowStage.uploading ||
              s.stage == FlowStage.analysing ||
              s.stage == FlowStage.verifying)
            const FlowEffect(FlowEffectKind.abortInFlight),
          // A local-only (provisional, cloud flag off) scan never created a
          // server document or an object, so cancelling it must not call or
          // queue anything on the server (D-52, SCAN-52).
          if (s.mayHaveUploaded && !c.localOnly)
            FlowEffect(c.online
                ? FlowEffectKind.deleteBodyScan
                : FlowEffectKind.markPendingRemoteDelete),
        ],
      );

    case FlowEventKind.error:
      if (s.stage != FlowStage.savingLocal &&
          s.stage != FlowStage.queued &&
          s.stage != FlowStage.uploading &&
          s.stage != FlowStage.analysing &&
          s.stage != FlowStage.verifying) {
        return illegal();
      }
      final job = BodyScanJob(status: JobStatus.queued, attempt: s.attempt);
      if (!e.retriable) {
        final failed = job.onFatalError(e.errorSlug);
        return FlowTransition(FlowState(
          FlowStage.failed,
          attempt: failed.attempt,
          retriable: false,
          failReason: e.errorSlug,
        ));
      }
      final after = job.onRetriableError(e.errorSlug);
      if (after.status == JobStatus.failed) {
        return FlowTransition(FlowState(
          FlowStage.failed,
          attempt: after.attempt,
          retriable: true,
          failReason: e.errorSlug,
        ));
      }
      return FlowTransition(
        FlowState(FlowStage.queued, attempt: after.attempt),
        [FlowEffect(FlowEffectKind.scheduleRetry, seconds: backoffSeconds(s.attempt))],
      );

    case FlowEventKind.retry:
      if (s.stage != FlowStage.failed) return illegal();
      return const FlowTransition(FlowState(FlowStage.queued));
  }
}

/// The state to resume from after an app kill, from the persisted job status;
/// null for terminal or unknown statuses (never resumed). Resume is idempotent
/// because `scanId` is the local id and every callable is idempotent on it.
FlowState? resumeStateFor(JobStatus status, {int attempt = 0}) =>
    switch (status) {
      JobStatus.queued => FlowState(FlowStage.queued, attempt: attempt),
      JobStatus.uploading =>
        FlowState(FlowStage.uploading, pose: ScanPose.front, attempt: attempt),
      JobStatus.analysing => FlowState(FlowStage.analysing, attempt: attempt),
      JobStatus.done || JobStatus.failed || JobStatus.cancelled => null,
    };
