import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/body_scan_flow_machine.dart';
import 'package:fitness_app/features/body_scan/state/scan_flow_controller.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';

FlowEvent _e(FlowEventKind k, {ScanPose? pose, bool retriable = true}) =>
    FlowEvent(k, pose: pose, retriable: retriable, errorSlug: 'x');

ScanFlowController _make() => ScanFlowController();

void main() {
  group('initial state', () {
    test('starts idle with no effects, default context and revision 0', () {
      final c = _make();
      expect(c.state.state.stage, FlowStage.idle);
      expect(c.state.effects, isEmpty);
      expect(c.state.revision, 0);
      expect(c.state.context.localOnly, isTrue);
      expect(c.state.context.latestWeightAge, isNull);
    });
  });

  group('dispatch', () {
    test('open moves idle to intro and requests checkAccess', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      expect(c.state.state.stage, FlowStage.intro);
      expect(c.state.effects, [const FlowEffect(FlowEffectKind.checkAccess)]);
      expect(c.state.revision, 1);
    });

    test('revision increments on every dispatch, also an illegal one', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.open)); // illegal in intro
      expect(c.state.revision, 2);
      expect(c.state.state.stage, FlowStage.intro);
    });

    test('illegal event leaves the state unchanged and clears the effects', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      expect(c.state.effects, isNotEmpty);
      c.dispatch(_e(FlowEventKind.verified));
      expect(c.state.state.stage, FlowStage.intro);
      expect(c.state.effects, isEmpty);
    });

    test('start with no weight on file goes to the weight prompt', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      expect(c.state.state.stage, FlowStage.weightPrompt);
    });

    test('start with a 2 day old weight skips the prompt', () {
      final c = _make();
      c.updateContext(const FlowContext(latestWeightAge: Duration(days: 2)));
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      expect(c.state.state.stage, FlowStage.capturing);
      expect(c.state.state.pose, ScanPose.front);
    });

    test('a weight exactly 3 days old still prompts (boundary)', () {
      final c = _make();
      c.updateContext(const FlowContext(latestWeightAge: Duration(days: 3)));
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      expect(c.state.state.stage, FlowStage.weightPrompt);
    });

    test('weightLogged writes the weight and starts the front capture', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      c.dispatch(_e(FlowEventKind.weightLogged));
      expect(c.state.state.stage, FlowStage.capturing);
      expect(c.state.effects, [const FlowEffect(FlowEffectKind.writeWeight)]);
    });

    test('skipWeight starts the capture with no effect', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      c.dispatch(_e(FlowEventKind.skipWeight));
      expect(c.state.state.stage, FlowStage.capturing);
      expect(c.state.effects, isEmpty);
    });
  });

  group('updateContext', () {
    test('keeps the stage and revision and clears the effects', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      final rev = c.state.revision;
      c.updateContext(const FlowContext(localOnly: false));
      expect(c.state.state.stage, FlowStage.intro);
      expect(c.state.effects, isEmpty);
      expect(c.state.revision, rev);
      expect(c.state.context.localOnly, isFalse);
    });

    test('the new context drives the next transition (cloud path queues)', () {
      final c = _make();
      c.updateContext(const FlowContext(
          latestWeightAge: Duration(hours: 1), localOnly: false));
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      for (final p in ScanPose.ordered) {
        c.dispatch(_e(FlowEventKind.captured, pose: p));
      }
      expect(c.state.state.stage, FlowStage.reviewing);
      c.dispatch(_e(FlowEventKind.confirm));
      expect(c.state.effects, [const FlowEffect(FlowEffectKind.saveLocal)]);
      c.dispatch(_e(FlowEventKind.saved));
      expect(c.state.state.stage, FlowStage.queued);
      expect(c.state.effects, [const FlowEffect(FlowEffectKind.syncReminder)]);
    });
  });

  group('full local-only journey', () {
    test('open to done runs the verifying stage and ends done', () {
      final c = _make();
      c.updateContext(const FlowContext(latestWeightAge: Duration(hours: 5)));
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      for (final p in ScanPose.ordered) {
        c.dispatch(_e(FlowEventKind.captured, pose: p));
      }
      c.dispatch(_e(FlowEventKind.confirm));
      c.dispatch(_e(FlowEventKind.saved));
      expect(c.state.state.stage, FlowStage.verifying);
      expect(c.state.effects,
          [const FlowEffect(FlowEffectKind.computeLocalEstimate)]);
      c.dispatch(_e(FlowEventKind.verified));
      expect(c.state.state.stage, FlowStage.done);
      expect(c.state.state.isActive, isFalse);
    });
  });

  group('cancel and failure', () {
    test('cancel from capturing ends cancelled; a second cancel is illegal', () {
      final c = _make();
      c.updateContext(const FlowContext(latestWeightAge: Duration(hours: 1)));
      c.dispatch(_e(FlowEventKind.open));
      c.dispatch(_e(FlowEventKind.start));
      c.dispatch(_e(FlowEventKind.cancel));
      expect(c.state.state.stage, FlowStage.cancelled);
      final rev = c.state.revision;
      c.dispatch(_e(FlowEventKind.cancel));
      expect(c.state.state.stage, FlowStage.cancelled);
      expect(c.state.effects, isEmpty);
      expect(c.state.revision, rev + 1);
    });

    test('a fatal error in verifying lands in failed and retry requeues', () {
      final c = _make();
      c.updateContext(const FlowContext(latestWeightAge: Duration(hours: 1)));
      for (final k in [FlowEventKind.open, FlowEventKind.start]) {
        c.dispatch(_e(k));
      }
      for (final p in ScanPose.ordered) {
        c.dispatch(_e(FlowEventKind.captured, pose: p));
      }
      c.dispatch(_e(FlowEventKind.confirm));
      c.dispatch(_e(FlowEventKind.saved));
      c.dispatch(_e(FlowEventKind.error, retriable: false));
      expect(c.state.state.stage, FlowStage.failed);
      expect(c.state.state.retriable, isFalse);
      expect(c.state.state.failReason, 'x');
      c.dispatch(_e(FlowEventKind.retry));
      expect(c.state.state.stage, FlowStage.queued);
    });

    test('a retriable error schedules a backoff retry instead of failing', () {
      final c = _make();
      c.updateContext(const FlowContext(
          latestWeightAge: Duration(hours: 1), localOnly: false));
      for (final k in [FlowEventKind.open, FlowEventKind.start]) {
        c.dispatch(_e(k));
      }
      for (final p in ScanPose.ordered) {
        c.dispatch(_e(FlowEventKind.captured, pose: p));
      }
      c.dispatch(_e(FlowEventKind.confirm));
      c.dispatch(_e(FlowEventKind.saved));
      c.dispatch(_e(FlowEventKind.error));
      expect(c.state.state.stage, FlowStage.queued);
      expect(c.state.state.attempt, 1);
      expect(c.state.effects.single.kind, FlowEffectKind.scheduleRetry);
      expect(c.state.effects.single.seconds, 1);
    });
  });

  group('reset', () {
    test('returns to idle, keeps the context, resets the revision', () {
      final c = _make();
      c.updateContext(const FlowContext(localOnly: false));
      c.dispatch(_e(FlowEventKind.open));
      c.reset();
      expect(c.state.state.stage, FlowStage.idle);
      expect(c.state.effects, isEmpty);
      expect(c.state.revision, 0);
      expect(c.state.context.localOnly, isFalse);
    });

    test('a new open works after reset', () {
      final c = _make();
      c.dispatch(_e(FlowEventKind.open));
      c.reset();
      c.dispatch(_e(FlowEventKind.open));
      expect(c.state.state.stage, FlowStage.intro);
    });
  });

  group('provider', () {
    test('is autoDispose: a fresh container starts idle again', () async {
      final container = ProviderContainer();
      final sub = container.listen(scanFlowControllerProvider, (_, __) {});
      container
          .read(scanFlowControllerProvider.notifier)
          .dispatch(_e(FlowEventKind.open));
      expect(sub.read().state.stage, FlowStage.intro);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      final sub2 = container.listen(scanFlowControllerProvider, (_, __) {});
      expect(sub2.read().state.stage, FlowStage.idle);
      container.dispose();
    });

    test('listeners see every dispatch, including repeated equal effects', () {
      final container = ProviderContainer();
      final seen = <int>[];
      container.listen(scanFlowControllerProvider, (_, n) => seen.add(n.revision),
          fireImmediately: false);
      final c = container.read(scanFlowControllerProvider.notifier);
      c.dispatch(_e(FlowEventKind.verified)); // illegal
      c.dispatch(_e(FlowEventKind.verified)); // illegal again
      expect(seen, [1, 2]);
      container.dispose();
    });
  });
}
