/// Minimal FIT (Flexible and Interoperable Data Transfer) export of an
/// [ActivitySession] (S02 design 7). A pure function returning bytes: no file
/// writing, no sharing, no dart:io, no Flutter.
///
/// Layout: 14-byte header (with its own CRC) -> definition + data messages ->
/// 2-byte file CRC over everything before it. Messages, in this order:
/// `file_id`, `record` (one per timeline instant), `lap` (the session's laps, or
/// one lap spanning the session when it has none), `session`.
///
/// Timeline of the `record` messages: the GPS offsets when the session has a GPS
/// stream, otherwise the sorted union of the offsets of every other stream. Other
/// streams are attached to a record when a sample lies within 5 s. Heart rate is
/// included when present locally (the user's own data on their own device,
/// design 7); route trimming does not apply to a full owner export.
///
/// Every message defines all its fields; an unknown value is written as the FIT
/// invalid value of its base type, so each message type has one fixed definition.
library;

import 'dart:typed_data';

import 'activity_merger.dart' show haversineMeters;
import 'activity_session.dart';
import 'export_sampling.dart';
import 'lap.dart';
import 'sample_stream.dart';
import 'sport_type.dart';

/// FIT epoch (1989-12-31T00:00:00Z) as Unix seconds.
const int kFitEpochUnixSeconds = 631065600;

/// Global message numbers used.
const int kFitMsgFileId = 0;
const int kFitMsgSession = 18;
const int kFitMsgLap = 19;
const int kFitMsgRecord = 20;

/// CRC-16 of the FIT SDK (nibble table). Public so a decoder written for tests
/// may reuse it or be proven against it.
int fitCrc16(List<int> bytes, [int start = 0, int? end]) {
  const table = <int>[
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, //
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];
  var crc = 0;
  final stop = end ?? bytes.length;
  for (var i = start; i < stop; i++) {
    final byte = bytes[i] & 0xFF;
    var tmp = table[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ table[byte & 0xF];
    tmp = table[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ table[(byte >> 4) & 0xF];
  }
  return crc;
}

// FIT base types (type byte) and invalid values.
const int _tEnum = 0x00;
const int _tSint8 = 0x01;
const int _tUint8 = 0x02;
const int _tUint16 = 0x84;
const int _tSint32 = 0x85;
const int _tUint32 = 0x86;

class _Field {
  const _Field(this.num, this.size, this.type);
  final int num;
  final int size;
  final int type;
}

class _Out {
  final List<int> bytes = <int>[];

  void u8(int v) => bytes.add(v & 0xFF);
  void u16(int v) {
    u8(v);
    u8(v >> 8);
  }

  void u32(int v) {
    u16(v & 0xFFFF);
    u16((v >> 16) & 0xFFFF);
  }

  /// Definition message for [local] (little endian, no developer fields).
  void definition(int local, int globalNum, List<_Field> fields) {
    u8(0x40 | (local & 0x0F));
    u8(0); // reserved
    u8(0); // architecture: little endian
    u16(globalNum);
    u8(fields.length);
    for (final f in fields) {
      u8(f.num);
      u8(f.size);
      u8(f.type);
    }
  }

  void dataHeader(int local) => u8(local & 0x0F);
}

int? _clampInt(num? v, int min, int max) {
  if (v == null || !v.isFinite) return null;
  final r = v.round();
  return r < min ? min : (r > max ? max : r);
}

class FitEncoder {
  const FitEncoder._();

  static const int profileVersion = 2132;

  /// Encodes [session] as a FIT file. Never throws for a valid session; a
  /// session without any stream still yields a valid file (no `record`).
  static Uint8List encode(ActivitySession session) {
    final body = _Out();
    final startSec = _fitSeconds(session.startUtc);
    final endSec = _fitSeconds(session.endUtc);

    _fileId(body, startSec);

    final timeline = _timeline(session);
    final gps = session.streams[StreamKind.gps];
    final distances = _cumulativeDistances(gps);
    final totalFromGps = distances.isEmpty ? null : distances.last;
    _records(body, session, timeline, gps, distances, startSec);

    final totalDistanceM = session.summary.distanceM ?? totalFromGps;
    final laps = session.laps.isEmpty
        ? [
            Lap(
              index: 0,
              kind: LapKind.auto,
              startOffsetS: 0,
              durationS: session.durationMs / 1000,
              distanceM: totalDistanceM,
              avgHrBpm: session.summary.avgHrBpm,
            ),
          ]
        : session.laps;
    _laps(body, session, laps, startSec);
    _session(body, session, laps.length, startSec, endSec, totalDistanceM);

    final data = body.bytes;
    final header = _Out()
      ..u8(14)
      ..u8(0x20) // protocol version 2.0
      ..u16(profileVersion)
      ..u32(data.length)
      ..bytes.addAll(const [0x2E, 0x46, 0x49, 0x54]); // ".FIT"
    final headerCrc = fitCrc16(header.bytes);
    header.u16(headerCrc);

    final file = <int>[...header.bytes, ...data];
    final crc = fitCrc16(file);
    file
      ..add(crc & 0xFF)
      ..add((crc >> 8) & 0xFF);
    return Uint8List.fromList(file);
  }

  static int _fitSeconds(DateTime t) {
    final s = t.toUtc().millisecondsSinceEpoch ~/ 1000 - kFitEpochUnixSeconds;
    return s < 0 ? 0 : s;
  }

  static void _fileId(_Out o, int createdSec) {
    o.definition(0, kFitMsgFileId, const [
      _Field(0, 1, _tEnum), // type
      _Field(1, 2, _tUint16), // manufacturer
      _Field(2, 2, _tUint16), // product
      _Field(4, 4, _tUint32), // time_created
    ]);
    o
      ..dataHeader(0)
      ..u8(4) // activity
      ..u16(255) // development
      ..u16(0)
      ..u32(createdSec);
  }

  /// Offsets (ms from start) of the `record` messages.
  static List<int> _timeline(ActivitySession s) {
    final gps = s.streams[StreamKind.gps];
    if (gps != null && !gps.isEmpty) return gps.offsetsMs;
    final all = <int>{};
    for (final k in const [
      StreamKind.heartRate,
      StreamKind.speed,
      StreamKind.altitude,
      StreamKind.cadence,
      StreamKind.power,
      StreamKind.temperature,
    ]) {
      final st = s.streams[k];
      if (st != null) all.addAll(st.offsetsMs);
    }
    return all.toList()..sort();
  }

  static List<double> _cumulativeDistances(SampleStream? gps) {
    if (gps == null ||
        gps.isEmpty ||
        gps.lats.length != gps.length ||
        gps.lons.length != gps.length) {
      return const [];
    }
    final d = List<double>.filled(gps.length, 0);
    for (var i = 1; i < gps.length; i++) {
      d[i] = d[i - 1] +
          haversineMeters(gps.lats[i - 1], gps.lons[i - 1], gps.lats[i], gps.lons[i]);
    }
    return d;
  }

  static void _records(
    _Out o,
    ActivitySession s,
    List<int> timeline,
    SampleStream? gps,
    List<double> distances,
    int startSec,
  ) {
    if (timeline.isEmpty) return;
    o.definition(1, kFitMsgRecord, const [
      _Field(253, 4, _tUint32), // timestamp
      _Field(0, 4, _tSint32), // position_lat (semicircles)
      _Field(1, 4, _tSint32), // position_long
      _Field(2, 2, _tUint16), // altitude, (m + 500) * 5
      _Field(3, 1, _tUint8), // heart_rate
      _Field(4, 1, _tUint8), // cadence
      _Field(5, 4, _tUint32), // distance, m * 100
      _Field(6, 2, _tUint16), // speed, m/s * 1000
      _Field(7, 2, _tUint16), // power
      _Field(13, 1, _tSint8), // temperature
    ]);
    final hasGps = distances.isNotEmpty;
    final hr = s.streams[StreamKind.heartRate];
    final alt = s.streams[StreamKind.altitude];
    final cad = s.streams[StreamKind.cadence];
    final spd = s.streams[StreamKind.speed];
    final pow = s.streams[StreamKind.power];
    final tmp = s.streams[StreamKind.temperature];
    const semi = 2147483648.0 / 180.0;
    for (var i = 0; i < timeline.length; i++) {
      final off = timeline[i];
      final ts = startSec + off ~/ 1000;
      final lat = hasGps ? _clampInt(gps!.lats[i] * semi, -2147483648, 2147483647) : null;
      final lon = hasGps ? _clampInt(gps!.lons[i] * semi, -2147483648, 2147483647) : null;
      final altV = _clampInt(
          nearestStreamValue(alt, off) == null
              ? null
              : (nearestStreamValue(alt, off)! + 500) * 5,
          0,
          65534);
      final hrV = _clampInt(nearestStreamValue(hr, off), 0, 254);
      final cadV = _clampInt(nearestStreamValue(cad, off), 0, 254);
      final distV = hasGps ? _clampInt(distances[i] * 100, 0, 4294967294) : null;
      final spdV = nearestStreamValue(spd, off);
      final speedV = _clampInt(spdV == null ? null : spdV * 1000, 0, 65534);
      final powV = _clampInt(nearestStreamValue(pow, off), 0, 65534);
      final tmpV = _clampInt(nearestStreamValue(tmp, off), -127, 126);
      o
        ..dataHeader(1)
        ..u32(ts)
        ..u32(lat ?? 0x7FFFFFFF)
        ..u32(lon ?? 0x7FFFFFFF)
        ..u16(altV ?? 0xFFFF)
        ..u8(hrV ?? 0xFF)
        ..u8(cadV ?? 0xFF)
        ..u32(distV ?? 0xFFFFFFFF)
        ..u16(speedV ?? 0xFFFF)
        ..u16(powV ?? 0xFFFF)
        ..u8(tmpV ?? 0x7F);
    }
  }

  static void _laps(_Out o, ActivitySession s, List<Lap> laps, int startSec) {
    o.definition(2, kFitMsgLap, const [
      _Field(254, 2, _tUint16), // message_index
      _Field(253, 4, _tUint32), // timestamp (lap end)
      _Field(2, 4, _tUint32), // start_time
      _Field(7, 4, _tUint32), // total_elapsed_time, s * 1000
      _Field(8, 4, _tUint32), // total_timer_time, s * 1000
      _Field(9, 4, _tUint32), // total_distance, m * 100
      _Field(15, 1, _tUint8), // avg_heart_rate
    ]);
    for (var i = 0; i < laps.length; i++) {
      final lap = laps[i];
      final start = startSec + (lap.startOffsetS.isFinite ? lap.startOffsetS.floor() : 0);
      final dur = lap.durationS.isFinite && lap.durationS > 0 ? lap.durationS : 0.0;
      final durMs = _clampInt(dur * 1000, 0, 4294967294)!;
      o
        ..dataHeader(2)
        ..u16(i)
        ..u32(start + dur.floor())
        ..u32(start)
        ..u32(durMs)
        ..u32(durMs)
        ..u32(_clampInt(lap.distanceM == null ? null : lap.distanceM! * 100, 0, 4294967294) ??
            0xFFFFFFFF)
        ..u8(_clampInt(lap.avgHrBpm, 0, 254) ?? 0xFF);
    }
  }

  static void _session(
    _Out o,
    ActivitySession s,
    int lapCount,
    int startSec,
    int endSec,
    double? totalDistanceM,
  ) {
    o.definition(3, kFitMsgSession, const [
      _Field(254, 2, _tUint16), // message_index
      _Field(253, 4, _tUint32), // timestamp
      _Field(2, 4, _tUint32), // start_time
      _Field(7, 4, _tUint32), // total_elapsed_time
      _Field(8, 4, _tUint32), // total_timer_time
      _Field(9, 4, _tUint32), // total_distance
      _Field(5, 1, _tEnum), // sport
      _Field(6, 1, _tEnum), // sub_sport
      _Field(25, 2, _tUint16), // first_lap_index
      _Field(26, 2, _tUint16), // num_laps
      _Field(16, 1, _tUint8), // avg_heart_rate
      _Field(17, 1, _tUint8), // max_heart_rate
      _Field(14, 2, _tUint16), // avg_speed, m/s * 1000
      _Field(22, 2, _tUint16), // total_ascent
      _Field(23, 2, _tUint16), // total_descent
    ]);
    final elapsedMs = _clampInt(s.durationMs, 0, 4294967294)!;
    final timerMs = _clampInt(
        s.movingTimeS == null ? s.durationMs : s.movingTimeS! * 1000, 0, 4294967294)!;
    final (sport, sub) = fitSportOf(s.sport);
    final sum = s.summary;
    o
      ..dataHeader(3)
      ..u16(0)
      ..u32(endSec)
      ..u32(startSec)
      ..u32(elapsedMs)
      ..u32(timerMs)
      ..u32(_clampInt(totalDistanceM == null ? null : totalDistanceM * 100, 0, 4294967294) ??
          0xFFFFFFFF)
      ..u8(sport)
      ..u8(sub)
      ..u16(0)
      ..u16(lapCount)
      ..u8(_clampInt(sum.avgHrBpm, 0, 254) ?? 0xFF)
      ..u8(_clampInt(sum.maxHrBpm, 0, 254) ?? 0xFF)
      ..u16(_clampInt(sum.avgSpeedMps == null ? null : sum.avgSpeedMps! * 1000, 0, 65534) ??
          0xFFFF)
      ..u16(_clampInt(sum.ascentM, 0, 65534) ?? 0xFFFF)
      ..u16(_clampInt(sum.descentM, 0, 65534) ?? 0xFFFF);
  }

  /// FIT `sport` and `sub_sport` enum values of a [SportType].
  static (int, int) fitSportOf(SportType t) => switch (t) {
        SportType.running => (1, 0),
        SportType.trailRunning => (1, 3),
        SportType.cycling => (2, 0),
        SportType.indoorCycling => (2, 6),
        SportType.mountainBiking => (2, 8),
        SportType.swimmingPool => (5, 17),
        SportType.swimmingOpenWater => (5, 18),
        SportType.rowing => (15, 0),
        SportType.walking => (11, 0),
        SportType.hiking => (17, 0),
        SportType.strength => (10, 20),
        SportType.other => (0, 0),
      };
}
