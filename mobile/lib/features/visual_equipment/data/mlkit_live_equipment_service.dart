import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';

import '../../../core/camera/camera_session.dart';
import 'live_equipment_service.dart';
import 'live_recognition.dart';
import 'visual_equipment_match.dart';
import 'visual_equipment_service.dart' show VisualEquipmentException;

/// Live recogniser: ML Kit custom labeler over a [CameraSession]'s frames.
///
/// Owns no camera. It attaches to a session that something else started, which
/// is what allows the cheap QR watcher to keep running continuously while this —
/// by far the most expensive thing in the app — is attached only while the user
/// has live mode switched on.
///
/// One frame at a time (`_busy`): the labeler is slower than the camera, and
/// queueing frames would blow memory and lag recognition by seconds.
class MlKitLiveEquipmentService implements LiveEquipmentService {
  MlKitLiveEquipmentService({
    required this.session,
    this.modelAssetPath = 'assets/models/equipment_v1.tflite',
    RecognitionSmoother? smoother,
  }) : _smoother = smoother ?? RecognitionSmoother();

  final CameraSession session;
  final String modelAssetPath;
  final RecognitionSmoother _smoother;

  /// Same map as the photo path: model label -> catalog equipmentId.
  static const _kLabelMap = <String, String>{
    'squat_rack': 'squat_rack',
    'barbell': 'barbell',
    'dumbbell': 'dumbbell',
    'kettlebell': 'kettlebell',
    'cable_machine': 'cable_machine',
    // Mirrors the photo path: a bench is a bench, not the press station.
    'bench': 'adjustable_bench',
    'leg_press': 'leg_press',
    'lat_pulldown': 'lat_pulldown',
    'rowing_machine': 'rowing_machine',
    'treadmill': 'treadmill',
  };

  mlkit.ImageLabeler? _labeler;
  StreamSubscription<InputImage>? _sub;
  final StreamController<LiveRecognition> _ctrl =
      StreamController<LiveRecognition>.broadcast();
  bool _busy = false;
  bool _running = false;

  @override
  Stream<LiveRecognition> recognitions() => _ctrl.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running) return;
    final dir = await getApplicationDocumentsDirectory();
    // Path must match AssetBootstrap: '<docs>/<asset path verbatim>'.
    final modelFile = File('${dir.path}/$modelAssetPath');
    // Check the model HERE, not later. `ImageLabeler(...)` is a pure Dart
    // constructor (google_mlkit_image_labeling 0.14.1 image_labeler.dart:16) --
    // the model is not loaded until the first processImage call, inside the
    // per-frame handler. Without this check a missing model fails silently on
    // every frame forever and the UI just says "Looking...".
    if (!await modelFile.exists()) {
      throw VisualEquipmentException(
        'Recognition model missing at ${modelFile.path}. The bundled model '
        'failed to unpack on first launch — reinstalling the app fixes it.',
      );
    }
    _labeler = mlkit.ImageLabeler(
      options: mlkit.LocalLabelerOptions(
        modelPath: modelFile.path,
        // Lower than the photo path on purpose: a single frame is weak
        // evidence and the smoother is what decides. Filtering hard here would
        // starve the vote.
        //
        // 0.05 was HALF of chance for a 10-class softmax, so it admitted every
        // frame ever shown to it — measured, 30/30 real gym photos passed with
        // a minimum score of 0.215 (B1, core/plans/B1_RECOGNITION_MEASUREMENT
        // _2026-08-07.md). A gate that rejects nothing is not a gate.
        //
        // Chance level is the floor a per-class score has to clear to mean
        // anything at all. It is deliberately NOT presented as a fix: B1 also
        // showed the model at 0.892 on a machine it has no class for, so no
        // threshold on this model separates right from wrong. It stops the
        // gate from being nonsense; B5 (more classes + a none-of-mine class)
        // is what makes the answer trustworthy.
        confidenceThreshold: 1 / 10,
        maxCount: 3,
      ),
    );
    await session.start();
    _running = true;
    _sub = session.frames().listen(
          _onFrame,
          onError: (Object e, StackTrace st) {
            if (!_ctrl.isClosed) _ctrl.addError(e, st);
          },
        );
  }

  Future<void> _onFrame(InputImage input) async {
    if (_busy || !_running) return;
    _busy = true;
    try {
      final labels = await _labeler!.processImage(input);
      VisualMatch? top;
      for (final l in labels) {
        final id = _kLabelMap[l.label.toLowerCase()];
        if (id == null) continue;
        if (top == null || l.confidence > top.confidence) {
          top = VisualMatch(
            equipmentId: id,
            confidence: l.confidence,
            labelHint: l.label,
          );
        }
      }
      // Settled if the vote passed its bars, otherwise the current leader as
      // a tentative reading — so the UI always has SOMETHING to show and a
      // hard scene never reads as an infinite spinner.
      final reading = _smoother.add(top) ?? _smoother.tentative;
      if (reading != null && !_ctrl.isClosed) _ctrl.add(reading);
    } on PlatformException catch (e) {
      // The native labeler rejected the call — a broken model, an unsupported
      // format, a dead detector. This does NOT recover on the next frame, so
      // surface it once and detach instead of spinning silently.
      debugPrint('live recognition failed natively: ${e.code} ${e.message}');
      if (!_ctrl.isClosed) {
        _ctrl.addError(VisualEquipmentException(
          'Recognition engine failed: ${e.message ?? e.code}',
        ));
      }
      unawaited(stop());
    } catch (e) {
      debugPrint('live recognition frame dropped: $e');
    } finally {
      _busy = false;
    }
  }

  /// Detaches the labeler. Does NOT stop the session: the QR watcher and the
  /// preview are still using it.
  @override
  Future<void> stop() async {
    _running = false;
    _smoother.reset();
    await _sub?.cancel();
    _sub = null;
    try {
      await _labeler?.close();
    } catch (e) {
      debugPrint('labeler close: $e');
    }
    _labeler = null;
  }

  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
  }
}
