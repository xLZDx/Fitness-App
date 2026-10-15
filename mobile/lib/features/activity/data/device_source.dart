/// The device-source abstraction and the capability matrix (design s31.2,
/// s31.6). Interfaces only: no adapter exists in this sprint. Pure Dart, no
/// Flutter imports.
library;

import 'activity_session.dart';
import 'sample_stream.dart';

enum SourceKind {
  platformHealth,
  bleSensor,
  vendorCloud,
  companionApp,
  fileImport;

  static SourceKind parse(Object? name) {
    if (name is String) {
      for (final k in values) {
        if (k.name == name) return k;
      }
    }
    return SourceKind.fileImport;
  }
}

enum SourcePermission { granted, denied, notDetermined, restricted }

/// How well a source provides something. Hypotheses from design 31.6 until
/// the Phase 2 API study confirms them.
enum CapabilityLevel { yes, partial, no, unknown }

/// The columns of the capability matrix.
enum CapabilityColumn {
  sessionList,
  heartRate,
  speedPace,
  cadence,
  power,
  gpsRoute,
  strokesLaps,
  steps,
  sleep,
  liveStream,
}

class SourceCapabilities {
  const SourceCapabilities(this.levels);

  final Map<CapabilityColumn, CapabilityLevel> levels;

  CapabilityLevel levelOf(CapabilityColumn c) =>
      levels[c] ?? CapabilityLevel.unknown;

  /// True when the source can deliver [kind] at least partially.
  bool supportsStream(StreamKind kind) {
    final c = switch (kind) {
      StreamKind.heartRate => CapabilityColumn.heartRate,
      StreamKind.speed => CapabilityColumn.speedPace,
      StreamKind.cadence => CapabilityColumn.cadence,
      StreamKind.power => CapabilityColumn.power,
      StreamKind.gps || StreamKind.altitude => CapabilityColumn.gpsRoute,
      StreamKind.strokeRate => CapabilityColumn.strokesLaps,
      StreamKind.temperature => null,
    };
    if (c == null) return false;
    final l = levelOf(c);
    return l == CapabilityLevel.yes || l == CapabilityLevel.partial;
  }
}

SourceCapabilities _caps({
  CapabilityLevel session = CapabilityLevel.no,
  CapabilityLevel hr = CapabilityLevel.no,
  CapabilityLevel speed = CapabilityLevel.no,
  CapabilityLevel cadence = CapabilityLevel.no,
  CapabilityLevel power = CapabilityLevel.no,
  CapabilityLevel gps = CapabilityLevel.no,
  CapabilityLevel strokes = CapabilityLevel.no,
  CapabilityLevel steps = CapabilityLevel.no,
  CapabilityLevel sleep = CapabilityLevel.no,
  CapabilityLevel live = CapabilityLevel.no,
}) =>
    SourceCapabilities({
      CapabilityColumn.sessionList: session,
      CapabilityColumn.heartRate: hr,
      CapabilityColumn.speedPace: speed,
      CapabilityColumn.cadence: cadence,
      CapabilityColumn.power: power,
      CapabilityColumn.gpsRoute: gps,
      CapabilityColumn.strokesLaps: strokes,
      CapabilityColumn.steps: steps,
      CapabilityColumn.sleep: sleep,
      CapabilityColumn.liveStream: live,
    });

const _y = CapabilityLevel.yes;
const _p = CapabilityLevel.partial;
const _u = CapabilityLevel.unknown;

/// The capability matrix of design 31.6 (HYPOTHESES to be confirmed in the
/// Phase 2 API study), keyed by source id. Vendor clouds are all unknown.
final Map<String, SourceCapabilities> kCapabilityMatrix = {
  'health_connect': _caps(
      session: _y, hr: _y, speed: _y, cadence: _y, power: _y, gps: _y,
      strokes: _p, steps: _y, sleep: _y),
  'healthkit': _caps(
      session: _y, hr: _y, speed: _y, cadence: _y, power: _y, gps: _y,
      strokes: _p, steps: _y, sleep: _y, live: _p),
  'ble_hr': _caps(hr: _y, live: _y),
  'ble_rsc': _caps(speed: _y, cadence: _y, live: _y),
  'ble_csc': _caps(speed: _y, cadence: _y, live: _y),
  'ble_cp': _caps(speed: _p, cadence: _p, power: _y, live: _y),
  'ble_ftms': _caps(hr: _p, speed: _y, cadence: _y, power: _y, live: _y),
  'wear_os': _caps(
      session: _y, hr: _y, speed: _y, cadence: _y, power: _u, gps: _y,
      strokes: _u, steps: _y, sleep: _u, live: _y),
  'vendor_cloud': _caps(
      session: _u, hr: _u, speed: _u, cadence: _u, power: _u, gps: _u,
      strokes: _u, steps: _u, sleep: _u),
};

/// One live sample from a BLE sensor or a watch.
class LiveSample {
  const LiveSample({
    required this.kind,
    required this.at,
    this.value,
    this.lat,
    this.lon,
  });

  final StreamKind kind;
  final DateTime at;
  final double? value;
  final double? lat;
  final double? lon;
}

/// A place activity data can come from. Adapters are Phase 2.
abstract class DeviceSource {
  /// "health_platform", "ble_hr", "garmin_cloud", ...
  String get id;

  SourceKind get kind;

  /// The static capability matrix row.
  SourceCapabilities get capabilities;

  Future<SourcePermission> permission(Set<StreamKind> kinds);
  Future<SourcePermission> request(Set<StreamKind> kinds);

  /// History for the window `[from, to]`.
  Future<List<ActivitySession>> fetchSessions({
    required DateTime from,
    required DateTime to,
  });

  /// BLE / watch only; empty for sources without a live stream.
  Stream<LiveSample> live(Set<StreamKind> kinds);

  /// Stops the source and, when [deleteImported] is true, discards what was
  /// imported from it.
  Future<void> disconnect({bool deleteImported = false});
}
