/// Seam providers of the recorder. Like `locationSourceProvider`, the ones
/// without a safe default throw until lane R9 overrides them at the app root,
/// so an unwired recorder fails loudly instead of recording nothing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permissions/permission_providers.dart';
import '../permissions/permission_revocation_watcher.dart';
import 'battery_monitor.dart';
import 'recorder_environment.dart';
import 'recording_journal_port.dart';

final recordingJournalPortProvider = Provider<RecordingJournalPort>(
  (ref) => throw UnimplementedError(
    'recordingJournalPortProvider must be overridden with a RecordingJournalPort',
  ),
);

final recorderEnvironmentProvider = Provider<RecorderEnvironment>(
  (ref) => throw UnimplementedError(
    'recorderEnvironmentProvider must be overridden with a RecorderEnvironment',
  ),
);

final batteryMonitorProvider = Provider<BatteryMonitor>(
  (ref) => throw UnimplementedError(
    'batteryMonitorProvider must be overridden with a BatteryMonitor',
  ),
);

/// Default is the safe branch of S04-37 (stop at once on engine detach).
final engineDetachPolicyProvider = Provider<EngineDetachPolicy>(
  (ref) => EngineDetachPolicy.stopImmediately,
);

/// The permission poller (1 s). One per recorder; disposed with the container.
final permissionRevocationWatcherProvider =
    Provider<PermissionRevocationWatcher>((ref) {
  final watcher =
      PermissionRevocationWatcher(ref.watch(permissionServiceProvider));
  ref.onDispose(watcher.dispose);
  return watcher;
});
