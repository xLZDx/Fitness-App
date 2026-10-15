import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_job_runner.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/state/weight_providers.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';

/// Records the calls the flow driver makes on the job runner.
class FakeRunner implements BodyScanJobRunner {
  final List<String> calls = [];

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> retry(String scanId) async => calls.add('retry:$scanId');

  @override
  Future<void> cancel(String scanId) async => calls.add('cancel:$scanId');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The persisted scan records the driver follows; tests set this state.
final fakeScanRecordsProvider = StateProvider<List<ScanRecord>>((_) => const []);

ScanRecord recordWith(String id, JobStatus status, {String? lastError}) =>
    ScanRecord(
      id: id,
      createdAt: DateTime(2026, 10, 15, 9),
      shots: const {},
      analysis: ScanAnalysis(status: status, lastError: lastError),
    );

final DateTime kDriverNow = DateTime(2026, 10, 15, 12);

List<Override> driverOverrides({
  FakeRunner? runner,
  BodyScanFlags flags = const BodyScanFlags(),
  BodyScanSettings settings = const BodyScanSettings(),
  List<WeightEntry> weights = const [],
}) {
  return [
    bodyScanRunnerProvider.overrideWithValue(runner),
    bodyScanFlagsProvider.overrideWithValue(flags),
    bodyScanSettingsProvider.overrideWith((ref) => Stream.value(settings)),
    weightEntriesProvider.overrideWithValue(AsyncData(weights)),
    nutritionClockProvider.overrideWithValue(() => kDriverNow),
    scanHistoryProvider
        .overrideWith((ref) async => ref.watch(fakeScanRecordsProvider)),
  ];
}
