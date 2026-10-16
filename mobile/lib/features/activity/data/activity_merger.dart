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

MergeResult merge(List<ActivitySession> candidates, MergePolicy policy) {
  final echoes = _echoIds(candidates);
  int rankOf(ActivitySession s) {
    if (echoes.contains(s.id)) return policy.echoRank;
    var best = 50;
    var any = false;
    for (final p in s.provenance) {
      final r = policy.priorityOf(p);
      if (!any || r < best) best = r;
      any = true;
    }
    return best;
  }

  int compare(ActivitySession a, ActivitySession b) {
    final r = rankOf(a).compareTo(rankOf(b));
    if (r != 0) return r;
    final t = a.startUtc.compareTo(b.startUtc);
    if (t != 0) return t;
    return a.id.compareTo(b.id);
  }

  final sorted = [...candidates]..sort(compare);

  // Rule 1: exact duplicate (same sourceId + externalId) keeps the first.
  final seen = <String>{};
  final unique = <ActivitySession>[];
  for (final s in sorted) {
    final keys = [
      for (final p in s.provenance)
        if (p.dedupKey != null) p.dedupKey!,
    ];
    if (keys.any(seen.contains)) continue;
    seen.addAll(keys);
    unique.add(s);
  }

  // Rules 2-4: cluster against each cluster's best-ranked member.
  final clusters = <List<ActivitySession>>[];
  for (final s in unique) {
    List<ActivitySession>? home;
    for (final c in clusters) {
      if (_sameWorkout(c.first, s, policy)) {
        home = c;
        break;
      }
    }
    if (home == null) {
      clusters.add([s]);
    } else {
      home.add(s);
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
Set<String> _echoIds(List<ActivitySession> all) {
  final echoes = <String>{};
  for (final s in all) {
    if (s.provenance.isEmpty) continue;
    final rec = s.provenance.first;
    final app = rec.appPackage;
    if (rec.sourceKind != SourceKind.platformHealth || app == null) continue;
    for (final t in all) {
      if (identical(t, s)) continue;
      final holds = t.provenance.any((p) =>
          p.sourceKind != SourceKind.platformHealth &&
          (p.sourceId == app || p.appPackage == app));
      if (holds) {
        echoes.add(s.id);
        break;
      }
    }
  }
  return echoes;
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
