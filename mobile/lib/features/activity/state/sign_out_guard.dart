/// The sign-out guard of S03-16 (design 2.5, F-19, F-42, F-45; RV-12, RV-16).
///
/// `confirmSignOutWithLocalData(context, ref)` is awaited by every user-initiated
/// sign-out. It returns true when the caller may sign out now, false when the
/// user stays signed in (cancelled, or an export or deletion failed).
///
/// Rules:
///  * `notEnabled` and an open journal with no activity: true, no prompt, no
///    wipe call.
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
import '../repository/activity_journal.dart';
import '../repository/activity_local_export.dart';
import '../repository/journal_models.dart' show SignOutAssessment;
import '../repository/uid_scoped_activity_journal.dart'
    show activityJournalScopeId;
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
  if (assessment.entryCount == 0) return true;

  return _warnLoop(context, ref, journal, uid, assessment.entryCount);
}

Future<bool> _warnLoop(
  BuildContext context,
  WidgetRef ref,
  ActivityJournal journal,
  String uid,
  int count,
) async {
  while (true) {
    if (!context.mounted) return false;
    final SignOutChoice choice =
        await showSignOutWarningSheet(context, count: count);
    if (!context.mounted) return false;
    switch (choice) {
      case SignOutChoice.exportFirst:
        await _guarded(context, () => _exportAndShare(journal, uid));
        // Back to the warning: the user may now delete, sign out or cancel.
        continue;
      case SignOutChoice.signOutKeep:
        return true;
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
      return true;
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
