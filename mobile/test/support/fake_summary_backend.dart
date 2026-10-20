// A fake cloud for the summary sync (test plan I05, I24). Enforces the rules
// `rev` rule (create needs an absent document and rev 1; an update needs a
// strictly greater rev), counts every call by name and can lose the answer of
// a write after applying it. Test-only.
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';

class FakeSummaryBackend implements ActivitySummaryBackend {
  final Map<String, Map<String, Object?>> docs = {};
  final Set<String> tombstones = {};

  /// Every call, by method name, in order.
  final List<String> calls = [];

  /// Number of writes that were APPLIED (server rows created or updated).
  int applied = 0;

  /// Fail every write without applying it.
  bool failWrites = false;

  /// Apply the next write, then report the backend as unavailable (the
  /// answer is lost).
  bool loseNextAnswer = false;

  /// Runs right after a write was applied and before it returns.
  void Function()? afterApply;

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    calls.add('readSummary');
    final d = docs[id];
    return d == null ? null : {...d};
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    calls.add('tombstoneExists');
    return tombstones.contains(id);
  }

  @override
  Future<Set<String>> listTombstoneIds() async {
    calls.add('listTombstoneIds');
    return {...tombstones};
  }

  @override
  Future<void> writeSummary(
    String id,
    Map<String, Object> summary, {
    required bool create,
  }) async {
    calls.add('writeSummary');
    if (failWrites) throw const SummaryBackendUnavailable('offline');
    final rev = summary['rev'];
    final stored = docs[id];
    if (create) {
      if (stored != null || rev != 1) {
        throw const SummaryWriteDenied('create over an existing document');
      }
    } else {
      final old = stored?['rev'];
      if (stored == null || rev is! int || old is! int || rev <= old) {
        throw const SummaryWriteDenied('rev must increase');
      }
    }
    docs[id] = {...summary};
    applied++;
    afterApply?.call();
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw const SummaryBackendUnavailable('answer lost');
    }
  }
}
