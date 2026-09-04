import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/camera/camera_session.dart';

/// SCAN-G1's on-device evidence mode (core/SCAN_G1_SCOPE.md, R1/R2/R7).
///
/// `--dart-define=SCAN_EVIDENCE=true` on a DEBUG build only -- `kDebugMode`
/// is the first operand, so a release or profile build cannot be put into
/// this mode by any define. What it changes:
///
///  * the viewfinder draws the raw camera preview with no brackets, glyph,
///    hint or sweep, so two screenshots a second apart differ only where the
///    camera's own pixels changed (the liveness proof, R1);
///  * a frame counter over the card, fed by [CameraSession.frames], so the
///    same screenshots also show the stream advancing;
///  * every capture's viewfinder crop is copied to
///    `<app documents>/scan_evidence/last_crop.jpg`, so `adb` can pull the
///    exact bytes the classifier received and they can be laid next to the
///    bracket window (R7).
///
/// Nothing here runs unless the flag is set: the constant is `false` in every
/// ordinary build and the branches on it are dead code the compiler drops.
const bool kScanEvidence =
    kDebugMode && bool.fromEnvironment('SCAN_EVIDENCE', defaultValue: false);

/// Copies the crop the classifier is about to receive to the evidence
/// folder. Returns the copy's path, or null with a log -- evidence must never
/// break the capture it documents.
Future<String?> saveScanEvidenceCrop(String croppedPath) async {
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/scan_evidence');
    await dir.create(recursive: true);
    final File out =
        await File(croppedPath).copy('${dir.path}/last_crop.jpg');
    debugPrint('SCAN_EVIDENCE crop -> ${out.path}');
    return out.path;
  } catch (e) {
    debugPrint('SCAN_EVIDENCE crop copy failed: $e');
    return null;
  }
}

/// Counts camera frames as they arrive. Evidence mode only.
///
/// Subscribes to [CameraSession.frames] -- the same stream the live labeler
/// reads, which is why the evidence run keeps Live off: the stream is what
/// starts the image pipeline, and one consumer is enough to prove it moves.
class ScanEvidenceCounter extends StatefulWidget {
  const ScanEvidenceCounter({super.key, required this.session});

  final CameraSession session;

  @override
  State<ScanEvidenceCounter> createState() => _ScanEvidenceCounterState();
}

class _ScanEvidenceCounterState extends State<ScanEvidenceCounter> {
  StreamSubscription<Object?>? _sub;
  int _frames = 0;
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.frames().listen((_) {
      if (!mounted) return;
      setState(() {
        _frames++;
        _last = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String last = _last == null
        ? '-'
        : '${_last!.hour.toString().padLeft(2, '0')}:'
            '${_last!.minute.toString().padLeft(2, '0')}:'
            '${_last!.second.toString().padLeft(2, '0')}.'
            '${_last!.millisecond.toString().padLeft(3, '0')}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'frames $_frames · $last',
          key: const Key('scan-evidence-frames'),
          style: const TextStyle(
            fontFamily: 'Roboto Mono',
            fontSize: 11,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}
