import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/widgets/rest_timer.dart';

void main() {
  group('RestTimerController', () {
    test('starts at totalSeconds, paused', () {
      final c = RestTimerController(totalSeconds: 60);
      expect(c.remaining, 60);
      expect(c.isRunning, isFalse);
      expect(c.progress, 0);
    });

    test('start() ticks at 1Hz down to 0', () {
      fakeAsync((async) {
        final c = RestTimerController(totalSeconds: 5);
        c.start();
        async.elapse(const Duration(seconds: 5));
        expect(c.remaining, 0);
        expect(c.isRunning, isFalse);
        expect(c.progress, 1.0);
      });
    });

    test('pause() halts the countdown', () {
      fakeAsync((async) {
        final c = RestTimerController(totalSeconds: 10);
        c.start();
        async.elapse(const Duration(seconds: 3));
        c.pause();
        async.elapse(const Duration(seconds: 5));
        expect(c.remaining, 7);
        expect(c.isRunning, isFalse);
      });
    });

    test('reset() returns remaining to totalSeconds', () {
      fakeAsync((async) {
        final c = RestTimerController(totalSeconds: 10);
        c.start();
        async.elapse(const Duration(seconds: 4));
        c.reset();
        expect(c.remaining, 10);
        expect(c.isRunning, isFalse);
        expect(c.progress, 0);
      });
    });

    test('progress reflects elapsed fraction', () {
      fakeAsync((async) {
        final c = RestTimerController(totalSeconds: 10);
        c.start();
        async.elapse(const Duration(seconds: 5));
        expect(c.progress, closeTo(0.5, 0.01));
      });
    });

    test('start() is idempotent', () {
      fakeAsync((async) {
        final c = RestTimerController(totalSeconds: 5);
        c.start();
        c.start();  // no-op, doesn't double-tick
        async.elapse(const Duration(seconds: 1));
        expect(c.remaining, 4);
      });
    });
  });
}
