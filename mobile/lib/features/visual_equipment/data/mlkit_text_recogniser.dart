import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import 'machine_text_evidence.dart';

/// Reads whatever text is visible in an image.
///
/// An interface rather than a direct plugin call, for the same reason
/// [VisualEquipmentService] is one: the plugin needs a platform channel, so a
/// test that touched it directly could not run. All the logic worth testing
/// lives in `machine_text_anchor.dart`, which is pure — this is only the
/// bridge to it.
abstract class MachineTextRecogniser {
  /// Every line of text found in the image at [path], joined by newlines.
  /// Empty string when there is none, which is the common case.
  Future<String> readText(String path);

  /// Same, for a live camera frame.
  ///
  /// Two methods rather than one taking `InputImage`, because the photo path
  /// genuinely has a file and `InputImage.fromFilePath` is what makes the
  /// platform decode JPEG and apply EXIF rotation for it. Collapsing them
  /// would push that decision into every caller.
  Future<String> readFrame(InputImage input);

  Future<void> dispose();
}

/// Structured capability: the same recognition pass as
/// [MachineTextRecogniser], but returns line-level geometry alongside the
/// full text instead of only the joined String.
///
/// A separate interface rather than new methods added directly to
/// [MachineTextRecogniser], for the same reason `FallbackReportingRecogniser`
/// (`visual_equipment_service.dart`) is separate from `VisualEquipmentService`:
/// Dart's `implements` does not inherit concrete members, so adding an
/// abstract method there would force every existing fake -- including
/// [FakeMachineTextRecogniser], which has nothing structured to report -- to
/// grow a stub it does not need. Callers probe for this capability with
/// `recogniser is StructuredTextRecogniser`, exactly as
/// `visual_equipment_providers.dart` already probes
/// `FallbackReportingRecogniser`.
abstract interface class StructuredTextRecogniser
    implements MachineTextRecogniser {
  /// Structured equivalent of [MachineTextRecogniser.readText].
  Future<MachineTextEvidence> readStructured(String path);

  /// Structured equivalent of [MachineTextRecogniser.readFrame].
  Future<MachineTextEvidence> readStructuredFrame(InputImage input);
}

/// Production implementation, ML Kit on-device text recognition.
class MlKitMachineTextRecogniser
    implements MachineTextRecogniser, StructuredTextRecogniser {
  mlkit.TextRecognizer? _recogniser;

  /// Latin script only. Gym equipment is labelled in English by every
  /// manufacturer that reaches this market -- Nautilus, Star Trac, Precor,
  /// Technogym, Life Fitness -- including in the operator's own gym, whose
  /// interface language is Russian but whose machines say "ABDUCTION /
  /// ADDUCTION". The other scripts are separate downloadable models and would
  /// be weight for nothing.
  mlkit.TextRecognizer get _r => _recogniser ??=
      mlkit.TextRecognizer(script: mlkit.TextRecognitionScript.latin);

  @override
  Future<String> readText(String path) async =>
      (await _r.processImage(mlkit.InputImage.fromFilePath(path))).text;

  @override
  Future<String> readFrame(InputImage input) async =>
      (await _r.processImage(input)).text;

  @override
  Future<MachineTextEvidence> readStructured(String path) async =>
      machineTextEvidenceFromRecognizedText(
          await _r.processImage(mlkit.InputImage.fromFilePath(path)));

  @override
  Future<MachineTextEvidence> readStructuredFrame(InputImage input) async =>
      machineTextEvidenceFromRecognizedText(await _r.processImage(input));

  @override
  Future<void> dispose() async {
    await _recogniser?.close();
    _recogniser = null;
  }
}

/// Maps ML Kit's own result shape to [MachineTextEvidence] verbatim --
/// `fullText` is the exact same `.text` the legacy String API already
/// returns, and every line's `cornerPoints`/`angle`/`confidence` is passed
/// through as ML Kit supplied it (nullable fields stay nullable; this
/// mapping never fabricates a value the platform did not return).
///
/// A top-level function rather than a private method, so it is directly
/// unit-testable against a hand-built [mlkit.RecognizedText] -- the model
/// classes (`RecognizedText`, `TextBlock`, `TextLine`) are plain Dart data
/// classes with public constructors; only [mlkit.TextRecognizer.processImage]
/// itself needs the platform channel this mapping never touches.
MachineTextEvidence machineTextEvidenceFromRecognizedText(
        mlkit.RecognizedText result) =>
    MachineTextEvidence(
      fullText: result.text,
      lines: [
        for (final block in result.blocks)
          for (final line in block.lines)
            MachineTextLine(
              text: line.text,
              bounds: line.boundingBox,
              cornerPoints: line.cornerPoints,
              angle: line.angle,
              confidence: line.confidence,
            ),
      ],
    );

/// Returns a fixed string. Lets a widget/unit test drive the full anchor path
/// without a device.
class FakeMachineTextRecogniser implements MachineTextRecogniser {
  FakeMachineTextRecogniser(this.text);

  String text;
  int calls = 0;

  @override
  Future<String> readText(String path) async {
    calls++;
    return text;
  }

  @override
  Future<String> readFrame(InputImage input) async {
    calls++;
    return text;
  }

  @override
  Future<void> dispose() async {}
}

/// Returns a fixed [MachineTextEvidence]. Lets a test drive the structured
/// adapter path without a device, the same way [FakeMachineTextRecogniser]
/// drives the legacy String path -- including the legacy methods, so a test
/// can also exercise a caller that has not yet been taught to probe for the
/// structured capability.
class FakeStructuredTextRecogniser implements StructuredTextRecogniser {
  FakeStructuredTextRecogniser(this.evidence);

  MachineTextEvidence evidence;
  int calls = 0;

  @override
  Future<MachineTextEvidence> readStructured(String path) async {
    calls++;
    return evidence;
  }

  @override
  Future<MachineTextEvidence> readStructuredFrame(InputImage input) async {
    calls++;
    return evidence;
  }

  @override
  Future<String> readText(String path) async {
    calls++;
    return evidence.fullText;
  }

  @override
  Future<String> readFrame(InputImage input) async {
    calls++;
    return evidence.fullText;
  }

  @override
  Future<void> dispose() async {}
}
