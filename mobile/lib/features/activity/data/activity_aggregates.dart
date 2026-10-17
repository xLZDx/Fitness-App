/// Pure, null-aware aggregation behind the Today, This week and Progress
/// dashboards (S03-13, design 3.1 to 3.5). No Flutter, no I/O, no clock: every
/// function takes `now` and an optional zone function.
///
/// Missing is missing: a metric that is null is never summed as zero and never
/// counted as contributing; a reported zero is a value.
library;

import '../../progress/data/progress_stats.dart'
    show ZoneFn, localDayOf, mondayWeekStartOf;
import '../repository/journal_models.dart' show JournalSyncState;
import 'activity_session.dart';
import 'source_kind.dart';
import 'sport_type.dart';
import 'summary_projection.dart';

export '../../progress/data/progress_stats.dart' show ZoneFn;

/// The six sport groups of the dashboards. `strength` has no group.
enum SportGroup { walkHike, run, ride, swim, row, other }

/// Fixed display order of the groups.
const List<SportGroup> kSportGroupOrder = [
  SportGroup.walkHike,
  SportGroup.run,
  SportGroup.ride,
  SportGroup.swim,
  SportGroup.row,
  SportGroup.other,
];

/// The group of [sport]; null for `strength` (never shown). Exhaustive: a new
/// [SportType] fails to compile until it is placed.
SportGroup? groupOf(SportType sport) => switch (sport) {
      SportType.walking || SportType.hiking => SportGroup.walkHike,
      SportType.running || SportType.trailRunning => SportGroup.run,
      SportType.cycling ||
      SportType.indoorCycling ||
      SportType.mountainBiking =>
        SportGroup.ride,
      SportType.swimmingPool || SportType.swimmingOpenWater => SportGroup.swim,
      SportType.rowing => SportGroup.row,
      SportType.other => SportGroup.other,
      SportType.strength => null,
    };

/// A small immutable view of one session. Streams are never part of it.
class SessionDigest {
  const SessionDigest({
    required this.id,
    required this.startUtc,
    required this.sportGroup,
    required this.syncState,
    required this.streamLost,
    this.movingTimeS,
    this.distanceM,
    this.primarySourceId,
    this.primarySourceKind,
    this.sourceCount = 0,
  });

  final String id;
  final DateTime startUtc;
  final SportGroup sportGroup;

  /// Effective moving time in seconds; null = missing (never zero).
  final double? movingTimeS;

  /// Effective distance in metres; null = missing (never zero).
  final double? distanceM;

  /// First provenance record (the contract's "primary source"); null = none.
  final String? primarySourceId;
  final SourceKind? primarySourceKind;

  /// Number of provenance records (for the "+k sources" suffix).
  final int sourceCount;
  final JournalSyncState syncState;
  final bool streamLost;
}

double? _value(Map<String, double?> eff, String key) {
  final v = eff[key];
  return v != null && v.isFinite ? v : null;
}

/// Builds the digest of [s]. Returns null for a `strength` session (dropped).
/// Throws when the session cannot be projected: the caller counts that session
/// as unreadable and never as "no data" (RV-11). Metric values come from
/// `SummaryProjection.effective`, never from raw summary fields.
SessionDigest? buildDigest(
  ActivitySession s, {
  JournalSyncState syncState = JournalSyncState.pending,
  bool streamLost = false,
}) {
  final group = groupOf(s.sport);
  if (group == null) return null;
  final eff = SummaryProjection.effective(s);
  final first = s.provenance.isEmpty ? null : s.provenance.first;
  return SessionDigest(
    id: s.id,
    startUtc: s.startUtc,
    sportGroup: group,
    movingTimeS: _value(eff, 'movingTimeS'),
    distanceM: _value(eff, 'distanceM'),
    primarySourceId: first?.sourceId,
    primarySourceKind: first?.sourceKind,
    sourceCount: s.provenance.length,
    syncState: syncState,
    streamLost: streamLost,
  );
}

int _newestFirst(SessionDigest a, SessionDigest b) {
  final c = b.startUtc.compareTo(a.startUtc);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Digests whose LOCAL start date equals the local date of [now], newest first
/// (ties by id). Calendar dates, not 24-hour arithmetic.
List<SessionDigest> todaySessions(
  Iterable<SessionDigest> digests,
  DateTime now, {
  ZoneFn? zone,
}) {
  final today = localDayOf(now, zone: zone);
  return [
    for (final d in digests)
      if (localDayOf(d.startUtc, zone: zone) == today) d,
  ]..sort(_newestFirst);
}

/// The [limit] latest digests, newest first (ties by id).
List<SessionDigest> recentSessions(Iterable<SessionDigest> digests,
    {int limit = 5}) {
  final all = [...digests]..sort(_newestFirst);
  return all.length <= limit ? all : all.sublist(0, limit);
}

/// One sport-group tile of the current week.
class WeekTile {
  const WeekTile({
    required this.group,
    required this.sessions,
    required this.timeSeconds,
    required this.timeContributing,
    required this.distanceM,
    required this.distanceContributing,
  });

  final SportGroup group;

  /// Number of sessions of the group in the week (each counted once).
  final int sessions;

  /// Sum of the non-null moving times; meaningful only when
  /// [timeContributing] is above zero.
  final double timeSeconds;

  /// How many of [sessions] had a time value.
  final int timeContributing;

  /// Sum of the non-null distances (a reported 0 is a value).
  final double distanceM;
  final int distanceContributing;

  bool get hasTime => timeContributing > 0;
  bool get hasDistance => distanceContributing > 0;

  /// True when the "Time from k of n sessions" hint applies.
  bool get timePartial => hasTime && timeContributing < sessions;
  bool get distancePartial => hasDistance && distanceContributing < sessions;
}

/// The week panel: tiles only for groups with at least one session in the week
/// (fixed group order) plus whether any session exists outside the week.
class WeekAggregate {
  const WeekAggregate({required this.tiles, required this.hasOutsideWeek});

  static const WeekAggregate empty =
      WeekAggregate(tiles: [], hasOutsideWeek: false);

  final List<WeekTile> tiles;

  /// Sessions exist, but not in this week ("no data this week, older data").
  final bool hasOutsideWeek;

  bool get hasWeekData => tiles.isNotEmpty;
}

/// Aggregates the week (Monday 00:00 local inclusive to the next Monday
/// exclusive) that contains [now]. Same rule as `deriveProgress`.
WeekAggregate aggregateWeek(
  Iterable<SessionDigest> digests,
  DateTime now, {
  ZoneFn? zone,
}) {
  final week = mondayWeekStartOf(now, zone: zone);
  final sessions = <SportGroup, int>{};
  final time = <SportGroup, double>{};
  final timeN = <SportGroup, int>{};
  final dist = <SportGroup, double>{};
  final distN = <SportGroup, int>{};
  var outside = false;
  for (final d in digests) {
    if (mondayWeekStartOf(d.startUtc, zone: zone) != week) {
      outside = true;
      continue;
    }
    final g = d.sportGroup;
    sessions[g] = (sessions[g] ?? 0) + 1;
    final t = d.movingTimeS;
    if (t != null) {
      time[g] = (time[g] ?? 0) + t;
      timeN[g] = (timeN[g] ?? 0) + 1;
    }
    final m = d.distanceM;
    if (m != null) {
      dist[g] = (dist[g] ?? 0) + m;
      distN[g] = (distN[g] ?? 0) + 1;
    }
  }
  return WeekAggregate(
    tiles: [
      for (final g in kSportGroupOrder)
        if ((sessions[g] ?? 0) > 0)
          WeekTile(
            group: g,
            sessions: sessions[g]!,
            timeSeconds: time[g] ?? 0,
            timeContributing: timeN[g] ?? 0,
            distanceM: dist[g] ?? 0,
            distanceContributing: distN[g] ?? 0,
          ),
    ],
    hasOutsideWeek: outside,
  );
}

/// Which label a source gets (contract 8.1). The UI maps a key to its ARB text.
enum SourceLabelKey {
  app,
  healthConnect,
  healthKit,
  watch,
  sensor,
  healthPlatform,
  service,
  companionApp,
  fileImport,
  unknown,
}

/// The label of a row's source plus the number of ADDITIONAL sources
/// ("+k sources" when [moreSources] is above zero).
class SourceLabel {
  const SourceLabel(this.key, {this.moreSources = 0});

  final SourceLabelKey key;
  final int moreSources;
}

/// Label of the FIRST provenance record (current behaviour; the priority after
/// a merge is not guaranteed). By `sourceId` first, then by `SourceKind`; no
/// record gives [SourceLabelKey.unknown].
SourceLabel sourceLabelOf(SessionDigest d) {
  final id = d.primarySourceId;
  final kind = d.primarySourceKind;
  if (id == null || kind == null) {
    return const SourceLabel(SourceLabelKey.unknown);
  }
  final more = d.sourceCount > 1 ? d.sourceCount - 1 : 0;
  return SourceLabel(sourceLabelKeyOf(id, kind), moreSources: more);
}

/// The label key of one provenance record.
SourceLabelKey sourceLabelKeyOf(String sourceId, SourceKind kind) {
  switch (sourceId) {
    case 'app':
      return SourceLabelKey.app;
    case 'health_connect':
      return SourceLabelKey.healthConnect;
    case 'healthkit':
      return SourceLabelKey.healthKit;
    case 'wear_os':
      return SourceLabelKey.watch;
  }
  if (sourceId.startsWith('ble_')) return SourceLabelKey.sensor;
  return switch (kind) {
    SourceKind.platformHealth => SourceLabelKey.healthPlatform,
    SourceKind.bleSensor => SourceLabelKey.sensor,
    SourceKind.vendorCloud => SourceLabelKey.service,
    SourceKind.companionApp => SourceLabelKey.companionApp,
    SourceKind.fileImport => SourceLabelKey.fileImport,
  };
}

/// Whether the value of [field] for [session] is an estimate. No value shown in
/// S03 is an estimate; the "Estimate" marker is a component capability only.
bool isEstimate(String field, ActivitySession session) => false;
