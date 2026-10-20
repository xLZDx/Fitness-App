// S03-01 DT-01-7: the mode state never resets or edits a running set or rest
// timer on an account switch (REAL controllers, injected clock, TP-2).
import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/workouts/data/cue_player.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mode_fakes.dart';

void main() {
  test('DT-01-7 an account switch never resets or edits a running set or rest '
      'timer; both keep ticking (real controllers, injected clock)', () {
    SharedPreferences.setMockInitialValues({});
    fakeAsync((async) {
      var now = DateTime.utc(2026, 10, 17, 12);
      final env = ModeEnv(initialUid: 'A', extra: [
        cuePlayerProvider.overrideWithValue(SilentCuePlayer()),
        voiceCoachProvider
            .overrideWithValue(MockVoiceCoach(resolveText: (k) => k.name)),
        restClockProvider.overrideWithValue(() => now),
      ]);
      final c = env.container;
      c.read(modeStateProvider);
      async.flushMicrotasks();
      expect(env.state.selectedMode, AppMode.train);

      const plan = SetPlan(
          sets: 3, workSeconds: 30, restSeconds: 10, readySeconds: 5, cueLead: 1);
      c.read(setTimerProvider.notifier).start(plan);
      c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      async.elapse(const Duration(seconds: 2));
      final setBefore = c.read(setTimerProvider);
      final restBefore = c.read(restTimerProvider);

      env.emitAuth('B');
      async.flushMicrotasks();
      expect(env.state, ModeState.initial(), reason: "B's own state");
      final setAfter = c.read(setTimerProvider);
      expect(setAfter.phase, setBefore.phase);
      expect(setAfter.secondsLeft, setBefore.secondsLeft);
      expect(setAfter.running, isTrue);
      expect(identical(c.read(restTimerProvider), restBefore), isTrue,
          reason: 'the rest state object was not replaced');
      expect(env.fake.writeCalls, 0);

      now = now.add(const Duration(seconds: 5));
      async.elapse(const Duration(seconds: 5));
      final setLater = c.read(setTimerProvider);
      expect(
          setLater.secondsLeft != setBefore.secondsLeft ||
              setLater.phase != setBefore.phase,
          isTrue,
          reason: 'the set timer must still tick after the switch');
      final rest = c.read(restTimerProvider);
      expect(rest.remaining(now), const Duration(seconds: 55),
          reason: 'rest deadline untouched: 60 s minus the 5 s of the injected clock');
    });
  });
}
