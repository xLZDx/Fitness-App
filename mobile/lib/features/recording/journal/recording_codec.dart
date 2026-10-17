/// Pure frame codec and whole-recording analysis of the recording journal (S04
/// design 4.2, 4.5, S04-31). No file I/O. [analyseRecording] is a top-level
/// function that runs in a worker isolate (`HeavyWorkRunner`); it never throws
/// and never returns an error message: damage is a fixed code (S04-R-052).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../activity/repository/journal_cipher.dart';
import '../pipeline/pipeline_types.dart';
import '../pipeline/recorded_track.dart';
import '../pipeline/summary_builder.dart';

const int kFrameHeaderBytes = 8;
const int kMaxFrameBytes = 4 * 1024 * 1024;
const int kFramesPerSegment = 5000;

/// Content-free damage codes of a scan.
class Damage {
  static const badFrame = 'badFrame';
  static const badSchema = 'badSchema';
  static const missingSegment = 'missingSegment';
  static const counterGap = 'counterGap';
  static const unannouncedTear = 'unannouncedTear';
  static const breakMismatch = 'breakMismatch';
  static const sealedMismatch = 'sealedMismatch';
  static const worker = 'worker';

  /// NOT damage: the recording could not be read right now (I/O error, key
  /// store, worker failure). Retryable; never quarantined (S04 review C3).
  static const unavailable = 'unavailable';

  /// True for a confirmed damage code (authentication, CRC, schema, ...).
  static bool isConfirmed(String? code) =>
      code != null && code != unavailable;
}

Uint32List _crcTable() {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}

final Uint32List _table = _crcTable();

int crc32(Uint8List data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// length (4, big endian) + CRC-32 of the sealed payload (4) + sealed payload.
Uint8List encodeFrame(JournalCipher cipher, Uint8List plain) {
  final sealed = cipher.seal(plain);
  final out = Uint8List(kFrameHeaderBytes + sealed.length);
  final bd = ByteData.sublistView(out);
  bd.setUint32(0, sealed.length);
  bd.setUint32(4, crc32(sealed));
  out.setRange(kFrameHeaderBytes, out.length, sealed);
  return out;
}

Uint8List _json(Map<String, Object?> m) =>
    Uint8List.fromList(utf8.encode(jsonEncode(m)));

/// Plain payload of a `samples` frame (columns; al/sp may be null).
Uint8List samplesPayload(
    int counter, List<PipelineSample> s, GateCounters rj) {
  return _json({
    'k': 's',
    'n': counter,
    't': [for (final x in s) x.offsetMs],
    'la': [for (final x in s) x.lat],
    'lo': [for (final x in s) x.lon],
    'ac': [for (final x in s) x.accuracyM],
    'al': [for (final x in s) x.altitudeM],
    'sp': [for (final x in s) x.speedMps],
    'rj': [rj.accuracy, rj.speed, rj.invalid, rj.nonMonotonic],
  });
}

/// Plain payload of an `event` frame. [prevSegment]/[prevFrames] only for
/// `segmentBreak`.
Uint8List eventPayload(int counter, String kind, int offsetMs,
    {int? prevSegment, int? prevFrames}) {
  return _json({
    'k': 'e',
    'n': counter,
    'e': kind,
    'o': offsetMs,
    if (prevSegment != null) 'ps': prevSegment,
    if (prevFrames != null) 'pf': prevFrames,
  });
}

const Set<String> _eventKinds = {
  'pause', 'resume', 'autoPause', 'autoResume', 'gapStart', 'gapEnd',
  'permissionRevoked', 'batteryCritical', 'stoppedBattery', 'stoppedStorage',
  'stoppedAccount', 'stoppedConsent', 'stoppedCap', 'restart', 'segmentBreak',
};

class AnalyseJob {
  const AnalyseJob({
    required this.segNumbers,
    required this.segBytes,
    required this.key,
    this.wantTrack = false,
    this.wantMetrics = false,
    this.startUtcMs = 0,
    this.elapsedOverrideMs,
  });

  final List<int> segNumbers;
  final List<Uint8List> segBytes;
  final Uint8List key;
  final bool wantTrack;
  final bool wantMetrics;
  final int startUtcMs;
  final int? elapsedOverrideMs;
}

class AnalyseResult {
  AnalyseResult({
    this.damage,
    this.sampleCount = 0,
    this.frameCount = 0,
    this.lastOffsetMs = 0,
    this.lastSegment = 0,
    this.lastSegmentFrames = 0,
    this.lastEvent,
    this.restartCount = 0,
    this.offsets,
    this.lats,
    this.lons,
    this.accuracies,
    this.altOffsets,
    this.alts,
    this.spdOffsets,
    this.spds,
    this.elapsedMs = 0,
    this.metricsOk = false,
    this.distanceM = 0,
    this.movingTimeS = 0,
    this.ascentM,
    this.descentM,
    this.avgSpeedMps,
    this.formulaVersion = '',
    this.metricDefinitionVersion = '',
    this.flagged = const [],
  });

  /// Null = readable. Otherwise a [Damage] code.
  final String? damage;
  final int sampleCount;
  final int frameCount;
  final int lastOffsetMs;
  final int lastSegment;
  final int lastSegmentFrames;
  final String? lastEvent;
  final int restartCount;
  final List<int>? offsets;
  final List<double>? lats;
  final List<double>? lons;
  final List<double>? accuracies;
  final List<int>? altOffsets;
  final List<double>? alts;
  final List<int>? spdOffsets;
  final List<double>? spds;
  final int elapsedMs;
  final bool metricsOk;
  final double distanceM;
  final double movingTimeS;
  final double? ascentM;
  final double? descentM;
  final double? avgSpeedMps;
  final String formulaVersion;
  final String metricDefinitionVersion;
  final List<String> flagged;

  bool get readable => damage == null;
}

class _Seg {
  int frames = 0;
  bool torn = false;
}

/// Decodes, verifies and (optionally) calculates a whole recording. Never
/// throws; the result carries a fixed damage code instead.
AnalyseResult analyseRecording(AnalyseJob job) {
  try {
    return _analyse(job);
  } catch (_) {
    return AnalyseResult(damage: Damage.worker);
  }
}

AnalyseResult _analyse(AnalyseJob job) {
  final cipher = AesGcmJournalCipher(job.key);
  final nums = job.segNumbers;
  for (var i = 0; i < nums.length; i++) {
    if (nums[i] != i + 1) return AnalyseResult(damage: Damage.missingSegment);
  }
  final samples = <PipelineSample>[];
  final gaps = <TrackInterval>[];
  final autos = <TrackInterval>[];
  final manuals = <TrackInterval>[];
  int? gs, as_, ms, restartAt;
  var counter = 0;
  var lastOffset = 0;
  var lastSampleOffset = -1;
  var restarts = 0;
  String? lastEvent;
  final segs = <_Seg>[];

  for (var si = 0; si < job.segBytes.length; si++) {
    final bytes = job.segBytes[si];
    final bd = ByteData.sublistView(bytes);
    final seg = _Seg();
    segs.add(seg);
    var pos = 0;
    var first = true;
    while (pos < bytes.length) {
      if (bytes.length - pos < kFrameHeaderBytes) {
        seg.torn = true;
        break;
      }
      final len = bd.getUint32(pos);
      final crc = bd.getUint32(pos + 4);
      if (len > kMaxFrameBytes || pos + kFrameHeaderBytes + len > bytes.length) {
        seg.torn = true;
        break;
      }
      final end = pos + kFrameHeaderBytes + len;
      final sealed =
          Uint8List.sublistView(bytes, pos + kFrameHeaderBytes, end);
      Map<String, dynamic>? m;
      if (crc32(sealed) == crc) {
        try {
          final d = jsonDecode(utf8.decode(cipher.open(sealed)));
          if (d is Map<String, dynamic>) m = d;
        } catch (_) {}
      }
      if (m == null) {
        if (end == bytes.length) {
          seg.torn = true;
          break;
        }
        return AnalyseResult(damage: Damage.badFrame);
      }
      final n = m['n'];
      if (n is! int) return AnalyseResult(damage: Damage.badSchema);
      if (n <= counter) {
        pos = end; // duplicate counter: the first occurrence wins
        continue;
      }
      if (n != counter + 1) return AnalyseResult(damage: Damage.counterGap);
      final kind = m['k'];
      if (kind == 's') {
        if (m.length != 9) return AnalyseResult(damage: Damage.badSchema);
        final t = m['t'], la = m['la'], lo = m['lo'];
        final ac = m['ac'], al = m['al'], sp = m['sp'];
        if (t is! List || la is! List || lo is! List || ac is! List ||
            al is! List || sp is! List || m['rj'] is! List) {
          return AnalyseResult(damage: Damage.badSchema);
        }
        if (t.isEmpty ||
            la.length != t.length || lo.length != t.length ||
            ac.length != t.length || al.length != t.length ||
            sp.length != t.length) {
          return AnalyseResult(damage: Damage.badSchema);
        }
        for (var i = 0; i < t.length; i++) {
          final ti = t[i], a = la[i], o = lo[i];
          if (ti is! int || a is! num || o is! num || ti <= lastSampleOffset) {
            return AnalyseResult(damage: Damage.badSchema);
          }
          if ((ac[i] != null && ac[i] is! num) ||
              (al[i] != null && al[i] is! num) ||
              (sp[i] != null && sp[i] is! num)) {
            return AnalyseResult(damage: Damage.badSchema);
          }
          lastSampleOffset = ti;
          samples.add(PipelineSample(
            offsetMs: ti,
            lat: a.toDouble(),
            lon: o.toDouble(),
            accuracyM: (ac[i] as num?)?.toDouble(),
            altitudeM: (al[i] as num?)?.toDouble(),
            speedMps: (sp[i] as num?)?.toDouble(),
          ));
        }
        if (lastSampleOffset > lastOffset) lastOffset = lastSampleOffset;
      } else if (kind == 'e') {
        final e = m['e'], o = m['o'];
        final ps = m['ps'], pf = m['pf'];
        final expected = 4 + (ps != null ? 1 : 0) + (pf != null ? 1 : 0);
        if (m.length != expected ||
            e is! String || !_eventKinds.contains(e) || o is! int || o < 0) {
          return AnalyseResult(damage: Damage.badSchema);
        }
        if (e == 'segmentBreak') {
          if (ps is! int || pf is! int || si == 0 || ps != si ||
              segs[si - 1].frames != pf) {
            return AnalyseResult(damage: Damage.breakMismatch);
          }
        } else if (ps != null || pf != null) {
          return AnalyseResult(damage: Damage.badSchema);
        }
        if (o > lastOffset) lastOffset = o;
        lastEvent = e;
        switch (e) {
          case 'pause':
            ms ??= o;
          case 'resume':
            if (ms != null) manuals.add(TrackInterval(ms, o));
            ms = null;
          case 'autoPause':
            as_ ??= o;
          case 'autoResume':
            if (as_ != null) autos.add(TrackInterval(as_, o));
            as_ = null;
          case 'gapStart':
            gs ??= o;
          case 'gapEnd':
            if (gs != null) {
              final iv = TrackInterval(gs, o);
              if (restartAt != null && o == restartAt) {
                manuals.add(iv);
              } else {
                gaps.add(iv);
              }
            }
            gs = null;
          case 'restart':
            restarts++;
            restartAt = o;
            if (ms != null) manuals.add(TrackInterval(ms, o));
            if (as_ != null) autos.add(TrackInterval(as_, o));
            ms = null;
            as_ = null;
          default:
            break;
        }
      } else {
        return AnalyseResult(damage: Damage.badSchema);
      }
      if (first && si > 0 && kind == 'e' && m['e'] != 'segmentBreak') {
        // A segment after a torn end must open with a break (checked below).
      }
      first = false;
      counter = n;
      seg.frames++;
      pos = end;
    }
    // A torn end of an earlier segment needs the announcing break in the next.
    if (si > 0 && segs[si - 1].torn) {
      // Verified when the break frame was read: frames > 0 and first was break.
      // If segment si has no break as first frame it is an unannounced tear.
      if (!_startsWithBreak(job.segBytes[si], cipher)) {
        return AnalyseResult(damage: Damage.unannouncedTear);
      }
    }
  }
  if (job.segBytes.length > 1) {
    // The last earlier segment may be torn only when announced (checked in the
    // loop for every following segment).
  }
  if (ms != null) manuals.add(TrackInterval(ms));
  if (as_ != null) autos.add(TrackInterval(as_));
  if (gs != null) gaps.add(TrackInterval(gs));
  final last = segs.isEmpty ? _Seg() : segs.last;
  final elapsed = job.elapsedOverrideMs != null && job.elapsedOverrideMs! > lastOffset
      ? job.elapsedOverrideMs!
      : lastOffset;

  List<int>? offs, ao, so;
  List<double>? la, lo, ac, al, sp;
  if (job.wantTrack) {
    offs = [for (final s in samples) s.offsetMs];
    la = [for (final s in samples) s.lat];
    lo = [for (final s in samples) s.lon];
    ac = [for (final s in samples) s.accuracyM ?? 30.0];
    ao = [for (final s in samples) if (s.altitudeM != null) s.offsetMs];
    al = [for (final s in samples) if (s.altitudeM != null) s.altitudeM!];
    so = [for (final s in samples) if (s.speedMps != null) s.offsetMs];
    sp = [for (final s in samples) if (s.speedMps != null) s.speedMps!];
  }
  var ok = false;
  var dist = 0.0, mov = 0.0;
  double? asc, desc, avg;
  var formula = '', metricV = '';
  var flagged = const <String>[];
  if (job.wantMetrics) {
    final track = RecordedTrack(
      samples: samples,
      elapsedMs: elapsed,
      gaps: gaps,
      autoPauses: autos,
      manualPauses: manuals,
    );
    final r = buildSessionSummary(
      track: track,
      startUtc: DateTime.fromMillisecondsSinceEpoch(job.startUtcMs, isUtc: true),
    );
    ok = !r.flagged;
    dist = r.metrics.distanceM;
    mov = r.movingTimeS;
    asc = r.metrics.ascentM;
    desc = r.metrics.descentM;
    avg = r.metrics.avgSpeedMps;
    formula = r.formulaVersion;
    metricV = r.metricDefinitionVersion;
    flagged = r.flaggedFields;
  }
  return AnalyseResult(
    sampleCount: samples.length,
    frameCount: counter,
    lastOffsetMs: lastOffset,
    lastSegment: segs.length,
    lastSegmentFrames: last.frames,
    lastEvent: lastEvent,
    restartCount: restarts,
    offsets: offs,
    lats: la,
    lons: lo,
    accuracies: ac,
    altOffsets: ao,
    alts: al,
    spdOffsets: so,
    spds: sp,
    elapsedMs: elapsed,
    metricsOk: ok,
    distanceM: dist,
    movingTimeS: mov,
    ascentM: asc,
    descentM: desc,
    avgSpeedMps: avg,
    formulaVersion: formula,
    metricDefinitionVersion: metricV,
    flagged: flagged,
  );
}

bool _startsWithBreak(Uint8List bytes, JournalCipher cipher) {
  try {
    if (bytes.length < kFrameHeaderBytes) return false;
    final bd = ByteData.sublistView(bytes);
    final len = bd.getUint32(0);
    if (kFrameHeaderBytes + len > bytes.length) return false;
    final d = jsonDecode(utf8.decode(
        cipher.open(Uint8List.sublistView(bytes, kFrameHeaderBytes, kFrameHeaderBytes + len))));
    return d is Map && d['k'] == 'e' && d['e'] == 'segmentBreak';
  } catch (_) {
    return false;
  }
}

/// Valid-frame count of ONE segment (used by the writer to name the count in a
/// `segmentBreak` after a write error or a resume). Pure.
({int frames, int lastCounter}) countValidFrames(
    JournalCipher cipher, Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  var pos = 0, frames = 0, last = 0;
  while (bytes.length - pos >= kFrameHeaderBytes) {
    final len = bd.getUint32(pos);
    if (len > kMaxFrameBytes || pos + kFrameHeaderBytes + len > bytes.length) break;
    final end = pos + kFrameHeaderBytes + len;
    final sealed = Uint8List.sublistView(bytes, pos + kFrameHeaderBytes, end);
    if (crc32(sealed) != bd.getUint32(pos + 4)) break;
    try {
      final d = jsonDecode(utf8.decode(cipher.open(sealed)));
      final n = d is Map ? d['n'] : null;
      if (n is! int) break;
      if (n > last) last = n;
    } catch (_) {
      break;
    }
    frames++;
    pos = end;
  }
  return (frames: frames, lastCounter: last);
}
