// Test-only fixture for the coach registry. NOT shipped content: the real
// exercises are authored by a later package. Returns a fresh deep copy each
// call so tests can mutate it freely.

import 'dart:convert';

Map<String, Object?> exampleForTests() {
  const exercise = <String, Object?>{
    'id': 'example_squat',
    'aliases': ['squat_pose'],
    'version': 1,
    'view': 'side',
    'sidePolicy': 'bestVisible',
    'tracked': ['hip', 'knee', 'ankle', 'leftShoulder'],
    'unscored': ['nose'],
    'phases': [
      {'name': 'top', 'entry': 'knee angle above exit threshold'},
      {'name': 'bottom', 'entry': 'knee angle below enter threshold'},
    ],
    'signal': {
      'kind': 'angle',
      'joints': ['hip', 'knee', 'ankle'],
      'direction': 'falling',
      'enter': 100,
      'exit': 160,
    },
    'counting': {'mode': 'reps'},
    'rules': [
      {
        'id': 'depth',
        'metric': 'knee_angle',
        'min': 60,
        'max': 100,
        'tolerance': 5,
        'phase': 'bottom',
        'severity': 'minor',
        'cueId': 'cue.example.depth',
        'advisory': true,
      },
    ],
    'safetyWording': false,
    'provenance': {'kind': 'authored', 'source': 'test', 'status': 'beta'},
  };
  final doc = <String, Object?>{
    'schema': 'coach_exercises/v1',
    'exercises': [exercise],
  };
  return jsonDecode(jsonEncode(doc)) as Map<String, Object?>;
}

/// The single exercise map inside [doc] for in-place mutation.
Map<String, Object?> firstExercise(Map<String, Object?> doc) =>
    ((doc['exercises']! as List).first as Map).cast<String, Object?>();
