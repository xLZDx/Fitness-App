// EP-G S04-24 strip sources (DT-24-1 to DT-24-6, DT-24-13, DT-24-15, DT-24-16):
// the prioritised, independent sources behind `activeSessionStatusProvider`.
// The REAL RecorderController feeds the GPS source; gym timers are scripted
// notifiers; the account is a scripted auth stream.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_display.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

import '../../../features/recording/pages/recorder_harness.dart';

const AuthUser kA = AuthUser(uid: 'uidA', displayName: 'A');
const AuthUser kB = AuthUser(uid: 'uidB', displayName: 'B');

class AuthCtl {
  AuthCtl(this.current);
  AuthUser? current;
  final StreamController<AuthUser?> _c = StreamController<AuthUser?>.broadcast();
  Override get override => authUserProvider.overrideWith((ref) async* {
        if (current != null) yield current;
        yield* _c.stream;
      });
  void set(AuthUser? u) {
    current = u;
    _c.add(u);
  }
}

class SetCtl extends SetTimerController {
  SetCtl(this.init);
  SetTimerState init;
  @override
  SetTimerState build() => init;
  void put(SetTimerState s) => state = s;
}

class RestCtl extends RestTimerController {
  @override
  RestTimerState build() => RestTimerState.idle;
  void put(RestTimerState s) => state = s;
}

SetTimerState setRunning() => const SetTimerState(
    phase: SetPhase.work,
    setNumber: 1,
    secondsLeft: 60,
    totalSets: 2,
    progress: 0.2,
    running: true);

class Fx {
  Fx(this.rig, this.auth, this.set, this.rest);
  final Rig rig;
  final AuthCtl auth;
  final SetCtl set;
  final RestCtl rest;
  ProviderContainer get c => rig.container;
  ActiveSessionStatus? get status => c.read(activeSessionStatusProvider);
  String? get gymOwner => c.read(activeSessionOwnerProvider)?.uid;
  String? get gpsOwner => c.read(gpsRecordingOwnerUidProvider);

  Future<void> startGym({String uid = 'uidA'}) async {
    c.read(activeSessionOwnerProvider.notifier)
        .capture(uid: uid, destination: '/workout/9');
    set.put(setRunning());
    await rig.flush();
  }

  Future<void> endGym() async {
    set.put(SetTimerState.idle);
    await rig.flush();
  }

  Future<void> signIn(AuthUser? u) async {
    auth.set(u);
    await rig.flush();
  }

  Future<void> endGps() async {
    unawaited(rig.controller.stop());
    await rig.flush();
    rig.controller.acknowledgeFinished();
    await rig.flush();
  }
}

void fxTest(String description, Future<void> Function(Fx f) body,
    {AuthUser? user = kA}) {
  final auth = AuthCtl(user);
  final set = SetCtl(SetTimerState.idle);
  final rest = RestCtl();
  rigTest(description, (rig) async {
    final f = Fx(rig, auth, set, rest);
    // keep the derived providers alive
    rig.container.listen(activeSessionStatusProvider, (_, __) {});
    rig.container.listen(gpsRecordingOwnerUidProvider, (_, __) {});
    rig.container.listen(activeSessionOwnerProvider, (_, __) {});
    await rig.flush();
    await body(f);
  }, extra: [
    auth.override,
    setTimerProvider.overrideWith(() => set),
    restTimerProvider.overrideWith(() => rest),
  ]);
}

void main() {
  group('DT-24-1 the provider can show a new source', () {
    test('a fake second source in activeSessionSourcesProvider is shown', () {
      final fake = StateProvider<ActiveSessionStatus?>((ref) =>
          const ActiveSessionStatus(
              kind: ActiveSessionKind.gpsRecording,
              state: ActiveSessionState.recording,
              destination: '/fake/route'));
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(kA)),
        activeSessionSourcesProvider.overrideWithValue([
          ActiveSessionSource(
              id: 'fake',
              priority: 5,
              status: fake,
              ownerUid: Provider<String?>((ref) => null)),
        ]),
      ]);
      addTearDown(c.dispose);
      c.listen(activeSessionStatusProvider, (_, __) {});
      expect(c.read(activeSessionStatusProvider)?.state,
          ActiveSessionState.recording);
      expect(c.read(activeSessionDestinationProvider), '/fake/route');
      c.read(fake.notifier).state = null;
      expect(c.read(activeSessionStatusProvider), isNull);
      expect(c.read(activeSessionDestinationProvider),
          kActiveSessionDefaultDestination);
    });

    test('registered ids and priorities: gym 10, gps 20', () {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(kA)),
        recordingJournalPortProvider.overrideWithValue(ScriptedJournal()),
        recorderEnvironmentProvider.overrideWithValue(ScriptedEnv()),
      ]);
      addTearDown(c.dispose);
      final sources = c.read(activeSessionSourcesProvider);
      expect(sources.map((s) => s.id), ['gymTimers', 'gpsRecording']);
      expect(kGymTimersSourcePriority, 10);
      expect(kGpsRecordingSourcePriority, 20);
      expect(kGpsRecordingSourcePriority, greaterThan(kGymTimersSourcePriority));
    });
  });

  group('DT-24-2 account switch hides, never clears', () {
    fxTest('/account-switch-hides: a GPS recording of A is invisible to B', (f) async {
        await f.rig.startRecording();
        expect(f.status?.kind, ActiveSessionKind.gpsRecording);
        expect(f.status?.ownerUid, 'uidA');
        await f.signIn(kB);
        expect(f.status, isNull, reason: 'B must not see A\'s recording');
        expect(f.c.read(activeSessionDestinationProvider),
            kActiveSessionDefaultDestination);
        await f.signIn(kA);
        expect(f.status?.kind, ActiveSessionKind.gpsRecording,
            reason: 'back to A: the recording is visible again');
    });

    fxTest('/foreign-skipped-not-cleared: both owner slots survive a switch', (f) async {
        await f.startGym();
        await f.rig.startRecording();
        expect(f.gymOwner, 'uidA');
        expect(f.gpsOwner, 'uidA');
        await f.signIn(kB);
        expect(f.status, isNull);
        expect(f.gymOwner, 'uidA', reason: 'gym owner not cleared by a switch');
        expect(f.gpsOwner, 'uidA', reason: 'gps owner not cleared by a switch');
        expect(f.rig.phase.isCollecting, isTrue,
            reason: 'the recorder is not touched by the strip');
        expect(f.rig.location.activeSubscriptions, 1);
    });

    fxTest('a transient null auth value hides the strip but changes no state', (f) async {
        await f.rig.startRecording();
        await f.signIn(null);
        expect(f.gpsOwner, 'uidA');
        expect(f.rig.phase, RecorderPhase.recording);
        await f.signIn(kA);
        expect(f.status?.kind, ActiveSessionKind.gpsRecording);
        expect(f.rig.journal.calls.where((c) => c.startsWith('seal')), isEmpty);
    });
  });

  group('DT-24-3 each source keeps its own owner', () {
    fxTest('/end-gps-keeps-gym-owner', (f) async {
        await f.startGym();
        await f.rig.startRecording();
        await f.endGps();
        expect(f.rig.phase, RecorderPhase.idle);
        expect(f.gpsOwner, isNull, reason: 'gps owner cleared when idle');
        expect(f.gymOwner, 'uidA');
        expect(f.status?.kind, ActiveSessionKind.gymWorkout);
    });

    fxTest('/end-gym-keeps-gps-owner', (f) async {
        await f.startGym();
        await f.rig.startRecording();
        await f.endGym();
        expect(f.gymOwner, isNull, reason: 'gym owner cleared with its session');
        expect(f.gpsOwner, 'uidA');
        expect(f.status?.kind, ActiveSessionKind.gpsRecording);
    });
  });

  group('DT-24-4 priority: a recording is never hidden by a timer', () {
    fxTest('/both-active-gps-wins', (f) async {
        await f.startGym();
        expect(f.status?.kind, ActiveSessionKind.gymWorkout);
        await f.rig.startRecording();
        expect(f.status?.kind, ActiveSessionKind.gpsRecording);
        expect(f.c.read(activeSessionDestinationProvider), kGpsRecordingDestination);
    });

    fxTest('/end-gps-shows-gym', (f) async {
        await f.startGym();
        await f.rig.startRecording();
        await f.endGps();
        expect(f.status?.kind, ActiveSessionKind.gymWorkout);
        expect(f.c.read(activeSessionDestinationProvider), '/workout/9');
    });

    fxTest('/end-gym-shows-gps', (f) async {
        await f.startGym();
        await f.rig.startRecording();
        await f.endGym();
        expect(f.status?.kind, ActiveSessionKind.gpsRecording);
    });

    test('flipping the two priorities flips the winner (D-12 one number)', () {
      final gps = Provider<ActiveSessionStatus?>((_) => const ActiveSessionStatus(
          kind: ActiveSessionKind.gpsRecording,
          state: ActiveSessionState.recording));
      final gym = Provider<ActiveSessionStatus?>((_) => const ActiveSessionStatus(
          kind: ActiveSessionKind.gymWorkout, state: ActiveSessionState.running));
      final none = Provider<String?>((_) => null);
      ProviderContainer build(int gpsP, int gymP) {
        final c = ProviderContainer(overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(kA)),
          activeSessionSourcesProvider.overrideWithValue([
            ActiveSessionSource(id: 'gym', priority: gymP, status: gym, ownerUid: none),
            ActiveSessionSource(id: 'gps', priority: gpsP, status: gps, ownerUid: none),
          ]),
        ]);
        c.listen(activeSessionStatusProvider, (_, __) {});
        return c;
      }

      final a = build(20, 10);
      final b = build(10, 20);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.read(activeSessionStatusProvider)?.kind, ActiveSessionKind.gpsRecording);
      expect(b.read(activeSessionStatusProvider)?.kind, ActiveSessionKind.gymWorkout);
    });
  });

  group('DT-24-5 activeSessionForeignOwnerProvider table', () {
    fxTest('nothing running: false', (f) async {
        expect(f.c.read(activeSessionForeignOwnerProvider), isFalse);
    });
    fxTest('foreign gym only: true (pill and rail slot hidden)', (f) async {
        await f.startGym(uid: 'uidB');
        expect(f.status, isNull);
        expect(f.c.read(activeSessionForeignOwnerProvider), isTrue);
    });
    fxTest('foreign gym plus own GPS recording: false, the recording shows', (f) async {
        await f.startGym(uid: 'uidB');
        await f.rig.startRecording();
        expect(f.c.read(activeSessionForeignOwnerProvider), isFalse);
        expect(f.status?.kind, ActiveSessionKind.gpsRecording);
    });
    fxTest('own gym only: false', (f) async {
        await f.startGym();
        expect(f.c.read(activeSessionForeignOwnerProvider), isFalse);
        expect(f.status?.kind, ActiveSessionKind.gymWorkout);
    });
    fxTest('foreign GPS recording only (switch): true', (f) async {
        await f.rig.startRecording();
        await f.signIn(kB);
        expect(f.c.read(activeSessionForeignOwnerProvider), isTrue);
    });
  });

  group('DT-24-6 the recovery word belongs to the recovery path only', () {
    test('the gym derivation never yields a GPS-only state', () {
      const gpsOnly = {
        ActiveSessionState.acquiring,
        ActiveSessionState.recording,
        ActiveSessionState.weakSignal,
        ActiveSessionState.autoPaused,
        ActiveSessionState.unfinished,
        ActiveSessionState.notRestored,
      };
      final now = DateTime.utc(2026, 10, 17, 12);
      final rests = <RestTimerState>[
        RestTimerState.idle,
        RestTimerState(
            total: const Duration(seconds: 60),
            endsAt: now.add(const Duration(seconds: 30))),
        const RestTimerState(
            total: Duration(seconds: 60), pausedRemaining: Duration(seconds: 5)),
        RestTimerState(
            total: const Duration(seconds: 60),
            endsAt: now.subtract(const Duration(minutes: 1))),
        const RestTimerState(skipped: true),
      ];
      for (final phase in SetPhase.values) {
        for (final running in [true, false]) {
          for (final rest in rests) {
            final s = deriveActiveSessionStatus(
              setTimer: SetTimerState(
                  phase: phase,
                  setNumber: 1,
                  secondsLeft: 5,
                  totalSets: 2,
                  progress: 0,
                  running: running),
              rest: rest,
              now: now,
            );
            if (s != null) {
              expect(gpsOnly.contains(s.state), isFalse, reason: '$phase $running');
              expect(s.kind, ActiveSessionKind.gymWorkout);
            }
          }
        }
      }
    });

    test('only restoring yields `unfinished`; only recoveryFailed `notRestored`',
        () {
      for (final h in RecorderDisplayState.values) {
        final s = deriveGpsRecordingStatus(
          display: RecorderDisplay(
              headline: h, banner: null, chips: const [], busy: false),
          movingSeconds: 5,
          ownerUid: 'u',
        );
        expect(s?.state == ActiveSessionState.unfinished,
            h == RecorderDisplayState.restoring,
            reason: '$h');
        expect(s?.state == ActiveSessionState.notRestored,
            h == RecorderDisplayState.recoveryFailed,
            reason: '$h');
      }
    });

    test('source scan: the workout code never names the recovery states', () {
      final dir = Directory('lib/features/workouts');
      expect(dir.existsSync(), isTrue, reason: 'cwd ${Directory.current.path}');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.replaceAll('\\', '/').endsWith('state/active_session_status.dart')) {
          continue;
        }
        final text = f.readAsStringSync();
        expect(text.contains('ActiveSessionState.unfinished'), isFalse, reason: f.path);
        expect(text.contains('ActiveSessionState.notRestored'), isFalse, reason: f.path);
        expect(text.contains('gpsStripUnfinished'), isFalse, reason: f.path);
      }
    });

    test('inside the status file `unfinished` is made only by the GPS derivation',
        () {
      final text = File('lib/features/workouts/state/active_session_status.dart')
          .readAsStringSync();
      final uses = RegExp(r'make\(ActiveSessionState\.unfinished\)')
          .allMatches(text)
          .length;
      expect(uses, 1);
      final start = text.indexOf('ActiveSessionStatus? deriveGpsRecordingStatus');
      final gymStart = text.indexOf('ActiveSessionStatus? deriveActiveSessionStatus');
      final gymEnd = text.indexOf('List<Duration> activeSessionTransitionDelays');
      final gymBody = text.substring(gymStart, gymEnd);
      expect(gymBody.contains('unfinished'), isFalse);
      expect(start, greaterThan(0));
    });
  });

  group('DT-24-13 phase table of the GPS derivation', () {
    RecorderState st(RecorderPhase p, {RecorderFlags? flags}) =>
        RecorderState(phase: p, flags: flags ?? const RecorderFlags());

    ActiveSessionStatus? of(RecorderState s, {int sec = 65}) =>
        deriveGpsRecordingStatus(
            display: displayOf(s), movingSeconds: sec, ownerUid: 'uidA');

    test('restoring gives unfinished, recoveryFailed gives notRestored', () {
      expect(of(st(RecorderPhase.restoring))?.state, ActiveSessionState.unfinished);
      expect(of(st(RecorderPhase.recoveryFailed))?.state,
          ActiveSessionState.notRestored);
      expect(of(st(RecorderPhase.restoring))?.remaining, isNull);
    });

    test('a pending revoked decision keeps a strip row (U4)', () {
      expect(of(st(RecorderPhase.permissionRevoked))?.state,
          ActiveSessionState.revoked);
    });

    test('finished and idle give no strip', () {
      for (final p in [
        RecorderPhase.finished,
        RecorderPhase.idle,
        RecorderPhase.preparing,
      ]) {
        expect(of(st(p)), isNull, reason: '$p');
      }
    });

    test('collecting phases and their words', () {
      expect(of(st(RecorderPhase.acquiring))?.state, ActiveSessionState.acquiring);
      expect(of(st(RecorderPhase.acquiring))?.remaining, isNull,
          reason: 'no time while acquiring');
      expect(of(st(RecorderPhase.recording))?.state, ActiveSessionState.recording);
      expect(
          of(st(RecorderPhase.recording,
                  flags: const RecorderFlags(poorAccuracy: true)))
              ?.state,
          ActiveSessionState.weakSignal);
      expect(of(st(RecorderPhase.pausedManual))?.state, ActiveSessionState.paused);
      expect(of(st(RecorderPhase.pausedAuto))?.state, ActiveSessionState.autoPaused);
      expect(of(st(RecorderPhase.stopping))?.state, ActiveSessionState.recording);
    });

    test('time is moving seconds, counts up, never negative', () {
      final s = of(st(RecorderPhase.recording), sec: 125)!;
      expect(s.remaining, const Duration(seconds: 125));
      expect(s.countsUp, isTrue);
      expect(of(st(RecorderPhase.recording), sec: -4)!.remaining, Duration.zero);
    });

    test('banner flags become the third-line note; storage wins over battery',
        () {
      final battery = of(st(RecorderPhase.recording,
          flags: const RecorderFlags(batteryCritical: true)))!;
      expect(battery.note, ActiveSessionNote.batteryCritical);
      final storage = of(st(RecorderPhase.recording,
          flags: const RecorderFlags(storageWriteFailing: true, batteryCritical: true)))!;
      expect(storage.note, ActiveSessionNote.storageWriteFailing);
      expect(of(st(RecorderPhase.recording))!.note, isNull);
    });

    test('every status carries the route and the owner uid, no mode label', () {
      final s = of(st(RecorderPhase.recording))!;
      expect(s.destination, kGpsRecordingDestination);
      expect(kGpsRecordingDestination, '/record/gps');
      expect(s.ownerUid, 'uidA');
      expect(s.mode, '');
      expect(s.kind, ActiveSessionKind.gpsRecording);
    });

    test('toString carries no content', () {
      expect(of(st(RecorderPhase.recording)).toString(),
          'ActiveSessionStatus(ActiveSessionKind.gpsRecording, ActiveSessionState.recording)');
    });
  });

  group('DT-24-15 the strip destination follows the winning source', () {
    fxTest('GPS wins: /record/gps; gym only: its own route; none: /workouts', (f) async {
        expect(f.c.read(activeSessionDestinationProvider), '/workouts');
        await f.startGym();
        expect(f.c.read(activeSessionDestinationProvider), '/workout/9');
        await f.rig.startRecording();
        expect(f.c.read(activeSessionDestinationProvider), '/record/gps');
    });
  });

  group('DT-24-16 recovery survives process death for GPS only', () {
    fxTest('/gps-survives-process-death: a fresh scope with an unfinished journal '
        'gives restoring and the unfinished strip word', (f) async {
        f.rig.journal.unfinished = [readableRecording()];
        unawaited(f.rig.controller.checkUnfinished());
        await f.rig.flush();
        expect(f.rig.phase, RecorderPhase.restoring);
        expect(f.status?.state, ActiveSessionState.unfinished);
        expect(f.status?.destination, '/record/gps');
        expect(f.gpsOwner, 'uidA',
            reason: 'a restored recording past idle is owned by the signed-in uid');
    });

    fxTest('/unreadable recording gives the not-restored word', (f) async {
        f.rig.journal.unfinished = [
          const UnfinishedRecording(
              recordingId: 'bad', status: UnfinishedStatus.unreadable)
        ];
        unawaited(f.rig.controller.checkUnfinished());
        await f.rig.flush();
        expect(f.rig.phase, RecorderPhase.recoveryFailed);
        expect(f.status?.state, ActiveSessionState.notRestored);
    });

    fxTest('/gym-timers-do-not: a fresh scope has no gym status', (f) async {
        expect(f.status, isNull);
        expect(f.gymOwner, isNull);
    });

    fxTest('the restored recording of A is invisible to B', (f) async {
        f.rig.journal.unfinished = [readableRecording()];
        unawaited(f.rig.controller.checkUnfinished());
        await f.rig.flush();
        await f.signIn(kB);
        expect(f.status, isNull);
    });
  });

  group('GPS owner controller', () {
    fxTest('captured when leaving idle, cleared on return to idle, not on a '
        'phase change inside a recording', (f) async {
        expect(f.gpsOwner, isNull);
        await f.rig.start();
        expect(f.gpsOwner, 'uidA');
        await f.signIn(kB); // switching must not re-capture
        await f.rig.fix();
        await f.rig.advance(const Duration(seconds: 1));
        await f.rig.fix();
        expect(f.gpsOwner, 'uidA', reason: 'never recomputed from current auth');
        await f.signIn(kA);
        await f.endGps();
        expect(f.gpsOwner, isNull);
    });
  });
}
