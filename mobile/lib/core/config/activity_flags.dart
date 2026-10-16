import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time switch of the unified-activity cloud path (S02 design 12.1).
///
/// [cloudSync] (`--dart-define=ACTIVITY_CLOUD_STREAMS=true`) is OFF by default.
/// OFF = device-only: no Firestore backend, no start-up sync, no tombstone
/// push and no sync-conflict entry point exist in the running app, so the
/// default build behaves exactly as before S02. Turning it on is an operator
/// action (privacy text and bucket runbook first, design 12.1).
///
/// Same pattern as `BodyScanFlags`: `bool.fromEnvironment` must be a
/// compile-time constant, so the value lives in [ActivityFlags.compileTime];
/// widgets read it through [activityFlagsProvider], which a test overrides.
class ActivityFlags {
  const ActivityFlags({this.cloudSync = false});

  /// Summary sync, tombstone push, conflict entry point and stream upload.
  final bool cloudSync;

  /// The flags this build was compiled with; false unless `--dart-define`d.
  static const ActivityFlags compileTime = ActivityFlags(
    cloudSync: bool.fromEnvironment('ACTIVITY_CLOUD_STREAMS'),
  );

  @override
  bool operator ==(Object other) =>
      other is ActivityFlags && other.cloudSync == cloudSync;

  @override
  int get hashCode => cloudSync.hashCode;

  @override
  String toString() => 'ActivityFlags(cloudSync: $cloudSync)';
}

/// The flags as a provider. Defaults to the compile-time values.
final activityFlagsProvider =
    Provider<ActivityFlags>((ref) => ActivityFlags.compileTime);
