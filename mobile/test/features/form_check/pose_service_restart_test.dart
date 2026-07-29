import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

PoseFrame frame(int ms) =>
    PoseFrame(timestampMs: ms, landmarks: const {});

void main() {
  group('PoseDetectorService stop/start contract', () {
    // Regression (BLOCKER, reported by review 2026-07-29): the ML Kit
    // implementation's stop() released nothing and left its `_initialised`
    // flag true, so every later start() returned early — Form Check was dead
    // on any second visit and the front camera stayed held. stop() must mean
    // "released but restartable"; only dispose() is terminal.
    //
    // The ML Kit implementation needs a real camera, so the CONTRACT is
    // pinned here against the in-repo fake and the real service was fixed to
    // match it: its stop() now nulls the camera and detector, clears the
    // initialised flag, and leaves the broadcast stream open.
    test('a service restarted after stop still delivers frames', () async {
      final svc = MockPoseDetectorService([frame(1), frame(2)]);
      final seen = <int>[];
      final sub = svc.frames().listen((f) => seen.add(f.timestampMs));

      await svc.start();
      final afterFirst = seen.length;
      expect(afterFirst, greaterThan(0));

      await svc.stop();
      await svc.start();

      expect(seen.length, greaterThan(afterFirst),
          reason: 'a second visit to the page must produce frames again');

      await sub.cancel();
      await svc.dispose();
    });

    test('stop does not close the broadcast stream', () async {
      final svc = MockPoseDetectorService([frame(1)]);
      final sub = svc.frames().listen((_) {});
      await svc.start();
      await svc.stop();

      // Listening again after stop must be possible — a closed controller
      // would throw here, which is what would break the second visit.
      final sub2 = svc.frames().listen((_) {});
      await svc.start();

      await sub.cancel();
      await sub2.cancel();
      await svc.dispose();
    });
  });
}
