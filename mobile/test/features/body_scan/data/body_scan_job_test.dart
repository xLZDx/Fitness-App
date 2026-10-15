// T27 body_scan_job_test (SCAN-09, SCAN-10 policy half). Backoff schedule,
// attempt cap and terminal states of the scan job.
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backoff min(2^attempt, 300) seconds', () {
    test('attempts 0..5 give 1, 2, 4, 8, 16, 32', () {
      expect([for (var a = 0; a <= 5; a++) backoffSeconds(a)],
          [1, 2, 4, 8, 16, 32]);
    });
    test('2^8 = 256 is still uncapped; 2^9 = 512 is capped at 300', () {
      expect(backoffSeconds(8), 256);
      expect(backoffSeconds(9), 300);
    });
    test('no value is ever above 300, for any attempt including absurd ones', () {
      for (final a in [9, 10, 20, 29, 30, 31, 63, 64, 100, 100000]) {
        expect(backoffSeconds(a), 300, reason: 'attempt $a');
      }
      for (var a = 0; a < 200; a++) {
        expect(backoffSeconds(a), lessThanOrEqualTo(300));
        expect(backoffSeconds(a), greaterThanOrEqualTo(1));
      }
    });
    test('a negative attempt is treated as the first (1 s)', () {
      expect(backoffSeconds(-1), 1);
      expect(backoffSeconds(-100), 1);
    });
    test('policy constants: 5 attempts, 300 s cap', () {
      expect(JobPolicy.maxAttempts, 5);
      expect(JobPolicy.maxBackoffSeconds, 300);
    });
  });

  group('retriable errors: queued with attempt + 1, max 5, then failed(retriable)', () {
    test('attempts 1..4 stay queued and carry the slug', () {
      var job = const BodyScanJob.queued();
      for (var i = 1; i <= 4; i++) {
        job = job.onRetriableError('network');
        expect(job.status, JobStatus.queued, reason: 'after failure $i');
        expect(job.attempt, i);
        expect(job.lastError, 'network');
        expect(job.isResumable, isTrue);
      }
    });
    test('the 5th failed attempt is failed(retriable: true), terminal', () {
      var job = const BodyScanJob.queued();
      for (var i = 0; i < 5; i++) {
        job = job.onRetriableError('timeout');
      }
      expect(job.status, JobStatus.failed);
      expect(job.attempt, 5);
      expect(job.retriable, isTrue);
      expect(job.isTerminal, isTrue);
      expect(job.isResumable, isFalse);
    });
    test('the cap boundary: attempt 3 -> 4 queued, attempt 4 -> 5 failed', () {
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 3)
              .onRetriableError()
              .status,
          JobStatus.queued);
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 4)
              .onRetriableError()
              .status,
          JobStatus.failed);
    });
    test('nextDelaySeconds follows the failures: attempts 0,1 -> 1 s; 2 -> 2 s; 5 -> 16 s', () {
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 0).nextDelaySeconds, 1);
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 1).nextDelaySeconds, 1);
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 2).nextDelaySeconds, 2);
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 3).nextDelaySeconds, 4);
      expect(const BodyScanJob(status: JobStatus.queued, attempt: 5).nextDelaySeconds, 16);
    });
  });

  group('non-retriable error', () {
    test('goes to failed(retriable: false) at once, keeps the attempt, never auto-retries', () {
      final job = const BodyScanJob(status: JobStatus.analysing, attempt: 2)
          .onFatalError('provider-output-invalid');
      expect(job.status, JobStatus.failed);
      expect(job.retriable, isFalse);
      expect(job.attempt, 2);
      expect(job.lastError, 'provider-output-invalid');
      expect(job.isTerminal, isTrue);
      expect(job.isResumable, isFalse);
    });
  });

  group('retry and cancel', () {
    test('retry resets the attempt to 0 and goes to queued', () {
      final failed = const BodyScanJob(
          status: JobStatus.failed, attempt: 5, retriable: true, lastError: 'x');
      final r = failed.retry();
      expect(r.status, JobStatus.queued);
      expect(r.attempt, 0);
      expect(r.lastError, isNull);
      expect(r.isResumable, isTrue);
    });
    test('cancel is terminal and keeps attempt and last error for diagnosis', () {
      final c = const BodyScanJob(
              status: JobStatus.uploading, attempt: 3, lastError: 'network')
          .cancel();
      expect(c.status, JobStatus.cancelled);
      expect(c.attempt, 3);
      expect(c.lastError, 'network');
      expect(c.isTerminal, isTrue);
    });
  });

  group('status model', () {
    test('terminal: done, failed, cancelled; resumable: queued, uploading, analysing', () {
      expect({for (final s in JobStatus.values) s: s.isTerminal}, {
        JobStatus.queued: false,
        JobStatus.uploading: false,
        JobStatus.analysing: false,
        JobStatus.done: true,
        JobStatus.failed: true,
        JobStatus.cancelled: true,
      });
      for (final s in JobStatus.values) {
        expect(BodyScanJob(status: s).isResumable, !s.isTerminal);
      }
    });
    test('parse: known names; unknown / null / non-string degrade to failed (never re-run)', () {
      for (final s in JobStatus.values) {
        expect(JobStatus.parse(s.name), s);
      }
      expect(JobStatus.parse('rebooting'), JobStatus.failed);
      expect(JobStatus.parse(null), JobStatus.failed);
      expect(JobStatus.parse(3), JobStatus.failed);
      expect(JobStatus.parse('Queued'), JobStatus.failed);
      expect(JobStatus.parse('rebooting').isTerminal, isTrue);
    });
    test('the default job is queued, retriable, attempt 0', () {
      const j = BodyScanJob.queued();
      expect(j.status, JobStatus.queued);
      expect(j.attempt, 0);
      expect(j.retriable, isTrue);
      expect(j.lastError, isNull);
    });
  });
}
