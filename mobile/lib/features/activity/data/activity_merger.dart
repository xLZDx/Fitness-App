/// Pure, deterministic merge and dedup of activity sessions from several
/// sources (design s31.3). No Flutter imports.
///
/// `merge` is ORDER-INDEPENDENT: inputs are sorted by `(priority, startUtc, id)`
/// first, so shuffling the list cannot change the result.
///
/// Documented simplification: the clock skew of a complementary stream is the
/// difference of the session start times (the sessions are already matched by
/// rule 2), not a cross-correlation search; a skew beyond the policy limit
/// (default 5 s) means the stream is NOT aligned and is not taken.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'activity_session.dart';
import 'activity_summary.dart';
import 'device_source.dart';
import 'lap.dart';
import 'merge_policy.dart';
import 'sample_stream.dart';
import 'source_record.dart';
import 'sport_type.dart';

class MergeResult {
  const MergeResult(this.sessions);

  /// Merged sessions ordered by `(startUtc, id)`.
  final List<ActivitySession> sessions;
}

const double _eps = 1e-9;

/// Optional [onPairCompared] is a test seam (design 10): it is invoked once per
/// pairwise comparison (echo lookup step or cluster-head comparison). With
/// null the behaviour and the result are identical.
MergeResult merge(
  List<ActivitySession> candidates,
  MergePolicy policy, {
  void Function()? onPairCompared,
}) {
  final echoes = _echoIds(candidates, onPairCompared);
  final ranks = Map<ActivitySession, int>.identity();
  int rankOf(ActivitySession s) {
    final cached = ranks[s];
    if (cached != null) return cached;
    var best = 50;
    if (echoes.contains(s.id)) {
      best = policy.echoRank;
    } else {
      var any = false;
      for (final p in s.provenance) {
        final r = policy.priorityOf(p);
        if (!any || r < best) best = r;
        any = true;
      }
    }
    ranks[s] = best;
    return best;
  }

  int compare(ActivitySession a, ActivitySession b) {
    final r = rankOf(a).compareTo(rankOf(b));
    if (r != 0) return r;
    final t = a.startUtc.compareTo(b.startUtc);
    if (t != 0) return t;
    final i = a.id.compareTo(b.id);
    if (i != 0) return i;
    return _sameIdTieBreak(a, b);
  }

  final sorted = [...candidates]..sort(compare);

  // Rule 0 (native-id rule, design 9): the same id is the same recording
  // (`activityIdFor` is a function of sourceId + externalId), so a replayed
  // or re-synced record collapses to one session before any other rule.
  // Rule 1: exact duplicate (same sourceId + externalId) keeps the first.
  final seenIds = <String>{};
  final seen = <String>{};
  final unique = <ActivitySession>[];
  for (final s in sorted) {
    if (!seenIds.add(s.id)) continue;
    final keys = [
      for (final p in s.provenance)
        if (p.dedupKey != null) p.dedupKey!,
    ];
    if (keys.any(seen.contains)) continue;
    seen.addAll(keys);
    unique.add(s);
  }

  // Rules 2-4: cluster against each cluster's best-ranked member. Only heads
  // in the time window of the session can match (see [_HeadWindow]), so the
  // work is bounded by the local density, not by the number of clusters. The
  // result is the same as scanning every head in creation order.
  final window = _HeadWindow.of(unique, policy);
  final clusters = <List<ActivitySession>>[];
  for (final s in unique) {
    int? home;
    for (final ci in window.candidates(s)) {
      onPairCompared?.call();
      if (_sameWorkout(clusters[ci].first, s, policy)) {
        home = ci;
        break;
      }
    }
    if (home == null) {
      window.addHead(clusters.length, s);
      clusters.add([s]);
    } else {
      clusters[home].add(s);
    }
  }

  var merged = [
    for (final c in clusters) _mergeCluster(c, policy, echoes),
  ];
  if (policy.joinSplits) merged = _joinSplits(merged, policy);
  merged.sort((a, b) {
    final t = a.startUtc.compareTo(b.startUtc);
    return t != 0 ? t : a.id.compareTo(b.id);
  });
  return MergeResult(List.unmodifiable(merged));
}

/// Rule 3: a platform-health record whose recording app names a source we
/// already hold is an echo of it.
///
/// Indexed by source id / app package, so the lookup is O(sessions), not
/// O(sessions^2): every holder list is scanned only until the first holder
/// that is not the session itself.
Set<String> _echoIds(List<ActivitySession> all, void Function()? onPair) {
  final holders = <String, List<ActivitySession>>{};
  for (final t in all) {
    final keys = <String>{};
    for (final p in t.provenance) {
      if (p.sourceKind == SourceKind.platformHealth) continue;
      keys.add(p.sourceId);
      final app = p.appPackage;
      if (app != null) keys.add(app);
    }
    for (final k in keys) {
      holders.putIfAbsent(k, () => []).add(t);
    }
  }
  final echoes = <String>{};
  for (final s in all) {
    if (s.provenance.isEmpty) continue;
    final rec = s.provenance.first;
    final app = rec.appPackage;
    if (rec.sourceKind != SourceKind.platformHealth || app == null) continue;
    final held = holders[app];
    if (held == null) continue;
    for (final t in held) {
      onPair?.call();
      if (identical(t, s)) continue;
      echoes.add(s.id);
      break;
    }
  }
  return echoes;
}

/// Deterministic order for two records with the same id, rank and start (a
/// replay or a re-sync of one recording): the newer import wins, then the
/// serialised content, so the kept record never depends on the input order.
int _sameIdTieBreak(ActivitySession a, ActivitySession b) {
  DateTime? newest(ActivitySession s) {
    DateTime? best;
    for (final p in s.provenance) {
      if (best == null || p.importedAt.isAfter(best)) best = p.importedAt;
    }
    return best;
  }

  final na = newest(a);
  final nb = newest(b);
  if (na != null && nb != null) {
    final c = nb.compareTo(na);
    if (c != 0) return c;
  } else if (na != null || nb != null) {
    return na != null ? -1 : 1;
  }
  return jsonEncode(a.toJson()).compareTo(jsonEncode(b.toJson()));
}

/// Time-bucket index over cluster heads (blocking by start time).
///
/// Two sessions can only be the same workout when their starts differ by at
/// most `W = max(maxStartDiff, (1 - minIou) / minIou * longest session)`:
/// from `inter >= minIou * union` follows `|startA - startB| <= union - inter
/// <= (1 - minIou) * union` and `union <= duration / minIou`. Heads are put in
/// buckets of width W, so a query reads three buckets. A policy with
/// `minIou <= 0` has no bound and uses one bucket (the old full scan).
class _HeadWindow {
  _HeadWindow._(this._width);

  factory _HeadWindow.of(List<ActivitySession> all, MergePolicy p) {
    var maxDurMs = 0;
    for (final s in all) {
      final d = s.endUtc.millisecondsSinceEpoch - s.startUtc.millisecondsSinceEpoch;
      if (d > maxDurMs) maxDurMs = d;
    }
    if (p.minIou <= 0) return _HeadWindow._(null);
    final iouSpan = p.minIou >= 1 ? 0.0 : (1 - p.minIou) / p.minIou * maxDurMs;
    final w = math.max(p.maxStartDiffSeconds * 1000.0, iouSpan) + 1000;
    return _HeadWindow._(w.isFinite && w < 1e15 ? w : null);
  }

  final double? _width;
  final Map<int, List<int>> _buckets = {};

  int _key(ActivitySession s) {
    final w = _width;
    return w == null ? 0 : (s.startUtc.millisecondsSinceEpoch / w).floor();
  }

  void addHead(int clusterIndex, ActivitySession s) {
    _buckets.putIfAbsent(_key(s), () => []).add(clusterIndex);
  }

  /// Cluster indices that may match [s], in creation order.
  List<int> candidates(ActivitySession s) {
    final k = _key(s);
    final out = <int>[];
    if (_width == null) {
      out.addAll(_buckets[0] ?? const []);
    } else {
      for (var b = k - 1; b <= k + 1; b++) {
        out.addAll(_buckets[b] ?? const []);
      }
      out.sort();
    }
    return out;
  }
}

bool _sameWorkout(ActivitySession a, ActivitySession b, MergePolicy p) {
  if (!a.sport.compatibleWith(b.sport)) return false;
  final as = a.startUtc.millisecondsSinceEpoch;
  final ae = a.endUtc.millisecondsSinceEpoch;
  final bs = b.startUtc.millisecondsSinceEpoch;
  final be = b.endUtc.millisecondsSinceEpoch;
  final inter = math.max(0, math.min(ae, be) - math.max(as, bs));
  final union = math.max(ae, be) - math.min(as, bs);
  final iouOk = union > 0 && inter >= p.minIou * union - _eps;
  final edgeOk = (as - bs).abs() <= p.maxStartDiffSeconds * 1000 &&
      (ae - be).abs() <= p.maxEndDiffSeconds * 1000;
  if (!(iouOk || edgeOk)) return false;

  final da = a.summary.distanceM;
  final db = b.summary.distanceM;
  if (da != null && db != null && da > 0 && db > 0) {
    final rel = (da - db).abs() / math.max(da, db);
    if (rel > p.maxDistanceRelDiff + _eps) return false;
  }

  final ga = a.streams[StreamKind.gps];
  final gb = b.streams[StreamKind.gps];
  if (ga != null && gb != null && !ga.isEmpty && !gb.isEmpty) {
    final mean = _meanGpsDistance(a, ga, b, gb);
    if (mean != null && mean > p.maxGpsMeanMeters + 1e-6) return false;
  }
  return true;
}

/// Mean distance between time-aligned GPS points (nearest sample in absolute
/// time); null when the tracks share no time.
double? _meanGpsDistance(
  ActivitySession a,
  SampleStream ga,
  ActivitySession b,
  SampleStream gb,
) {
  final aStart = a.startUtc.millisecondsSinceEpoch;
  final bStart = b.startUtc.millisecondsSinceEpoch;
  final bTimes = [for (final o in gb.offsetsMs) bStart + o];
  var sum = 0.0;
  var n = 0;
  for (var i = 0; i < ga.length; i++) {
    final t = aStart + ga.offsetsMs[i];
    final j = _nearest(bTimes, t);
    if ((bTimes[j] - t).abs() > _maxGpsPairGapMs) continue;
    sum += haversineMeters(ga.lats[i], ga.lons[i], gb.lats[j], gb.lons[j]);
    n++;
  }
  return n == 0 ? null : sum / n;
}

const int _maxGpsPairGapMs = 30000;

int _nearest(List<int> sortedTimes, int t) {
  var lo = 0;
  var hi = sortedTimes.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (sortedTimes[mid] < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0 && (sortedTimes[lo - 1] - t).abs() <= (sortedTimes[lo] - t).abs()) {
    return lo - 1;
  }
  return lo;
}

/// Great-circle distance in metres (mean Earth radius).
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h.toDouble())));
}

ActivitySession _mergeCluster(
  List<ActivitySession> members,
  MergePolicy policy,
  Set<String> echoes,
) {
  if (members.length == 1) return members.first;
  final primary = members.first;
  final durationMs = primary.durationMs;

  // User edits: the first (highest priority) holder of a key wins.
  final edits = <String, Object?>{};
  for (final m in members) {
    for (final e in m.userEdits.entries) {
      edits.putIfAbsent(e.key, () => e.value);
    }
  }

  // Streams: per kind, the best-ranked source covering >= 80 % of the session;
  // samples are never mixed within a kind.
  final streams = <StreamKind, SampleStream>{};
  final contributed = <String, Set<String>>{};
  for (final kind in StreamKind.values) {
    for (final m in members) {
      final s = m.streams[kind];
      if (s == null || s.isEmpty) continue;
      final skewMs =
          m.startUtc.millisecondsSinceEpoch - primary.startUtc.millisecondsSinceEpoch;
      if (!identical(m, primary) &&
          skewMs.abs() > policy.maxClockSkewSeconds * 1000) {
        continue;
      }
      final aligned = skewMs == 0 ? s : s.shifted(skewMs);
      if (aligned.coverage(durationMs) + _eps < policy.minStreamCoverage) {
        continue;
      }
      streams[kind] = aligned;
      contributed.putIfAbsent(s.sourceId, () => <String>{}).add(kind.name);
      break;
    }
  }

  // Summary: highest-priority non-null value, overridden by values recomputed
  // from the merged streams; disagreements above 10 % are noted.
  final notes = <String>{for (final m in members) ...m.mergeNotes};
  final fieldNames = ActivitySummary.empty.toFieldMap().keys.toList();
  final fields = <String, double?>{};
  for (final f in fieldNames) {
    double? chosen;
    final reported = <double>[];
    for (final m in members) {
      final v = m.summary.toFieldMap()[f];
      if (v != null) {
        reported.add(v);
        chosen ??= v;
      }
    }
    fields[f] = chosen;
    if (reported.length >= 2) {
      final hi = reported.reduce(math.max);
      final lo = reported.reduce(math.min);
      if (hi > 0 && (hi - lo) / hi > policy.summaryDisagreement + _eps) {
        notes.add('summaryDisagreement:$f');
      }
    }
  }
  fields.addAll(_summaryFromStreams(streams));
  for (final e in edits.entries) {
    if (fields.containsKey(e.key) && e.value is num) {
      fields[e.key] = (e.value as num).toDouble();
    }
  }

  for (final m in members) {
    if (echoes.contains(m.id)) {
      for (final p in m.provenance) {
        notes.add('echo:${p.sourceId}');
      }
    }
  }

  final laps = members
      .firstWhere((m) => m.laps.isNotEmpty, orElse: () => primary)
      .laps;

  // Provenance: every contributing record, originals kept.
  final recs = <String, SourceRecord>{};
  for (final m in members) {
    for (final p in m.provenance) {
      final key = '${p.sourceId}|${p.externalId ?? ''}|${p.importedAt.toIso8601String()}';
      final names = contributed[p.sourceId];
      recs.putIfAbsent(
        key,
        () => names == null
            ? p
            : p.withFields([...{...p.fieldsContributed, ...names}]..sort()),
      );
    }
  }
  final provenance = recs.values.toList()
    ..sort((a, b) {
      final r = policy.priorityOf(a).compareTo(policy.priorityOf(b));
      if (r != 0) return r;
      final s = a.sourceId.compareTo(b.sourceId);
      if (s != 0) return s;
      return (a.externalId ?? '').compareTo(b.externalId ?? '');
    });

  return ActivitySession(
    id: primary.id,
    sport: edits.containsKey('sport')
        ? SportType.parse(edits['sport'])
        : primary.sport,
    startUtc: primary.startUtc,
    endUtc: primary.endUtc,
    utcOffsetMinutes: primary.utcOffsetMinutes,
    movingTimeS: members
        .map((m) => m.movingTimeS)
        .firstWhere((v) => v != null, orElse: () => null),
    summary: ActivitySummary.fromFieldMap(fields),
    streams: streams,
    laps: laps,
    provenance: provenance,
    userEdits: edits,
    privacy: primary.privacy,
    schema: primary.schema,
    mergeNotes: notes.toList()..sort(),
    extras: primary.extras,
    formulaVersion: primary.formulaVersion,
    metricDefinitionVersion: primary.metricDefinitionVersion,
    thresholdPolicyVersion: primary.thresholdPolicyVersion,
    sourceTermsSnapshot: primary.sourceTermsSnapshot,
    explicitValues: primary.explicitValues,
    summaryOverrides: primary.summaryOverrides,
    userEditCount: primary.userEditCount,
    editHistory: primary.editHistory,
  );
}

/// Summary values derivable from the merged streams.
Map<String, double?> _summaryFromStreams(Map<StreamKind, SampleStream> s) {
  final out = <String, double?>{};
  double? mean(StreamKind k) {
    final v = s[k]?.values;
    if (v == null || v.isEmpty) return null;
    return v.reduce((a, b) => a + b) / v.length;
  }

  final hr = s[StreamKind.heartRate]?.values;
  if (hr != null && hr.isNotEmpty) {
    out['avgHrBpm'] = mean(StreamKind.heartRate);
    out['maxHrBpm'] = hr.reduce(math.max);
  }
  if (s[StreamKind.speed] != null) out['avgSpeedMps'] = mean(StreamKind.speed);
  if (s[StreamKind.cadence] != null) out['avgCadence'] = mean(StreamKind.cadence);
  if (s[StreamKind.power] != null) out['avgPowerW'] = mean(StreamKind.power);
  final gps = s[StreamKind.gps];
  if (gps != null && gps.length >= 2) {
    var d = 0.0;
    for (var i = 1; i < gps.length; i++) {
      d += haversineMeters(gps.lats[i - 1], gps.lons[i - 1], gps.lats[i], gps.lons[i]);
    }
    out['distanceM'] = d;
  }
  final alt = s[StreamKind.altitude]?.values;
  if (alt != null && alt.length >= 2) {
    var up = 0.0;
    var down = 0.0;
    for (var i = 1; i < alt.length; i++) {
      final diff = alt[i] - alt[i - 1];
      if (diff > 0) {
        up += diff;
      } else {
        down -= diff;
      }
    }
    out['ascentM'] = up;
    out['descentM'] = down;
  }
  return out;
}

/// Joins back-to-back sessions of ONE source (gap 0..`splitGapSeconds`) of the
/// same sport. Only used when `policy.joinSplits` is on.
List<ActivitySession> _joinSplits(List<ActivitySession> all, MergePolicy p) {
  final bySource = <String, List<ActivitySession>>{};
  final rest = <ActivitySession>[];
  for (final s in all) {
    final ids = {for (final r in s.provenance) r.sourceId};
    if (ids.length == 1) {
      bySource.putIfAbsent(ids.first, () => []).add(s);
    } else {
      rest.add(s);
    }
  }
  final out = [...rest];
  for (final list in bySource.values) {
    list.sort((a, b) {
      final t = a.startUtc.compareTo(b.startUtc);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
    var cur = list.first;
    for (var i = 1; i < list.length; i++) {
      final next = list[i];
      final gapMs = next.startUtc.millisecondsSinceEpoch -
          cur.endUtc.millisecondsSinceEpoch;
      if (next.sport == cur.sport && gapMs >= 0 && gapMs <= p.splitGapSeconds * 1000) {
        cur = _join(cur, next);
      } else {
        out.add(cur);
        cur = next;
      }
    }
    out.add(cur);
  }
  return out;
}

ActivitySession _join(ActivitySession a, ActivitySession b) {
  final shiftMs =
      b.startUtc.millisecondsSinceEpoch - a.startUtc.millisecondsSinceEpoch;
  final streams = <StreamKind, SampleStream>{};
  for (final k in StreamKind.values) {
    final sa = a.streams[k];
    final sb = b.streams[k];
    if (sa != null && sb != null) {
      final moved = sb.shifted(shiftMs);
      streams[k] = SampleStream.checked(
        kind: k,
        sourceId: sa.sourceId,
        offsetsMs: [...sa.offsetsMs, ...moved.offsetsMs],
        values: [...sa.values, ...moved.values],
        lats: [...sa.lats, ...moved.lats],
        lons: [...sa.lons, ...moved.lons],
        accuracies: sa.accuracies.length == sa.length &&
                moved.accuracies.length == moved.length
            ? [...sa.accuracies, ...moved.accuracies]
            : const [],
      );
    }
  }
  final fa = a.summary.toFieldMap();
  final fb = b.summary.toFieldMap();
  const additive = {
    'distanceM', 'ascentM', 'descentM', 'activeEnergyKcal', 'steps',
    'strokeCount', 'lapCount',
  };
  final merged = <String, double?>{};
  for (final k in fa.keys) {
    final x = fa[k];
    final y = fb[k];
    if (x == null || y == null) {
      merged[k] = x ?? y;
    } else if (additive.contains(k)) {
      merged[k] = x + y;
    } else if (k == 'maxHrBpm') {
      merged[k] = math.max(x, y);
    } else {
      final da = a.durationMs.toDouble();
      final db = b.durationMs.toDouble();
      merged[k] = da + db == 0 ? x : (x * da + y * db) / (da + db);
    }
  }
  final laps = <Lap>[
    ...a.laps,
    for (final l in b.laps)
      Lap(
        index: a.laps.length + l.index,
        kind: l.kind,
        startOffsetS: l.startOffsetS + shiftMs / 1000,
        durationS: l.durationS,
        distanceM: l.distanceM,
        avgHrBpm: l.avgHrBpm,
        strokeCount: l.strokeCount,
        strokeType: l.strokeType,
      ),
  ];
  return ActivitySession(
    id: a.id,
    sport: a.sport,
    startUtc: a.startUtc,
    endUtc: b.endUtc,
    utcOffsetMinutes: a.utcOffsetMinutes,
    movingTimeS: a.movingTimeS != null && b.movingTimeS != null
        ? a.movingTimeS! + b.movingTimeS!
        : (a.movingTimeS ?? b.movingTimeS),
    summary: ActivitySummary.fromFieldMap(merged),
    streams: streams,
    laps: laps,
    provenance: [...a.provenance, ...b.provenance],
    userEdits: {...b.userEdits, ...a.userEdits},
    privacy: a.privacy,
    schema: a.schema,
    mergeNotes: ([...{...a.mergeNotes, ...b.mergeNotes, 'joinedSplit'}]..sort()),
    extras: a.extras,
    formulaVersion: a.formulaVersion,
    metricDefinitionVersion: a.metricDefinitionVersion,
    thresholdPolicyVersion: a.thresholdPolicyVersion,
    sourceTermsSnapshot: a.sourceTermsSnapshot,
    explicitValues: a.explicitValues,
    summaryOverrides: a.summaryOverrides,
    userEditCount: a.userEditCount,
    editHistory: a.editHistory,
  );
}
