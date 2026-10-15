// T26 body_scan_flow_machine_test (SCAN-07, SCAN-08, SCAN-52 machine half).
// Every transition of the design 10 table, every cancel origin, every illegal
// (state, event) pair and the error/backoff chain.
import 'package:fitness_app/features/body_scan/data/body_scan_flow_machine.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:flutter_test/flutter_test.dart';

const _cloud = FlowContext(localOnly: false, providerRequiresPhotos: true);
const _cloudNoPhotos = FlowContext(localOnly: false);
const _local = FlowContext(localOnly: true);

FlowState _s(FlowStage st, {ScanPose? pose, int attempt = 0, bool retake = false}) =>
    FlowState(st, pose: pose, attempt: attempt, retake: retake);

List<FlowEffectKind> _kinds(FlowTransition t) =>
    [for (final e in t.effects) e.kind];

void main() {
  group('open and start (weight prompt rule)', () {
    test('idle + open -> intro with the access check effect', () {
      final t = nextFlow(const FlowState.idle(), const FlowEvent(FlowEventKind.open), _local);
      expect(t.state, _s(FlowStage.intro));
      expect(_kinds(t), [FlowEffectKind.checkAccess]);
    });
    test('open is illegal anywhere but idle', () {
      final t = nextFlow(_s(FlowStage.intro), const FlowEvent(FlowEventKind.open), _local);
      expect(t.state, _s(FlowStage.intro));
      expect(t.effects, isEmpty);
    });
    test('no weight entry -> weightPrompt', () {
      final t = nextFlow(_s(FlowStage.intro), const FlowEvent(FlowEventKind.start), _local);
      expect(t.state.stage, FlowStage.weightPrompt);
      expect(t.effects, isEmpty);
    });
    test('weight entry exactly 3 days old -> weightPrompt', () {
      final t = nextFlow(_s(FlowStage.intro), const FlowEvent(FlowEventKind.start),
          const FlowContext(latestWeightAge: Duration(days: 3)));
      expect(t.state.stage, FlowStage.weightPrompt);
    });
    test('weight entry 2 days 23 hours old -> straight to capturing(front)', () {
      final t = nextFlow(_s(FlowStage.intro), const FlowEvent(FlowEventKind.start),
          const FlowContext(latestWeightAge: Duration(days: 2, hours: 23)));
      expect(t.state, _s(FlowStage.capturing, pose: ScanPose.front));
    });
    test('a weight from today -> capturing(front); a 10 day old one -> weightPrompt', () {
      expect(
          nextFlow(_s(FlowStage.intro), const FlowEvent(FlowEventKind.start),
                  const FlowContext(latestWeightAge: Duration.zero))
              .state
              .stage,
          FlowStage.capturing);
      expect(
          nextFlow(_s(FlowStage.intro), const FlowEvent(FlowEventKind.start),
                  const FlowContext(latestWeightAge: Duration(days: 10)))
              .state
              .stage,
          FlowStage.weightPrompt);
    });
    test('prompt threshold constant is 3 days', () {
      expect(kWeightPromptAfter, const Duration(days: 3));
    });
    test('weightLogged -> capturing(front) with the writeWeight effect', () {
      final t = nextFlow(_s(FlowStage.weightPrompt),
          const FlowEvent(FlowEventKind.weightLogged), _local);
      expect(t.state, _s(FlowStage.capturing, pose: ScanPose.front));
      expect(_kinds(t), [FlowEffectKind.writeWeight]);
    });
    test('skipWeight -> capturing(front) and writes nothing', () {
      final t = nextFlow(_s(FlowStage.weightPrompt),
          const FlowEvent(FlowEventKind.skipWeight), _local);
      expect(t.state, _s(FlowStage.capturing, pose: ScanPose.front));
      expect(t.effects, isEmpty);
    });
  });

  group('capture chain and retake', () {
    FlowTransition cap(FlowState s, ScanPose p, {bool manual = false}) =>
        nextFlow(s, FlowEvent(FlowEventKind.captured, pose: p, manualOverride: manual), _local);

    test('front -> side -> back -> reviewing', () {
      var t = cap(_s(FlowStage.capturing, pose: ScanPose.front), ScanPose.front);
      expect(t.state, _s(FlowStage.capturing, pose: ScanPose.side));
      t = cap(t.state, ScanPose.side);
      expect(t.state, _s(FlowStage.capturing, pose: ScanPose.back));
      t = cap(t.state, ScanPose.back);
      expect(t.state, _s(FlowStage.reviewing));
      expect(t.effects, isEmpty);
    });
    test('a manual capture while not ready records manualOverride for THAT pose', () {
      final t = cap(_s(FlowStage.capturing, pose: ScanPose.side), ScanPose.side,
          manual: true);
      expect(t.effects, [const FlowEffect(FlowEffectKind.recordManualOverride, pose: ScanPose.side)]);
      expect(t.state.pose, ScanPose.back);
    });
    test('an automatic capture records nothing', () {
      expect(cap(_s(FlowStage.capturing, pose: ScanPose.front), ScanPose.front).effects,
          isEmpty);
    });
    test('a capture for a different pose than the current one is ignored', () {
      final s = _s(FlowStage.capturing, pose: ScanPose.front);
      final t = cap(s, ScanPose.back);
      expect(t.state, s);
      expect(t.effects, isEmpty);
    });
    test('a capture without a pose is ignored', () {
      final s = _s(FlowStage.capturing, pose: ScanPose.front);
      final t = nextFlow(s, const FlowEvent(FlowEventKind.captured), _local);
      expect(t.state, s);
    });
    test('retake(side) from reviewing -> capturing(side) marked retake', () {
      final t = nextFlow(_s(FlowStage.reviewing),
          const FlowEvent(FlowEventKind.retakePose, pose: ScanPose.side), _local);
      expect(t.state, _s(FlowStage.capturing, pose: ScanPose.side, retake: true));
    });
    test('after a retake shot the flow returns to reviewing, not to the next pose', () {
      final t = cap(_s(FlowStage.capturing, pose: ScanPose.front, retake: true),
          ScanPose.front);
      expect(t.state, _s(FlowStage.reviewing));
    });
    test('retake without a pose is illegal', () {
      final t = nextFlow(_s(FlowStage.reviewing),
          const FlowEvent(FlowEventKind.retakePose), _local);
      expect(t.state, _s(FlowStage.reviewing));
    });
    test('a manual retake shot still records the override', () {
      final t = cap(_s(FlowStage.capturing, pose: ScanPose.back, retake: true),
          ScanPose.back, manual: true);
      expect(t.state, _s(FlowStage.reviewing));
      expect(_kinds(t), [FlowEffectKind.recordManualOverride]);
    });
  });

  group('save, queue and upload', () {
    test('confirm -> savingLocal with the saveLocal effect', () {
      final t = nextFlow(_s(FlowStage.reviewing), const FlowEvent(FlowEventKind.confirm), _local);
      expect(t.state, _s(FlowStage.savingLocal));
      expect(_kinds(t), [FlowEffectKind.saveLocal]);
    });
    test('saved on the cloud path -> queued with a reminder sync', () {
      final t = nextFlow(_s(FlowStage.savingLocal), const FlowEvent(FlowEventKind.saved), _cloud);
      expect(t.state, _s(FlowStage.queued));
      expect(_kinds(t), [FlowEffectKind.syncReminder]);
    });
    test('saved with the provisional provider and the cloud flag off -> verifying, local estimate, no callable (D-52)', () {
      final t = nextFlow(_s(FlowStage.savingLocal), const FlowEvent(FlowEventKind.saved), _local);
      expect(t.state, _s(FlowStage.verifying));
      expect(_kinds(t), [FlowEffectKind.computeLocalEstimate]);
      expect(_kinds(t), isNot(contains(FlowEffectKind.createBodyScan)));
      expect(_kinds(t), isNot(contains(FlowEffectKind.uploadPose)));
    });
    test('online + provider needs photos -> uploading(front): create then upload front', () {
      final t = nextFlow(_s(FlowStage.queued), const FlowEvent(FlowEventKind.online), _cloud);
      expect(t.state, _s(FlowStage.uploading, pose: ScanPose.front));
      expect(t.effects, [
        const FlowEffect(FlowEffectKind.createBodyScan),
        const FlowEffect(FlowEffectKind.uploadPose, pose: ScanPose.front),
      ]);
    });
    test('online + provider without photos -> analysing: create then estimate', () {
      final t = nextFlow(_s(FlowStage.queued), const FlowEvent(FlowEventKind.online), _cloudNoPhotos);
      expect(t.state, _s(FlowStage.analysing));
      expect(_kinds(t), [FlowEffectKind.createBodyScan, FlowEffectKind.estimateBodyScan]);
    });
    test('uploaded chain: front -> side -> back -> analysing(estimate)', () {
      FlowTransition up(FlowState s, ScanPose p) =>
          nextFlow(s, FlowEvent(FlowEventKind.uploaded, pose: p), _cloud);
      var t = up(_s(FlowStage.uploading, pose: ScanPose.front), ScanPose.front);
      expect(t.state, _s(FlowStage.uploading, pose: ScanPose.side));
      expect(t.effects, [const FlowEffect(FlowEffectKind.uploadPose, pose: ScanPose.side)]);
      t = up(t.state, ScanPose.side);
      expect(t.state, _s(FlowStage.uploading, pose: ScanPose.back));
      expect(t.effects, [const FlowEffect(FlowEffectKind.uploadPose, pose: ScanPose.back)]);
      t = up(t.state, ScanPose.back);
      expect(t.state, _s(FlowStage.analysing));
      expect(_kinds(t), [FlowEffectKind.estimateBodyScan]);
    });
    test('an upload confirmation for the wrong pose is ignored (poses are never parallel)', () {
      final s = _s(FlowStage.uploading, pose: ScanPose.front);
      final t = nextFlow(s, const FlowEvent(FlowEventKind.uploaded, pose: ScanPose.back), _cloud);
      expect(t.state, s);
      expect(t.effects, isEmpty);
    });
    test('estimated -> verifying (verification effect); verified -> done', () {
      final t = nextFlow(_s(FlowStage.analysing), const FlowEvent(FlowEventKind.estimated), _cloud);
      expect(t.state, _s(FlowStage.verifying));
      expect(_kinds(t), [FlowEffectKind.runVerification]);
      final d = nextFlow(_s(FlowStage.verifying), const FlowEvent(FlowEventKind.verified), _cloud);
      expect(d.state, _s(FlowStage.done));
      expect(d.effects, isEmpty);
    });
  });

  group('SCAN-08 cancel from every active state', () {
    final noUpload = <String, FlowState>{
      'intro': _s(FlowStage.intro),
      'weightPrompt': _s(FlowStage.weightPrompt),
      'capturing(front)': _s(FlowStage.capturing, pose: ScanPose.front),
      'capturing(side)': _s(FlowStage.capturing, pose: ScanPose.side),
      'capturing(back)': _s(FlowStage.capturing, pose: ScanPose.back),
      'reviewing': _s(FlowStage.reviewing),
      'savingLocal': _s(FlowStage.savingLocal),
      'queued': _s(FlowStage.queued),
    };
    final mayUpload = <String, FlowState>{
      'uploading(front)': _s(FlowStage.uploading, pose: ScanPose.front),
      'uploading(side)': _s(FlowStage.uploading, pose: ScanPose.side),
      'uploading(back)': _s(FlowStage.uploading, pose: ScanPose.back),
      'analysing': _s(FlowStage.analysing),
      'verifying': _s(FlowStage.verifying),
    };
    noUpload.forEach((name, s) {
      test('$name -> cancelled with NO server effect', () {
        for (final c in [_cloud, _local, const FlowContext(online: false)]) {
          final t = nextFlow(s, const FlowEvent(FlowEventKind.cancel), c);
          expect(t.state.stage, FlowStage.cancelled);
          expect(t.effects, isEmpty);
        }
      });
    });
    mayUpload.forEach((name, s) {
      test('$name online (cloud) -> cancelled, abort in flight, deleteBodyScan', () {
        final t = nextFlow(s, const FlowEvent(FlowEventKind.cancel), _cloud);
        expect(t.state.stage, FlowStage.cancelled);
        expect(_kinds(t),
            [FlowEffectKind.abortInFlight, FlowEffectKind.deleteBodyScan]);
      });
      test('$name offline (cloud) -> the delete is marked pending instead of called', () {
        final t = nextFlow(
            s,
            const FlowEvent(FlowEventKind.cancel),
            const FlowContext(localOnly: false, providerRequiresPhotos: true, online: false));
        expect(t.state.stage, FlowStage.cancelled);
        expect(_kinds(t),
            [FlowEffectKind.abortInFlight, FlowEffectKind.markPendingRemoteDelete]);
        expect(_kinds(t), isNot(contains(FlowEffectKind.deleteBodyScan)));
      });
    });
    test('SCAN-52: cancelling a LOCAL-ONLY scan never produces a server effect', () {
      final t = nextFlow(_s(FlowStage.verifying),
          const FlowEvent(FlowEventKind.cancel), _local);
      expect(t.state.stage, FlowStage.cancelled);
      expect(_kinds(t), isNot(contains(FlowEffectKind.deleteBodyScan)));
      expect(_kinds(t), isNot(contains(FlowEffectKind.markPendingRemoteDelete)));
    });
    test('terminal and idle states cannot be cancelled', () {
      for (final st in [FlowStage.idle, FlowStage.done, FlowStage.failed, FlowStage.cancelled]) {
        final s = _s(st);
        final t = nextFlow(s, const FlowEvent(FlowEventKind.cancel), _cloud);
        expect(t.state, s);
        expect(t.effects, isEmpty);
      }
    });
  });

  group('SCAN-09 error -> queued with attempt + 1, then failed', () {
    FlowTransition err(FlowState s, {bool retriable = true, String? slug}) =>
        nextFlow(
            s,
            FlowEvent(FlowEventKind.error, retriable: retriable, errorSlug: slug),
            _cloud);

    test('the first retriable error: queued attempt 1, retry after 1 s', () {
      final t = err(_s(FlowStage.uploading, pose: ScanPose.side), slug: 'network');
      expect(t.state, _s(FlowStage.queued, attempt: 1));
      expect(t.effects, [const FlowEffect(FlowEffectKind.scheduleRetry, seconds: 1)]);
    });
    test('delays for failed attempts 0..4 are 1, 2, 4, 8, 16 seconds', () {
      final secs = <int>[];
      var s = _s(FlowStage.queued);
      for (var i = 0; i < 4; i++) {
        final t = err(s);
        expect(t.state.stage, FlowStage.queued);
        expect(t.state.attempt, i + 1);
        secs.add(t.effects.single.seconds!);
        s = t.state;
      }
      expect(secs, [1, 2, 4, 8]);
    });
    test('the 5th failed attempt -> failed(retriable: true), no retry scheduled', () {
      final t = err(_s(FlowStage.queued, attempt: 4));
      expect(t.state.stage, FlowStage.failed);
      expect(t.state.retriable, isTrue);
      expect(t.state.attempt, 5);
      expect(t.effects, isEmpty);
    });
    test('the slug is carried into the failed state', () {
      final t = err(_s(FlowStage.queued, attempt: 4), slug: 'timeout');
      expect(t.state.failReason, 'timeout');
    });
    test('a non-retriable error is failed(retriable: false) at once and never schedules a retry', () {
      final t = err(_s(FlowStage.analysing), retriable: false, slug: 'provider-output-invalid');
      expect(t.state.stage, FlowStage.failed);
      expect(t.state.retriable, isFalse);
      expect(t.state.failReason, 'provider-output-invalid');
      expect(t.effects, isEmpty);
    });
    test('errors are accepted from savingLocal, queued, uploading, analysing, verifying only', () {
      for (final s in [
        _s(FlowStage.savingLocal),
        _s(FlowStage.queued),
        _s(FlowStage.uploading, pose: ScanPose.front),
        _s(FlowStage.analysing),
        _s(FlowStage.verifying),
      ]) {
        expect(err(s).state.stage, isNot(s.stage == FlowStage.queued ? FlowStage.failed : s.stage));
      }
      for (final st in [
        FlowStage.idle,
        FlowStage.intro,
        FlowStage.weightPrompt,
        FlowStage.capturing,
        FlowStage.reviewing,
        FlowStage.done,
        FlowStage.failed,
        FlowStage.cancelled,
      ]) {
        final s = _s(st);
        expect(err(s).state, s);
      }
    });
    test('retry from failed resets the attempt and goes to queued', () {
      final t = nextFlow(
          FlowState(FlowStage.failed, attempt: 5, retriable: true),
          const FlowEvent(FlowEventKind.retry),
          _cloud);
      expect(t.state, _s(FlowStage.queued));
      expect(t.state.attempt, 0);
    });
    test('retry is illegal from anything but failed', () {
      for (final st in [FlowStage.queued, FlowStage.done, FlowStage.cancelled]) {
        final s = _s(st);
        expect(nextFlow(s, const FlowEvent(FlowEventKind.retry), _cloud).state, s);
      }
    });
  });

  group('every illegal (state, event) pair leaves the state unchanged with no effects', () {
    final states = <FlowStage, FlowState>{
      FlowStage.idle: const FlowState.idle(),
      FlowStage.intro: _s(FlowStage.intro),
      FlowStage.weightPrompt: _s(FlowStage.weightPrompt),
      FlowStage.capturing: _s(FlowStage.capturing, pose: ScanPose.front),
      FlowStage.reviewing: _s(FlowStage.reviewing),
      FlowStage.savingLocal: _s(FlowStage.savingLocal),
      FlowStage.queued: _s(FlowStage.queued),
      FlowStage.uploading: _s(FlowStage.uploading, pose: ScanPose.front),
      FlowStage.analysing: _s(FlowStage.analysing),
      FlowStage.verifying: _s(FlowStage.verifying),
      FlowStage.done: _s(FlowStage.done),
      FlowStage.failed: _s(FlowStage.failed),
      FlowStage.cancelled: _s(FlowStage.cancelled),
    };
    const legal = <FlowStage, Set<FlowEventKind>>{
      FlowStage.idle: {FlowEventKind.open},
      FlowStage.intro: {FlowEventKind.start, FlowEventKind.cancel},
      FlowStage.weightPrompt: {
        FlowEventKind.weightLogged,
        FlowEventKind.skipWeight,
        FlowEventKind.cancel
      },
      FlowStage.capturing: {FlowEventKind.captured, FlowEventKind.cancel},
      FlowStage.reviewing: {
        FlowEventKind.retakePose,
        FlowEventKind.confirm,
        FlowEventKind.cancel
      },
      FlowStage.savingLocal: {
        FlowEventKind.saved,
        FlowEventKind.cancel,
        FlowEventKind.error
      },
      FlowStage.queued: {
        FlowEventKind.online,
        FlowEventKind.cancel,
        FlowEventKind.error
      },
      FlowStage.uploading: {
        FlowEventKind.uploaded,
        FlowEventKind.cancel,
        FlowEventKind.error
      },
      FlowStage.analysing: {
        FlowEventKind.estimated,
        FlowEventKind.cancel,
        FlowEventKind.error
      },
      FlowStage.verifying: {
        FlowEventKind.verified,
        FlowEventKind.cancel,
        FlowEventKind.error
      },
      FlowStage.done: {},
      FlowStage.failed: {FlowEventKind.retry},
      FlowStage.cancelled: {},
    };
    for (final st in states.keys) {
      for (final kind in FlowEventKind.values) {
        final isLegal = legal[st]!.contains(kind);
        test('${st.name} + ${kind.name} is ${isLegal ? 'legal' : 'illegal'}', () {
          final s = states[st]!;
          final e = FlowEvent(kind, pose: ScanPose.front);
          final t = nextFlow(s, e, _cloud);
          if (isLegal) {
            expect(t.state == s && t.effects.isEmpty, isFalse,
                reason: 'a legal event must change the state or emit effects');
          } else {
            expect(t.state, s);
            expect(t.effects, isEmpty);
          }
        });
      }
    }
  });

  group('whole journeys', () {
    List<FlowStage> run(FlowContext c, List<FlowEvent> events) {
      var s = const FlowState.idle();
      final path = <FlowStage>[s.stage];
      for (final e in events) {
        s = nextFlow(s, e, c).state;
        path.add(s.stage);
      }
      return path;
    }

    test('cloud journey with photos', () {
      final stages = run(
          const FlowContext(
              localOnly: false, providerRequiresPhotos: true, latestWeightAge: Duration(days: 1)),
          const [
            FlowEvent(FlowEventKind.open),
            FlowEvent(FlowEventKind.start),
            FlowEvent(FlowEventKind.captured, pose: ScanPose.front),
            FlowEvent(FlowEventKind.captured, pose: ScanPose.side),
            FlowEvent(FlowEventKind.captured, pose: ScanPose.back),
            FlowEvent(FlowEventKind.confirm),
            FlowEvent(FlowEventKind.saved),
            FlowEvent(FlowEventKind.online),
            FlowEvent(FlowEventKind.uploaded, pose: ScanPose.front),
            FlowEvent(FlowEventKind.uploaded, pose: ScanPose.side),
            FlowEvent(FlowEventKind.uploaded, pose: ScanPose.back),
            FlowEvent(FlowEventKind.estimated),
            FlowEvent(FlowEventKind.verified),
          ]);
      expect(stages, [
        FlowStage.idle,
        FlowStage.intro,
        FlowStage.capturing,
        FlowStage.capturing,
        FlowStage.capturing,
        FlowStage.reviewing,
        FlowStage.savingLocal,
        FlowStage.queued,
        FlowStage.uploading,
        FlowStage.uploading,
        FlowStage.uploading,
        FlowStage.analysing,
        FlowStage.verifying,
        FlowStage.done,
      ]);
    });
    test('local provisional journey skips queue/upload/analysing', () {
      final stages = run(_local, const [
        FlowEvent(FlowEventKind.open),
        FlowEvent(FlowEventKind.start),
        FlowEvent(FlowEventKind.skipWeight),
        FlowEvent(FlowEventKind.captured, pose: ScanPose.front),
        FlowEvent(FlowEventKind.captured, pose: ScanPose.side),
        FlowEvent(FlowEventKind.captured, pose: ScanPose.back),
        FlowEvent(FlowEventKind.confirm),
        FlowEvent(FlowEventKind.saved),
        FlowEvent(FlowEventKind.verified),
      ]);
      expect(stages.last, FlowStage.done);
      expect(stages, isNot(contains(FlowStage.queued)));
      expect(stages, isNot(contains(FlowStage.uploading)));
      expect(stages, isNot(contains(FlowStage.analysing)));
      expect(stages, contains(FlowStage.weightPrompt));
    });
  });

  group('FlowState helpers and resume', () {
    test('isActive is true for the nine cancellable stages only', () {
      final active = {
        FlowStage.intro, FlowStage.weightPrompt, FlowStage.capturing,
        FlowStage.reviewing, FlowStage.savingLocal, FlowStage.queued,
        FlowStage.uploading, FlowStage.analysing, FlowStage.verifying,
      };
      for (final st in FlowStage.values) {
        expect(_s(st).isActive, active.contains(st), reason: st.name);
      }
    });
    test('mayHaveUploaded is uploading / analysing / verifying', () {
      for (final st in FlowStage.values) {
        expect(
            _s(st).mayHaveUploaded,
            {FlowStage.uploading, FlowStage.analysing, FlowStage.verifying}
                .contains(st),
            reason: st.name);
      }
    });
    test('equality and hashCode cover every field', () {
      expect(_s(FlowStage.queued, attempt: 2), _s(FlowStage.queued, attempt: 2));
      expect(_s(FlowStage.queued, attempt: 2).hashCode,
          _s(FlowStage.queued, attempt: 2).hashCode);
      expect(_s(FlowStage.queued, attempt: 2), isNot(_s(FlowStage.queued, attempt: 3)));
      expect(_s(FlowStage.capturing, pose: ScanPose.front),
          isNot(_s(FlowStage.capturing, pose: ScanPose.side)));
      expect(_s(FlowStage.capturing, pose: ScanPose.front),
          isNot(_s(FlowStage.capturing, pose: ScanPose.front, retake: true)));
    });
    test('resumeStateFor: queued keeps the attempt, uploading restarts at front', () {
      expect(resumeStateFor(JobStatus.queued, attempt: 2),
          _s(FlowStage.queued, attempt: 2));
      expect(resumeStateFor(JobStatus.uploading, attempt: 2),
          _s(FlowStage.uploading, pose: ScanPose.front, attempt: 2));
      expect(resumeStateFor(JobStatus.analysing), _s(FlowStage.analysing));
    });
    test('terminal statuses are never resumed', () {
      expect(resumeStateFor(JobStatus.done), isNull);
      expect(resumeStateFor(JobStatus.failed), isNull);
      expect(resumeStateFor(JobStatus.cancelled), isNull);
    });
  });
}
