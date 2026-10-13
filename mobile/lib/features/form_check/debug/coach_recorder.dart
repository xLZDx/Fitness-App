import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/state/auth_providers.dart';
import '../data/measured_rep_configs.dart' show jointAngleDeg;
import '../data/pose_landmark.dart';
import '../state/form_check_providers.dart';

// Developer-only record-and-review harness for the coach engine.
//
// Records, per camera frame, the joint angles and the engine's own decisions
// (rep phase, gate verdict, rule/cue ids). No video, no images, no landmark
// coordinates: only angles in degrees and timestamps. Stored locally under
// `<documents>/coach_recordings/<uid>/` and erased by the account-deletion
// wipe (`local_data_wipe.dart`). Built in debug and profile builds only.
//
// Decisions are read from the providers when a frame arrives, so they may lag
// the frame's own verdict by one frame. Fine for threshold review.

/// Folder under the documents directory; the wipe deletes `<this>/<uid>`.
const kCoachRecordingsDir = 'coach_recordings';

/// Whether the harness is built. Overridable so a test can simulate release
/// (`kReleaseMode`) without a release build.
final coachHarnessEnabledProvider =
    Provider<bool>((_) => kDebugMode || kProfileMode);

/// Hard cap so a forgotten recording cannot grow without bound (~10 min at 30fps).
const kCoachRecordingMaxFrames = 20000;

class CoachRecording {
  CoachRecording({required this.exercise, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  final String exercise;
  final DateTime startedAt;
  final List<Map<String, Object?>> frames = [];
  int? _firstTs;

  bool get isFull => frames.length >= kCoachRecordingMaxFrames;

  /// Angles at the eight main joints, degrees, image space; a joint whose
  /// landmarks are missing is omitted.
  static Map<String, double> anglesOf(PoseFrame f) {
    final out = <String, double>{};
    void add(String name, LandmarkType a, LandmarkType b, LandmarkType c) {
      final pa = f.landmarks[a], pb = f.landmarks[b], pc = f.landmarks[c];
      if (pa == null || pb == null || pc == null) return;
      out[name] = double.parse(jointAngleDeg(pa, pb, pc).toStringAsFixed(1));
    }

    const t = LandmarkType.values;
    for (final side in ['left', 'right']) {
      LandmarkType l(String n) =>
          t.firstWhere((e) => e.name == '$side${n[0].toUpperCase()}${n.substring(1)}');
      add('${side}Elbow', l('shoulder'), l('elbow'), l('wrist'));
      add('${side}Shoulder', l('hip'), l('shoulder'), l('elbow'));
      add('${side}Hip', l('shoulder'), l('hip'), l('knee'));
      add('${side}Knee', l('hip'), l('knee'), l('ankle'));
    }
    return out;
  }

  void add(
    PoseFrame frame, {
    String? repPhase,
    int? reps,
    int? holdMs,
    String? gate,
    String? rule,
    int? severity,
    String? cueId,
    bool? advisory,
  }) {
    if (isFull) return;
    _firstTs ??= frame.timestampMs;
    frames.add({
      't': frame.timestampMs - _firstTs!,
      'angles': anglesOf(frame),
      if (repPhase != null) 'phase': repPhase,
      if (reps != null) 'reps': reps,
      if (holdMs != null) 'holdMs': holdMs,
      if (gate != null) 'gate': gate,
      if (rule != null) 'rule': rule,
      if (severity != null) 'severity': severity,
      if (cueId != null) 'cueId': cueId,
      if (advisory != null) 'advisory': advisory,
    });
  }

  Map<String, Object?> toJson() => {
        'schema': 'coach_recording/v1',
        'exercise': exercise,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'frames': frames,
      };
}

class CoachRecordingStore {
  CoachRecordingStore({Directory? documents}) : _documents = documents;
  final Directory? _documents;

  Future<Directory> directoryFor(String uid) async {
    final docs = _documents ?? await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$kCoachRecordingsDir/$uid');
  }

  Future<File> save(String uid, CoachRecording rec) async {
    final dir = await directoryFor(uid);
    await dir.create(recursive: true);
    final stamp = rec.startedAt.toUtc().millisecondsSinceEpoch;
    final file = File('${dir.path}/${rec.exercise}-$stamp.json');
    await file.writeAsString(jsonEncode(rec.toJson()));
    return file;
  }
}

/// The panel. Returns an empty box when the harness is not enabled, so a
/// release build never builds any of it.
class CoachRecorderPanel extends ConsumerStatefulWidget {
  const CoachRecorderPanel({super.key, this.store});
  final CoachRecordingStore? store;

  @override
  ConsumerState<CoachRecorderPanel> createState() => _CoachRecorderPanelState();
}

class _CoachRecorderPanelState extends ConsumerState<CoachRecorderPanel> {
  CoachRecording? _rec;
  StreamSubscription<PoseFrame>? _sub;
  File? _saved;
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _error = 'no-signed-in-user');
      return;
    }
    final rec = CoachRecording(
        exercise: ref.read(selectedExerciseProvider).name);
    _sub = ref.read(poseDetectorServiceProvider).frames().listen((frame) {
      final session = ref.read(repSessionControllerProvider);
      final fb = ref.read(formFeedbackControllerProvider);
      rec.add(
        frame,
        repPhase: session.phase.name,
        reps: session.repCount,
        holdMs: session.holdMs,
        gate: ref.read(poseEffectiveGateVerdictProvider).name,
        rule: fb?.rule,
        severity: fb?.severity,
        cueId: fb?.cueId,
        advisory: fb?.advisory,
      );
    });
    setState(() {
      _rec = rec;
      _saved = null;
      _error = null;
    });
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    final rec = _rec;
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (rec == null || uid == null) return;
    try {
      final file =
          await (widget.store ?? CoachRecordingStore()).save(uid, rec);
      if (mounted) setState(() => _saved = file);
    } catch (e) {
      if (mounted) setState(() => _error = 'save-failed:${e.runtimeType}');
    }
    if (mounted) setState(() => _rec = null);
  }

  Future<void> _export() async {
    final f = _saved;
    if (f == null) return;
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')]);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(coachHarnessEnabledProvider)) return const SizedBox.shrink();
    final recording = _rec != null;
    return Card(
      key: const Key('coach.recorder'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('DEV-recorder'),
            TextButton(
              key: const Key('coach.recorder.toggle'),
              onPressed: recording ? _stop : _start,
              child: Text(recording ? 'Stop' : 'Record'),
            ),
            if (_saved != null)
              TextButton(
                key: const Key('coach.recorder.export'),
                onPressed: _export,
                child: const Text('Export'),
              ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    );
  }
}
