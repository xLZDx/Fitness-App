import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/body_scan/body_scan_flow_page.dart'
    show bodyScanActiveScanIdProvider;
import 'package:fitness_app/features/body_scan/data/body_scan_flow_machine.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_flow_driver.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/scan_flow_controller.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';

import '../support/driver_harness.dart';

const _cloud = BodyScanFlags(cloudPhotos: true);
const _consented = BodyScanSettings(cloudConsentVersion: kBodyScanCloudConsentVersion);

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Rig {
  _Rig(this.container, this.runner) {
    container.listen(scanFlowControllerProvider, (_, __) {});
    driver = container.listen(bodyScanFlowDriverProvider, (_, __) {}).read();
  }
  final ProviderContainer container;
  final FakeRunner runner;
  late final BodyScanFlowDriver driver;

  ScanFlowController get ctl =>
      container.read(scanFlowControllerProvider.notifier);
  ScanFlowSnapshot get snap => container.read(scanFlowControllerProvider);
  FlowStage get stage => snap.state.stage;
  String? get activeId => container.read(bodyScanActiveScanIdProvider);

  void send(FlowEventKind k) => ctl.dispatch(FlowEvent(k));

  /// intro -> capturing front (fresh weight on file).
  Future<void> toCapturing() async {
    await _settle();
    send(FlowEventKind.open);
    send(FlowEventKind.start);
    await _settle();
  }

  void setRecords(List<dynamic> r) =>
      container.read(fakeScanRecordsProvider.notifier).state = List.of(r.cast());
}

Future<_Rig> _rig({
  BodyScanFlags flags = const BodyScanFlags(),
  BodyScanSettings settings = const BodyScanSettings(),
  List<WeightEntry>? weights,
}) async {
  final runner = FakeRunner();
  final container = ProviderContainer(
    overrides: driverOverrides(
      runner: runner,
      flags: flags,
      settings: settings,
      weights: weights ??
          [WeightEntry(at: kDriverNow.subtract(const Duration(hours: 2)), kg: 80)],
    ),
  );
  addTearDown(container.dispose);
  // Keeps the settings stream alive so valueOrNull is populated.
  container.listen(bodyScanSettingsProvider, (_, __) {});
  await _settle();
  final rig = _Rig(container, runner);
  await _settle();
  return rig;
}

void main() {
  group('flowContextFor', () {
    final now = DateTime(2026, 10, 15, 12);

    test('flag off: local only, no photos required', () {
      final c = flowContextFor(
          flags: const BodyScanFlags(),
          settings: _consented,
          now: now,
          latestWeightAt: null);
      expect(c.localOnly, isTrue);
      expect(c.providerRequiresPhotos, isFalse);
      expect(c.latestWeightAge, isNull);
    });

    test('cloud flag on but no consent: still local only (D-5)', () {
      final c = flowContextFor(
          flags: _cloud,
          settings: const BodyScanSettings(),
          now: now,
          latestWeightAt: null);
      expect(c.localOnly, isTrue);
      expect(c.providerRequiresPhotos, isTrue);
    });

    test('cloud flag on with current consent: not local only', () {
      final c = flowContextFor(
          flags: _cloud, settings: _consented, now: now, latestWeightAt: null);
      expect(c.localOnly, isFalse);
    });

    test('an outdated consent version does not count', () {
      final c = flowContextFor(
          flags: _cloud,
          settings: const BodyScanSettings(cloudConsentVersion: 0),
          now: now,
          latestWeightAt: null);
      expect(c.localOnly, isTrue);
    });

    test('weight age is now minus the latest weigh-in', () {
      final c = flowContextFor(
          flags: const BodyScanFlags(),
          settings: const BodyScanSettings(),
          now: now,
          latestWeightAt: now.subtract(const Duration(days: 4, hours: 1)));
      expect(c.latestWeightAge, const Duration(days: 4, hours: 1));
    });
  });

  group('context from the app state', () {
    test('the newest weigh-in sets the age, regardless of list order', () async {
      final r = await _rig(weights: [
        WeightEntry(at: kDriverNow.subtract(const Duration(days: 5)), kg: 81),
        WeightEntry(at: kDriverNow.subtract(const Duration(hours: 3)), kg: 80),
        WeightEntry(at: kDriverNow.subtract(const Duration(days: 9)), kg: 82),
      ]);
      expect(r.snap.context.latestWeightAge, const Duration(hours: 3));
    });

    test('no weigh-ins gives a null age so the weight prompt appears', () async {
      final r = await _rig(weights: const []);
      expect(r.snap.context.latestWeightAge, isNull);
      r.send(FlowEventKind.open);
      r.send(FlowEventKind.start);
      expect(r.stage, FlowStage.weightPrompt);
    });

    test('flags and consent reach the controller context', () async {
      final r = await _rig(flags: _cloud, settings: _consented);
      expect(r.snap.context.localOnly, isFalse);
      expect(r.snap.context.providerRequiresPhotos, isTrue);
    });
  });

  group('captureReturned (local only path)', () {
    test('a scan id replays the captures and reaches verifying with one '
        'runner resume', () async {
      final r = await _rig();
      await r.toCapturing();
      expect(r.stage, FlowStage.capturing);
      r.driver.captureReturned('scan-1');
      await _settle();
      expect(r.activeId, 'scan-1');
      expect(r.stage, FlowStage.verifying);
      expect(r.runner.calls, ['resume']);
    });

    test('a null id from capturing cancels the flow without touching the '
        'runner', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned(null);
      await _settle();
      expect(r.stage, FlowStage.cancelled);
      expect(r.runner.calls, isEmpty);
      expect(r.activeId, isNull);
    });

    test('a null id outside capturing is ignored', () async {
      final r = await _rig();
      await _settle();
      r.send(FlowEventKind.open);
      r.driver.captureReturned(null);
      expect(r.stage, FlowStage.intro);
    });

    test('a saved record with done status advances verifying to done',
        () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.done)]);
      await _settle();
      expect(r.stage, FlowStage.done);
    });

    test('a record of ANOTHER scan does not finish this flow', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('other', JobStatus.done)]);
      await _settle();
      expect(r.stage, FlowStage.verifying);
    });

    test('a queued or analysing record changes nothing', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.analysing)]);
      await _settle();
      expect(r.stage, FlowStage.verifying);
    });

    test('a failed record moves to failed with the stored slug', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.failed, lastError: 'internal')]);
      await _settle();
      expect(r.stage, FlowStage.failed);
      expect(r.snap.state.failReason, 'internal');
      expect(r.snap.state.retriable, isFalse);
    });

    test('a failed record without a slug uses the generic one', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.failed)]);
      await _settle();
      expect(r.snap.state.failReason, 'failed');
    });

    test('once done, a later failed record is ignored', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.done)]);
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.failed)]);
      await _settle();
      expect(r.stage, FlowStage.done);
    });
  });

  group('save failure', () {
    test('saveLocal without a scan id fails non-retriably as save-failed',
        () async {
      final r = await _rig();
      await r.toCapturing();
      for (final p in [0, 1, 2]) {
        r.ctl.dispatch(FlowEvent(FlowEventKind.captured,
            pose: r.snap.state.pose));
        expect(p, isNonNegative);
      }
      r.send(FlowEventKind.confirm);
      await _settle();
      expect(r.stage, FlowStage.failed);
      expect(r.snap.state.failReason, 'save-failed');
      expect(r.snap.state.retriable, isFalse);
      expect(r.runner.calls, isEmpty);
    });
  });

  group('cloud path', () {
    test('saved -> queued -> online -> uploading, runner resumed', () async {
      final r = await _rig(flags: _cloud, settings: _consented);
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      expect(r.stage, FlowStage.uploading);
      expect(r.runner.calls, ['resume']);
    });

    test('a done record walks uploading -> ... -> done', () async {
      final r = await _rig(flags: _cloud, settings: _consented);
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.done)]);
      await _settle();
      expect(r.stage, FlowStage.done);
    });

    test('without consent the cloud flag still runs the local path', () async {
      final r = await _rig(flags: _cloud);
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      expect(r.stage, FlowStage.verifying);
    });
  });

  group('cancel and retry', () {
    test('cancel while verifying cancels the runner once', () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.runner.calls.clear();
      r.send(FlowEventKind.cancel);
      await _settle();
      expect(r.stage, FlowStage.cancelled);
      expect(r.runner.calls, ['cancel:scan-1']);
    });

    test('cancel before any scan exists never calls the runner', () async {
      final r = await _rig();
      await r.toCapturing();
      r.send(FlowEventKind.cancel);
      await _settle();
      expect(r.stage, FlowStage.cancelled);
      expect(r.runner.calls, isEmpty);
    });

    test('retry from failed asks the runner to retry the same scan once',
        () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned('scan-1');
      await _settle();
      r.setRecords([recordWith('scan-1', JobStatus.failed, lastError: 'x')]);
      await _settle();
      r.runner.calls.clear();
      r.send(FlowEventKind.retry);
      await _settle();
      expect(r.stage, FlowStage.queued);
      expect(r.runner.calls, ['retry:scan-1']);
    });
  });

  group("deleteFailedScan (D-78)", () {
    test("cancels the scan on the runner and returns the flow to idle", () async {
      final r = await _rig();
      await r.toCapturing();
      r.driver.captureReturned("scan-1");
      await _settle();
      r.setRecords([recordWith("scan-1", JobStatus.failed, lastError: "x")]);
      await _settle();
      expect(r.stage, FlowStage.failed);
      r.runner.calls.clear();
      r.driver.deleteFailedScan();
      await _settle();
      expect(r.runner.calls, ["cancel:scan-1"]);
      expect(r.stage, FlowStage.idle);
    });

    test("without a scan id it only resets", () async {
      final r = await _rig();
      await _settle();
      r.send(FlowEventKind.open);
      r.driver.deleteFailedScan();
      expect(r.runner.calls, isEmpty);
      expect(r.stage, FlowStage.idle);
    });
  });

  group("no runner (signed out)", () {
    test('the flow still advances and nothing throws', () async {
      final container = ProviderContainer(
          overrides: driverOverrides(weights: [
        WeightEntry(at: kDriverNow.subtract(const Duration(hours: 1)), kg: 80)
      ]));
      addTearDown(container.dispose);
      container.listen(scanFlowControllerProvider, (_, __) {});
      container.listen(bodyScanSettingsProvider, (_, __) {});
      final driver =
          container.listen(bodyScanFlowDriverProvider, (_, __) {}).read();
      await _settle();
      final ctl = container.read(scanFlowControllerProvider.notifier);
      ctl.dispatch(const FlowEvent(FlowEventKind.open));
      ctl.dispatch(const FlowEvent(FlowEventKind.start));
      await _settle();
      driver.captureReturned('scan-1');
      await _settle();
      expect(container.read(scanFlowControllerProvider).state.stage,
          FlowStage.verifying);
      ctl.dispatch(const FlowEvent(FlowEventKind.cancel));
      await _settle();
      expect(container.read(scanFlowControllerProvider).state.stage,
          FlowStage.cancelled);
    });
  });

  group('lifecycle', () {
    test('after the container is disposed, late calls are ignored', () async {
      final r = await _rig();
      await r.toCapturing();
      final driver = r.driver;
      r.container.dispose();
      expect(() => driver.captureReturned('scan-1'), returnsNormally);
    });
  });
}
