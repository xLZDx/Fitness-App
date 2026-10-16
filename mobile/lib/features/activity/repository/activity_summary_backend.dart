/// The cloud side of the summary sync as the sync layer sees it (S02 design
/// 3.2, 6.2). A thin adapter over Firestore implements it in production; tests
/// supply a fake that enforces the rules `rev` rule and the tombstone check.
///
/// Summaries cross this seam as plain maps with `DateTime` values for the
/// timestamp keys (`startUtc`, `endUtc`, `updatedAt`) and `int` / `double` for
/// numbers; the adapter converts from and to Firestore types.
library;

/// A summary write was rejected by the backend rules: the `rev` rule, the
/// immutability or clamp rules, the batch rule or the account-deletion fence.
/// It is NEVER read as a deletion (design 6.2); the sync layer reads the
/// tombstone and the server summary to decide.
class SummaryWriteDenied implements Exception {
  const SummaryWriteDenied([this.reason]);

  final String? reason;

  @override
  String toString() => 'SummaryWriteDenied($reason)';
}

/// The backend could not be reached or the answer was lost (timeout, offline).
/// The write MAY have been applied; the same rev is resent later and a denial
/// of that resend resolves through read and three-way merge.
class SummaryBackendUnavailable implements Exception {
  const SummaryBackendUnavailable([this.cause]);

  final Object? cause;

  @override
  String toString() => 'SummaryBackendUnavailable($cause)';
}

/// More summaries than one batched write allows (design 6.2: at most 8).
class SummaryBatchTooLarge implements Exception {
  const SummaryBatchTooLarge(this.count, this.max);

  final int count;
  final int max;

  @override
  String toString() => 'SummaryBatchTooLarge($count > $max)';
}

/// Maximum number of summaries in one batched write (design 6.2, section 4).
const int kMaxSummaryBatch = 8;

abstract class ActivitySummaryBackend {
  /// The server summary of [id], or null when the document does not exist.
  /// Throws [SummaryBackendUnavailable] when it cannot be read.
  Future<Map<String, Object?>?> readSummary(String id);

  /// `true` = the tombstone `activity_tombstones/{id}` exists, `false` = the
  /// read succeeded and it is absent. Throws [SummaryBackendUnavailable] when
  /// the read failed (the caller treats that as "unknown", never as deleted).
  Future<bool> tombstoneExists(String id);

  /// Ids with a server tombstone (owner-readable). Throws
  /// [SummaryBackendUnavailable] when the list cannot be read.
  Future<Set<String>> listTombstoneIds();

  /// Writes [summary] for [id]. [create] is true only when the client knows
  /// the document does not exist (rev must then be 1); otherwise the write is
  /// an update whose `rev` must be strictly greater than the stored one.
  /// Throws [SummaryWriteDenied] or [SummaryBackendUnavailable].
  Future<void> writeSummary(
    String id,
    Map<String, Object> summary, {
    required bool create,
  });
}
