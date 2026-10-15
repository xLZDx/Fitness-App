/// Actions of the scan history (C16): delete a scan's photos and edit the
/// recorded weight. Plain async methods over providers; the confirmation
/// dialogs and the data-notice acknowledgement stay with the calling widget
/// (the notice is the caller's job, D-79).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/body_scan_flags.dart';
import '../../account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import '../../auth/state/auth_providers.dart';
import '../../nutrition_plan/data/energy_math.dart';
import '../../nutrition_plan/data/weight_entry.dart';
import '../../nutrition_plan/state/weight_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../progress_photos/scan/scan_repository.dart';
import '../../progress_photos/scan/ui/scan_compare_screen.dart'
    show deleteScanFiles;
import '../data/provisional_estimator.dart';
import '../data/scan_result_math.dart';
import 'body_scan_providers.dart';
import 'scan_history_rows.dart';

/// What deleting a scan's photos did.
enum DeletePhotosOutcome {
  /// The cloud copy (if any) and the phone copy are gone.
  deleted,

  /// The server could not be reached: the delete is owed and the scan stays on
  /// this phone until the runner has finished it (`pendingRemoteDelete`).
  queuedOffline,

  /// Nothing was removed that should have been; try again.
  failed,
}

/// What editing the recorded weight did.
enum EditWeightOutcome {
  saved,

  /// Outside 30..300 kg; nothing written.
  invalid,

  /// At least one of the writes failed; the others stand.
  failed,
}

class ScanHistoryActions {
  ScanHistoryActions(this._ref);

  final Ref _ref;

  bool _accountGone(String? uid) {
    if (uid == null || uid.isEmpty) return true;
    return _ref.read(accountBeingDeletedUidProvider) == uid;
  }

  /// Deletes the photos of [row]: the cloud copy first (so an owed delete is
  /// recorded before anything local disappears), then the phone copy through
  /// the existing scan delete path.
  Future<DeletePhotosOutcome> deletePhotos(ScanHistoryRow row) async {
    final record = row.record;
    final serverId = row.serverScanId;
    final cloudOn = _ref.read(bodyScanFlagsProvider).cloudPhotos;
    if (serverId != null && cloudOn) {
      try {
        await _ref
            .read(bodyScanApiProvider)
            .deleteBodyScan(serverId, photosOnly: true);
      } catch (e) {
        debugPrint('body scan: cloud photo delete deferred (${e.runtimeType})');
        if (record == null) return DeletePhotosOutcome.failed;
        try {
          await _ref
              .read(scanRepositoryProvider)
              .save(record.copyWith(pendingRemoteDelete: true));
          _ref.invalidate(scanHistoryProvider);
          // The runner flushes owed deletes when it next runs.
          _ref.read(bodyScanRunnerProvider)?.resume();
          return DeletePhotosOutcome.queuedOffline;
        } catch (e2) {
          debugPrint('body scan: owed delete not saved (${e2.runtimeType})');
          return DeletePhotosOutcome.failed;
        }
      }
    }
    if (record != null) {
      _ref.read(bodyScanRunnerProvider)?.forget(record.id);
      try {
        await deleteScanFiles(_ref.read, record);
      } catch (e) {
        debugPrint('body scan: local delete failed (${e.runtimeType})');
        _ref.invalidate(scanHistoryProvider);
        return DeletePhotosOutcome.failed;
      }
      _ref.invalidate(scanHistoryProvider);
    }
    return DeletePhotosOutcome.deleted;
  }

  /// Sets the recorded weight of [row] to [kg]:
  ///  1. the local record (and, for a PROVISIONAL scan, its estimate, which the
  ///     formula derives from the weight, D-52);
  ///  2. the server document when there is one (the server estimate stays);
  ///  3. the same local day's `weight_entries` row when [writeDayEntry] (the
  ///     caller acknowledged the data notice), D-72.
  /// Every step is tried even when another fails, so one outage does not lose
  /// the rest.
  Future<EditWeightOutcome> editWeight(
    ScanHistoryRow row,
    double kg, {
    bool writeDayEntry = true,
  }) async {
    if (!WeightEntry.isValidKg(kg)) return EditWeightOutcome.invalid;
    final uid = _ref.read(authUserProvider).valueOrNull?.uid;
    if (_accountGone(uid)) return EditWeightOutcome.failed;
    var ok = true;

    final record = row.record;
    if (record != null) {
      try {
        var next = record.copyWith(weightKg: kg);
        final analysis = record.analysis;
        final estimate = analysis?.estimate;
        if (analysis != null && estimate != null && estimate.provisional) {
          final subject = _subject(record.createdAt.year, kg);
          if (subject != null) {
            next = next.copyWith(
              analysis: analysis.copyWith(
                estimate: rederiveForEditedWeight(
                  estimate: estimate,
                  subjectWithNewWeight: subject,
                ),
                updatedAt: _ref.read(nutritionClockProvider)(),
              ),
            );
          }
        }
        await _ref.read(scanRepositoryProvider).save(next);
        _ref.invalidate(scanHistoryProvider);
      } catch (e) {
        debugPrint('body scan: local weight edit failed (${e.runtimeType})');
        ok = false;
      }
    }

    final entry = row.entry;
    if (entry != null) {
      try {
        await _ref
            .read(bodyScanRepositoryProvider)
            .updateRecordedWeight(entry.scanId, kg);
      } catch (e) {
        debugPrint('body scan: server weight edit failed (${e.runtimeType})');
        ok = false;
      }
    }

    if (writeDayEntry) {
      try {
        final status = await _ref
            .read(weightLogActionsProvider)
            .saveScanWeight(kg, at: row.takenAt);
        if (status == WeightWriteStatus.invalid ||
            status == WeightWriteStatus.unavailable) {
          ok = false;
        }
      } catch (e) {
        debugPrint('body scan: weight entry write failed (${e.runtimeType})');
        ok = false;
      }
    }
    return ok ? EditWeightOutcome.saved : EditWeightOutcome.failed;
  }

  EstimatorSubject? _subject(int year, double kg) {
    final profile = _ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) return null;
    final height = profile.personal.heightCm;
    final age = profile.personal.ageAt(year);
    final sex = resolveSexBasis(profile);
    if (height == null || age == null || sex == null) return null;
    return EstimatorSubject(
      heightCm: height.toDouble(),
      weightKg: kg,
      ageYears: age,
      sex: sex,
    );
  }
}

final scanHistoryActionsProvider =
    Provider<ScanHistoryActions>((ref) => ScanHistoryActions(ref));

/// The merged history rows, newest first.
final scanHistoryRowsProvider = Provider<List<ScanHistoryRow>>((ref) {
  final records =
      ref.watch(scanHistoryProvider).valueOrNull ?? const [];
  final entries = ref.watch(bodyScanEntriesProvider).valueOrNull ?? const [];
  final trend = ref.watch(scanTrendProvider);
  return buildHistoryRows(records: records, entries: entries, trend: trend);
});
