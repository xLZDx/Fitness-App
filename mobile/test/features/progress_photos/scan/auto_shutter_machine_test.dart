import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/scan/auto_shutter_machine.dart';

/// Deterministic driver: a fake clock stepping in fixed increments.
class Rig {
  Rig({int stepMs = 100, AutoShutterConfig? config})
      : step = stepMs,
        m = AutoShutterMachine(config: config ?? const AutoShutterConfig());
  final AutoShutterMachine m;
  final int step;
  int now = 0;
  final log = <ShutterEvent>[];

  List<ShutterEvent> tick({required bool ready}) {
    final e = m.update(now, ready: ready);
    log.addAll(e);
    now += step;
    return e;
  }

  void run(int ms, {required bool ready}) {
    final end = now + ms;
    while (now < end) {
      tick(ready: ready);
    }
  }

  Iterable<ShutterEvent> of(ShutterEventType t) =>
      log.where((e) => e.type == t);
}

void main() {
  test('stable readiness fires exactly 4.0 s after it began', () {
    final r = Rig();
    r.run(5000, ready: true);
    expect(r.of(ShutterEventType.holdStart).single.atMs, 0);
    expect(
      r.of(ShutterEventType.tick).map((e) => (e.value, e.atMs)).toList(),
      [(3, 1000), (2, 2000), (1, 3000)],
    );
    expect(r.of(ShutterEventType.shutter).single.atMs, 4000);
    expect(r.of(ShutterEventType.poseDone).single.atMs, 4000);
    expect(r.of(ShutterEventType.cancelled), isEmpty);
  });

  test('shutter is followed by poseDone in the same update, in order', () {
    final r = Rig();
    List<ShutterEvent> last = [];
    for (var i = 0; i <= 40; i++) {
      last = r.tick(ready: true);
    }
    expect(last.map((e) => e.type), [
      ShutterEventType.shutter,
      ShutterEventType.poseDone,
    ]);
  });

  test('jittery frame times do not move the anchored schedule', () {
    final m = AutoShutterMachine();
    final times = [0, 130, 260, 400, 530, 700, 820, 1010, 1130, 1300, 1480];
    final events = <ShutterEvent>[];
    for (final t in times) {
      events.addAll(m.update(t, ready: true));
    }
    // Tick 3 is due at 1000; the first update at/after it is 1010.
    expect(
        events.where((e) => e.type == ShutterEventType.tick).single.atMs, 1010);
  });

  test('losing readiness before the hold ends never starts a countdown', () {
    final r = Rig();
    r.run(900, ready: true);
    r.tick(ready: false);
    expect(r.of(ShutterEventType.tick), isEmpty);
    expect(r.of(ShutterEventType.cancelled), hasLength(1));
    expect(r.m.state, ShutterState.idle);
  });

  test('a single flicker during holding cancels; the hold restarts from zero',
      () {
    final r = Rig();
    r.run(800, ready: true);
    r.tick(ready: false); // at 800
    r.run(4500, ready: true); // restarts at 900
    expect(r.of(ShutterEventType.holdStart).map((e) => e.atMs), [0, 900]);
    expect(r.of(ShutterEventType.shutter).single.atMs, 900 + 4000);
  });

  test('flicker during the countdown cancels with one cancelled event', () {
    final r = Rig();
    r.run(2500, ready: true); // ticks 3 and 2 shown
    r.tick(ready: false);
    expect(r.of(ShutterEventType.cancelled).single.atMs, 2500);
    expect(r.m.state, ShutterState.idle);
    expect(r.m.currentTick, isNull);
    r.run(500, ready: false);
    expect(r.of(ShutterEventType.shutter), isEmpty);
  });

  test("lost readiness while '1' is showing cancels", () {
    final r = Rig();
    r.run(3300, ready: true); // tick 1 emitted at 3000
    expect(r.m.currentTick, 1);
    r.tick(ready: false);
    expect(r.of(ShutterEventType.cancelled), hasLength(1));
    expect(r.of(ShutterEventType.shutter), isEmpty);
  });

  test('not ready exactly at the shutter instant cancels instead of firing',
      () {
    final r = Rig();
    r.run(4000, ready: true); // last update at 3900
    expect(r.now, 4000);
    r.tick(ready: false);
    expect(r.of(ShutterEventType.shutter), isEmpty);
    expect(r.of(ShutterEventType.cancelled), hasLength(1));
  });

  test('no double fire while ready stays true; cooldown spaces the shots', () {
    final r = Rig();
    r.run(4100, ready: true);
    expect(r.of(ShutterEventType.shutter), hasLength(1));
    expect(r.m.state, ShutterState.cooldown);
    r.run(2800, ready: true); // to 6900, cooldown ends at 7000
    expect(r.of(ShutterEventType.shutter), hasLength(1));
    expect(r.of(ShutterEventType.holdStart), hasLength(1));
    r.run(4500, ready: true);
    expect(r.of(ShutterEventType.shutter), hasLength(2));
    expect(r.of(ShutterEventType.holdStart).last.atMs, 7000);
    expect(r.of(ShutterEventType.shutter).last.atMs, 11000);
    expect(
      r.of(ShutterEventType.shutter).last.atMs -
          r.of(ShutterEventType.shutter).first.atMs,
      greaterThanOrEqualTo(const AutoShutterConfig().cooldownMs),
    );
  });

  test('readiness changes during cooldown produce no events', () {
    final r = Rig();
    r.run(4100, ready: true);
    final before = r.log.length;
    r.run(1000, ready: false);
    expect(r.log.length, before);
  });

  test('a long gap between updates is treated as lost readiness', () {
    final m = AutoShutterMachine();
    m.update(0, ready: true);
    m.update(100, ready: true);
    final e = m.update(2000, ready: true); // 1.9 s unobserved
    expect(e.map((x) => x.type), [ShutterEventType.cancelled]);
    expect(m.state, ShutterState.idle);
  });

  test('a clock going backwards cancels', () {
    final m = AutoShutterMachine();
    m.update(1000, ready: true);
    final e = m.update(900, ready: true);
    expect(e.map((x) => x.type), [ShutterEventType.cancelled]);
  });

  test('idle with not-ready produces nothing', () {
    final r = Rig();
    r.run(2000, ready: false);
    expect(r.log, isEmpty);
  });

  test('reset returns to idle silently and restarts cleanly', () {
    final r = Rig();
    r.run(2500, ready: true);
    r.m.reset();
    expect(r.m.state, ShutterState.idle);
    final before = r.log.length;
    r.tick(ready: true);
    expect(r.log.length, before + 1);
    expect(r.log.last.type, ShutterEventType.holdStart);
  });

  test('custom config: 2-1 countdown, zero hold', () {
    final r = Rig(
      config: const AutoShutterConfig(holdMs: 0, countdownFrom: 2, tickMs: 500),
    );
    r.run(1500, ready: true);
    expect(r.of(ShutterEventType.tick).map((e) => e.value), [2, 1]);
    expect(r.of(ShutterEventType.shutter).single.atMs, 1000);
  });
}
