import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E1 - PLAN-20, ACT-13, A11Y-11: the pure data layers stay pure.
///
/// Source-scanning guard. Comments are stripped before matching so prose that
/// names `package:flutter/` cannot satisfy or fail a check.
const _pureDirs = <String>[
  'lib/features/body_scan/data',
  'lib/features/nutrition_plan/data',
  'lib/features/food_diary/data',
  'lib/features/activity/data',
  'lib/core/math',
];

String _stripComments(String s) {
  final noBlocks = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlocks
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}

List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _rel(File f) => f.path.replaceAll('\\', '/');

void main() {
  test('guard on the guard: every pure directory exists and holds sources', () {
    for (final d in _pureDirs) {
      expect(Directory(d).existsSync(), isTrue, reason: '$d moved or renamed');
      expect(_dartFiles(d), isNotEmpty, reason: '$d holds no Dart files');
    }
    final total = _pureDirs.map((d) => _dartFiles(d).length).reduce((a, b) => a + b);
    expect(total, greaterThanOrEqualTo(40),
        reason: 'the scan saw suspiciously few files: $total');
  });

  test('PLAN-20: no pure data file imports package:flutter, dart:ui or a Flutter plugin UI', () {
    final offenders = <String>[];
    final flutterImport =
        RegExp(r'''^\s*(import|export)\s+['"](package:flutter/|dart:ui)''',
            multiLine: true);
    for (final d in _pureDirs) {
      for (final f in _dartFiles(d)) {
        final src = _stripComments(f.readAsStringSync());
        if (flutterImport.hasMatch(src)) offenders.add(_rel(f));
      }
    }
    expect(offenders, isEmpty,
        reason: 'pure data layers must run in a plain Dart VM: $offenders');
  });

  test('pure data files do not import any Flutter-bound sibling layer (widgets/state/ui)', () {
    final bad = RegExp(
        r'''^\s*(import|export)\s+['"][^'"]*/(widgets|ui)/''',
        multiLine: true);
    final offenders = <String>[];
    for (final d in _pureDirs) {
      for (final f in _dartFiles(d)) {
        if (bad.hasMatch(_stripComments(f.readAsStringSync()))) {
          offenders.add(_rel(f));
        }
      }
    }
    expect(offenders, isEmpty, reason: '$offenders');
  });

  test('ACT-13: the activity data layer has no UI and no persistence imports', () {
    final forbidden = RegExp(
        r'''^\s*(import|export)\s+['"](package:flutter/|package:cloud_firestore|package:shared_preferences|package:flutter_secure_storage|package:riverpod|package:flutter_riverpod|dart:io)''',
        multiLine: true);
    final files = _dartFiles('lib/features/activity/data');
    expect(files, isNotEmpty);
    for (final f in files) {
      final src = _stripComments(f.readAsStringSync());
      expect(forbidden.hasMatch(src), isFalse,
          reason: '${_rel(f)} imports UI/persistence/IO');
    }
  });

  test('A11Y-11: no Color(0x literals in the new feature widgets directories', () {
    final colorLiteral = RegExp(r'Color\(\s*0x', caseSensitive: true);
    final dirs = [
      'lib/features/body_scan/widgets',
      'lib/features/nutrition_plan/widgets',
      'lib/features/food_diary/widgets',
    ];
    final offenders = <String>[];
    for (final d in dirs) {
      for (final f in _dartFiles(d)) {
        if (colorLiteral.hasMatch(_stripComments(f.readAsStringSync()))) {
          offenders.add(_rel(f));
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use app_semantic_colors tokens instead of literals: $offenders');
  });

  test('the matcher can fail: a synthetic offender is detected', () {
    final flutterImport =
        RegExp(r'''^\s*(import|export)\s+['"](package:flutter/|dart:ui)''',
            multiLine: true);
    expect(flutterImport.hasMatch("import 'package:flutter/material.dart';"), isTrue);
    expect(flutterImport.hasMatch("export 'dart:ui';"), isTrue);
    expect(
        flutterImport.hasMatch(
            _stripComments("// import 'package:flutter/material.dart';\nimport 'a.dart';")),
        isFalse);
  });
}
