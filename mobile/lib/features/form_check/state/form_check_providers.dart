import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/form_classifier.dart';
import '../data/pose_detector_service.dart';
import '../data/pose_landmark.dart';

/// Currently-active classifier set. Defaults to the three movements with
/// highest injury risk. The page swaps the set when the user picks an
/// exercise.
final activeClassifiersProvider =
    StateProvider<List<FormClassifier>>((_) => [
          SquatDepthClassifier(),
          DeadliftBackAngleClassifier(),
          PushupAlignmentClassifier(),
        ]);

final poseDetectorServiceProvider =
    Provider<PoseDetectorService>((_) {
  // Default mock yields nothing — production binds the MlKit-backed
  // service from main.dart.
  return MockPoseDetectorService(const []);
});

/// Drives the live overlay: every frame, run the active classifier set
/// and emit the worst feedback. Null when no frame yet / no rule fires.
class FormFeedbackController extends Notifier<FormFeedback?> {
  StreamSubscription<PoseFrame>? _sub;

  @override
  FormFeedback? build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    _sub?.cancel();
    _sub = svc.frames().listen(_onFrame);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onFrame(PoseFrame frame) {
    final classifiers = ref.read(activeClassifiersProvider);
    state = worstFeedback(classifiers, frame);
  }
}

final formFeedbackControllerProvider =
    NotifierProvider<FormFeedbackController, FormFeedback?>(
        FormFeedbackController.new);
