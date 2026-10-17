// Shared helpers of the S03 epic 5C conformance files (test code only).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/modes/data/mode_models.dart';

import '../modes/mode_epic2_harness.dart';

/// Window classes of the test plan (width x height, dp at DPR 1.0).
const List<Size> kConformanceSizes = <Size>[
  Size(360, 640),
  Size(600, 900),
  Size(1100, 800),
  Size(1400, 900),
];

const List<double> kConformanceScales = <double>[1.0, 2.0];
const List<String> kConformanceLangs = <String>['en', 'ru'];

String sizeName(Size s) => '${s.width.toInt()}x${s.height.toInt()}';

/// Seeds a pending chooser state for [uid-a] so `/mode-chooser` stays open.
FakeModeStore pendingStore() => FakeModeStore()
  ..seed('uid-a', status: ChooserStatus.pending);

/// Every RenderParagraph under [root] that clipped its text (maxLines hit).
List<String> clippedParagraphs(WidgetTester tester, {Finder? root}) {
  final Finder scope = root ?? find.byType(MaterialApp);
  final List<String> out = <String>[];
  for (final Element e in find
      .descendant(of: scope, matching: find.byType(RichText))
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderParagraph && ro.didExceedMaxLines) {
      out.add(ro.text.toPlainText());
    }
  }
  return out;
}

/// Global rect of a semantics node (walks the transforms up to the root).
Rect globalRect(SemanticsNode n) {
  Rect r = n.rect;
  SemanticsNode? cur = n;
  while (cur != null) {
    final Matrix4? t = cur.transform;
    if (t != null) r = MatrixUtils.transformRect(t, r);
    cur = cur.parent;
  }
  return r;
}

/// Tappable semantics nodes (enabled, with a tap action) that are on screen.
List<SemanticsNode> tappableNodes(WidgetTester tester) {
  final List<SemanticsNode> out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    // ignore: deprecated_member_use
    if (n.getSemanticsData().hasAction(SemanticsAction.tap) && !n.isInvisible && !n.isMergedIntoParent) {
      out.add(n);
    }
    n.visitChildren((SemanticsNode c) {
      walk(c);
      return true;
    });
  }

  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

/// Description of every tappable node smaller than [min] in either direction.
List<String> smallTargets(WidgetTester tester, {double min = 48}) {
  final List<String> bad = <String>[];
  for (final SemanticsNode n in tappableNodes(tester)) {
    final Rect r = globalRect(n);
    if (r.width < min - 0.5 || r.height < min - 0.5) {
      bad.add('"${n.label}" ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}');
    }
  }
  return bad;
}

/// Tappable nodes without any accessible name.
List<String> unnamedTargets(WidgetTester tester) {
  final List<String> bad = <String>[];
  for (final SemanticsNode n in tappableNodes(tester)) {
    if (n.label.trim().isEmpty && n.value.trim().isEmpty && n.tooltip.trim().isEmpty) {
      bad.add('${globalRect(n)}');
    }
  }
  return bad;
}

/// Labels owned by pre-S03 code (L12 triage, branch base 2c121242): the
/// bottom-bar labels (hud_scaffold.dart, accepted comment), the Home stat and
/// adaptive-plan labels (home_page.dart) and the eligibility notice button.
bool isCarriedLabel(String s) {
  const Set<String> carried = <String>{
    'kg lifted', 'кг поднято', 'тренировки',
    "Today's adaptive plan", 'Адаптивный план на сегодня',
    'Проверить мои ответы о здоровье',
    'HOME', 'WORKOUTS', 'SCAN', 'PROGRESS', 'PROFILE',
    'ГЛАВНАЯ', 'ТРЕНИРОВКИ', 'СКАН', 'ПРОГРЕСС', 'ПРОФИЛЬ',
  };
  return carried.contains(s);
}

/// Cells (page/size/scale/lang or size/scale/lang) that fail on carried labels.
const Set<String> kCarriedHomeCells = <String>{
  'home/360x640/x1.0/en', 'home/360x640/x1.0/ru',
  'home/360x640/x2.0/en', 'home/360x640/x2.0/ru',
  'home/600x900/x2.0/en', 'home/600x900/x2.0/ru',
  'home/1100x800/x1.0/ru', 'home/1100x800/x2.0/en', 'home/1100x800/x2.0/ru',
  'home/1400x900/x1.0/ru', 'home/1400x900/x2.0/en', 'home/1400x900/x2.0/ru',
};
const Set<String> kCarriedShellCells = <String>{
  '360x640/x1.0/en', '360x640/x1.0/ru', '360x640/x2.0/en', '360x640/x2.0/ru',
  '600x900/x2.0/en', '600x900/x2.0/ru',
};
