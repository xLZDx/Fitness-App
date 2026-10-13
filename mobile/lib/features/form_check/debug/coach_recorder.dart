import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
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

  /// Removes a file [save] wrote, and its uid folder when that leaves it empty.
  /// Best effort and never throws: it must not recreate anything.
  Future<void> discard(String uid, File file) async {
    try {
      if (await file.exists()) await file.delete();
      final dir = await directoryFor(uid);
      if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
    } catch (e) {
      debugPrint('coach recorder: could not remove an aborted recording: $e');
    }
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

  /// The uid that started the current recording. Immutable for that recording;
  /// the save destination is derived only from it, never from a later session.
  String? _recUid;

  @override
  void dispose() {
    _sub?.cancel();
    _rec = null;
    _recUid = null;
    super.dispose();
  }

  /// Cancels the capture and drops the in-memory frames without saving.
  void _discard({String? error}) {
    _sub?.cancel();
    _sub = null;
    _rec = null;
    _recUid = null;
    if (mounted) {
      setState(() {
        _saved = null;
        _error = error;
      });
    }
  }

  void _onAuthChanged(AsyncValue<dynamic> next) {
    if (_rec == null) return;
    // A transient reload with no value is not an identity change.
    if (next.isLoading && !next.hasValue) return;
    final uid = (next.valueOrNull as dynamic)?.uid as String?;
    if (uid != _recUid) _discard(error: 'recording-discarded:auth-changed');
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
      _recUid = uid;
      _saved = null;
      _error = null;
    });
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    final rec = _rec;
    final startUid = _recUid;
    if (rec == null || startUid == null) return;
    // The account is still the one that started this recording: same uid and
    // not being deleted. Read through the container so it still works after
    // this widget is disposed; an unreadable scope counts as "not valid".
    final container = ProviderScope.containerOf(context, listen: false);
    bool accountStillValid() {
      try {
        return container.read(authUserProvider).valueOrNull?.uid == startUid &&
            container.read(accountBeingDeletedUidProvider) != startUid;
      } catch (_) {
        return false;
      }
    }

    if (!accountStillValid()) {
      // Identity changed or signed out: save nothing, never use another path.
      _discard(error: 'recording-discarded:auth-changed');
      return;
    }
    final store = widget.store ?? CoachRecordingStore();
    try {
      final file = await store.save(startUid, rec);
      if (!accountStillValid()) {
        // The account changed or was deleted DURING the write (the local wipe
        // may already have run): remove what this save just wrote, from the
        // original uid's folder only, and report nothing.
        await store.discard(startUid, file);
        if (mounted && identical(_rec, rec)) _discard();
        return;
      }
      if (mounted && identical(_rec, rec)) setState(() => _saved = file);
    } catch (e) {
      if (mounted) setState(() => _error = 'save-failed:${e.runtimeType}');
    }
    if (mounted && identical(_rec, rec)) {
      setState(() {
        _rec = null;
        _recUid = null;
      });
    }
  }

  Future<void> _export() async {
    final f = _saved;
    if (f == null) return;
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')]);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(coachHarnessEnabledProvider)) return const SizedBox.shrink();
    ref.listen(authUserProvider, (_, next) => _onAuthChanged(next));
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
