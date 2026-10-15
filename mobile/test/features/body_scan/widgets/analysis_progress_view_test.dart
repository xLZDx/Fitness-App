import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/widgets/analysis_progress_view.dart';

import '../support/scan_test_support.dart';

final DateTime _t0 = DateTime(2026, 10, 15, 8);

class _Rig {
  _Rig(this.tester);
  final WidgetTester tester;
  DateTime now = _t0;
  int cancels = 0;
  int retries = 0;
  final List<Map<dynamic, dynamic>> announcements = [];
  late SemanticsHandle handle;

  void dispose() {
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility, null);
    handle.dispose();
  }

  void install() {
    handle = tester.ensureSemantics();
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (dynamic m) async {
        if (m is Map && m['type'] == 'announce') {
          announcements.add(m['data'] as Map);
        }
        return null;
      },
    );
  }

  Widget view(AnalysisStage stage,
          {bool photosKeptLocal = false, bool reduce = false}) =>
      scanHost(
        AnalysisProgressView(
          stage: stage,
          startedAt: _t0,
          photosKeptLocal: photosKeptLocal,
          now: () => now,
          onCancel: () => cancels++,
          onRetry: () => retries++,
        ),
        disableAnimations: reduce,
      );

  Future<void> show(AnalysisStage stage,
      {bool photosKeptLocal = false, bool reduce = false}) async {
    await tester.pumpWidget(
        view(stage, photosKeptLocal: photosKeptLocal, reduce: reduce));
    await tester.pump();
  }

  /// Advances the fake clock and the periodic timer second by second.
  Future<void> advance(int seconds) async {
    for (var i = 0; i < seconds; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  String get liveLabel =>
      tester.getSemantics(find.byKey(const Key('bodyScan.progress.live'))).label;

  int get liveRegionCount {
    var n = 0;
    void walk(SemanticsNode node) {
      if (node.hasFlag(SemanticsFlag.isLiveRegion)) n++;
      node.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    return n;
  }
}

void rigTest(String name, Future<void> Function(_Rig r) body) {
  testWidgets(name, (tester) async {
    final r = _Rig(tester)..install();
    try {
      await body(r);
    } finally {
      r.dispose();
    }
  });
}

Finder _k(String key) => find.byKey(Key(key));

void main() {
  group('formatElapsed', () {
    test('m:ss with zero padding', () {
      expect(formatElapsed(Duration.zero), '0:00');
      expect(formatElapsed(const Duration(seconds: 7)), '0:07');
      expect(formatElapsed(const Duration(seconds: 65)), '1:05');
    });
    test('negative durations clamp to zero', () {
      expect(formatElapsed(const Duration(seconds: -5)), '0:00');
    });
  });

  group('stage list', () {
    rigTest('lists five named stages with state labels for stage 2', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.composition);
      for (final label in [
        'Photos secured, done',
        'Body composition, in progress',
        'Plausibility check, waiting',
        'Trend verification, waiting',
        'Result saved, waiting',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
    });

    rigTest('photosKeptLocal renames stage one', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos, photosKeptLocal: true);
      expect(find.text('Photos kept on this device'), findsWidgets);
      expect(find.text('Photos secured'), findsNothing);
    });

    rigTest('a stage change updates the live region text', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      expect(r.liveLabel, 'Step 1 of 5: Photos secured');
      await r.show(AnalysisStage.plausibility);
      expect(r.liveLabel, 'Step 3 of 5: Plausibility check');
    });
  });

  group('live region contract (D-81)', () {
    rigTest('exactly one live region exists', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      expect(r.liveRegionCount, 1);
    });

    rigTest('the live text never contains the elapsed counter', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      for (var s = 1; s <= 19; s++) {
        await r.advance(1);
        expect(r.liveLabel, 'Step 1 of 5: Photos secured',
            reason: 'second $s');
        expect(r.liveLabel, isNot(contains('Elapsed')));
        expect(r.liveLabel, isNot(contains('0:')));
      }
      expect(r.announcements, isEmpty);
    });

    rigTest('the elapsed counter advances as a plain element', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      expect(find.text('Elapsed: 0:00'), findsOneWidget);
      await r.advance(7);
      expect(find.text('Elapsed: 0:07'), findsOneWidget);
      final node = tester.getSemantics(find.text('Elapsed: 0:07'));
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isFalse);
    });

    rigTest('at 19 s there is no slow notice, at 20 s there is', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(19);
      expect(_k('bodyScan.progress.slow'), findsNothing);
      await r.advance(1);
      expect(_k('bodyScan.progress.slow'), findsOneWidget);
      expect(r.liveLabel, contains('This is taking longer than usual.'));
      expect(r.liveLabel, startsWith('Step 1 of 5: Photos secured.'));
      expect(r.announcements, isEmpty); // polite: via the live region only
    });

    rigTest('Keep waiting removes the notice from the live text', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(21);
      expect(_k('bodyScan.progress.keepWaiting'), findsOneWidget);
      await tester.tap(_k('bodyScan.progress.keepWaiting'));
      await tester.pump();
      expect(_k('bodyScan.progress.keepWaiting'), findsNothing);
      expect(r.liveLabel, 'Step 1 of 5: Photos secured');
      expect(r.retries, 0);
      expect(r.cancels, 0);
    });

    rigTest('25 s: ONE assertive announcement, live text emptied', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(24);
      expect(r.announcements, isEmpty);
      await r.advance(1);
      expect(r.announcements, hasLength(1));
      expect(r.announcements.single['message'],
          'The analysis timed out. Your photos are safe. Try again.');
      expect(r.announcements.single['assertiveness'], 1);
      expect(r.liveLabel, isEmpty);
      await r.advance(10);
      expect(r.announcements, hasLength(1), reason: 'not repeated');
    });

    rigTest('no announcement ever carries elapsed seconds', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(40);
      for (final a in r.announcements) {
        expect('${a['message']}', isNot(contains('Elapsed')));
        expect('${a['message']}', isNot(matches(r'\d:\d\d')));
      }
    });
  });

  group('timeout state', () {
    rigTest('shows the timeout text and a Retry button that works', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(25);
      expect(_k('bodyScan.progress.timeout'), findsOneWidget);
      expect(_k('bodyScan.progress.slow'), findsNothing);
      await tester.tap(_k('bodyScan.progress.retry'));
      expect(r.retries, 1);
    });

    rigTest('focus moves to Retry at 25 s', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(25);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      expect(focus, isNotNull);
      final retry = find.byKey(const Key('bodyScan.progress.retry'));
      expect(
          find.descendant(
              of: retry,
              matching: find.byWidgetPredicate(
                  (w) => w is Focus && w.focusNode == focus)),
          findsWidgets);
    });

    rigTest('Cancel stays reachable after the timeout', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(26);
      await tester.tap(_k('bodyScan.progress.cancel'));
      expect(r.cancels, 1);
    });
  });

  group('Cancel first', () {
    rigTest('the first Tab lands on Cancel', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus!;
      final owner = focus.context!
          .findAncestorWidgetOfExactType<TextButton>();
      expect(owner?.key, const Key("bodyScan.progress.cancel"),
          reason: "focused: ${focus.context}");
    });

    rigTest('Cancel precedes the title in semantics order', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      final labels = <String>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) labels.add(n.label);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      final cancelAt = labels.indexWhere((l) => l == "Cancel");
      final titleAt = labels.indexWhere((l) => l == "Analysing your scan");
      expect(cancelAt, isNonNegative, reason: "$labels");
      expect(titleAt, isNonNegative, reason: "$labels");
      expect(cancelAt, lessThan(titleAt));
    });

    rigTest('tapping Cancel calls onCancel once', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await tester.tap(_k('bodyScan.progress.cancel'));
      expect(r.cancels, 1);
    });
  });

  group('reduced motion', () {
    rigTest('normal motion shows the progress indicator', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      expect(_k('bodyScan.progress.indicator'), findsOneWidget);
    });

    rigTest('reduced motion has no indicator, text still changes', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos, reduce: true);
      expect(_k('bodyScan.progress.indicator'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(r.liveLabel, 'Step 1 of 5: Photos secured');
      await r.show(AnalysisStage.trend, reduce: true);
      expect(r.liveLabel, 'Step 4 of 5: Trend verification');
      expect(_k('bodyScan.progress.indicator'), findsNothing);
    });

    rigTest('the indicator is dropped on timeout even with motion on', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await r.advance(25);
      expect(_k('bodyScan.progress.indicator'), findsNothing);
    });
  });

  group('lifecycle', () {
    rigTest('disposing cancels the periodic timer (no pending timers)', (r) async {
      final tester = r.tester;
      await r.show(AnalysisStage.photos);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    rigTest('RU text at scale 2.0 does not overflow', (r) async {
      final tester = r.tester;
      await tester.pumpWidget(scanHost(
        AnalysisProgressView(
            stage: AnalysisStage.composition,
            startedAt: _t0,
            now: () => r.now,
            onCancel: () {},
            onRetry: () {}),
        locale: const Locale('ru'),
        textScale: 2.0,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
