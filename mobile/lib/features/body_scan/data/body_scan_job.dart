/// Job status and the retry/backoff policy of the scan pipeline (design s10).
/// Pure Dart, no Flutter imports.
library;

import 'dart:math' as math;

/// Persisted in `ScanRecord.analysis.status`.
enum JobStatus {
  queued,
  uploading,
  analysing,
  done,
  failed,
  cancelled;

  /// Terminal states are never re-run by the job runner.
  bool get isTerminal =>
      this == JobStatus.done ||
      this == JobStatus.failed ||
      this == JobStatus.cancelled;

  /// Unknown names degrade to [failed] (terminal, never auto-resumed): a state
  /// this build cannot name must not be re-run.
  static JobStatus parse(Object? name) {
    if (name is String) {
      for (final s in values) {
        if (s.name == name) return s;
      }
    }
    return JobStatus.failed;
  }
}

/// Retry policy [OWN].
abstract final class JobPolicy {
  /// After this many failed attempts the job becomes `failed(retriable)`.
  static const int maxAttempts = 5;

  /// Backoff cap in seconds.
  static const int maxBackoffSeconds = 300;
}

/// Seconds to wait before the next try after [attempt] failed attempts:
/// `min(2^attempt, 300)`; attempts 0..5 give 1, 2, 4, 8, 16, 32.
int backoffSeconds(int attempt) {
  if (attempt < 0) return 1;
  if (attempt >= 30) return JobPolicy.maxBackoffSeconds;
  return math.min(1 << attempt, JobPolicy.maxBackoffSeconds);
}

/// One scan job: status, attempt counter and the last closed error slug.
class BodyScanJob {
  const BodyScanJob({
    required this.status,
    this.attempt = 0,
    this.retriable = true,
    this.lastError,
  });

  const BodyScanJob.queued() : this(status: JobStatus.queued);

  final JobStatus status;

  /// Failed attempts so far.
  final int attempt;

  /// Meaningful for [JobStatus.failed]: whether a Retry button makes sense.
  final bool retriable;

  /// Closed slug, never a raw exception message (D-67).
  final String? lastError;

  bool get isTerminal => status.isTerminal;

  /// A non-terminal job is part of the offline queue and is resumed on the
  /// next foreground.
  bool get isResumable => !isTerminal;

  /// Seconds before the next try, for a queued job after a failure.
  int get nextDelaySeconds => backoffSeconds(attempt - 1 < 0 ? 0 : attempt - 1);

  /// A retriable error: back to `queued` with `attempt + 1`, or, once the cap
  /// is reached, `failed(retriable: true)`.
  BodyScanJob onRetriableError([String? slug]) {
    final next = attempt + 1;
    if (next >= JobPolicy.maxAttempts) {
      return BodyScanJob(
        status: JobStatus.failed,
        attempt: next,
        retriable: true,
        lastError: slug,
      );
    }
    return BodyScanJob(
      status: JobStatus.queued,
      attempt: next,
      lastError: slug,
    );
  }

  /// A non-retriable error never auto-retries.
  BodyScanJob onFatalError([String? slug]) => BodyScanJob(
        status: JobStatus.failed,
        attempt: attempt,
        retriable: false,
        lastError: slug,
      );

  /// The user pressed Retry on a failed job: attempts reset.
  BodyScanJob retry() => const BodyScanJob(status: JobStatus.queued);

  BodyScanJob cancel() => BodyScanJob(
        status: JobStatus.cancelled,
        attempt: attempt,
        lastError: lastError,
      );
}
