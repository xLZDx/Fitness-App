import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';

import '../../../core/camera/camera_session.dart';
import '../../../core/debug/g3_step10b_probe.dart';
import 'live_equipment_service.dart';
import 'live_recognition.dart';
import 'machine_text_anchor.dart';
import 'mlkit_text_recogniser.dart';
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
    this.textRecogniser,
    this.catalogue = const {},
    this.ocrEveryNthFrame = 8,
  }) : _smoother = smoother ?? RecognitionSmoother();

  final CameraSession session;
  final String modelAssetPath;
  final RecognitionSmoother _smoother;

  /// B5b, live. Null keeps the old behaviour exactly: classifier only.
  ///
  /// Measured on the operator's 30 gym photos: the machine's printed name
  /// identifies 18 of the 18 gradeable frames, the classifier 5. In live mode
  /// that gap matters more, not less — the user is standing in front of the
  /// machine with the shroud in view.
  final MachineTextRecogniser? textRecogniser;

  /// `equipmentId -> display name`. Passed in so the anchor cannot name a
  /// machine the catalogue has no page for.
  final Map<String, String> catalogue;

  /// OCR is a SECOND ML Kit call per frame, on a path that already drops
  /// frames to keep up (`_busy`). Running it on every frame would roughly
  /// double the cost of live mode for no gain: a decal does not move, so
  /// reading it eight times a second buys nothing over reading it once.
  ///
  /// 8 at the labeler's real cadence is well under a second to first read.
  final int ocrEveryNthFrame;

  int _frameCount = 0;

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

  /// Set on the first OCR-anchor failure of a live session, so a decal that
  /// fails to read on every one of `ocrEveryNthFrame` frames reports once,
  /// not every ~1/8th of a second for as long as live mode stays open.
  bool _ocrAnchorFailureReported = false;

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
    _ocrAnchorFailureReported = false;
    _sub = session.frames().listen(
          _onFrame,
          onError: (Object e, StackTrace st) {
            if (!_ctrl.isClosed) _ctrl.addError(e, st);
          },
        );
  }

  /// Reads the machine's printed name off a live frame.
  ///
  /// Returns a settled [LiveRecognition] ONLY when the reading names exactly
  /// one machine; null for everything else — no recogniser configured, not an
  /// OCR frame this tick, no text, text that named nothing we know, and text
  /// that named several machines. Every one of those falls through to the
  /// classifier, which is the point: the anchor adds answers, it never removes
  /// them.
  ///
  /// Its own try/catch, deliberately swallowing. A text-recognition fault must
  /// not reach the caller's `PlatformException` handler, which detaches live
  /// mode outright — that handler is for a broken LABELER, where every
  /// subsequent frame would fail too. OCR is additive; losing it should cost
  /// the anchor, not the feature.
  Future<LiveRecognition?> _anchorFromFrame(InputImage input) async {
    final recogniser = textRecogniser;
    if (recogniser == null || catalogue.isEmpty) return null;
    // Counted per frame, not per OCR attempt, so the cadence is in frames the
    // camera actually delivered.
    if (_frameCount++ % ocrEveryNthFrame != 0) return null;
    try {
      // MVP1.G3 Step 10B fault injection -- see g3_step10b_probe.dart. Dead
      // code (compiler-eliminated) in every build that does not pass
      // --dart-define=G3_STEP10B_PROBE=true --dart-define=G3_STEP10B_OCR_FAIL=true.
      if (G3Step10bProbe.forceOcrFailure) {
        throw Exception('G3_STEP10B_PROBE: injected OCR anchor failure');
      }
      final text = await recogniser.readFrame(input);
      if (text.trim().isEmpty) return null;
      final hits = matchMachineText(text, catalogue: catalogue);
      // Exactly one, or nothing. Several candidates means the text could not
      // decide, and resolving that by taking the first is the defect the photo
      // path returns null to avoid.
      if (hits.length != 1) return null;
      final hit = hits.single;
      return LiveRecognition(
        equipmentId: hit.equipmentId,
        confidence: hit.confidence,
        // 1.0 rather than a vote share: nothing was voted on. Reporting a
        // fraction of a window that never ran would be a number we invented.
        agreement: 1,
        settled: true,
      );
    } catch (e, stackTrace) {
      debugPrint('live text anchor failed, continuing without it: $e');
      // First failure per session only -- see `_ocrAnchorFailureReported`.
      if (!_ocrAnchorFailureReported) {
        _ocrAnchorFailureReported = true;
        // Same guard as main.dart's Crashlytics calls: telemetry must never
        // break the feature it instruments (and has no app to report against
        // at all in a plain `flutter test` run).
        try {
          // Branch at the call site -- see gemini_equipment_service.dart's
          // matching comment. G3_STEP10B_PROBE=false (every normal build)
          // must call FirebaseCrashlytics directly, with no
          // g3_step10b_probe.dart frame in between.
          if (G3Step10bProbe.kEnabled) {
            unawaited(
              G3Step10bProbe.recordError(
                e,
                stackTrace,
                fatal: false,
                reason: 'live OCR anchor failed',
              ),
            );
          } else {
            unawaited(
              FirebaseCrashlytics.instance.recordError(
                e,
                stackTrace,
                fatal: false,
                reason: 'live OCR anchor failed',
              ),
            );
          }
        } catch (_) {
          // Reporting failure is not itself reportable -- see above.
        }
      }
      return null;
    }
  }

  Future<void> _onFrame(InputImage input) async {
    if (_busy || !_running) return;
    _busy = true;
    try {
      // B5b — the printed name, tried first and only every Nth frame.
      //
      // A hit here is emitted as SETTLED immediately and bypasses the
      // smoother. The smoother exists because a 62%-top-1 classifier flickers
      // between candidates frame to frame; a name printed on the shroud does
      // not flicker, and making the user wait six frames for a vote on
      // something already read in full would be latency for its own sake.
      final anchored = await _anchorFromFrame(input);
      if (anchored != null) {
        if (!_ctrl.isClosed) _ctrl.add(anchored);
        return;
      }

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
