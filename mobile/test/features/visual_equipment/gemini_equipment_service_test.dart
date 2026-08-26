import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/visual_equipment/data/gemini_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';

EquipmentAliasIndex loadIndex() => EquipmentAliasIndex.fromJson(
      (jsonDecode(File('assets/data/equipment_aliases.json')
              .readAsStringSync()) as Map)
          .cast<String, dynamic>(),
    );

class _FixedService implements VisualEquipmentService {
  _FixedService(this.result);
  final List<VisualMatch> Function() result;
  int calls = 0;

  @override
  Future<List<VisualMatch>> classifyFile(
      {required String path, int topK = 3}) async {
    calls++;
    return result();
  }
}

void main() {
  final index = loadIndex();

  // Pins the request/response wiring the injected-`ask` tests below cannot
  // see: `FirebaseFunctions`/`HttpsCallable` have private constructors (no
  // fake possible without heavier Firebase test scaffolding this project
  // does not have), so every other test in this file bypasses
  // `cloudFunctionsEquipmentAsk` entirely via the injected `ask` seam. GPT-PM's
  // G1 round-1 review named the resulting blind spot directly: a typo in the
  // function name or either JSON key would compile and ship unnoticed. These
  // pin the pure halves that function is built from instead.
  group('the aiEquipmentRecognition wire contract', () {
    test('calls the function by its exact name', () {
      expect(kEquipmentRecognitionFunctionName, 'aiEquipmentRecognition');
    });

    test('the request carries a fixed JPEG mimeType and the base64 of the bytes given', () {
      final body = buildEquipmentRecognitionRequest(Uint8List.fromList([1, 2, 3]));
      expect(body, {
        'mimeType': 'image/jpeg',
        'imageBase64': base64Encode([1, 2, 3]),
      });
    });

    test('the response text is read from the "text" field', () {
      expect(extractEquipmentRecognitionText({'text': '{"machine": "treadmill"}'}),
          '{"machine": "treadmill"}');
    });

    test('a response with no "text" field extracts null, not a crash', () {
      expect(extractEquipmentRecognitionText({'somethingElse': 1}), isNull);
    });
  });

  group('GeminiVisualEquipmentService.parseResponse', () {
    test('plain JSON answer resolves through the registry', () {
      final out = GeminiVisualEquipmentService.parseResponse(
        '{"machine": "smith machine", "confidence": 0.83, '
        '"alternatives": [{"machine": "squat rack", "confidence": 0.2}]}',
        index,
      );
      expect(out.first.equipmentId, 'smith_machine');
      expect(out.first.confidence, closeTo(0.83, 1e-9),
          reason: 'the model score is shown as-is, never renormalised');
      expect(out[1].equipmentId, 'squat_rack');
    });

    test('tolerates markdown code fences', () {
      final out = GeminiVisualEquipmentService.parseResponse(
        '```json\n{"machine": "treadmill", "confidence": 0.9}\n```',
        index,
      );
      expect(out.single.equipmentId, 'treadmill');
    });

    test('unknown means no match, not a guess', () {
      final out = GeminiVisualEquipmentService.parseResponse(
        '{"machine": "unknown", "confidence": 0.1}',
        index,
      );
      expect(out, isEmpty);
    });

    test('a machine outside the registry is dropped, not invented', () {
      final out = GeminiVisualEquipmentService.parseResponse(
        '{"machine": "vibration plate", "confidence": 0.9}',
        index,
      );
      expect(out, isEmpty);
    });

    test('duplicate machines keep the best score', () {
      final out = GeminiVisualEquipmentService.parseResponse(
        '{"machine": "treadmill", "confidence": 0.4, "alternatives": '
        '[{"machine": "running machine", "confidence": 0.7}]}',
        index,
      );
      expect(out.single.equipmentId, 'treadmill');
      expect(out.single.confidence, closeTo(0.7, 1e-9));
    });

    test('non-JSON raises the recognition error, not a crash', () {
      expect(
        () => GeminiVisualEquipmentService.parseResponse(
            'I think it is a treadmill', index),
        throwsA(isA<VisualEquipmentException>()),
      );
    });
  });

  // The three tests that used to live here (`kCanonicalMachines` vs. the
  // alias registry, both directions, and "the prompt mentions the CENTER of
  // the frame") moved to
  // `functions/src/__tests__/ai_equipment_recognition.test.ts` in G1:
  // `buildPrompt()`/`kCanonicalMachines` were deleted from this file once the
  // model call moved server-side, since a Dart-side copy would no longer
  // drive what a real call actually sends — see
  // `functions/src/ai_equipment_recognition.ts`'s `CANONICAL_MACHINES` for
  // the list that is now live, and its own test file for the same
  // two-directional registry tripwire run against it instead.

  group('classifyFile with an injected cloud', () {
    test('reads the file and returns resolved matches', () async {
      final tmp = File(
          '${Directory.systemTemp.createTempSync('scan').path}/shot.jpg');
      tmp.writeAsBytesSync([1, 2, 3]);
      Uint8List? sent;
      final svc = GeminiVisualEquipmentService(
        index: Future.value(index),
        ask: (bytes) async {
          sent = bytes;
          return '{"machine": "lat pulldown", "confidence": 0.77}';
        },
      );
      final out = await svc.classifyFile(path: tmp.path);
      expect(sent, [1, 2, 3]);
      expect(out.single.equipmentId, 'lat_pulldown');
    });

    test('an empty cloud answer is an error, not silence', () async {
      final tmp = File(
          '${Directory.systemTemp.createTempSync('scan').path}/shot.jpg');
      tmp.writeAsBytesSync([1]);
      final svc = GeminiVisualEquipmentService(
        index: Future.value(index),
        ask: (_) async => '',
      );
      expect(() => svc.classifyFile(path: tmp.path),
          throwsA(isA<VisualEquipmentException>()));
    });

    test('a stalled cloud call times out instead of spinning forever',
        () async {
      // THE regression for "после 3 раза вообще ничего не возвращает и
      // просто спинится" -- classifyFile used to have no deadline at all.
      final tmp = File(
          '${Directory.systemTemp.createTempSync('scan').path}/shot.jpg');
      tmp.writeAsBytesSync([1]);
      final svc = GeminiVisualEquipmentService(
        index: Future.value(index),
        timeout: const Duration(milliseconds: 50),
        ask: (_) => Future.delayed(
            const Duration(seconds: 5), () => '{"machine": "treadmill"}'),
      );
      await expectLater(
        svc.classifyFile(path: tmp.path),
        throwsA(isA<VisualEquipmentException>().having(
            (e) => '$e', 'message', contains('TimeoutException'))),
      );
    });

    test('a photo above 1024px is downsized before it reaches the model',
        () async {
      final dir = Directory.systemTemp.createTempSync('scan');
      final big = img.Image(width: 2000, height: 1500);
      final path = '${dir.path}/big.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(big, quality: 90));

      Uint8List? sent;
      final svc = GeminiVisualEquipmentService(
        index: Future.value(index),
        ask: (bytes) async {
          sent = bytes;
          return '{"machine": "treadmill"}';
        },
      );
      await svc.classifyFile(path: path);
      final decoded = img.decodeImage(sent!)!;
      expect(decoded.width, lessThanOrEqualTo(1024));
      expect(decoded.height, lessThanOrEqualTo(1024));
    });

    test('an unreadable image falls back to the original bytes, not a throw',
        () async {
      final tmp = File(
          '${Directory.systemTemp.createTempSync('scan').path}/junk.jpg');
      tmp.writeAsBytesSync([1, 2, 3, 4, 5]);
      Uint8List? sent;
      final svc = GeminiVisualEquipmentService(
        index: Future.value(index),
        ask: (bytes) async {
          sent = bytes;
          return '{"machine": "treadmill"}';
        },
      );
      await svc.classifyFile(path: tmp.path);
      expect(sent, [1, 2, 3, 4, 5]);
    });
  });

  group('HybridVisualEquipmentService', () {
    const match = VisualMatch(equipmentId: 'treadmill', confidence: 0.9);

    test('cloud answer wins and the local model is not consulted', () async {
      final cloud = _FixedService(() => const [match]);
      final local = _FixedService(() => fail('local must not run'));
      final hybrid = HybridVisualEquipmentService(cloud: cloud, local: local);
      expect(await hybrid.classifyFile(path: 'x'), const [match]);
      expect(local.calls, 0);
    });

    test('cloud failure falls back to the on-device model', () async {
      final cloud =
          _FixedService(() => throw const VisualEquipmentException('offline'));
      final local = _FixedService(() => const [match]);
      final hybrid = HybridVisualEquipmentService(cloud: cloud, local: local);
      expect(await hybrid.classifyFile(path: 'x'), const [match]);
      expect(local.calls, 1);
    });

    test('when both fail the error names both reasons', () async {
      final cloud =
          _FixedService(() => throw const VisualEquipmentException('offline'));
      final local =
          _FixedService(() => throw const VisualEquipmentException('no model'));
      final hybrid = HybridVisualEquipmentService(cloud: cloud, local: local);
      try {
        await hybrid.classifyFile(path: 'x');
        fail('must throw');
      } on VisualEquipmentException catch (e) {
        expect('$e', contains('offline'));
        expect('$e', contains('no model'));
      }
    });
  });

  // The `AiCoachService` group that used to live here moved to
  // `test/features/ai_coach/ai_coach_context_test.dart` in gate F2, where the
  // rest of that feature's coverage now sits. It was only ever here because
  // both services talk to the same model; nothing else in this file is about
  // coaching.
}
