import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time switches of the unified-activity feature (S02 design 12.1).
///
/// Two independent flags, both OFF by default:
/// - [localJournal] (`--dart-define=ACTIVITY_LOCAL_JOURNAL=true`) opens the
///   device journal with NO network path at all (later sprints use it without
///   turning the cloud on).
/// - [cloudSync] (`--dart-define=ACTIVITY_CLOUD_STREAMS=true`) adds the Firestore
///   backend, start-up sync, tombstone push, sync-conflict entry point and
///   stream upload. It also opens the journal ([journalEnabled]).
///
/// Both OFF = device-only without a journal: the default build behaves exactly
/// as before S02. Turning the cloud on is an operator action (privacy text and
/// bucket runbook first, design 12.1).
///
/// Same pattern as `BodyScanFlags`: `bool.fromEnvironment` must be a
/// compile-time constant, so the values live in [ActivityFlags.compileTime];
/// widgets read them through [activityFlagsProvider], which a test overrides.
class ActivityFlags {
  const ActivityFlags({this.cloudSync = false, this.localJournal = false});

  /// Summary sync, tombstone push, conflict entry point and stream upload.
  final bool cloudSync;

  /// Opens the device journal without any network path.
  final bool localJournal;

  /// True when a journal must exist: local-only or cloud.
  bool get journalEnabled => localJournal || cloudSync;

  /// The flags this build was compiled with; false unless `--dart-define`d.
  static const ActivityFlags compileTime = ActivityFlags(
    cloudSync: bool.fromEnvironment('ACTIVITY_CLOUD_STREAMS'),
    localJournal: bool.fromEnvironment('ACTIVITY_LOCAL_JOURNAL'),
  );

  @override
  bool operator ==(Object other) =>
      other is ActivityFlags &&
      other.cloudSync == cloudSync &&
      other.localJournal == localJournal;

  @override
  int get hashCode => Object.hash(cloudSync, localJournal);

  @override
  String toString() =>
      'ActivityFlags(cloudSync: $cloudSync, localJournal: $localJournal)';
}

/// The flags as a provider. Defaults to the compile-time values.
final activityFlagsProvider =
    Provider<ActivityFlags>((ref) => ActivityFlags.compileTime);
