// Shared test harness of the EP_F_G_J group (S04 battery, strip, GPS page,
// account events). Test-only. Not a test file: it has no `main`.
//
// It builds a REAL RecorderController (production state machine, pipeline and
// display projection) on top of scripted seams: FakeLocationSource,
// FakePermissionService, FakeBatteryMonitor, a scripted journal port and a
// scripted environment (clock, uid, consent, gym timer flags).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/location/fake_location_source.dart';
import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/location/location_providers.dart';
import 'package:fitness_app/features/recording/permissions/fake_permission_service.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/permissions/permission_providers.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/state/battery_monitor.dart';
import 'package:fitness_app/features/recording/state/recorder_controller.dart';
import 'package:fitness_app/features/recording/state/recorder_environment.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

/// Scripted journal port. Records every call, in order, in [calls].
class ScriptedJournal implements RecordingJournalPort {
  /// Ordered log of port calls, for example `begin`, `seal:battery`, `handOff`.
  final List<String> calls = <String>[];
  final List<JournalEvent> events = <JournalEvent>[];
  final List<PipelineSample> samples = <PipelineSample>[];
  final List<int> flushIntervals = <int>[];
  final StreamController<JournalFault> faultController =
      StreamController<JournalFault>.broadcast();

  List<UnfinishedRecording> unfinished = <UnfinishedRecording>[];
  Object? listError;
  Completer<List<UnfinishedRecording>>? listGate;
  Object? beginError;
  Completer<void>? beginGate;
  Object? sealError;
  HandOffResult handOffResult = HandOffResult.done;
  Object? handOffError;
  DecisionOutcome keepOutcome = DecisionOutcome.committed;
  DecisionOutcome deleteOutcome = DecisionOutcome.committed;
  RecordingMeta? lastMeta;
  SealRequest? lastSeal;
  RecoveredRecording? resumeResult;
  int listCalls = 0;
  int flushCalls = 0;

  List<String> get eventKinds =>
      events.map((e) => e.kind.name).toList(growable: false);

  @override
  Future<List<UnfinishedRecording>> listUnfinished() async {
    listCalls++;
    calls.add('listUnfinished');
    final gate = listGate;
    if (gate != null) return gate.future;
    final err = listError;
    if (err != null) throw err;
    return List<UnfinishedRecording>.of(unfinished);
  }

  @override
  Future<void> begin(RecordingMeta meta) async {
    calls.add('begin');
    lastMeta = meta;
    final gate = beginGate;
    if (gate != null) await gate.future;
    final err = beginError;
    if (err != null) throw err;
  }

  @override
  void enqueueSample(PipelineSample sample, GateCounters counters) {
    samples.add(sample);
  }

  @override
  Future<void> appendEvent(JournalEvent event) async {
    calls.add('event:${event.kind.name}');
    events.add(event);
  }

  @override
  Future<void> flush() async {
    flushCalls++;
    calls.add('flush');
  }

  @override
  void setFlushIntervalMs(int ms) {
    flushIntervals.add(ms);
  }

  @override
  Stream<JournalFault> get faults => faultController.stream;

  @override
  Future<RecoveredRecording> openForResume(String recordingId) async {
    calls.add('openForResume');
    final r = resumeResult;
    if (r == null) throw StateError('no resume result scripted');
    return r;
  }

  @override
  Future<void> seal(String recordingId, SealRequest request) async {
    calls.add('seal:${request.reason.name}');
    lastSeal = request;
    final err = sealError;
    if (err != null) throw err;
  }

  @override
  Future<HandOffResult> handOff(String recordingId) async {
    calls.add('handOff');
    final err = handOffError;
    if (err != null) throw err;
    return handOffResult;
  }

  @override
  Future<DecisionOutcome> decideKeep(String recordingId) async {
    calls.add('decideKeep');
    return keepOutcome;
  }

  @override
  Future<DecisionOutcome> decideDelete(String recordingId) async {
    calls.add('decideDelete');
    return deleteOutcome;
  }

  @override
  Future<void> quarantine(String recordingId) async {
    calls.add('quarantine');
  }
}

/// Scripted environment. [now] is the fake clock in UTC milliseconds.
class ScriptedEnv implements RecorderEnvironment {
  ScriptedEnv({this.now = 1700000000000});

  int now;
  String? ownerUid = 'uidA';
  bool consent = true;
  bool gymTimer = false;
  bool foreign = false;
  bool requireNotif = true;
  int idCounter = 0;

  @override
  String? get openJournalOwnerUid => ownerUid;
  @override
  bool get locationConsentGranted => consent;
  @override
  bool get gymTimerRunning => gymTimer;
  @override
  bool get foreignSessionRunning => foreign;
  @override
  int nowUtcMs() => now;
  @override
  int utcOffsetMinutes() => 0;
  @override
  String newRecordingId() => 'rec-${++idCounter}';
  @override
  String? get notificationTitle => 'Fitness App';
  @override
  String? get notificationText => 'Recording';
  @override
  bool get requireNotificationPermission => requireNotif;
}

/// A battery monitor whose `current()` can be scripted to throw or answer null.
class ThrowingBattery implements BatteryMonitor {
  @override
  Future<BatteryReading?> current() async => throw StateError('no battery');
  @override
  Stream<BatteryReading> get readings =>
      Stream<BatteryReading>.error(StateError('no battery stream'));
}

/// The scripted seams of one recorder, usable with a ProviderContainer or with
/// a widget-test ProviderScope (`overrides`).
class Seams {
  final ScriptedJournal journal = ScriptedJournal();
  final ScriptedEnv env = ScriptedEnv();
  final FakeBatteryMonitor battery = FakeBatteryMonitor();
  final FakeLocationSource location = FakeLocationSource();
  final FakePermissionService perms = FakePermissionService(
    location: LocationPermissionStatus.grantedPrecise,
    notification: NotificationPermissionStatus.granted,
  );

  List<Override> get overrides => <Override>[
        recordingJournalPortProvider.overrideWithValue(journal),
        recorderEnvironmentProvider.overrideWithValue(env),
        batteryMonitorProvider.overrideWithValue(battery),
        locationSourceProvider.overrideWithValue(location),
        permissionServiceProvider.overrideWithValue(perms),
      ];

  double _lat = 50.0;
  int? _lastFixMs;

  /// Emits one good fix at the current scripted time. The position moves
  /// [speed] metres per second since the previous fix, so the implied speed
  /// stays plausible whatever the interval between fixes is.
  void emitFix({double accuracy = 5, double? speed = 2.5}) {
    final last = _lastFixMs;
    final dt = last == null ? 1.0 : (env.now - last) / 1000.0;
    _lastFixMs = env.now;
    _lat += (speed ?? 2.5) * dt / 111195.0;
    location.emit(Fix(
      timeUtcMs: env.now,
      latitude: _lat,
      longitude: 10.0,
      accuracyMeters: accuracy,
      speedMps: speed,
    ));
  }
}

/// One recorder wired to scripted seams on a plain container, driven by a
/// WidgetTester: `tester.pump(d)` moves the fake timers (ticks, timeouts) and
/// `flush()` lets the real microtask chains (stream cancel, journal futures)
/// finish. Use it only through [rigTest].
class Rig {
  Rig(this.t, {List<Override> extra = const <Override>[]}) {
    container = ProviderContainer(overrides: <Override>[
      ...seams.overrides,
      ...extra,
    ]);
    // Keep the controller alive for the whole test.
    container.listen<RecorderState>(recorderControllerProvider, (_, next) {
      history.add(next);
    });
  }

  final WidgetTester t;
  final Seams seams = Seams();
  late final ProviderContainer container;
  final List<RecorderState> history = <RecorderState>[];

  ScriptedJournal get journal => seams.journal;
  ScriptedEnv get env => seams.env;
  FakeBatteryMonitor get battery => seams.battery;
  FakeLocationSource get location => seams.location;
  FakePermissionService get perms => seams.perms;

  RecorderController get controller =>
      container.read(recorderControllerProvider.notifier);
  RecorderState get state => container.read(recorderControllerProvider);
  RecorderPhase get phase => state.phase;

  /// Lets every pending microtask chain finish on the real event loop, then
  /// pumps the fake clock by nothing.
  Future<void> flush() async {
    for (var i = 0; i < 2; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pump(Duration.zero);
    }
  }

  /// Advances both the fake timers and the scripted clock, one second at a
  /// time, letting the async work of each step finish.
  Future<void> advance(Duration d) async {
    var left = d.inMilliseconds;
    while (left > 0) {
      final step = left > 1000 ? 1000 : left;
      left -= step;
      env.now += step;
      await t.pump(Duration(milliseconds: step));
      await flush();
    }
  }

  /// Calls Start and runs the checks to completion (acquiring).
  Future<void> start({SportType sport = SportType.running, bool? autoPause}) async {
    unawaited(controller.requestStart(sport: sport, autoPauseEnabled: autoPause));
    await flush();
  }

  /// Start, then deliver two good fixes so the phase becomes `recording`.
  Future<void> startRecording({SportType sport = SportType.running}) async {
    await start(sport: sport);
    await fix();
    await advance(const Duration(seconds: 1));
    await fix();
  }

  Future<void> fix({double accuracy = 5, double? speed = 2.5}) async {
    seams.emitFix(accuracy: accuracy, speed: speed);
    await flush();
  }

  /// Emits a battery reading and lets the controller react.
  Future<void> emitBattery(int percent, {bool charging = false}) async {
    battery.emit(percent, charging: charging);
    await flush();
  }

  Future<void> dispose() async {
    container.dispose();
    await flush();
  }
}

/// A widget test with a fresh [Rig] (the recorder on scripted seams).
void rigTest(String description, Future<void> Function(Rig rig) body,
    {List<Override> extra = const <Override>[]}) {
  testWidgets(description, (t) async {
    final rig = Rig(t, extra: extra);
    try {
      await body(rig);
    } finally {
      await rig.dispose();
    }
  });
}

UnfinishedRecording readableRecording([String id = 'old-1']) =>
    UnfinishedRecording(
      recordingId: id,
      status: UnfinishedStatus.readable,
      startUtcMs: 1700000000000 - 600000,
      sport: SportType.running,
      lastOffsetMs: 540000,
      sampleCount: 100,
    );
