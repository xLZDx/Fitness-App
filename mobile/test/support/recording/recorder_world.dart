// Controller test world for the S04 recorder (EP-A..C tests). Wires the real
// RecorderController to FakeLocationSource, FakePermissionService,
// FakeBatteryMonitor and an in-memory journal port; time is driven by
// fake_async plus a clock the environment reads.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/location/fake_location_source.dart';
import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/location/location_providers.dart';
import 'package:fitness_app/features/recording/location/location_source.dart';
import 'package:fitness_app/features/recording/permissions/fake_permission_service.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/permissions/permission_providers.dart';
import 'package:fitness_app/features/recording/pipeline/geo.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/battery_monitor.dart';
import 'package:fitness_app/features/recording/state/recorder_controller.dart';
import 'package:fitness_app/features/recording/state/recorder_environment.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A journal port that records every call and writes nothing.
class MemoryJournalPort implements RecordingJournalPort {
  final List<RecordingMeta> begun = [];
  final List<({PipelineSample sample, GateCounters counters})> samples = [];
  final List<JournalEvent> events = [];
  final List<String> calls = [];
  final List<int> flushIntervals = [];
  int flushCount = 0;
  final List<({String id, SealRequest request})> seals = [];
  final List<String> deletes = [];
  final List<String> keeps = [];
  final List<String> quarantined = [];
  int handOffCount = 0;
  final StreamController<JournalFault> _faults =
      StreamController<JournalFault>.broadcast();

  Object? beginError;
  Completer<void>? beginGate;
  List<UnfinishedRecording> unfinished = const [];
  Object? listError;
  Object? sealError;
  Object? flushError;
  HandOffResult handOffResult = HandOffResult.done;
  Object? handOffError;
  RecoveredRecording? recovered;
  DecisionOutcome keepOutcome = DecisionOutcome.committed;
  DecisionOutcome deleteOutcome = DecisionOutcome.committed;
  Object? decideError;
  final List<String> abandoned = [];

  void fault(JournalFault f) => _faults.add(f);

  @override
  Stream<JournalFault> get faults => _faults.stream;

  @override
  Future<List<UnfinishedRecording>> listUnfinished() async {
    calls.add('listUnfinished');
    final e = listError;
    if (e != null) throw e;
    return unfinished;
  }

  @override
  Future<void> begin(RecordingMeta meta) async {
    calls.add('begin');
    final g = beginGate;
    if (g != null) await g.future;
    final e = beginError;
    if (e != null) throw e;
    begun.add(meta);
  }

  @override
  void enqueueSample(PipelineSample sample, GateCounters counters) {
    calls.add('sample');
    samples.add((sample: sample, counters: counters));
  }

  @override
  Future<void> appendEvent(JournalEvent event) async {
    calls.add('event:${event.kind.name}');
    events.add(event);
  }

  @override
  Future<void> flush() async {
    flushCount++;
    calls.add('flush');
    final e = flushError;
    if (e != null) throw e;
  }

  @override
  void setFlushIntervalMs(int ms) => flushIntervals.add(ms);

  @override
  Future<RecoveredRecording> openForResume(String recordingId) async {
    calls.add('openForResume');
    return recovered!;
  }

  @override
  Future<void> seal(String recordingId, SealRequest request) async {
    calls.add('seal');
    final e = sealError;
    if (e != null) throw e;
    seals.add((id: recordingId, request: request));
  }

  @override
  Future<HandOffResult> handOff(String recordingId) async {
    calls.add('handOff');
    handOffCount++;
    final e = handOffError;
    if (e != null) throw e;
    return handOffResult;
  }

  @override
  Future<DecisionOutcome> decideKeep(String recordingId) async {
    calls.add('decideKeep');
    keeps.add(recordingId);
    final e = decideError;
    if (e != null) throw e;
    return keepOutcome;
  }

  @override
  Future<DecisionOutcome> decideDelete(String recordingId) async {
    calls.add('decideDelete');
    deletes.add(recordingId);
    final e = decideError;
    if (e != null) throw e;
    return deleteOutcome;
  }

  @override
  Future<void> abandonActive(String recordingId) async {
    calls.add('abandonActive');
    abandoned.add(recordingId);
  }

  @override
  Future<void> quarantine(String recordingId) async {
    calls.add('quarantine');
    quarantined.add(recordingId);
  }

  List<JournalEventKind> get eventKinds => events.map((e) => e.kind).toList();
}

class FakeRecorderEnvironment implements RecorderEnvironment {
  FakeRecorderEnvironment(this.clock);
  final _Clock clock;

  @override
  String? openJournalOwnerUid = 'user-1';
  @override
  bool locationConsentGranted = true;
  @override
  bool gymTimerRunning = false;
  @override
  bool foreignSessionRunning = false;
  @override
  String? notificationTitle = 'Recording';
  @override
  String? notificationText = 'Activity in progress';
  @override
  bool requireNotificationPermission = false;
  int idCounter = 0;

  @override
  int nowUtcMs() => clock.nowMs;

  @override
  int utcOffsetMinutes() => 0;

  @override
  String newRecordingId() => 'rec-${++idCounter}';
}

class _Clock {
  int nowMs = 1700000000000;
}

/// One controller, its fakes and a time driver.
///
/// Time is driven by a manually created [FakeAsync]. Every call into the
/// controller goes through [run] so that its timers and futures live in the
/// fake zone. Stream `cancel()` futures complete through the root zone
/// (`Future._nullFuture`), so [settle] alternates fake microtask flushes with
/// real event-loop turns; all helpers are therefore `async`.
class RecorderWorld {
  RecorderWorld._(this.fa, LocationPermissionStatus permission,
      EngineDetachPolicy detachPolicy, LocationSource? custom)
      : location = FakeLocationSource(),
        permissions = FakePermissionService(location: permission),
        battery = FakeBatteryMonitor(),
        journal = MemoryJournalPort() {
    env = FakeRecorderEnvironment(_clock);
    container = ProviderContainer(overrides: [
      locationSourceProvider.overrideWithValue(custom ?? location),
      permissionServiceProvider.overrideWithValue(permissions),
      recordingJournalPortProvider.overrideWithValue(journal),
      recorderEnvironmentProvider.overrideWithValue(env),
      batteryMonitorProvider.overrideWithValue(battery),
      engineDetachPolicyProvider.overrideWithValue(detachPolicy),
    ]);
    states = [];
    fa.run((_) {
      container.listen<RecorderState>(
          recorderControllerProvider, (_, next) => states.add(next),
          fireImmediately: true);
    });
  }

  static RecorderWorld create({
    LocationPermissionStatus permission =
        LocationPermissionStatus.grantedPrecise,
    EngineDetachPolicy detachPolicy = EngineDetachPolicy.stopImmediately,
  }) =>
      RecorderWorld._(FakeAsync(), permission, detachPolicy, null);

  /// A world whose location source is [source] instead of the stock fake.
  static RecorderWorld createWithLocation(LocationSource source) =>
      RecorderWorld._(FakeAsync(), LocationPermissionStatus.grantedPrecise,
          EngineDetachPolicy.stopImmediately, source);

  final FakeAsync fa;
  final FakeLocationSource location;
  final FakePermissionService permissions;
  final FakeBatteryMonitor battery;
  final MemoryJournalPort journal;
  late final FakeRecorderEnvironment env;
  late final ProviderContainer container;
  late final List<RecorderState> states;
  final _Clock _clock = _Clock();

  RecorderController get controller =>
      container.read(recorderControllerProvider.notifier);
  RecorderState get state => container.read(recorderControllerProvider);
  RecorderPhase get phase => state.phase;

  /// Start time of the current recording (wall-clock ms).
  int get startMs => state.startUtcMs ?? _clock.nowMs;

  int get nowMs => _clock.nowMs;

  /// Seconds since the start of the current recording.
  double get secondsSinceStart => (_clock.nowMs - startMs) / 1000.0;

  /// Phases entered, in order, without consecutive duplicates.
  List<RecorderPhase> get phaseTrail {
    final out = <RecorderPhase>[];
    for (final s in states) {
      if (out.isEmpty || out.last != s.phase) out.add(s.phase);
    }
    return out;
  }

  /// Runs [f] inside the fake zone, then lets every pending future finish.
  Future<void> run(void Function() f) async {
    fa.run((_) => f());
    await settle();
  }

  /// Flushes fake microtasks and real event-loop turns until quiet.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      fa.flushMicrotasks();
      await Future<void>.delayed(Duration.zero);
    }
    fa.flushMicrotasks();
  }

  /// Advances fake time and the wall clock together in 100 ms steps.
  Future<void> advance(Duration d) async {
    var left = d.inMilliseconds;
    while (left > 0) {
      final step = left > 100 ? 100 : left;
      _clock.nowMs += step;
      fa.elapse(Duration(milliseconds: step));
      left -= step;
      // Only yield to the real loop once per second of fake time: enough for
      // cancel futures, cheap for long advances.
      if (left % 1000 == 0) await settle();
    }
    await settle();
  }

  /// Taps Start and lets the asynchronous start complete.
  Future<void> start({SportType sport = SportType.walking, bool? autoPause}) =>
      run(() => unawaited(
          controller.requestStart(sport: sport, autoPauseEnabled: autoPause)));

  Future<void> pause() => run(controller.pause);
  Future<void> resume() => run(controller.resume);
  Future<void> stop() => run(() => unawaited(controller.stop()));
  Future<void> discard() => run(() => unawaited(controller.discard()));
  Future<void> acknowledge() => run(controller.acknowledgeFinished);

  /// A fix [secondsAfterStart] seconds after Start, [eastM] metres east.
  Fix fixAt(double secondsAfterStart, double eastM,
      {double acc = 6, double? alt, double? speed, double northM = 0}) {
    final lat = 10.0 + northM / kMetresPerDegree;
    final lon = 20.0 + eastM / (kMetresPerDegree * cosLatDeg(10.0));
    return Fix(
      timeUtcMs: startMs + (secondsAfterStart * 1000).round(),
      latitude: lat,
      longitude: lon,
      accuracyMeters: acc,
      altitudeMeters: alt,
      speedMps: speed,
    );
  }

  /// Emits a fix and lets listeners run.
  Future<void> emit(Fix f) => run(() => location.emit(f));

  /// Emits a fix stamped with the current wall clock.
  Future<void> emitNow(double eastM,
          {double acc = 6, double? alt, double? speed}) =>
      emit(fixAt(secondsSinceStart, eastM, acc: acc, alt: alt, speed: speed));

  /// Walks [seconds] seconds at 1 Hz at [mps], one fix per second.
  /// Returns the eastward position reached.
  Future<double> walk(int seconds,
      {double mps = 1.4, double fromEastM = 0}) async {
    var x = fromEastM;
    for (var i = 0; i < seconds; i++) {
      await advance(const Duration(seconds: 1));
      x += mps;
      await emitNow(x, speed: mps);
    }
    return x;
  }

  /// Stands still for [seconds] seconds at [eastM] (provider speed [speed]).
  Future<void> stand(int seconds, double eastM, {double speed = 0.0}) async {
    for (var i = 0; i < seconds; i++) {
      await advance(const Duration(seconds: 1));
      await emitNow(eastM, speed: speed);
    }
  }

  Future<void> dispose() async {
    fa.run((_) => container.dispose());
    await settle();
  }
}
