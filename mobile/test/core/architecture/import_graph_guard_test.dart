import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E1 - PLAN-29 / D-71: the file-level import graph of the new features'
/// `data/` layers is acyclic, and `nutrition_plan/data` depends on no sibling
/// feature. Imports are resolved to normalised `lib/...` paths so relative and
/// package imports are treated alike.
const _features = ['body_scan', 'nutrition_plan', 'food_diary', 'activity'];

String _stripComments(String s) {
  final noBlocks = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlocks
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}

String _norm(String p) {
  final parts = <String>[];
  for (final seg in p.replaceAll('\\', '/').split('/')) {
    if (seg == '' || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

final _importRe =
    RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

/// Direct project imports of [file] as `lib/...` paths.
List<String> _imports(File file) {
  final dir = _norm(file.parent.path);
  final out = <String>[];
  for (final m in _importRe.allMatches(_stripComments(file.readAsStringSync()))) {
    final uri = m.group(1)!;
    if (uri.startsWith('dart:')) continue;
    if (uri.startsWith('package:fitness_app/')) {
      out.add('lib/${uri.substring('package:fitness_app/'.length)}');
    } else if (uri.startsWith('package:')) {
      continue;
    } else {
      out.add(_norm('$dir/$uri'));
    }
  }
  return out;
}

List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

String? _featureOf(String libPath) {
  final m = RegExp(r'^lib/features/([a-z_]+)/').firstMatch(libPath);
  return m?.group(1);
}

Map<String, List<String>> _graph(List<String> dirs) {
  final g = <String, List<String>>{};
  for (final dir in dirs) {
    for (final f in _dartFiles(dir)) {
      g[_norm(f.path)] = _imports(f);
    }
  }
  return g;
}

/// A cycle as a path, or null.
List<String>? _findCycle(Map<String, List<String>> g) {
  final state = <String, int>{}; // 1 = on stack, 2 = done
  final stack = <String>[];
  List<String>? hit;
  void visit(String n) {
    if (hit != null) return;
    state[n] = 1;
    stack.add(n);
    for (final next in g[n] ?? const <String>[]) {
      if (!g.containsKey(next)) continue;
      if (state[next] == 1) {
        hit = [...stack.sublist(stack.indexOf(next)), next];
        return;
      }
      if (state[next] == null) visit(next);
      if (hit != null) return;
    }
    stack.removeLast();
    state[n] = 2;
  }

  for (final n in g.keys) {
    if (state[n] == null) visit(n);
    if (hit != null) break;
  }
  return hit;
}

void main() {
  final dataDirs = [
    for (final f in _features) 'lib/features/$f/data',
    'lib/core/math',
  ];

  test('guard on the guard: the scan sees real files and real edges', () {
    final g = _graph(dataDirs);
    expect(g.length, greaterThanOrEqualTo(40));
    final edges = g.values.expand((v) => v).length;
    expect(edges, greaterThan(50), reason: 'resolution produced almost no edges');
    // A known edge, resolved from a relative import.
    expect(g['lib/features/body_scan/data/scan_trend.dart'],
        contains('lib/core/math/series_math.dart'));
    expect(
        g['lib/features/body_scan/data/scan_result_math.dart'],
        containsAll([
          'lib/features/nutrition_plan/data/energy_math.dart',
          'lib/features/nutrition_plan/data/safety_clamps.dart',
        ]));
  });

  test('the cycle detector can fail: a synthetic cycle is found, a DAG is not', () {
    expect(
        _findCycle({
          'a': ['b'],
          'b': ['c'],
          'c': ['a'],
        }),
        ['a', 'b', 'c', 'a']);
    expect(
        _findCycle({
          'a': ['b', 'c'],
          'b': ['c'],
          'c': [],
        }),
        isNull);
  });

  test('PLAN-29: the data/ import graph of the four features and core/math is acyclic', () {
    final cycle = _findCycle(_graph(dataDirs));
    expect(cycle, isNull, reason: 'import cycle: $cycle');
  });

  test('D-71: nutrition_plan/data imports no sibling feature (only profile/safety/core)', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/features/nutrition_plan/data')) {
      for (final imp in _imports(f)) {
        final feat = _featureOf(imp);
        if (feat != null && _features.contains(feat) && feat != 'nutrition_plan') {
          bad.add('${_norm(f.path)} -> $imp');
        }
      }
    }
    expect(bad, isEmpty, reason: 'nutrition_plan/data must not depend on $bad');
  });

  test('activity/data is a leaf: it imports no sibling new feature', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/features/activity/data')) {
      for (final imp in _imports(f)) {
        final feat = _featureOf(imp);
        if (feat != null && _features.contains(feat) && feat != 'activity') {
          bad.add('${_norm(f.path)} -> $imp');
        }
      }
    }
    expect(bad, isEmpty, reason: '$bad');
  });

  test('food_diary/data and body_scan/data depend on nutrition_plan only, never on each other', () {
    for (final pair in const [
      ['food_diary', 'body_scan'],
      ['body_scan', 'food_diary'],
    ]) {
      for (final f in _dartFiles('lib/features/${pair[0]}/data')) {
        for (final imp in _imports(f)) {
          expect(_featureOf(imp), isNot(pair[1]),
              reason: '${_norm(f.path)} -> $imp');
        }
      }
    }
  });

  test('food_suggestions lives in food_diary/data and series_math in core/math', () {
    expect(File('lib/features/food_diary/data/food_suggestions.dart').existsSync(),
        isTrue);
    expect(File('lib/core/math/series_math.dart').existsSync(), isTrue);
    expect(File('lib/features/nutrition_plan/data/food_suggestions.dart').existsSync(),
        isFalse,
        reason: 'D-71: food_suggestions must not live in nutrition_plan');
  });

  test('the nutrition_plan -> body_scan edges outside data/ are exactly the two known ones', () {
    // FINDING (reported, not edited: files belong to other epics). PLAN-29 says
    // "none the other way", yet nutrition_plan's state and page import
    // body_scan. The data layers stay acyclic, so this pins the current set:
    // a THIRD edge fails here and must be justified.
    final edges = <String>{};
    for (final f in _dartFiles('lib/features/nutrition_plan')) {
      final p = _norm(f.path);
      if (p.startsWith('lib/features/nutrition_plan/data/')) continue;
      for (final imp in _imports(f)) {
        if (_featureOf(imp) == 'body_scan') edges.add('$p -> $imp');
      }
    }
    expect(edges, {
      'lib/features/nutrition_plan/nutrition_plan_page.dart -> '
          'lib/features/body_scan/state/body_scan_providers.dart',
      'lib/features/nutrition_plan/state/scan_plan_context_source.dart -> '
          'lib/features/body_scan/data/scan_plan_context.dart',
    });
  });
}
