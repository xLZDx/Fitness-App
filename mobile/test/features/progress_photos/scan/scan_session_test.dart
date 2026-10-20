import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_session.dart';

void main() {
  group('scanAllowedForAge', () {
    test('under 18 and unknown are refused; 18+ allowed', () {
      expect(scanAllowedForAge(null), isFalse);
      expect(scanAllowedForAge(0), isFalse);
      expect(scanAllowedForAge(16), isFalse);
      expect(scanAllowedForAge(17), isFalse);
      expect(scanAllowedForAge(18), isTrue);
      expect(scanAllowedForAge(45), isTrue);
    });
  });

  group('ScanSession', () {
    test('starts pending in front, side, back order', () {
      final s = ScanSession.start();
      expect(s.entries.map((e) => e.pose), [
        ScanPose.front,
        ScanPose.side,
        ScanPose.back,
      ]);
      expect(s.entries.every((e) => !e.isCaptured), isTrue);
      expect(s.currentPose, ScanPose.front);
      expect(s.isComplete, isFalse);
    });

    test('captures advance the current pose until complete', () {
      var s = ScanSession.start();
      s = s.markCaptured(ScanPose.front, 'a');
      expect(s.currentPose, ScanPose.side);
      s = s.markCaptured(ScanPose.side, 'b');
      expect(s.currentPose, ScanPose.back);
      expect(s.capturedCount, 2);
      s = s.markCaptured(ScanPose.back, 'c');
      expect(s.currentPose, isNull);
      expect(s.isComplete, isTrue);
      expect(s.entryFor(ScanPose.side).shotRef, 'b');
    });

    test('is immutable: the original is untouched', () {
      final s0 = ScanSession.start();
      s0.markCaptured(ScanPose.front, 'a');
      expect(s0.capturedCount, 0);
      expect(() => s0.entries.add(const ScanPoseEntry(pose: ScanPose.front)),
          throwsUnsupportedError);
    });

    test('retake reopens a pose, then current returns to the next pending', () {
      var s = ScanSession.start()
          .markCaptured(ScanPose.front, 'a')
          .markCaptured(ScanPose.side, 'b');
      s = s.retake(ScanPose.front);
      expect(s.currentPose, ScanPose.front);
      expect(s.entryFor(ScanPose.front).shotRef, isNull);
      expect(s.statusOf(ScanPose.side), ScanPoseStatus.captured);
      s = s.markCaptured(ScanPose.front, 'a2');
      expect(s.currentPose, ScanPose.back);
    });

    test('retaking from a complete scan makes it incomplete', () {
      var s = ScanSession.start()
          .markCaptured(ScanPose.front, 'a')
          .markCaptured(ScanPose.side, 'b')
          .markCaptured(ScanPose.back, 'c');
      s = s.retake(ScanPose.back);
      expect(s.isComplete, isFalse);
      expect(s.currentPose, ScanPose.back);
    });

    test('capturing an already captured pose without retake is an error', () {
      final s = ScanSession.start().markCaptured(ScanPose.front, 'a');
      expect(() => s.markCaptured(ScanPose.front, 'x'), throwsStateError);
    });

    test('retake of a pending pose is a harmless no-op', () {
      final s = ScanSession.start().retake(ScanPose.back);
      expect(s.capturedCount, 0);
    });
  });
}
