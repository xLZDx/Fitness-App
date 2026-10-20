/// The sign-out guard of S03-16 (design 2.5, F-19, F-42, F-45; RV-12, RV-16).
///
/// `confirmSignOutWithLocalData(context, ref)` is awaited by every user-initiated
/// sign-out. It returns true when the caller may sign out now, false when the
/// user stays signed in (cancelled, or an export or deletion failed).
///
/// Rules:
///  * `notEnabled` and an open journal with no activity: true, no prompt, no
///    wipe call. With no activity and no counted recording, the bounded
///    pre-unbind hook is still run when the recording journal lists any
///    recording (quarantined, FALLBACK or permission-revoked pending included);
///    only a journal with no recording files at all skips it.
///  * `binding`, `gaveUp`, `failedToOpen` (and an open journal that cannot be
///    counted): the "cannot check" sheet with Try again (not for
///    `failedToOpen`), Sign out anyway and Cancel. Never a silent pass.
///  * An open journal with activities: the warning sheet. Export first writes
///    the files to a cache directory outside backup named after the departing
///    account's scope, shares them and deletes them afterwards; the warning
///    then shows again. Sign out and delete asks a second confirmation and only
///    then calls `ActivityWipeCoordinator.onSignOut` (only while the
///    availability is `open`; it throws when the journal is unbound).
///  * Export or deletion runs BEFORE the sign-out; a failure keeps the user
///    signed in with an error sheet and Retry. "Deleted" is announced only after
///    the wipe returned normally.
///  * Recordings (S04-30 AC-6): an active or unfinished recording counts and is
///    named in the warning sheet. Once the user commits to leaving, the guard
///    runs the SAME pre-unbind hook as the bind controller (registry
///    `activityPreUnbindHookRegistryProvider`, bounded) while the scope is still
///    bound. If the hook timed out or failed, or a recording is still left
///    afterwards (30-day fallback), the user is told with `gpsSignOutNotice`.
///    A recording count that cannot be read is the "cannot check" case; "Sign
///    out anyway" stays allowed.
///  * Failures are logged as a fixed message, a content-free code and the
///    exception type; never ids, paths or content.
library;

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/wiring/activity_wiring.dart';
import '../../recording/journal/pre_unbind_hook.dart';
import '../../recording/state/recorder_phase.dart';
import '../../recording/state/recorder_providers.dart';
import '../../recording/state/recording_journal_port.dart';
import '../repository/activity_journal.dart';
import '../repository/activity_local_export.dart';
import '../repository/journal_models.dart' show SignOutAssessment;
import '../repository/uid_scoped_activity_journal.dart'
    show AccountScopedJournal, activityJournalScopeId;
import '../widgets/sign_out_warning_sheet.dart';
import 'journal_availability.dart';

/// Longest wait for a manual bind attempt to finish (40 x 250 ms).
const int _kBindWaitPolls = 40;
const Duration _kBindWaitStep = Duration(milliseconds: 250);

Future<bool> confirmSignOutWithLocalData(
  BuildContext context,
  WidgetRef ref,
) async {
  while (true) {
    if (!context.mounted) return false;
    final JournalAvailability availability =
        ref.read(journalAvailabilityProvider);
    if (availability is JournalNotEnabled) return true;

    bool? result;
    if (availability is JournalOpen) {
      result = await _handleOpen(context, ref, availability);
    }
    if (result != null) return result;
    if (!context.mounted) return false;

    result = await _cannotCheck(context, ref, availability);
    if (result != null) return result;
    // Try again: evaluate the availability afresh.
  }
}

/// True: sign out; false: stay; null: the journal cannot be checked.
Future<bool?> _handleOpen(
  BuildContext context,
  WidgetRef ref,
  JournalOpen availability,
) async {
  final ActivityJournal? journal = ref.read(activityJournalProvider);
  final String? uid = availability.ownerUid;
  if (journal == null || uid == null || uid.isEmpty) return null;

  final SignOutAssessment assessment;
  try {
    assessment = await journal.assessSignOut();
  } catch (e) {
    debugPrint('activity: sign-out check failed '
        '(code=assess_failed, ${e.runtimeType})');
    return null;
  }
  if (!context.mounted) return false;
  // The account or the journal state may have moved on while counting.
  final JournalAvailability now = ref.read(journalAvailabilityProvider);
  if (now is! JournalOpen || now.ownerUid != uid) return null;
  final int? recordings = await _recordingCount(ref);
  if (recordings == null) return null; // cannot check: never a silent pass
  if (!context.mounted) return false;
  if (assessment.entryCount == 0 && recordings == 0) {
    // Nothing to warn about. The fast path may skip the pre-unbind hook only
    // when the recording journal lists no recording at all: quarantined,
    // FALLBACK and permission-revoked pending recordings are not counted above
    // but still need the bounded hand-off while the scope is bound.
    final bool? anyFiles = await _anyRecordingFiles(ref);
    if (anyFiles == null) return null; // cannot check: never a silent pass
    if (!context.mounted) return false;
    if (!anyFiles) return true;
    return _leaveWithRecordings(context, ref, uid);
  }

  return _warnLoop(
      context, ref, journal, uid, assessment.entryCount, recordings);
}

/// Active plus unfinished recordings of the bound account; null when they
/// cannot be counted. 0 ONLY when the recorder is not wired: the default body
/// of `recordingJournalPortProvider` throws [UnimplementedError] (flag off and
/// non-Android builds never override it); that is the sole "not wired" signal.
/// Any other failure reading the port, and any failure reading the recorder
/// phase once the port was read (the recorder IS wired), is null: cannot check,
/// never a silent pass. (Riverpod 2.6.1 rethrows the provider's own error, so
/// no wrapper type has to be unwrapped.) An active recording is normally also
/// listed as unfinished, so the larger of the two is used, never the sum.
Future<int?> _recordingCount(WidgetRef ref) async {
  final RecordingJournalPort port;
  try {
    port = ref.read(recordingJournalPortProvider);
  } on UnimplementedError {
    return 0;
  } catch (e) {
    debugPrint('activity: sign-out recording check failed '
        '(code=recording_provider_failed, ${e.runtimeType})');
    return null;
  }
  final bool active;
  try {
    active = ref.read(recorderPhaseProvider).isActive;
  } catch (e) {
    debugPrint('activity: sign-out recording check failed '
        '(code=recording_provider_failed, ${e.runtimeType})');
    return null;
  }
  try {
    final List<UnfinishedRecording> list = await port.listUnfinished();
    final int unfinished = list.where((r) => r.blocksStart).length;
    return unfinished > 0 ? unfinished : (active ? 1 : 0);
  } catch (e) {
    debugPrint('activity: sign-out recording check failed '
        '(code=recording_count_failed, ${e.runtimeType})');
    return null;
  }
}

/// True when the recording journal lists any recording of the bound account at
/// all (every status, including quarantined and permission-revoked pending ones)
/// or a recording is active; null when that cannot be read. False ONLY when the
/// recorder is not wired: the default body of `recordingJournalPortProvider`
/// throws [UnimplementedError], the sole "not wired" signal. Any other failure
/// reading the port, or any failure reading the recorder phase once the port
/// was read (the recorder IS wired), is null: cannot check, never a silent
/// pass (Riverpod 2.6.1 rethrows the provider's own error, no wrapper).
Future<bool?> _anyRecordingFiles(WidgetRef ref) async {
  final RecordingJournalPort port;
  try {
    port = ref.read(recordingJournalPortProvider);
  } on UnimplementedError {
    return false;
  } catch (e) {
    debugPrint('activity: sign-out recording check failed '
        '(code=recording_provider_failed, ${e.runtimeType})');
    return null;
  }
  final bool active;
  try {
    active = ref.read(recorderPhaseProvider).isActive;
  } catch (e) {
    debugPrint('activity: sign-out recording check failed '
        '(code=recording_provider_failed, ${e.runtimeType})');
    return null;
  }
  try {
    final List<UnfinishedRecording> list = await port.listUnfinished();
    return list.isNotEmpty || active;
  } catch (e) {
    debugPrint('activity: sign-out recording check failed '
        '(code=recording_list_failed, ${e.runtimeType})');
    return null;
  }
}

/// Runs the registered pre-unbind hook for [uid] (bounded, never throws) and
/// returns true when the user must be told that a recording stays on the phone
/// under the 30-day fallback.
Future<bool> _finishRecordings(WidgetRef ref, String uid) async {
  final PreUnbindOutcome outcome = await ref
      .read(activityPreUnbindHookRegistryProvider)
      .runBounded(uid, UnbindReason.signOut);
  if (outcome == PreUnbindOutcome.noHook) return false;
  if (outcome != PreUnbindOutcome.completed) return true;
  try {
    final List<UnfinishedRecording> left =
        await ref.read(recordingJournalPortProvider).listUnfinished();
    return left.any((r) => r.blocksStart);
  } catch (_) {
    return false;
  }
}

/// Leaves with the strict hand-off first; tells the user when it did not
/// complete. Always true (the user may always leave).
Future<bool> _leaveWithRecordings(
  BuildContext context,
  WidgetRef ref,
  String? uid,
) async {
  if (uid == null || uid.isEmpty) return true;
  final bool notify = await _finishRecordings(ref, uid);
  if (notify && context.mounted) {
    await showSignOutRecordingNoticeSheet(context);
  }
  return true;
}

Future<bool> _warnLoop(
  BuildContext context,
  WidgetRef ref,
  ActivityJournal journal,
  String uid,
  int activities,
  int recordings,
) async {
  final int count = activities + recordings;
  while (true) {
    if (!context.mounted) return false;
    final SignOutChoice choice = await showSignOutWarningSheet(context,
        count: activities, recordingCount: recordings);
    if (!context.mounted) return false;
    switch (choice) {
      case SignOutChoice.exportFirst:
        await _guarded(context, () => _exportAndShare(journal, uid));
        // Back to the warning: the user may now delete, sign out or cancel.
        continue;
      case SignOutChoice.signOutKeep:
        return _leaveWithRecordings(context, ref, uid);
      case SignOutChoice.signOutAndDelete:
        final SignOutChoice confirm =
            await showSignOutConfirmDeleteSheet(context, count: count);
        if (confirm != SignOutChoice.confirmDelete) continue;
        if (!context.mounted) return false;
        // Nothing has been deleted so far. Resolve the message and messenger
        // now: the screen may be gone after the sign-out.
        final ScaffoldMessengerState? messenger =
            ScaffoldMessenger.maybeOf(context);
        final String deletedText = AppLocalizations.of(context).signOutDeleted;
        final bool wiped = await _guarded(context, () async {
          // Only while the availability is open (onSignOut throws when the
          // journal is unbound).
          if (ref.read(journalAvailabilityProvider) is! JournalOpen) {
            throw StateError('journal is not open');
          }
          // Recorder shutdown (and hand-off) while the scope is still bound.
          if (recordings > 0) await _finishRecordings(ref, uid);
          final bool done =
              await ActivityWipeCoordinator(journal).onSignOut(_ConfirmedHooks());
          if (!done) throw StateError('wipe did not complete');
        });
        if (!wiped) return false;
        // The wipe returned normally: only now is "deleted" true.
        messenger?.showSnackBar(SnackBar(content: Text(deletedText)));
        return true;
      case SignOutChoice.cancel:
      case SignOutChoice.tryAgain:
      case SignOutChoice.anyway:
      case SignOutChoice.confirmDelete:
      case SignOutChoice.retry:
        return false;
    }
  }
}

/// The user already confirmed before [ActivityWipeCoordinator.onSignOut] runs
/// and the export (if wanted) already happened.
class _ConfirmedHooks implements ActivitySignOutHooks {
  @override
  Future<void> offerExport(SignOutAssessment assessment) async {}

  @override
  Future<bool> confirmWipe(SignOutAssessment assessment) async => true;
}

/// Runs [step]; on a failure shows the error sheet. True when [step] finished,
/// false when it failed and the user did not retry.
Future<bool> _guarded(
  BuildContext context,
  Future<void> Function() step,
) async {
  while (true) {
    try {
      await step();
      return true;
    } catch (e) {
      debugPrint('activity: sign-out step failed '
          '(code=sign_out_step_failed, ${e.runtimeType})');
    }
    if (!context.mounted) return false;
    final SignOutChoice choice = await showSignOutErrorSheet(context);
    if (choice != SignOutChoice.retry) return false;
    if (!context.mounted) return false;
  }
}

/// True: sign out anyway; false: stay; null: Try again was chosen.
Future<bool?> _cannotCheck(
  BuildContext context,
  WidgetRef ref,
  JournalAvailability availability,
) async {
  final SignOutChoice choice = await showSignOutCannotCheckSheet(
    context,
    canRetry: availability is! JournalFailedToOpen,
  );
  switch (choice) {
    case SignOutChoice.anyway:
      final JournalAvailability now = ref.read(journalAvailabilityProvider);
      String? uid = now is JournalOpen ? now.ownerUid : null;
      if (uid == null) {
        final ActivityJournal? j = ref.read(activityJournalProvider);
        uid = j is AccountScopedJournal ? (j as AccountScopedJournal).boundUid : null;
      }
      return _leaveWithRecordings(context, ref, uid);
    case SignOutChoice.tryAgain:
      if (availability is! JournalOpen) {
        final RetryResult started =
            await ref.read(activityBindStatusProvider.notifier).retryNow();
        if (started == RetryResult.started) {
          for (var i = 0; i < _kBindWaitPolls; i++) {
            if (!context.mounted) return false;
            if (!ref.read(activityBindStatusProvider).bindBusy) break;
            await Future<void>.delayed(_kBindWaitStep);
          }
        }
      }
      return null;
    case SignOutChoice.cancel:
    case SignOutChoice.exportFirst:
    case SignOutChoice.signOutAndDelete:
    case SignOutChoice.signOutKeep:
    case SignOutChoice.confirmDelete:
    case SignOutChoice.retry:
      return false;
  }
}

/// Exports every activity (GPX; FIT, then JSON, for a session GPX cannot
/// carry), writes the files to a cache directory outside backup, shares them
/// and deletes them afterwards. The directory is named after the scope of the
/// departing account (a hash, never the raw uid).
Future<void> _exportAndShare(ActivityJournal journal, String uid) async {
  final JournalActivityLocalExport export = JournalActivityLocalExport(journal);
  final List<ActivityExportResult> results =
      await export.exportAll(ActivityExportFormat.gpx);

  final List<ActivityExportFile> files = <ActivityExportFile>[];
  for (final ActivityExportResult r in results) {
    switch (r) {
      case ActivityExportFile():
        files.add(r);
      case ActivityExportNotFound():
        break;
      case ActivityExportAccountChanged():
        throw StateError('account changed during export');
      case ActivityExportUnavailable():
        throw StateError('export unavailable');
      case ActivityExportNoGeometry():
      case ActivityExportStreamLost():
        files.add(await _fallbackFile(export, r.activityId));
    }
  }
  if (files.isEmpty) throw StateError('nothing to export');

  final Directory base = await getTemporaryDirectory();
  final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}activity_export_${activityJournalScopeId(uid)}');
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final List<XFile> shared = <XFile>[];
    for (final ActivityExportFile f in files) {
      final String path = '${dir.path}${Platform.pathSeparator}${f.fileName}';
      await File(path).writeAsBytes(f.bytes, flush: true);
      shared.add(XFile(path, mimeType: f.format.mimeType));
    }
    // A dismissed share sheet is not an error: nothing was lost or deleted.
    await Share.shareXFiles(shared);
  } finally {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('activity: export cleanup failed '
          '(code=export_cleanup_failed, ${e.runtimeType})');
    }
  }
}

Future<ActivityExportFile> _fallbackFile(
  JournalActivityLocalExport export,
  String activityId,
) async {
  for (final ActivityExportFormat format in <ActivityExportFormat>[
    ActivityExportFormat.fit,
    ActivityExportFormat.json,
  ]) {
    final ActivityExportResult r =
        await export.exportActivity(activityId, format);
    if (r is ActivityExportFile) return r;
  }
  throw StateError('activity could not be exported');
}
