import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/window_size.dart';

import '../../support/s03_shell_harness.dart' show kTabPaths;

/// Probe that records the info it reads and counts its builds.
class _Probe extends StatelessWidget {
  const _Probe({this.aspect, required this.sink});
  final WindowSizeAspect? aspect;
  final _Sink sink;
  @override
  Widget build(BuildContext context) {
    sink.builds++;
    sink.last = WindowSizeInfo.of(context, aspect: aspect);
    return const SizedBox.expand();
  }
}

class _Sink {
  int builds = 0;
  WindowSizeInfo? last;
}

Future<void> _pump(WidgetTester t, Size size, _Sink sink,
    {bool scope = true,
    List<Override> overrides = const <Override>[],
    WindowSizeAspect? aspect}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final Widget probe = _Probe(aspect: aspect, sink: sink);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      home: const SizedBox(),
      builder: (BuildContext c, Widget? _) =>
          scope ? WindowSizeScope(child: probe) : probe,
    ),
  ));
}

void main() {
  test('AC-WS-1a boundaries 599/600/839/840 at height 800', () {
    final table = <(double, WindowSizeClass)>[
      (599, WindowSizeClass.compact),
      (600, WindowSizeClass.medium),
      (839, WindowSizeClass.medium),
      (840, WindowSizeClass.expanded),
    ];
    for (final (w, c) in table) {
      final i = classifyWindow(Size(w, 800));
      expect(i.sizeClass, c, reason: 'width $w');
      expect(i.isShort, isFalse, reason: 'width $w');
    }
  });

  for (final s in <Size>[const Size(700, 420), const Size(500, 420)]) {
    testWidgets('AC-WS-1b/${s.width.toInt()}x${s.height.toInt()}', (t) async {
      final sink = _Sink();
      await _pump(t, s, sink);
      expect(sink.last!.isShort, isTrue);
      expect(sink.last!.sizeClass,
          s.width == 700 ? WindowSizeClass.medium : WindowSizeClass.compact);
    });
  }

  test('DT-02-1 short threshold: 479 short, 480 and 481 not', () {
    expect(classifyWindow(const Size(700, 479)).isShort, isTrue);
    expect(classifyWindow(const Size(700, 480)).isShort, isFalse);
    expect(classifyWindow(const Size(700, 481)).isShort, isFalse);
    // Rail rule: medium and short, or expanded.
    expect(classifyWindow(const Size(700, 479)).usesRail, isTrue);
    expect(classifyWindow(const Size(700, 480)).usesRail, isFalse);
    expect(classifyWindow(const Size(500, 300)).usesRail, isFalse);
    expect(classifyWindow(const Size(840, 900)).usesRail, isTrue);
  });

  testWidgets('DT-02-2 fractional widths are not rounded', (t) async {
    final sink = _Sink();
    await _pump(t, const Size(599.5, 800), sink);
    expect(sink.last!.sizeClass, WindowSizeClass.compact);
    await _pump(t, const Size(839.5, 800), _Sink()..builds = 0);
    final s2 = _Sink();
    await _pump(t, const Size(839.5, 800), s2);
    expect(s2.last!.sizeClass, WindowSizeClass.medium);
  });

  testWidgets('DT-02-3 live resize: one rebuild per class change', (t) async {
    final sink = _Sink();
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(360, 800);
    final Widget probe =
        _Probe(aspect: WindowSizeAspect.sizeClass, sink: sink);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: const SizedBox(),
        builder: (BuildContext c, Widget? _) => WindowSizeScope(child: probe),
      ),
    ));
    final seq = <WindowSizeClass>[sink.last!.sizeClass];
    Future<void> resize(Size s) async {
      t.view.physicalSize = s;
      await t.pump();
      if (seq.last != sink.last!.sizeClass) seq.add(sink.last!.sizeClass);
    }

    final int b0 = sink.builds;
    await resize(const Size(380, 800));
    await resize(const Size(420, 900));
    expect(sink.builds, b0, reason: 'resize inside one class must not rebuild');
    await resize(const Size(700, 900));
    expect(sink.builds, b0 + 1);
    await resize(const Size(760, 900));
    expect(sink.builds, b0 + 1);
    await resize(const Size(1100, 800));
    expect(sink.builds, b0 + 2);
    await resize(const Size(360, 800));
    expect(sink.builds, b0 + 3);
    expect(seq, <WindowSizeClass>[
      WindowSizeClass.compact,
      WindowSizeClass.medium,
      WindowSizeClass.expanded,
      WindowSizeClass.compact,
    ]);
  });

  testWidgets('DT-02-4 override wins over the view (scope and no scope)',
      (t) async {
    final override = windowSizeOverrideProvider.overrideWith(
        (ref) => WindowSizeInfo.forClass(WindowSizeClass.expanded));
    final withScope = _Sink();
    await _pump(t, const Size(360, 800), withScope, overrides: [override]);
    expect(withScope.last!.sizeClass, WindowSizeClass.expanded);
    expect(withScope.last!.usesRail, isTrue);
    final noScope = _Sink();
    await _pump(t, const Size(360, 800), noScope,
        scope: false, overrides: [override]);
    expect(noScope.last!.sizeClass, WindowSizeClass.expanded);
    final noOverride = _Sink();
    await _pump(t, const Size(360, 800), noOverride);
    expect(noOverride.last!.sizeClass, WindowSizeClass.compact);
  });

  test('DT-02-5 K: no screen reads raw widths against 600/840', () {
    final files = <String>[
      'lib/shared/widgets/shell_layout.dart',
      'lib/shared/widgets/shell_destinations.dart',
      'lib/shared/widgets/hud/hud_side_rail.dart',
      'lib/shared/widgets/shell_dock.dart',
      'lib/shared/widgets/dock_widgets.dart',
      'lib/shared/widgets/adaptive_surface.dart',
      'lib/shared/widgets/main_shell.dart',
      'lib/shared/widgets/app_shortcuts.dart',
      'lib/features/workouts/state/active_session_status.dart',
    ];
    final dir = Directory('lib/features/modes');
    expect(dir.existsSync(), isTrue, reason: 'scan dir must exist');
    final modes = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList();
    expect(modes, isNotEmpty);
    final all = <String>[...files, ...modes];
    expect(all.length, greaterThanOrEqualTo(15));
    expect(all, contains('lib/shared/widgets/hud/hud_side_rail.dart'));
    expect(all, contains('lib/shared/widgets/main_shell.dart'));
    final bad = <RegExp>[
      RegExp(r'MediaQuery\.of\([^)]*\)\.size\.width'),
      RegExp(r'MediaQuery\.sizeOf\([^)]*\)\.width'),
      RegExp(r'\.width\s*[<>]=?\s*(600|840)\b'),
      RegExp(r'\b(600|840)(\.0)?\s*[<>]=?\s*[\w.]*width'),
      RegExp(r'LayoutBuilder[\s\S]{0,300}?(600|840)\b'),
    ];
    final hits = <String>[];
    for (final p in all) {
      final f = File(p);
      expect(f.existsSync(), isTrue, reason: '$p missing from scan set');
      final src = f.readAsStringSync();
      for (final re in bad) {
        if (re.hasMatch(src)) hits.add('$p: ${re.pattern}');
      }
    }
    expect(hits, isEmpty);
    expect(kTabPaths.length, 5); // keeps the harness import honest
  });
}
