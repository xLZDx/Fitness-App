/// Providers and wiring helpers of the recording journal (lane R5).
///
/// `recordingJournalPortProvider` itself is declared by lane R4 in
/// `state/recorder_ports.dart` and throws until overridden. Lane R9 overrides
/// it with [recordingJournalPortOverride] in `main.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/wiring/activity_wiring.dart'
    show activityJournalProvider, activityPreUnbindHookRegistryProvider;
import '../../activity/repository/journal_cipher.dart';
import '../../activity/repository/journal_layout.dart' show kScopedJournalRootDirName;
import '../../activity/repository/uid_scoped_activity_journal.dart';
import '../../activity/state/activity_dashboard_providers.dart'
    show activityJournalRevisionProvider;
import '../state/recorder_ports.dart' show recordingJournalPortProvider;
import 'file_recording_journal.dart';

/// `<app support>/activity_journal`, the parent of every scope directory.
Future<String> scopedJournalsRoot() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/$kScopedJournalRootDirName';
}

/// The concrete journal (also a [RecordingScopeGuard] and the source of the
/// pre-unbind hook). Throws when no account-scoped S02 journal is wired.
final fileRecordingJournalProvider = Provider<FileRecordingJournal>((ref) {
  final activity = ref.watch(activityJournalProvider);
  if (activity == null || activity is! AccountScopedJournal) {
    throw StateError('recording journal needs the account-scoped activity journal');
  }
  final scoped = activity as AccountScopedJournal;
  final journal = FileRecordingJournal(
    activity: activity,
    boundUid: () => scoped.boundUid,
    scopesRoot: scopedJournalsRoot,
    keyProviderFor: (scopeId) => SecureStorageJournalKeyProvider(scopeId: scopeId),
    onHandedOff: () =>
        ref.read(activityJournalRevisionProvider.notifier).state++,
  );
  // Wipe ordering (design 4.7): the wipe closes this journal first.
  if (activity is UidScopedActivityJournal) {
    activity.recordingGuard = journal;
  }
  return journal;
});

/// Override for the recorder state's port provider (lane R9 `main.dart`).
Override recordingJournalPortOverride() =>
    recordingJournalPortProvider.overrideWith(
        (ref) => ref.watch(fileRecordingJournalProvider));

/// Registers the recorder's pre-unbind hook with the single registry of
/// `activity_wiring.dart`. [shutdownRecorder] must call the recorder's
/// `releaseAll()`. Returns the hook so the caller can unregister it.
RecordingPreUnbindHook registerRecordingPreUnbindHook(
  Ref ref, {
  required Future<void> Function() shutdownRecorder,
  void Function(int kept)? onFallbackKept,
}) {
  final hook = RecordingPreUnbindHook(
    journal: ref.read(fileRecordingJournalProvider),
    shutdownRecorder: shutdownRecorder,
    onFallbackKept: onFallbackKept,
  );
  final registry = ref.read(activityPreUnbindHookRegistryProvider);
  registry.register(hook);
  ref.onDispose(() => registry.unregister(hook));
  return hook;
}
