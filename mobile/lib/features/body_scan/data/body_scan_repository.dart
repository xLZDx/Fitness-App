/// Interface of the server scan history (design s4, s5.1). Interface only: the
/// Firestore + callable implementation and an in-memory fake live in `state/`
/// (C14). Pure Dart, no Flutter imports.
library;

import 'body_scan_entry.dart';

abstract class BodyScanRepository {
  /// Newest first by `takenAt`, at most [limit] entries (history reads use
  /// 120). Documents that cannot be read are skipped, never thrown.
  Stream<List<BodyScanEntry>> watchEntries({int limit = 120});

  /// The one client-editable numeric field; the server estimate is unchanged
  /// and the caller also writes the day's weight entry (D-72).
  Future<void> updateRecordedWeight(String scanId, double weightKg);

  /// The one other client-editable field (<= 200 characters).
  Future<void> updateNote(String scanId, String? note);
}
