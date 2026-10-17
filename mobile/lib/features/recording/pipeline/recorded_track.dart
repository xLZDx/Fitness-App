/// A finished recording as the calculators see it, and the whole-session
/// calculation (S04-R-032 .. S04-R-034, design 3.7). Pure Dart, no Flutter
/// imports, no I/O.
///
/// The same input always gives the same output: there is no clock, no
/// randomness and no iteration over unordered collections.
library;

import 'elevation.dart';
import 'geo.dart';
import 'pace.dart';
import 'pipeline_types.dart';
import 'smoothing.dart';

/// The data a stop hands to the calculators: the raw kept fixes and the spans
/// that break or pause the track. The journal reader (lane R5) builds it from
/// the stored frames; the live pipeline builds it with [RecordedTrack.fromEvents].
class RecordedTrack {
  RecordedTrack({
    required List<PipelineSample> samples,
    required this.elapsedMs,
    List<TrackInterval> gaps = const [],
    List<TrackInterval> autoPauses = const [],
    List<TrackInterval> manualPauses = const [],
  })  : samples = List.unmodifiable(samples),
        gaps = List.unmodifiable(gaps),
        autoPauses = List.unmodifiable(autoPauses),
        manualPauses = List.unmodifiable(manualPauses);

  /// Builds a track from pipeline [events] (kept fixes, gaps, auto-pause
  /// spans) plus the manual pause spans, which the recorder owns.
  factory RecordedTrack.fromEvents({
    required Iterable<PipelineEvent> events,
    required int elapsedMs,
    List<TrackInterval> manualPauses = const [],
  }) {
    final samples = <PipelineSample>[];
    final gaps = <TrackInterval>[];
    final autos = <TrackInterval>[];
    int? gapStart;
    int? autoStart;
    for (final e in events) {
      switch (e) {
        case FixKept():
          samples.add(e.sample);
        case GapStarted():
          gapStart ??= e.offsetMs;
        case GapEnded():
          final s = gapStart;
          if (s != null) gaps.add(TrackInterval(s, e.offsetMs));
          gapStart = null;
        case AutoPaused():
          autoStart ??= e.offsetMs;
        case AutoResumed():
          final s = autoStart;
          if (s != null) autos.add(TrackInterval(s, e.offsetMs));
          autoStart = null;
        case FirstFixAcquired():
        case FixRejected():
          break;
      }
    }
    if (gapStart != null) gaps.add(TrackInterval(gapStart));
    if (autoStart != null) autos.add(TrackInterval(autoStart));
    return RecordedTrack(
      samples: samples,
      elapsedMs: elapsedMs,
      gaps: gaps,
      autoPauses: autos,
      manualPauses: manualPauses,
    );
  }

  /// Raw gate-passed fixes in journal order, offsets strictly increasing.
  final List<PipelineSample> samples;

  /// Recording length in ms: stop offset minus start offset.
  final int elapsedMs;

  /// Poor-accuracy gaps; an open gap runs to [elapsedMs].
  final List<TrackInterval> gaps;

  /// Auto-pause spans; an open span runs to [elapsedMs].
  final List<TrackInterval> autoPauses;

  /// Manual pause spans; an open span runs to [elapsedMs].
  final List<TrackInterval> manualPauses;
}

/// The calculated values of one recording. Undefined values are null.
class SessionMetrics {
  const SessionMetrics({
    required this.distanceM,
    required this.movingTimeS,
    required this.elapsedS,
    required this.ascentM,
    required this.descentM,
    required this.avgSpeedMps,
    required this.avgPaceSecPerKm,
    required this.segmentCount,
    required this.smoothingId,
  });

  final double distanceM;
  final double movingTimeS;
  final double elapsedS;
  final double? ascentM;
  final double? descentM;
  final double? avgSpeedMps;
  final double? avgPaceSecPerKm;

  /// Number of continuous segments that contributed distance.
  final int segmentCount;
  final String smoothingId;
}

/// Computes [SessionMetrics] over a whole [RecordedTrack].
///
/// Distance is the sum of great-circle segments between consecutive SMOOTHED
/// kept fixes inside one moving segment; no distance across a gap, a manual
/// pause or an auto-pause span (the step into and out of a span is excluded;
/// the fixes that mark the span ends belong to the moving segments next to
/// it). Fixes strictly inside a pause are ignored by distance and elevation.
/// Moving time is elapsed minus manual and auto pause time. Gap time counts as
/// moving time (design 3.4, D-8).
class SessionCalculator {
  const SessionCalculator({
    this.smoothing = const WeightedMovingAverageSmoothing(),
  });

  final SmoothingStrategy smoothing;

  SessionMetrics compute(RecordedTrack track) {
    final elapsed = track.elapsedMs < 0 ? 0 : track.elapsedMs;
    final pauses = _union([...track.autoPauses, ...track.manualPauses], elapsed);
    final breaks = _union(
        [...track.autoPauses, ...track.manualPauses, ...track.gaps], elapsed);

    var pausedMs = 0;
    for (final p in pauses) {
      pausedMs += p.endMs! - p.startMs;
    }
    final movingS = (elapsed - pausedMs) / 1000.0;

    // Drop fixes strictly inside a pause.
    final kept = <PipelineSample>[];
    var pi = 0;
    for (final s in track.samples) {
      while (pi < pauses.length && pauses[pi].endMs! <= s.offsetMs) {
        pi++;
      }
      final inside = pi < pauses.length &&
          pauses[pi].startMs < s.offsetMs &&
          s.offsetMs < pauses[pi].endMs!;
      if (!inside) kept.add(s);
    }

    // Split into continuous segments and sum smoothed distance.
    var distance = 0.0;
    var segments = 0;
    final elevation = ElevationAccumulator();
    var bi = 0;
    var segment = <PipelineSample>[];
    void closeSegment() {
      if (segment.isEmpty) return;
      final smoothed = smoothing.smooth(segment);
      for (var i = 1; i < smoothed.length; i++) {
        distance += haversineM(smoothed[i - 1].lat, smoothed[i - 1].lon,
            smoothed[i].lat, smoothed[i].lon);
      }
      if (smoothed.length > 1) segments++;
      segment = <PipelineSample>[];
    }

    PipelineSample? prev;
    for (final s in kept) {
      elevation.add(s.offsetMs, s.altitudeM);
      if (prev != null) {
        while (bi < breaks.length && breaks[bi].endMs! <= prev.offsetMs) {
          bi++;
        }
        final broken =
            bi < breaks.length && breaks[bi].startMs < s.offsetMs;
        if (broken) closeSegment();
      }
      segment.add(s);
      prev = s;
    }
    closeSegment();

    return SessionMetrics(
      distanceM: distance,
      movingTimeS: movingS,
      elapsedS: elapsed / 1000.0,
      ascentM: elevation.ascentM,
      descentM: elevation.descentM,
      avgSpeedMps: averageSpeedMps(distance, movingS),
      avgPaceSecPerKm: averagePaceSecPerKm(distance, movingS),
      segmentCount: segments,
      smoothingId: smoothing.id,
    );
  }

  /// Sorted, disjoint, closed intervals clipped to `[0, elapsedMs]`. Open
  /// intervals end at [elapsedMs]; empty ones are dropped; touching and
  /// overlapping ones are merged.
  static List<TrackInterval> _union(List<TrackInterval> input, int elapsedMs) {
    final clipped = <TrackInterval>[];
    for (final i in input) {
      final s = i.startMs < 0 ? 0 : i.startMs;
      var e = i.endMs ?? elapsedMs;
      if (e > elapsedMs) e = elapsedMs;
      if (e > s) clipped.add(TrackInterval(s, e));
    }
    clipped.sort((a, b) {
      final c = a.startMs.compareTo(b.startMs);
      return c != 0 ? c : a.endMs!.compareTo(b.endMs!);
    });
    final out = <TrackInterval>[];
    for (final i in clipped) {
      if (out.isNotEmpty && i.startMs <= out.last.endMs!) {
        final last = out.removeLast();
        out.add(TrackInterval(
            last.startMs, i.endMs! > last.endMs! ? i.endMs : last.endMs));
      } else {
        out.add(i);
      }
    }
    return out;
  }
}
