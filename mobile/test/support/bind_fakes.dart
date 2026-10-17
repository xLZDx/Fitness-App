// Test-only fakes for the S03-0 bind state machine tests (journal availability).
// A controllable AccountScopedJournal (scripted, completer-held results, call
// and concurrency counters) and a fake timer factory with a virtual clock.
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Script entries: `bool`, an `Exception` (thrown) or a `Completer<bool>`
/// (held until the test completes it). An empty script means success.
class ControlledJournal extends Fake
    implements ActivityJournal, AccountScopedJournal, RecoveryReportSource {
  final List<String?> calls = [];
  final List<Object> script = [];
  int inFlight = 0;
  int maxInFlight = 0;
  JournalRecoveryReport? report;
  String? _uid;

  @override
  JournalRecoveryReport? get lastRecoveryReport => _uid == null ? null : report;

  @override
  Future<bool> bindUid(String? uid) async {
    calls.add(uid);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final Object r = script.isEmpty ? true : script.removeAt(0);
      if (r is Completer<bool>) {
        final v = await r.future;
        if (v) _uid = uid;
        return v;
      }
      if (r is Exception) throw r;
      if (r == true) _uid = uid;
      return r as bool;
    } finally {
      inFlight--;
    }
  }

  @override
  String? get boundUid => _uid;

  @override
  bool get isBound => _uid != null;
}

/// Implements ONLY the three bind members; any other call throws (Fake).
class MinimalJournal extends Fake
    implements ActivityJournal, AccountScopedJournal {
  final List<String?> calls = [];
  String? _uid;

  @override
  Future<bool> bindUid(String? uid) async {
    calls.add(uid);
    _uid = uid;
    return true;
  }

  @override
  String? get boundUid => _uid;

  @override
  bool get isBound => _uid != null;
}

class FakeBindTimer implements Timer {
  FakeBindTimer(this.delay, this.due, this._callback);

  final Duration delay;
  final Duration due;
  final void Function() _callback;
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

/// Fake timer factory with a virtual clock. [advance] fires due timers in
/// order of their deadline, letting microtasks run after each firing.
class FakeBindTimers {
  final List<FakeBindTimer> all = [];
  Duration now = Duration.zero;

  FakeBindTimer call(Duration delay, void Function() cb) {
    final t = FakeBindTimer(delay, now + delay, cb);
    all.add(t);
    return t;
  }

  int get active => all.where((t) => t.isActive).length;
  FakeBindTimer get last => all.last;

  Future<void> advance(Duration d) async {
    final target = now + d;
    while (true) {
      FakeBindTimer? next;
      for (final t in all) {
        if (t.isActive && t.due <= target && (next == null || t.due < next.due)) {
          next = t;
        }
      }
      if (next == null) break;
      now = next.due;
      next.fire();
      await pumpEventQueue();
    }
    now = target;
    await pumpEventQueue();
  }
}
