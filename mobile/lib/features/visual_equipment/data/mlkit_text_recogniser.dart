import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

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

/// Production implementation, ML Kit on-device text recognition.
class MlKitMachineTextRecogniser implements MachineTextRecogniser {
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
  Future<void> dispose() async {
    await _recogniser?.close();
    _recogniser = null;
  }
}

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
