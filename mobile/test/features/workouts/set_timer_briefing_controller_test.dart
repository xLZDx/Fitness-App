import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/workouts/data/cue_player.dart';
import 'package:fitness_app/features/workouts/data/set_prescription.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

/// A coach whose "speech" ends only when the test says so, to prove the gate
/// really waits for the voice instead of for a clock.
class _SlowVoice extends MockVoiceCoach {
  _SlowVoice() : super(resolveText: (k) => k.name);

  /// Texts handed to [sayAndWait], in order.
  final List<String> waited = <String>[];
  final List<Completer<void>> speeches = <Completer<void>>[];

  /// When set, [sayAndWait] fails instead of speaking.
  Object? failWith;

  /// When true, [sayAndWait] throws synchronously instead of returning.
  bool throwSync = false;

  Completer<void> get last => speeches.last;

  @override
  Future<void> sayAndWait(String text) {
    waited.add(text);
    if (throwSync) throw StateError('engine exploded');
    if (failWith != null) return Future<void>.error(failWith!);
    final c = Completer<void>();
    speeches.add(c);
    return c.future;
  }
}

/// A recording cue player that also remembers ordering relative to nothing
/// else: [SilentCuePlayer] is enough, this alias keeps the harness readable.
typedef _H = ({
  ProviderContainer container,
  SilentCuePlayer player,
  _SlowVoice voice,
  SetTimerController ctl,
});

_H _harness() {
  final player = SilentCuePlayer();
  final voice = _SlowVoice();
  final c = ProviderContainer(overrides: [
    cuePlayerProvider.overrideWithValue(player),
    voiceCoachProvider.overrideWithValue(voice),
  ]);
  addTearDown(c.dispose);
  return (
    container: c,
    player: player,
    voice: voice,
    ctl: c.read(setTimerProvider.notifier),
  );
}

SetTimerState _s(_H h) => h.container.read(setTimerProvider);

const _plan = SetPlan(
    sets: 2, workSeconds: 3, restSeconds: 2, readySeconds: 3, cueLead: 2);

const _repPlan = SetPlan(
  sets: 2,
  workSeconds: 30,
  restSeconds: 2,
  readySeconds: 1,
  cueLead: 1,
  prescription: SetPrescription(mode: SetMode.reps, targetReps: 10, loadKg: 40),
);

const _sec = Duration(seconds: 1);

void main() {
  group('start enters the briefing and nothing runs', () {
    test('phase is briefing, running, with no clock and no cues', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(_s(h).phase, SetPhase.briefing);
        expect(_s(h).running, isTrue);
        expect(_s(h).setNumber, 0);
        expect(_s(h).secondsLeft, 0);
        expect(_s(h).isBriefing, isTrue);

        // Ten minutes in the gate: no tick sounds, no gong, no movement.
        async.elapse(const Duration(minutes: 10));
        expect(h.player.played, isEmpty);
        expect(_s(h).phase, SetPhase.briefing);
        expect(_s(h).setNumber, 0);
        expect(_s(h).secondsLeft, 0);
      });
    });

    test('there is no periodic timer driving the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('start without any intro still waits in the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        async.flushMicrotasks();
        expect(_s(h).phase, SetPhase.briefing);
        expect(_s(h).introSpeaking, isFalse,
            reason: 'nothing to speak, so the ready button is available');
        async.elapse(const Duration(seconds: 60));
        expect(_s(h).phase, SetPhase.briefing);
      });
    });
  });

  group('the intro is spoken in full', () {
    test('introSpeaking is true until the speech completes', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat. Two sets.');
        async.flushMicrotasks();
        expect(h.voice.waited, ['Squat. Two sets.']);
        expect(_s(h).introSpeaking, isTrue);

        async.elapse(const Duration(seconds: 5));
        expect(_s(h).introSpeaking, isTrue,
            reason: 'a long sentence is not cut by the clock');

        h.voice.last.complete();
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
        expect(_s(h).phase, SetPhase.briefing,
            reason: 'finishing the speech opens the gate, it does not start');
      });
    });

    test('the intro goes through sayAndWait exactly once', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        h.voice.last.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(h.voice.waited, ['Squat.']);
      });
    });

    test('timeout: 15 s + length/8; then speech is stopped and gate opens', () {
      fakeAsync((async) {
        final h = _harness();
        final text = 'x' * 80; // 15 + 80 ~/ 8 = 25 s
        h.ctl.start(_plan, spokenIntro: text);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24, milliseconds: 900));
        expect(_s(h).introSpeaking, isTrue, reason: 'cap is 25 s for 80 chars');
        expect(h.voice.stopCalls, 0);

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
        expect(h.voice.stopCalls, 1, reason: 'the stuck speech is cut');
        expect(_s(h).phase, SetPhase.briefing);
      });
    });

    test('timeout for a short text is 15 s', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Hi'); // 15 + 0
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 14, milliseconds: 900));
        expect(_s(h).introSpeaking, isTrue);
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
        expect(h.voice.stopCalls, 1);
      });
    });

    test('a longer text gets a longer cap', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'y' * 160); // 15 + 20 = 35 s
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 34));
        expect(_s(h).introSpeaking, isTrue);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
      });
    });

    test('speech finishing before the cap does not call stop', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.voice.last.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        expect(h.voice.stopCalls, 0);
      });
    });

    test('an engine error opens the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.voice.failWith = StateError('tts crashed');
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
        expect(_s(h).phase, SetPhase.briefing);
      });
    });

    test('an engine that throws synchronously also opens the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.voice.throwSync = true;
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
        expect(_s(h).phase, SetPhase.briefing);
      });
    });

    test('an error after speech started also opens the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isTrue);
        h.voice.last.completeError(StateError('mid-sentence failure'));
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
      });
    });

    test('voice off before start: nothing is said and there is no wait', () {
      fakeAsync((async) {
        final h = _harness();
        h.container.read(setVoiceEnabledProvider.notifier).state = false;
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        expect(_s(h).introSpeaking, isFalse, reason: 'synchronously');
        async.flushMicrotasks();
        expect(h.voice.waited, isEmpty);
        expect(_s(h).introSpeaking, isFalse);
        expect(_s(h).phase, SetPhase.briefing);
      });
    });

    test('a muted coach opens the gate at once', () {
      fakeAsync((async) {
        // The real default sayAndWait (say) returns immediately when muted.
        final player = SilentCuePlayer();
        final mock = MockVoiceCoach(resolveText: (k) => k.name)..setMuted(true);
        final c = ProviderContainer(overrides: [
          cuePlayerProvider.overrideWithValue(player),
          voiceCoachProvider.overrideWithValue(mock),
        ]);
        addTearDown(c.dispose);
        c.read(setTimerProvider.notifier).start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(c.read(setTimerProvider).introSpeaking, isFalse);
        expect(mock.spoken, isEmpty);
        expect(c.read(setTimerProvider).phase, SetPhase.briefing);
      });
    });

    test('an unmuted default coach speaks and then opens the gate', () {
      fakeAsync((async) {
        final mock = MockVoiceCoach(resolveText: (k) => k.name);
        final c = ProviderContainer(overrides: [
          cuePlayerProvider.overrideWithValue(SilentCuePlayer()),
          voiceCoachProvider.overrideWithValue(mock),
        ]);
        addTearDown(c.dispose);
        c.read(setTimerProvider.notifier).start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(mock.spoken, ['Squat.']);
        expect(c.read(setTimerProvider).introSpeaking, isFalse);
      });
    });

    test('switching voice off mid-sentence stops speech and opens the gate',
        () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat. Two sets.');
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isTrue);

        h.container.read(setVoiceEnabledProvider.notifier).state = false;
        async.flushMicrotasks();
        expect(h.voice.stopCalls, 1);
        expect(_s(h).introSpeaking, isFalse, reason: 'no waiting for a mute');
        expect(_s(h).phase, SetPhase.briefing);
      });
    });

    test('late completion of an abandoned intro cannot touch the state', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'First.');
        async.flushMicrotasks();
        h.container.read(setVoiceEnabledProvider.notifier).state = false;
        async.flushMicrotasks();
        h.container.read(setVoiceEnabledProvider.notifier).state = true;
        h.ctl.reset();
        h.ctl.start(_plan, spokenIntro: 'Second.');
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isTrue);

        // The first sentence finally reports "done": it is a stale token.
        h.voice.speeches.first.complete();
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isTrue,
            reason: 'the current intro is still speaking');

        h.voice.speeches.last.complete();
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isFalse);
      });
    });

    test('disposing the container while speaking is safe', () {
      fakeAsync((async) {
        final player = SilentCuePlayer();
        final voice = _SlowVoice();
        final c = ProviderContainer(overrides: [
          cuePlayerProvider.overrideWithValue(player),
          voiceCoachProvider.overrideWithValue(voice),
        ]);
        c.read(setTimerProvider.notifier).start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        c.dispose();
        voice.last.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        expect(player.played, isEmpty);
      });
    });
  });

  group('confirmReady starts the short countdown', () {
    test('countdown 3, ticks at 2 and 1, start gong, then work', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        async.flushMicrotasks();
        h.ctl.confirmReady();
        expect(_s(h).phase, SetPhase.gettingReady);
        expect(_s(h).secondsLeft, 3);
        expect(_s(h).running, isTrue);
        expect(h.player.played, isEmpty, reason: 'pressing ready makes no sound');

        async.elapse(_sec);
        expect(_s(h).secondsLeft, 2);
        expect(h.player.played, [SetCue.tick]);
        async.elapse(_sec);
        expect(_s(h).secondsLeft, 1);
        expect(h.player.played, [SetCue.tick, SetCue.tick]);
        async.elapse(_sec);
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 1);
        expect(h.player.played, [SetCue.tick, SetCue.tick, SetCue.startGong]);
      });
    });

    test('cues are muted but the countdown still runs', () {
      fakeAsync((async) {
        final h = _harness();
        h.container.read(setCuesMutedProvider.notifier).state = true;
        h.ctl.start(_plan);
        h.ctl.confirmReady();
        async.elapse(const Duration(seconds: 3));
        expect(_s(h).phase, SetPhase.work);
        expect(h.player.played, isEmpty);
      });
    });

    test('pressing ready while the intro still talks cuts the speech', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.ctl.confirmReady();
        async.flushMicrotasks();
        expect(h.voice.stopCalls, 1);
        expect(_s(h).introSpeaking, isFalse);
        expect(_s(h).phase, SetPhase.gettingReady);

        // The cancelled speech finishing later changes nothing.
        h.voice.last.complete();
        async.flushMicrotasks();
        expect(_s(h).phase, SetPhase.gettingReady);
      });
    });

    test('confirmReady is a no-op when idle, counting down or working', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.confirmReady();
        expect(_s(h).isIdle, isTrue);

        h.ctl.start(_plan);
        h.ctl.confirmReady();
        async.elapse(_sec);
        final left = _s(h).secondsLeft;
        h.ctl.confirmReady(); // double tap
        expect(_s(h).phase, SetPhase.gettingReady);
        expect(_s(h).secondsLeft, left);

        async.elapse(const Duration(seconds: 2));
        expect(_s(h).phase, SetPhase.work);
        h.ctl.confirmReady();
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 1);
      });
    });

    test('readySeconds 0 goes straight to work with the gong', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan.copyWith(readySeconds: 0));
        h.ctl.confirmReady();
        expect(_s(h).phase, SetPhase.work);
        expect(h.player.played, [SetCue.startGong]);
      });
    });

    test('a timed set then runs through rest to the end', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        h.ctl.confirmReady();
        async.elapse(const Duration(minutes: 2));
        expect(_s(h).isDone, isTrue);
        final n = h.player.played.length;
        async.elapse(const Duration(minutes: 2));
        expect(h.player.played.length, n);
        expect(h.player.played.where((c) => c == SetCue.startGong).length, 2);
        expect(h.player.played.where((c) => c == SetCue.endGong).length, 2);
      });
    });
  });

  group('pause, resume, skip, stop in the gate', () {
    test('pause while speaking cancels the speech and shows the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(_s(h).introSpeaking, isTrue);

        h.ctl.pause();
        async.flushMicrotasks();
        expect(h.voice.stopCalls, 1);
        expect(_s(h).introSpeaking, isFalse,
            reason: 'the ready button is shown while paused');
        expect(_s(h).running, isFalse);
        expect(_s(h).phase, SetPhase.briefing);
      });
    });

    test('resume does not repeat the intro and stays in the gate', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.ctl.pause();
        async.flushMicrotasks();
        h.ctl.start(_plan); // the card passes no intro on resume
        async.flushMicrotasks();
        expect(h.voice.waited, ['Squat.']);
        expect(_s(h).phase, SetPhase.briefing);
        expect(_s(h).running, isTrue);
        expect(_s(h).introSpeaking, isFalse);
        async.elapse(const Duration(seconds: 60));
        expect(_s(h).phase, SetPhase.briefing);
        expect(h.player.played, isEmpty);
      });
    });

    test('even a resume that carries an intro does not repeat it', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.ctl.pause();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(h.voice.waited.length, 1);
      });
    });

    test('the ready button works while paused', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        h.ctl.pause();
        expect(_s(h).running, isFalse);
        h.ctl.confirmReady();
        expect(_s(h).phase, SetPhase.gettingReady);
        expect(_s(h).running, isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(_s(h).phase, SetPhase.work);
      });
    });

    test('skip in the gate means ready, not skipping a set', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        h.ctl.skip();
        expect(_s(h).phase, SetPhase.gettingReady);
        expect(_s(h).setNumber, 0);
        expect(_s(h).secondsLeft, 3);
        async.elapse(const Duration(seconds: 3));
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 1);
      });
    });

    test('skip while the intro speaks cuts the speech and goes ready', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.ctl.skip();
        async.flushMicrotasks();
        expect(h.voice.stopCalls, 1);
        expect(_s(h).phase, SetPhase.gettingReady);
        expect(_s(h).introSpeaking, isFalse);
      });
    });

    test('stop in the gate resets to idle and silences the speech', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.ctl.reset();
        async.flushMicrotasks();
        expect(h.voice.stopCalls, 1);
        expect(_s(h).isIdle, isTrue);
        expect(_s(h).introSpeaking, isFalse);
        async.elapse(const Duration(seconds: 120));
        expect(h.player.played, isEmpty);
        expect(_s(h).isIdle, isTrue);
      });
    });

    test('stop after the speech finished does not call stop on the coach', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        h.voice.last.complete();
        async.flushMicrotasks();
        h.ctl.reset();
        async.flushMicrotasks();
        expect(h.voice.stopCalls, 0);
      });
    });

    test('a fresh start after stop briefs again', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        h.ctl.reset();
        h.ctl.start(_plan, spokenIntro: 'Squat.');
        async.flushMicrotasks();
        expect(h.voice.waited, ['Squat.', 'Squat.']);
        expect(_s(h).phase, SetPhase.briefing);
        expect(_s(h).introSpeaking, isTrue);
      });
    });

    test('pause during the countdown, then resume, finishes the countdown', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        h.ctl.confirmReady();
        async.elapse(_sec);
        h.ctl.pause();
        final left = _s(h).secondsLeft;
        async.elapse(const Duration(seconds: 30));
        expect(_s(h).secondsLeft, left);
        h.ctl.start(_plan);
        async.elapse(const Duration(seconds: 3));
        expect(_s(h).phase, SetPhase.work);
        expect(h.voice.waited, isEmpty, reason: 'no intro was ever given');
      });
    });
  });

  group('repetition based work', () {
    void toWork(_H h, FakeAsync async) {
      h.ctl.start(_repPlan);
      h.ctl.confirmReady();
      async.elapse(_sec); // readySeconds 1
    }

    test('work has no clock: nothing advances and nothing sounds', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 1);
        expect(_s(h).secondsLeft, 0);
        final played = List<SetCue>.of(h.player.played);
        expect(played, [SetCue.startGong]);

        async.elapse(const Duration(minutes: 30));
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 1);
        expect(h.player.played, played);
      });
    });

    test('skip (Done) ends the set into rest, which runs by the clock', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        h.ctl.skip();
        expect(_s(h).phase, SetPhase.rest);
        expect(_s(h).secondsLeft, 2);
        expect(h.player.played.last, SetCue.endGong);
        async.elapse(const Duration(seconds: 2));
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 2);
      });
    });

    test('Done on the last set ends the session and stops the clock', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        h.ctl.skip();
        async.elapse(const Duration(seconds: 2));
        h.ctl.skip();
        expect(_s(h).isDone, isTrue);
        expect(
            h.player.played.sublist(h.player.played.length - 2),
            [SetCue.endGong, SetCue.finished]);
        expect(async.pendingTimers, isEmpty,
            reason: 'finished: no periodic timer left running');
      });
    });

    test('pause then resume in rep work keeps the set', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        h.ctl.pause();
        async.elapse(const Duration(seconds: 30));
        expect(_s(h).phase, SetPhase.work);
        h.ctl.start(_repPlan);
        async.elapse(const Duration(seconds: 30));
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 1);
      });
    });

    test('Done while paused resumes into rest and the rest clock runs', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        h.ctl.pause();
        expect(_s(h).running, isFalse);
        h.ctl.finishRepSet();
        expect(_s(h).phase, SetPhase.rest);
        expect(_s(h).running, isTrue);
        expect(h.player.played.last, SetCue.endGong);
        async.elapse(const Duration(seconds: 2));
        expect(_s(h).phase, SetPhase.work);
        expect(_s(h).setNumber, 2, reason: 'the rest clock really ran');
      });
    });

    test('Done while running goes to rest the same way', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        h.ctl.finishRepSet();
        expect(_s(h).phase, SetPhase.rest);
        async.elapse(const Duration(seconds: 2));
        expect(_s(h).setNumber, 2);
      });
    });

    test('Done on the last set (even paused) finishes and stops the clock', () {
      fakeAsync((async) {
        final h = _harness();
        toWork(h, async);
        h.ctl.finishRepSet();
        async.elapse(const Duration(seconds: 2));
        h.ctl.pause();
        h.ctl.finishRepSet();
        expect(_s(h).isDone, isTrue);
        expect(async.pendingTimers, isEmpty, reason: 'no one-tick leak');
        expect(
            h.player.played.sublist(h.player.played.length - 2),
            [SetCue.endGong, SetCue.finished]);
      });
    });

    test('finishRepSet is a no-op in the gate, in rest and when idle', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.finishRepSet();
        expect(_s(h).isIdle, isTrue);
        h.ctl.start(_repPlan);
        h.ctl.finishRepSet();
        expect(_s(h).phase, SetPhase.briefing);
        h.ctl.confirmReady();
        h.ctl.finishRepSet();
        expect(_s(h).phase, SetPhase.gettingReady);
      });
    });

    test('skip that finishes a timed session stops the clock at once', () {
      fakeAsync((async) {
        final h = _harness();
        h.ctl.start(_plan);
        h.ctl.confirmReady();
        async.elapse(const Duration(seconds: 3)); // work, set 1
        h.ctl.skip(); // -> rest
        async.elapse(const Duration(seconds: 2)); // -> work, set 2
        h.ctl.skip(); // last set -> done
        expect(_s(h).isDone, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
