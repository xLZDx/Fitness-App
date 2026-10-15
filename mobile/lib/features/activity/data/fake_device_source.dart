/// A deterministic in-memory [DeviceSource] for tests (design s31.7). It lives
/// under `data/` because tests import it; no Flutter imports, no platform code.
library;

import 'activity_session.dart';
import 'device_source.dart';
import 'sample_stream.dart';

class FakeDeviceSource implements DeviceSource {
  FakeDeviceSource({
    required this.id,
    this.kind = SourceKind.fileImport,
    SourceCapabilities? capabilities,
    List<ActivitySession> sessions = const [],
    Set<StreamKind> granted = const {},
    this.grantOnRequest = true,
  })  : capabilities = capabilities ?? kCapabilityMatrix['vendor_cloud']!,
        _sessions = [...sessions],
        _granted = {...granted};

  @override
  final String id;

  @override
  final SourceKind kind;

  @override
  final SourceCapabilities capabilities;

  final bool grantOnRequest;
  final List<ActivitySession> _sessions;
  final Set<StreamKind> _granted;
  final List<LiveSample> _liveScript = [];

  /// How many times each call happened, for assertions.
  int requestCalls = 0;
  int disconnectCalls = 0;
  bool lastDisconnectDeletedImported = false;

  /// Imported sessions currently held (cleared by `disconnect(deleteImported)`).
  List<ActivitySession> get imported => List.unmodifiable(_sessions);

  void scriptLive(List<LiveSample> samples) => _liveScript
    ..clear()
    ..addAll(samples);

  @override
  Future<SourcePermission> permission(Set<StreamKind> kinds) async =>
      kinds.every(_granted.contains)
          ? SourcePermission.granted
          : SourcePermission.notDetermined;

  @override
  Future<SourcePermission> request(Set<StreamKind> kinds) async {
    requestCalls++;
    if (!grantOnRequest) return SourcePermission.denied;
    _granted.addAll(kinds);
    return SourcePermission.granted;
  }

  @override
  Future<List<ActivitySession>> fetchSessions({
    required DateTime from,
    required DateTime to,
  }) async {
    final f = from.toUtc();
    final t = to.toUtc();
    return [
      for (final s in _sessions)
        if (!s.endUtc.isBefore(f) && !s.startUtc.isAfter(t)) s,
    ];
  }

  @override
  Stream<LiveSample> live(Set<StreamKind> kinds) => Stream.fromIterable(
        [for (final s in _liveScript) if (kinds.contains(s.kind)) s],
      );

  @override
  Future<void> disconnect({bool deleteImported = false}) async {
    disconnectCalls++;
    lastDisconnectDeletedImported = deleteImported;
    _granted.clear();
    if (deleteImported) _sessions.clear();
  }
}
