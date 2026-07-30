import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_coach/ai_coach_service.dart';
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

  test('every canonical prompt name resolves in the alias index', () {
    // The prompt offers these names to the model; if a registry rename
    // orphans one, the model's correct answer would silently become
    // "no match". This is the tripwire.
    for (final name in GeminiVisualEquipmentService.kCanonicalMachines) {
      expect(index.resolve(name), isNotNull,
          reason: 'prompt offers "$name" but the registry cannot resolve it');
    }
  });

  test('the prompt tells the model to look at the CENTER of the frame', () {
    // Operator: machines stand shoulder to shoulder in a real gym; framing
    // one alone is impossible. The center rule is the contract.
    final prompt = GeminiVisualEquipmentService.buildPrompt();
    expect(prompt, contains('center'));
    expect(prompt, contains('unknown'));
  });

  group('classifyFile with an injected cloud', () {
    test('reads the file and returns resolved matches', () async {
      final tmp = File(
          '${Directory.systemTemp.createTempSync('scan').path}/shot.jpg');
      tmp.writeAsBytesSync([1, 2, 3]);
      Uint8List? sent;
      final svc = GeminiVisualEquipmentService(
        index: Future.value(index),
        ask: (bytes, prompt) async {
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
        ask: (_, __) async => '',
      );
      expect(() => svc.classifyFile(path: tmp.path),
          throwsA(isA<VisualEquipmentException>()));
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

  group('AiCoachService', () {
    test('asks in the interface language about the exact machine', () async {
      String? seen;
      final svc = AiCoachService(ask: (p) async {
        seen = p;
        return '  Совет.  ';
      });
      final out =
          await svc.advise(machineName: 'Гакк-машина', languageCode: 'ru');
      expect(out, 'Совет.');
      expect(seen, contains('Гакк-машина'));
      expect(seen, contains('Russian'));
    });

    test('an empty answer throws instead of rendering a blank sheet', () {
      final svc = AiCoachService(ask: (_) async => '   ');
      expect(() => svc.advise(machineName: 'x', languageCode: 'en'),
          throwsException);
    });
  });
}
