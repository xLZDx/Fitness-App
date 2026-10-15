/// Thresholds and priorities of the activity merger (design s31.3). Pure Dart,
/// no Flutter imports. All numbers are [OWN] and user-configurable via the
/// constructor.
library;

import 'device_source.dart';
import 'source_record.dart';

class MergePolicy {
  const MergePolicy({
    this.minIou = 0.8,
    this.maxStartDiffSeconds = 120,
    this.maxEndDiffSeconds = 300,
    this.maxDistanceRelDiff = 0.15,
    this.maxGpsMeanMeters = 100,
    this.minStreamCoverage = 0.8,
    this.maxClockSkewSeconds = 5,
    this.summaryDisagreement = 0.10,
    this.splitGapSeconds = 60,
    this.joinSplits = false,
    this.kindPriority = defaultKindPriority,
    this.sourcePriority = const {},
  });

  /// Time intersection over union of `[start, end]` (or the start/end rule).
  final double minIou;
  final int maxStartDiffSeconds;
  final int maxEndDiffSeconds;

  /// Relative distance difference when both sessions report a distance.
  final double maxDistanceRelDiff;

  /// Mean distance between time-aligned GPS points when both have GPS.
  final double maxGpsMeanMeters;

  /// A stream is taken from a source only if it covers this fraction of the
  /// session.
  final double minStreamCoverage;

  /// Beyond this start-time skew a complementary stream is NOT aligned.
  final int maxClockSkewSeconds;

  /// A summary disagreement above this fraction is noted in `mergeNotes`.
  final double summaryDisagreement;

  /// Back-to-back records from ONE source within this gap may be joined.
  final int splitGapSeconds;
  final bool joinSplits;

  /// Lower number = higher priority. Default: dedicated sensor > watch or
  /// vendor cloud > phone app / file > platform aggregate.
  final Map<SourceKind, int> kindPriority;

  /// Per-source override (`sourceId` -> rank); wins over [kindPriority].
  final Map<String, int> sourcePriority;

  static const Map<SourceKind, int> defaultKindPriority = {
    SourceKind.bleSensor: 0,
    SourceKind.companionApp: 1,
    SourceKind.vendorCloud: 1,
    SourceKind.fileImport: 2,
    SourceKind.platformHealth: 3,
  };

  /// The platform aggregate rank, used to demote echoes.
  int get echoRank => 100;

  int priorityOf(SourceRecord r) =>
      sourcePriority[r.sourceId] ?? kindPriority[r.sourceKind] ?? 50;
}
