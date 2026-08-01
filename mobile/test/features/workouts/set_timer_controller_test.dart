import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/workouts/data/cue_player.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

/// The timer against a real clock, faked.
///
/// [SetSession] is tested without any clock at all; this covers the layer that
/// owns one — that the ticks are actually driven, that the sounds are actually
/// played, and above all that stopping stops. A `Timer.periodic` that outlives
/// its page is the classic version of this bug: the user leaves mid-set and
/// the gongs keep going off in their pocket.
ExerciseItem _ex({String? equipmentId, List<String> steps = const []}) =>
    ExerciseItem(
      id: 'e',
      title: 'Plank',
      equipmentId: equipmentId,
      muscles: const ['core'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 5,
      summary: '',
      steps: steps,
    );

({ProviderContainer container, SilentCuePlayer player, MockVoiceCoach voice})
    harness() {
  final player = SilentCuePlayer();
  final voice = MockVoiceCoach(resolveText: (k) => k.name);
  final c = ProviderContainer(overrides: [
    cuePlayerProvider.overrideWithValue(player),
    voiceCoachProvider.overrideWithValue(voice),
  ]);
  addTearDown(c.dispose);
  return (container: c, player: player, voice: voice);
}

const quick =
    SetPlan(sets: 2, workSeconds: 3, restSeconds: 2, readySeconds: 1, cueLead: 1);

void main() {
  group('driving the clock', () {
    test('a started timer advances once a second', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(setTimerProvider.notifier).start(quick);
        expect(h.container.read(setTimerProvider).phase, SetPhase.gettingReady);

        async.elapse(const Duration(seconds: 1));
        expect(h.container.read(setTimerProvider).phase, SetPhase.work);
        expect(h.container.read(setTimerProvider).setNumber, 1);

        async.elapse(const Duration(seconds: 3));
        expect(h.container.read(setTimerProvider).phase, SetPhase.rest);
      });
    });

    test('it runs to the end and stops itself', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(setTimerProvider.notifier).start(quick);
        async.elapse(const Duration(seconds: 60));
        expect(h.container.read(setTimerProvider).isDone, isTrue);

        // And the clock is not still running underneath.
        final playedByNow = h.player.played.length;
        async.elapse(const Duration(seconds: 60));
        expect(h.player.played.length, playedByNow);
      });
    });

    test('pause stops the clock, resume picks it up', () {
      fakeAsync((async) {
        final h = harness();
        final ctl = h.container.read(setTimerProvider.notifier);
        ctl.start(quick);
        async.elapse(const Duration(seconds: 2));
        final left = h.container.read(setTimerProvider).secondsLeft;

        ctl.pause();
        async.elapse(const Duration(seconds: 30));
        expect(h.container.read(setTimerProvider).secondsLeft, left,
            reason: 'a paused timer must not advance');

        ctl.start(quick);
        async.elapse(const Duration(seconds: 1));
        expect(h.container.read(setTimerProvider).secondsLeft,
            lessThan(left));
      });
    });

    test('reset silences a running set', () {
      fakeAsync((async) {
        final h = harness();
        final ctl = h.container.read(setTimerProvider.notifier);
        ctl.start(quick);
        async.elapse(const Duration(seconds: 2));
        ctl.reset();
        final count = h.player.played.length;

        // This is the "gongs in your pocket" case.
        async.elapse(const Duration(seconds: 120));
        expect(h.player.played.length, count);
        expect(h.container.read(setTimerProvider).isIdle, isTrue);
      });
    });

    test('disposing the container kills the clock', () {
      fakeAsync((async) {
        final player = SilentCuePlayer();
        final c = ProviderContainer(overrides: [
          cuePlayerProvider.overrideWithValue(player),
          voiceCoachProvider
              .overrideWithValue(MockVoiceCoach(resolveText: (k) => k.name)),
        ]);
        c.read(setTimerProvider.notifier).start(quick);
        async.elapse(const Duration(seconds: 2));
        c.dispose();
        final count = player.played.length;
        async.elapse(const Duration(seconds: 120));
        expect(player.played.length, count);
      });
    });
  });

  group('sound', () {
    test('gongs and ticks reach the player', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(setTimerProvider.notifier).start(quick);
        async.elapse(const Duration(seconds: 60));
        expect(h.player.played.where((c) => c == SetCue.startGong).length, 2);
        expect(h.player.played.where((c) => c == SetCue.endGong).length, 2);
        expect(h.player.played, contains(SetCue.tick));
      });
    });

    test('muted means silent, and the set still runs', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(setCuesMutedProvider.notifier).state = true;
        h.container.read(setTimerProvider.notifier).start(quick);
        async.elapse(const Duration(seconds: 60));
        expect(h.player.played, isEmpty);
        expect(h.container.read(setTimerProvider).isDone, isTrue,
            reason: 'muting the speaker must not stop the timer');
      });
    });
  });

  group('voice', () {
    test('the intro is spoken once, at the start', () {
      fakeAsync((async) {
        final h = harness();
        h.container
            .read(setTimerProvider.notifier)
            .start(quick, spokenIntro: 'Plank. Two sets.');
        async.elapse(const Duration(seconds: 60));
        expect(h.voice.spoken, ['Plank. Two sets.']);
      });
    });

    test('resuming does not repeat the intro', () {
      fakeAsync((async) {
        final h = harness();
        final ctl = h.container.read(setTimerProvider.notifier);
        ctl.start(quick, spokenIntro: 'Plank.');
        async.elapse(const Duration(seconds: 1));
        ctl.pause();
        ctl.start(quick); // no intro on resume — the card passes null
        async.elapse(const Duration(seconds: 30));
        expect(h.voice.spoken.length, 1);
      });
    });

    test('voice off means nothing is said', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(setVoiceEnabledProvider.notifier).state = false;
        h.container
            .read(setTimerProvider.notifier)
            .start(quick, spokenIntro: 'Plank.');
        async.elapse(const Duration(seconds: 5));
        expect(h.voice.spoken, isEmpty);
      });
    });

    test('a muted coach stays muted even when asked directly', () {
      // `say` bypasses the cue gate but must not bypass mute — otherwise the
      // timer would talk over a user who silenced the form coach.
      final voice = MockVoiceCoach(resolveText: (k) => k.name)..setMuted(true);
      voice.say('anything');
      expect(voice.spoken, isEmpty);
    });
  });

  group('plans', () {
    test('experience picks the plan', () {
      expect(planFor(_ex(), FitnessTier.beginner), SetPlan.beginner);
      expect(planFor(_ex(), FitnessTier.advanced), SetPlan.advanced);
      expect(planFor(_ex(), null), SetPlan.intermediate,
          reason: 'an unanswered questionnaire gets the middle plan');
    });

    test('loaded work gets longer sets and a real rest', () {
      final floor = planFor(_ex(), FitnessTier.intermediate);
      final barbell =
          planFor(_ex(equipmentId: 'barbell'), FitnessTier.intermediate);
      expect(barbell.workSeconds, greaterThan(floor.workSeconds));
      expect(barbell.restSeconds, greaterThanOrEqualTo(60),
          reason: 'nobody re-racks a barbell in ten seconds');
    });

    test('an unknown equipment id is treated as bodyweight', () {
      expect(planFor(_ex(equipmentId: 'foam_roller'), FitnessTier.intermediate),
          SetPlan.intermediate);
    });
  });
}
