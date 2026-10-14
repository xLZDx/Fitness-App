import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/form_check/data/coach_registry.dart';
import 'package:fitness_app/features/form_check/data/coach_spec.dart';

import 'coach_registry_fixture.dart';

void main() {
  CoachRegistry parse(Map<String, Object?> doc) =>
      CoachRegistry.parse(jsonEncode(doc));

  /// Mutates a fresh fixture, then expects a loud, descriptive rejection whose
  /// message contains [pathPart].
  void rejects(String name, void Function(Map<String, Object?> ex) mutate,
      String pathPart) {
    test('rejects: $name', () {
      final doc = exampleForTests();
      mutate(firstExercise(doc));
      expect(
        () => parse(doc),
        throwsA(isA<CoachRegistryException>()
            .having((e) => e.toString(), 'message', contains(pathPart))),
      );
    });
  }

  group('parse success', () {
    test('example fixture parses into immutable typed specs', () {
      final reg = parse(exampleForTests());
      expect(reg.exercises, hasLength(1));
      final s = reg.byId('example_squat')!;
      expect(reg.lookup('squat_pose'), same(s));
      expect(s.view, CoachView.side);
      expect(s.sidePolicy, CoachSidePolicy.bestVisible);
      expect(s.signal.kind, CoachSignalKind.angle);
      expect(s.signal.enter, 100);
      expect(s.rules.single.cueId, 'cue.example.depth');
      expect(s.provenance.status, CoachProvenanceStatus.beta);
      expect(() => s.tracked.add('nose'), throwsUnsupportedError);
      expect(() => reg.exercises.add(s), throwsUnsupportedError);
    });

    test('empty exercises list is valid', () {
      final reg = parse({'schema': 'coach_exercises/v1', 'exercises': []});
      expect(reg.exercises, isEmpty);
      expect(reg.lookup('anything'), isNull);
    });

    test('shipped asset file parses (8 authored exercises)', () {
      final text = _readAsset();
      final reg = CoachRegistry.parse(text);
      expect(reg.exercises, hasLength(8));
    });

    test('rising direction, ratio signal, hold counting, fixed:left, stable',
        () {
      final doc = exampleForTests();
      final ex = firstExercise(doc);
      ex['sidePolicy'] = 'fixed:left';
      ex['signal'] = {
        'kind': 'ratio',
        'joints': ['leftWrist', 'leftHip'],
        'normalizeBy': 'torso',
        'direction': 'rising',
        'enter': 0.8,
        'exit': 0.3,
      };
      ex['counting'] = {'mode': 'hold', 'minHoldMs': 3000};
      ex['provenance'] = {
        'kind': 'measured',
        'source': 'lab',
        'status': 'stable'
      };
      ((ex['rules']! as List).first as Map)['advisory'] = false;
      final s = parse(doc).exercises.single;
      expect(s.sidePolicy, CoachSidePolicy.fixedLeft);
      expect(s.signal.normalizeTorso, isTrue);
      expect(s.counting.minHoldMs, 3000);
    });
  });

  group('rejections (one fixture per rule)', () {
    test('rejects: invalid JSON', () {
      expect(() => CoachRegistry.parse('{nope'),
          throwsA(isA<CoachRegistryException>()));
    });
    test('rejects: wrong schema tag', () {
      final doc = exampleForTests()..['schema'] = 'coach_exercises/v2';
      expect(() => parse(doc), throwsA(isA<CoachRegistryException>()));
    });
    test('rejects: duplicate exercise ids', () {
      final doc = exampleForTests();
      final list = doc['exercises']! as List;
      final copy = jsonDecode(jsonEncode(list.first)) as Map<String, Object?>;
      copy['aliases'] = ['other_alias'];
      list.add(copy);
      expect(
          () => parse(doc),
          throwsA(isA<CoachRegistryException>()
              .having((e) => e.message, 'message', contains('duplicate id'))));
    });
    rejects('falling signal with enter >= exit', (ex) {
      (ex['signal']! as Map)['enter'] = 170;
    }, 'signal.enter');
    rejects('rising signal with enter <= exit', (ex) {
      (ex['signal']! as Map)['direction'] = 'rising';
    }, 'signal.enter');
    rejects('missing required field (view)', (ex) => ex.remove('view'),
        'exercises[0].view');
    rejects('missing signal.exit', (ex) => (ex['signal']! as Map).remove('exit'),
        'signal.exit');
    rejects('unknown landmark in tracked', (ex) {
      (ex['tracked']! as List).add('leftElbowz');
    }, 'unknown landmark name "leftElbowz"');
    rejects('unknown landmark in signal joints', (ex) {
      (ex['signal']! as Map)['joints'] = ['hip', 'knee', 'toe'];
    }, 'signal.joints[2]');
    rejects('unknown landmark in unscored', (ex) {
      (ex['unscored']! as List).add('belly');
    }, 'unscored[1]');
    rejects('authored rule with advisory=false', (ex) {
      ((ex['rules']! as List).first as Map)['advisory'] = false;
    }, 'advisory');
    rejects('authored row with status stable', (ex) {
      (ex['provenance']! as Map)['status'] = 'stable';
    }, 'provenance.status');
    rejects('hold without minHoldMs', (ex) {
      ex['counting'] = {'mode': 'hold'};
    }, 'minHoldMs');
    rejects('minHoldMs on a reps exercise', (ex) {
      ex['counting'] = {'mode': 'reps', 'minHoldMs': 1000};
    }, 'minHoldMs');
    rejects('rule referencing undeclared phase', (ex) {
      ((ex['rules']! as List).first as Map)['phase'] = 'lockout';
    }, 'rules[0].phase');
    rejects('ratio signal without torso normalisation', (ex) {
      ex['signal'] = {
        'kind': 'ratio',
        'joints': ['hip', 'knee'],
        'direction': 'falling',
        'enter': 0.2,
        'exit': 0.5,
      };
    }, 'normalizeBy');
    rejects('angle with wrong joint count', (ex) {
      (ex['signal']! as Map)['joints'] = ['hip', 'knee'];
    }, 'signal.joints');
    rejects('rule with min > max', (ex) {
      ((ex['rules']! as List).first as Map)['min'] = 120;
    }, 'min');
    rejects('unknown field', (ex) => ex['pixelThreshold'] = 40,
        'pixelThreshold');
    test('rejects: alias shared by two exercises', () {
      final doc = exampleForTests();
      final list = doc['exercises']! as List;
      final copy = jsonDecode(jsonEncode(list.first)) as Map<String, Object?>;
      copy['id'] = 'second';
      list.add(copy);
      expect(
          () => parse(doc),
          throwsA(isA<CoachRegistryException>()
              .having((e) => e.message, 'message', contains('alias'))));
    });
  });

  group('validateCueIds', () {
    test('passes when every cueId is known', () {
      final reg = parse(exampleForTests());
      validateCueIds(reg, {'cue.example.depth', 'cue.other'});
    });
    test('throws listing unknown cue ids', () {
      final reg = parse(exampleForTests());
      expect(
          () => validateCueIds(reg, {'cue.other'}),
          throwsA(isA<CoachRegistryException>().having((e) => e.message,
              'message', contains('example_squat.depth'))));
    });
    test('empty registry passes with an empty known set', () {
      validateCueIds(
          parse({'schema': 'coach_exercises/v1', 'exercises': []}), {});
    });
  });
}

String _readAsset() => File('assets/data/coach_exercises.json').readAsStringSync();
