/// The pure three-way merge of two cloud summaries against their common base
/// (S02 design 3.2 "Rev conflict handling"). Pure Dart, no Flutter imports.
library;

import 'summary_fields.dart';

/// Result of [mergeSummaries].
sealed class SummaryMergeResult {
  const SummaryMergeResult();
}

/// All fields merged. [summary] is ready to store (with the next `rev`).
/// [adoptedFromServer] names the fields where only the server changed, so the
/// caller can record an override for them (design 3.2 rule 1).
class SummaryMerged extends SummaryMergeResult {
  const SummaryMerged(this.summary, this.adoptedFromServer);

  final Map<String, Object> summary;
  final Set<String> adoptedFromServer;
}

/// At least one field was changed to different values on both sides. There is
/// no merged value and no partial merge: the entry stays `sync_conflict`.
class SummaryMergeConflict extends SummaryMergeResult {
  const SummaryMergeConflict(this.fields);

  final List<String> fields;
}

/// `startUtc` or `sport` differ between local and server: the immutability
/// rule was violated, which is an error and never a merge.
class ImmutableSummaryFieldViolation implements Exception {
  const ImmutableSummaryFieldViolation(this.field);

  final String field;

  @override
  String toString() => 'ImmutableSummaryFieldViolation($field)';
}

bool _same(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a == b;
}

/// Merges [local] and [server] against [base] per field. A null [base] (a
/// legacy entry) conflicts on every differing field and never means "server
/// wins". Deterministic and symmetric in the roles of local and server. The
/// merged `rev` is `max(local, server) + 1`; only allowlisted keys are emitted.
SummaryMergeResult mergeSummaries({
  required Map<String, Object?>? base,
  required Map<String, Object?> local,
  required Map<String, Object?> server,
}) {
  for (final k in kSummaryImmutableKeys) {
    if (!_same(local[k], server[k])) throw ImmutableSummaryFieldViolation(k);
  }
  final keys = <String>{
    ...local.keys,
    ...server.keys,
    if (base != null) ...base.keys,
  }
    ..removeAll(kSummaryBookkeepingKeys)
    ..retainWhere(kSummaryAllowedKeys.contains);
  final sorted = keys.toList()..sort();
  final merged = <String, Object>{};
  final adopted = <String>{};
  final conflicts = <String>[];
  for (final k in sorted) {
    final l = local[k];
    final s = server[k];
    Object? pick;
    if (base == null) {
      if (_same(l, s)) {
        pick = l;
      } else {
        conflicts.add(k);
        continue;
      }
    } else {
      final b = base[k];
      final lc = !_same(l, b);
      final sc = !_same(s, b);
      if (!lc && !sc) {
        pick = b;
      } else if (lc && !sc) {
        pick = l;
      } else if (!lc && sc) {
        pick = s;
        adopted.add(k);
      } else if (_same(l, s)) {
        pick = l;
      } else {
        conflicts.add(k);
        continue;
      }
    }
    if (pick != null) merged[k] = pick;
  }
  if (conflicts.isNotEmpty) return SummaryMergeConflict(conflicts);
  final lr = local['rev'];
  final sr = server['rev'];
  final top = [if (lr is int) lr, if (sr is int) sr, 0]
      .reduce((a, b) => a > b ? a : b);
  merged['rev'] = top + 1 > 1000000 ? 1000000 : top + 1;
  final hint = local['updatedAt'];
  if (hint != null) merged['updatedAt'] = hint;
  return SummaryMerged(merged, adopted);
}
