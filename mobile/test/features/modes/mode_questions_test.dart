// S03-09 First-run questions S-2 (test plan 4.2). Real ModeQuestionPage on the
// real `/mode-questions/:mode` route (with its redirect), stub destinations.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/home/widgets/home_lens.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/onboarding/widgets/ob_shell.dart'
    show ObProgressHeader;
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_gate_view.dart'
    show scanAccessMessage;
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart' show HudButton;

import 'mode_epic2_harness.dart';

Finder _opt(String id) => byKeyS('modeQuestion.option.$id');
Finder _skip() => byKeyS('modeQuestion.skip');

FakeModeStore _store({AppMode mode = AppMode.train, ChooserStatus status = ChooserStatus.resolved}) =>
    FakeModeStore()..seed('uid-a', mode: mode, status: status);

String _progress(WidgetTester t) =>
    t.widget<Text>(byKeyS('modeQuestion.progress')).data!;

Future<void> _wait(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AC-Q-1 a known answer is not asked again', () {
    for (final answer in ['gymMachines', 'skipped']) {
      testWidgets('AC-Q-1/context=$answer chooser Continue goes to Home',
          (tester) async {
        final store = FakeModeStore()..seed('uid-a', status: ChooserStatus.pending);
        final rig = await pumpRig(tester,
            store: store, prefValues: {'training_context.v1.uid-a': answer});
        await tester.tap(byKeyS('modeChooser.card.train'));
        await settleFrames(tester, frames: 3);
        await tester.tap(byKeyS('modeChooser.continue'));
        await settleFrames(tester);
        expect(rig.visits.last, '/home');
        expect(byKeyS('modeQuestion.skip'), findsNothing);
      });
    }

    testWidgets('AC-Q-1/control: unanswered context IS asked', (tester) async {
      final store = FakeModeStore()..seed('uid-a', status: ChooserStatus.pending);
      await pumpRig(tester, store: store);
      await tester.tap(byKeyS('modeChooser.card.train'));
      await settleFrames(tester, frames: 3);
      await tester.tap(byKeyS('modeChooser.continue'));
      await settleFrames(tester);
      expect(_skip(), findsOneWidget);
    });
  });

  testWidgets('AC-Q-2 Skip sticks: stored skipped, not asked on a second visit',
      (tester) async {
    final store = _store(mode: AppMode.body);
    await pumpRig(tester, store: store, initial: '/mode-questions/body');
    await tester.tap(_skip());
    await _wait(tester);
    expect(store.stored('uid-a')!.answerFor(AppMode.body), ModeAnswer.skipped);
    await tester.pumpWidget(const SizedBox());
    final rig2 = await pumpRig(tester, store: store, initial: '/mode-questions/body');
    expect(_skip(), findsNothing);
    expect(rig2.visits.last, '/home');
  });

  for (final c in [
    ('food', 'nutrition', 'bodyScan'),
    ('photos', 'bodyScan', 'nutrition'),
  ]) {
    testWidgets('AC-Q-3/${c.$1} the BODY answer reorders the Home lens',
        (tester) async {
      final store = _store(mode: AppMode.body);
      final rig = await pumpRig(tester,
          store: store, initial: '/mode-questions/body');
      await tester.tap(_opt(c.$1));
      await _wait(tester);
      final ms = rig.container.read(modeStateProvider).valueOrNull!;
      final a = ms.answerFor(AppMode.body);
      expect(a.value, c.$1);
      final order = homeSectionOrder(homeLensOf(ms.selectedMode),
          bodyStart: a.isAnswered ? a.value : null);
      expect(order.indexOf(c.$2), lessThan(order.indexOf(c.$3)),
          reason: '$order');
      expect(store.stored('uid-a')!.answerFor(AppMode.body).value, c.$1);
    });
  }

  for (final lang in ['en', 'ru']) {
    for (final m in [AppMode.train, AppMode.body]) {
      testWidgets('AC-Q-4/$lang/${m.name} counter shows true index and total',
          (tester) async {
        final l10n = l10nOf(lang);
        await pumpRig(tester,
            store: _store(mode: m),
            locale: Locale(lang),
            initial: '/mode-questions/${m.name}');
        expect(_progress(tester), l10n.modeQuestionProgress(1, 1));
        var screens = 1;
        // Walk: answer the single question; never more than 3 screens.
        final id = m == AppMode.train ? 'gym' : 'photos';
        await tester.tap(_opt(id));
        await _wait(tester);
        while (_skip().evaluate().isNotEmpty && screens < 4) {
          screens++;
          await tester.tap(_skip());
          await _wait(tester);
        }
        expect(screens, lessThanOrEqualTo(3));
      });
    }
  }

  testWidgets('AC-Q-5 failed save: inline error, Skip and Back stay enabled',
      (tester) async {
    final l10n = l10nOf('en');
    final store = _store(mode: AppMode.body)..throwOnWrite = true;
    await pumpRig(tester, store: store, initial: '/mode-questions/body');
    await tester.tap(_opt('food'));
    await _wait(tester);
    expect(tester.widget<Text>(byKeyS('modeQuestion.error')).data,
        l10n.modeQuestionSaveError);
    expect(tester.widget<HudButton>(_skip()).enabled, isTrue);
    expect(tester.widget<HudButton>(_skip()).onPressed, isNotNull);
    expect(tester.widget<ObProgressHeader>(find.byType(ObProgressHeader)).onBack,
        isNotNull);
    expect(byKeyS('modeQuestion.retry'), findsOneWidget);
  });

  testWidgets('AC-Q-6 refused option is present, disabled, reason in hint',
      (tester) async {
    final h = tester.ensureSemantics();
    final l10n = l10nOf('en');
    await pumpRig(tester,
        store: _store(mode: AppMode.body),
        initial: '/mode-questions/body',
        overrides: [
          fakeScanAccessProvider.overrideWith((_) => ScanAccess.underage)
        ]);
    expect(_opt('photos'), findsOneWidget);
    final n = tester.getSemantics(_opt('photos'));
    expect(isEnabledNode(n), isFalse);
    expect(allText(n), contains(scanAccessMessage(l10n, ScanAccess.underage)));
    // The other options stay usable.
    expect(isEnabledNode(tester.getSemantics(_opt('food'))), isTrue);
    h.dispose();
  });

  testWidgets('RV-9c Skip and Retry show the full ru label at scale 2.0 on 360 dp',
      (tester) async {
    final l10n = l10nOf('ru');
    final store = _store(mode: AppMode.body)..throwOnWrite = true;
    await pumpRig(tester,
        store: store,
        initial: '/mode-questions/body',
        locale: const Locale('ru'),
        textScale: 2.0);
    await tester.ensureVisible(_opt('food'));
    await tester.tap(_opt('food'));
    await _wait(tester);
    for (final c in [
      (_skip(), l10n.modeQuestionSkip),
      (byKeyS('modeQuestion.retry'), l10n.modeQuestionRetry),
    ]) {
      await tester.ensureVisible(c.$1);
      final text = find.descendant(of: c.$1, matching: find.text(c.$2));
      expect(text, findsOneWidget, reason: c.$2);
      final p = tester.renderObject<RenderParagraph>(text);
      expect(p.didExceedMaxLines, isFalse, reason: c.$2);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('DT-09-1 saving feedback for >= 300 ms, no spinner, no double submit',
      (tester) async {
    final l10n = l10nOf('en');
    final store = _store(mode: AppMode.body)
      ..writeDelay = const Duration(milliseconds: 400);
    await pumpRig(tester, store: store, initial: '/mode-questions/body');
    await tester.tap(_opt('food'));
    await tester.pump(const Duration(milliseconds: 310));
    expect(tester.widget<Text>(byKeyS('modeQuestion.saving')).data,
        l10n.modeQuestionSaving);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<HudButton>(_skip()).enabled, isFalse);
    await tester.tap(_opt('weight'), warnIfMissed: false);
    await _wait(tester, 800);
    expect(store.writes.length, 1, reason: 'double submit');
    expect(store.stored('uid-a')!.answerFor(AppMode.body).value, 'food');
  });

  testWidgets('DT-09-2 Retry stores the answer and continues', (tester) async {
    final store = _store(mode: AppMode.body)..throwTimes = 1;
    final rig = await pumpRig(tester, store: store, initial: '/mode-questions/body');
    await tester.tap(_opt('weight'));
    await _wait(tester);
    expect(byKeyS('modeQuestion.error'), findsOneWidget);
    await tester.tap(byKeyS('modeQuestion.retry'));
    await _wait(tester, 800);
    expect(store.stored('uid-a')!.answerFor(AppMode.body).value, 'weight');
    expect(store.writes.length, 2);
    expect(rig.visits.last, '/home');
  });

  testWidgets('DT-09-3 only unknown questions are counted', (tester) async {
    // Context answered: TRAIN has nothing to ask and leaves at once.
    final rig = await pumpRig(tester,
        store: _store(),
        initial: '/mode-questions/train',
        prefValues: {'training_context.v1.uid-a': 'home'});
    expect(_skip(), findsNothing);
    expect(rig.visits.last, '/home');
    // Context unknown: exactly "1 of 1".
    await tester.pumpWidget(const SizedBox());
    await pumpRig(tester, store: _store(), initial: '/mode-questions/train');
    expect(_progress(tester), l10nOf('en').modeQuestionProgress(1, 1));
  });

  testWidgets('DT-09-4 (single-question reduction) Back writes nothing and keeps no answer',
      (tester) async {
    final store = _store(mode: AppMode.body);
    final rig = await pumpRig(tester, store: store, initial: '/mode-questions/body');
    await tester.binding.handlePopRoute();
    await _wait(tester);
    expect(store.writes, isEmpty);
    expect(rig.visits.last, '/home');
  });

  testWidgets('DT-09-5 (single-question reduction) answer survives a kill, not asked again',
      (tester) async {
    final store = _store(mode: AppMode.body);
    await pumpRig(tester, store: store, initial: '/mode-questions/body');
    await tester.tap(_opt('food'));
    await _wait(tester);
    await tester.pumpWidget(const SizedBox());
    final rig2 = await pumpRig(tester, store: store, initial: '/mode-questions/body');
    expect(_skip(), findsNothing);
    expect(rig2.visits.last, '/home');
    expect(store.writes.length, 1);
  });

  for (final raw in ['xyz', 'ride', 'explore']) {
    testWidgets('DT-09-6/$raw deep link redirects to /home, zero writes',
        (tester) async {
      final store = _store();
      final rig = await pumpRig(tester,
          store: store, initial: '/mode-questions/$raw');
      expect(rig.visits.last, '/home');
      expect(_skip(), findsNothing);
      expect(store.writes, isEmpty);
    });
  }
}
