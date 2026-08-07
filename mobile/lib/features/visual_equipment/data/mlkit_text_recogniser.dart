import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

/// Reads whatever text is visible in a photo.
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

  Future<void> dispose();
}

/// Production implementation, ML Kit on-device text recognition.
class MlKitMachineTextRecogniser implements MachineTextRecogniser {
  mlkit.TextRecognizer? _recogniser;

  @override
  Future<String> readText(String path) async {
    // Latin script only. Gym equipment is labelled in English by every
    // manufacturer that reaches this market -- Nautilus, Star Trac, Precor,
    // Technogym, Life Fitness -- including in the operator's own gym, whose
    // interface language is Russian but whose machines say "ABDUCTION /
    // ADDUCTION". The other scripts are separate downloadable models and
    // would be weight for nothing.
    final r = _recogniser ??=
        mlkit.TextRecognizer(script: mlkit.TextRecognitionScript.latin);
    final result = await r.processImage(mlkit.InputImage.fromFilePath(path));
    return result.text;
  }

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
  Future<void> dispose() async {}
}
