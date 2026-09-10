import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';

/// P2.G1 device/plugin evidence: proves the real ML Kit text recognizer, via
/// [MlKitMachineTextRecogniser.readStructured], actually returns structured
/// [MachineTextEvidence] on a physical device -- the seam that had zero test
/// coverage anywhere in this repo before this gate (GPT-PM's second REVISE
/// finding, verified true via `grep -rln MlKitMachineTextRecogniser
/// mobile/test/` returning empty).
///
/// Fixture: a deterministic 480x160 PNG, bold black "LEG PRESS" / "MAX 200 KG"
/// on white (Pillow, Arial Bold 48pt/36pt), embedded as base64 rather than a
/// bundled Flutter asset -- the GO-approved plan explicitly excludes a
/// pubspec.yaml asset-declaration change. Decoded and written to the
/// device's own temp directory at run time.
///
/// PRIVACY (binding rule, v4.2_REMEDIATED_RC_2026-08-22.md section 8.5,
/// verified against the file directly, not assumed): raw/structured OCR
/// text is never written to a log, report, or decision-log entry -- only
/// parsed identity tokens are. This test's IN-PROCESS assertions read
/// `evidence.fullText`/line text directly (that is the test's own pass/fail
/// logic, not something that leaves the process); everything printed as
/// EVIDENCE below is limited to the fixture's SHA-256, PASS/FAIL, line
/// count, a non-degenerate-bounds boolean, and confidence/angle
/// NULLABILITY presence -- never the verbatim OCR string.
const _fixturePngBase64 =
    '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';

const _fixtureSha256 =
    '011d2dfa08b3dd3b60ffead51b0b8e4596c8efcff0d1ef50443044599e9d6316';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MlKitMachineTextRecogniser reads structured text from a real '
    'nameplate-style image on-device',
    (tester) async {
      final bytes = base64Decode(_fixturePngBase64);
      final actualSha = sha256.convert(bytes).toString();
      expect(actualSha, _fixtureSha256,
          reason: 'fixture identity check -- not itself OCR evidence');

      final dir = await Directory.systemTemp.createTemp('p2g1_ocr_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/nameplate.png');
      await file.writeAsBytes(bytes);

      final recogniser = MlKitMachineTextRecogniser();
      addTearDown(recogniser.dispose);

      final evidence = await recogniser.readStructured(file.path);

      // In-process assertions: the test's own pass/fail logic, not evidence
      // that leaves the process (see the privacy note in the file doc
      // comment above). Reduced to a boolean BEFORE it reaches `expect`,
      // deliberately: `expect`'s own failure formatter
      // (package:matcher's `expect.dart`) prints `prettyPrint(actual)` next
      // to `Actual:` on any mismatch, so passing `fullText` itself as the
      // actual value would print the verbatim OCR string into the test
      // failure output on the one path that matters most -- when the
      // fixture is NOT read correctly. Passing a bool means a failure here
      // still names the problem without ever naming the text (GPT-PM
      // review, verified against the matcher package's own `expect.dart`).
      final matchesExpectedPhrase =
          evidence.fullText.toUpperCase().contains('LEG PRESS');
      expect(matchesExpectedPhrase, isTrue,
          reason: 'the fixture prints LEG PRESS in bold black on white -- '
              'this is the one assertion that would fail if ML Kit were '
              'never actually invoked');
      expect(evidence.lines, isNotEmpty);
      final hasNonDegenerateBounds = evidence.lines
          .any((l) => l.bounds.width > 0 && l.bounds.height > 0);
      expect(hasNonDegenerateBounds, isTrue,
          reason: 'a real recognition pass reports real geometry, not an '
              'empty Rect');

      // Externally-recorded evidence -- exactly the fields the GO-approved
      // plan's privacy constraint allows, and nothing else. No fullText, no
      // line.text, anywhere below this point.
      final confidencePresent =
          evidence.lines.any((l) => l.confidence != null);
      final anglePresent = evidence.lines.any((l) => l.angle != null);
      // ignore: avoid_print
      print('P2.G1 device OCR evidence: '
          'fixtureSha256=$_fixtureSha256 '
          'result=PASS '
          'lineCount=${evidence.lines.length} '
          'nonDegenerateBounds=$hasNonDegenerateBounds '
          'confidencePresent=$confidencePresent '
          'anglePresent=$anglePresent');
    },
  );
}
