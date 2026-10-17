// S03-08 Mode chooser S-1 (test plan 4.1). Uses the REAL ModeChooserPage and
// the REAL buildS03Routes next to stub destinations.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/moments/data/moment.dart';
import 'package:fitness_app/features/moments/data/moment_repository.dart';
import 'package:fitness_app/features/moments/state/moment_providers.dart';
import 'package:fitness_app/features/moments/widgets/day3_welcome_modal.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/widgets/mode_chooser_offer.dart';
import 'package:fitness_app/features/modes/widgets/mode_card.dart';
import 'package:fitness_app/features/modes/widgets/mode_switcher_sheet.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart' show HudButton, HudChip;

import 'mode_epic2_harness.dart';

const _ctxAnswered = <String, String>{
  'training_context.v1.uid-a': 'gymMachines',
};

FakeModeStore _pending() =>
    FakeModeStore()..seed('uid-a', status: ChooserStatus.pending);

Finder _card(String m) => byKeyS('modeChooser.card.$m');
Finder _continue() => byKeyS('modeChooser.continue');

Rect _r(WidgetTester t, String m) => t.getRect(_card(m));

bool _continueEnabled(WidgetTester t) =>
    t.widget<HudButton>(_continue()).enabled &&
    t.widget<HudButton>(_continue()).onPressed != null;

List<String> _traversalLabels(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode n) {
    if (n.label.isNotEmpty) out.add(n.label);
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

Future<void> _tapCard(WidgetTester t, String m) async {
  await t.tap(_card(m));
  await settleFrames(t, frames: 3);
}

Future<void> _focusCard(WidgetTester t, String m) async {
  for (var i = 0; i < 30; i++) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx?.findAncestorWidgetOfExactType<ModeCard>()?.mode.name == m) return;
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  fail('could not focus card $m');
}

Future<void> _focusCardDirect(WidgetTester t, String m) async {
  Focus.of(t.element(find
          .descendant(of: _card(m), matching: find.byType(InkWell))
          .first))
      .requestFocus();
  await t.pump();
}

String? _focusedCard() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<ModeCard>()
    ?.mode
    .name;

Future<void> _closeSurfaces(WidgetTester t) async {
  // The Coming-later and switcher flags are module-level: always close.
  for (var i = 0; i < 3; i++) {
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    if (find.byKey(const Key('comingLater.sheet')).evaluate().isEmpty &&
        find.byKey(const Key('modeSwitcher.sheet')).evaluate().isEmpty) {
      break;
    }
    nav.pop();
    await settleFrames(t, frames: 4);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lang in ['ru', 'en']) {
    final loc = Locale(lang);
    final l10n = l10nOf(lang);

    testWidgets('AC-CH-1/$lang card keys and order', (tester) async {
      final h = tester.ensureSemantics();
      await pumpRig(tester, store: _pending(), locale: loc);
      final train = _r(tester, 'train'), ride = _r(tester, 'ride');
      final explore = _r(tester, 'explore'), body = _r(tester, 'body');
      expect(ride.top, train.top);
      expect(ride.left, greaterThan(train.left));
      expect(explore.top, greaterThan(train.bottom - 1));
      expect(body.top, explore.top);
      expect(body.left, greaterThan(explore.left));
      expect(explore.left, train.left);
      final labels = _traversalLabels(tester);
      int idx(String name) => labels.indexWhere((l) => l.startsWith(name));
      final order = [
        idx(l10n.modeTrainName),
        idx(l10n.modeRideName),
        idx(l10n.modeExploreName),
        idx(l10n.modeBodyName),
      ];
      expect(order.every((i) => i >= 0), isTrue, reason: '$labels');
      expect(order, orderedEquals([...order]..sort()),
          reason: 'semantics traversal order: $labels');
      h.dispose();
    });

    testWidgets('AC-CH-2/$lang coming-later card opens the sheet, no write',
        (tester) async {
      final store = _pending();
      await pumpRig(tester, store: store, locale: loc);
      await _tapCard(tester, 'ride');
      expect(byKeyS('comingLater.sheet'), findsOneWidget);
      expect(
          tester.widget<Text>(byKeyS('comingLater.title')).data,
          l10n.modeComingLaterSheetTitle('ride'));
      expect(store.writes, isEmpty);
      expect(_continueEnabled(tester), isFalse);
      await _closeSurfaces(tester);
      expect(store.writes, isEmpty);
    });

    testWidgets('AC-CH-3/$lang exactly one card selected', (tester) async {
      final h = tester.ensureSemantics();
      await pumpRig(tester, store: _pending(), locale: loc);
      await _tapCard(tester, 'train');
      await _tapCard(tester, 'body');
      final selected = <String>[
        for (final m in AppMode.values)
          if (isSelectedNode(sem(tester, find.descendant(
              of: _card(m.name), matching: find.byType(Semantics)).first)))
            m.name
      ];
      // Fallback via widget state: ModeCard.selected.
      final byWidget = [
        for (final m in AppMode.values)
          if (tester.widget<ModeCard>(_card(m.name)).selected) m.name
      ];
      expect(byWidget, ['body']);
      expect(selected.where((s) => s != 'body'), isEmpty,
          reason: 'semantics selected: $selected');
      expect(selected, contains('body'));
      h.dispose();
    });

    testWidgets('AC-CH-9/$lang compact grid, no panel [AC-LS-7]',
        (tester) async {
      await pumpRig(tester, store: _pending(), locale: loc);
      expect(_r(tester, 'ride').top, _r(tester, 'train').top);
      expect(_r(tester, 'explore').top, greaterThan(_r(tester, 'train').top));
      expect(byKeyS('modeChooser.detailPanel'), findsNothing);
    });
  }

  testWidgets('AC-CH-4 Decide later stores train+resolved, restart keeps it',
      (tester) async {
    final store = _pending();
    final rig = await pumpRig(tester,
        store: store, prefValues: _ctxAnswered, initial: '/mode-chooser');
    await tester.tap(byKeyS('modeChooser.decideLater'));
    await settleFrames(tester);
    final s = store.stored('uid-a')!;
    expect(s.selectedMode, AppMode.train);
    expect(s.chooserStatus, ChooserStatus.resolved);
    expect(rig.visits.last, '/home');
    // Restart: new scope over the same store reads resolved.
    await tester.pumpWidget(const SizedBox());
    final rig2 = await pumpRig(tester,
        store: store, prefValues: _ctxAnswered, initial: '/home');
    expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.resolved);
    expect(rig2.visits.count('/mode-chooser'), 0);
    expect(byKeyS('modeChooser.decideLater'), findsNothing);
  });

  testWidgets('AC-CH-6 failed save: error shown, still reaches Home, stays pending',
      (tester) async {
    final store = _pending()..throwOnWrite = true;
    final rig = await pumpRig(tester, store: store, prefValues: _ctxAnswered);
    await _tapCard(tester, 'train');
    await tester.tap(_continue());
    await settleFrames(tester);
    expect(rig.visits.last, '/home');
    expect(byKeyS('modeChooser.saveError'), findsOneWidget);
    expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.pending);
    expect(store.writes, isNotEmpty, reason: 'the save was attempted');
  });

  for (final size in [const Size(360, 800), const Size(1100, 800)]) {
    testWidgets('AC-CH-7/${size.width.toInt()}x${size.height.toInt()} no permission call',
        (tester) async {
      final perm = MockPermissionChannel(tester.binding);
      addTearDown(() => perm.dispose(tester.binding));
      await pumpRig(tester, store: _pending(), size: size);
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      addTearDown(g.removePointer);
      await g.moveTo(tester.getCenter(_card('train')));
      await tester.pump();
      await _focusCard(tester, 'body');
      await _tapCard(tester, 'body');
      expect(perm.calls, isEmpty);
    });
  }

  group('AC-CH-10 grid rule [AC-LS-7]', () {
    Future<Rig> pump(WidgetTester t, double w, double h) =>
        pumpRig(t, store: _pending(), size: Size(w, h));

    void noOverflow(WidgetTester t) => expect(t.takeException(), isNull);

    testWidgets('AC-CH-10/700x900', (tester) async {
      await pump(tester, 700, 900);
      expect(_r(tester, 'ride').top, _r(tester, 'train').top);
      expect(_r(tester, 'explore').top, greaterThan(_r(tester, 'train').top));
      expect(tester.getSize(byKeyS('modeChooser.grid')).width, lessThanOrEqualTo(640));
      expect(byKeyS('modeChooser.detailPanel'), findsNothing);
      noOverflow(tester);
    });

    for (final s in [const Size(700, 420), const Size(640, 360)]) {
      testWidgets('AC-CH-10/${s.width.toInt()}x${s.height.toInt()} 4x1', (tester) async {
        await pump(tester, s.width, s.height);
        final tops = {for (final m in ['train', 'ride', 'explore', 'body']) _r(tester, m).top};
        expect(tops.length, 1, reason: 'one row of four: $tops');
        for (final m in ['train', 'ride', 'explore', 'body']) {
          expect(_r(tester, m).width, greaterThanOrEqualTo(136));
          expect(
              find.descendant(
                  of: _card(m), matching: find.text(l10nOf('en').modeTrainBlurb)),
              findsNothing);
        }
        noOverflow(tester);
      });
    }

    for (final s in [const Size(600, 400), const Size(360, 420)]) {
      testWidgets('AC-CH-10/${s.width.toInt()}x${s.height.toInt()} 2x2 scrolls', (tester) async {
        await pump(tester, s.width, s.height);
        expect(_r(tester, 'ride').top, _r(tester, 'train').top);
        expect(_r(tester, 'explore').top, greaterThan(_r(tester, 'train').top));
        for (final m in ['train', 'ride', 'explore', 'body']) {
          expect(_r(tester, m).width, greaterThanOrEqualTo(136));
        }
        await tester.scrollUntilVisible(_continue(), 100,
            scrollable: find.byType(Scrollable).first);
        expect(tester.getRect(_continue()).bottom,
            lessThanOrEqualTo(s.height));
        for (final sc in tester.widgetList<Scrollable>(find.byType(Scrollable))) {
          expect(sc.axis, Axis.vertical, reason: 'no horizontal scroll');
        }
        noOverflow(tester);
      });
    }
  });

  testWidgets('AC-CH-11 expanded: panel at the end of the grid, <=960',
      (tester) async {
    await pumpRig(tester, store: _pending(), size: const Size(1100, 800));
    final grid = tester.getRect(byKeyS('modeChooser.grid'));
    final panel = tester.getRect(byKeyS('modeChooser.detailPanel'));
    expect(panel.left, greaterThanOrEqualTo(grid.right));
    expect(
        find.descendant(
            of: byKeyS('modeChooser.detailPanel'), matching: _continue()),
        findsOneWidget);
    expect(panel.right - grid.left, lessThanOrEqualTo(960));
    expect(_r(tester, 'ride').top, _r(tester, 'train').top);
    expect(_r(tester, 'ride').left, greaterThan(_r(tester, 'train').left));
    expect(_r(tester, 'body').top, greaterThan(_r(tester, 'ride').top));
  });

  for (final c in [
    (599.0, false, true),
    (839.0, false, false),
    (840.0, true, true),
  ]) {
    testWidgets('AC-CH-12/${c.$1.toInt()}x800 panel=${c.$2}', (tester) async {
      await pumpRig(tester, store: _pending(), size: Size(c.$1, 800));
      expect(byKeyS('modeChooser.detailPanel'),
          c.$2 ? findsOneWidget : findsNothing);
      if (c.$3) {
        // 599 and 840: grid is 2x2 either way.
        expect(_r(tester, 'explore').top, greaterThan(_r(tester, 'train').top));
      }
    });
  }

  testWidgets('AC-CH-13/hoverFocus hover and focus do not select',
      (tester) async {
    final l10n = l10nOf('en');
    await pumpRig(tester, store: _pending(), size: const Size(1100, 800));
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(tester.getCenter(_card('body')));
    await tester.pump();
    expect(tester.widget<Text>(byKeyS('modeChooser.description')).data,
        l10n.modeBodyDesc);
    expect(tester.widget<ModeCard>(_card('body')).selected, isFalse);
    expect(_continueEnabled(tester), isFalse);
    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    await _focusCard(tester, 'body');
    await tester.pump();
    expect(tester.widget<Text>(byKeyS('modeChooser.description')).data,
        l10n.modeBodyDesc);
    expect(tester.widget<ModeCard>(_card('body')).selected, isFalse);
  });

  testWidgets('AC-CH-13/scale2ru names are not cut', (tester) async {
    final l10n = l10nOf('ru');
    await pumpRig(tester,
        store: _pending(),
        size: const Size(1100, 800),
        locale: const Locale('ru'),
        textScale: 2.0);
    expect(tester.takeException(), isNull);
    for (final n in [
      l10n.modeTrainName,
      l10n.modeRideName,
      l10n.modeExploreName,
      l10n.modeBodyName
    ]) {
      final p = tester.renderObject<RenderParagraph>(find
          .descendant(of: find.byType(ModeCard), matching: find.text(n))
          .first);
      expect(p.didExceedMaxLines, isFalse, reason: n);
    }
  });

  testWidgets('AC-CH-14 resize keeps selection, focus, no writes',
      (tester) async {
    final store = _pending();
    await pumpRig(tester, store: store, size: const Size(1100, 800));
    await _focusCard(tester, 'body');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(_focusedCard(), 'body');
    expect(_continueEnabled(tester), isTrue);
    tester.view.physicalSize = const Size(360, 800);
    await settleFrames(tester, frames: 3);
    expect(tester.widget<ModeCard>(_card('body')).selected, isTrue);
    expect(tester.widget<ModeCard>(_card('train')).selected, isFalse);
    expect(_continueEnabled(tester), isTrue);
    expect(_focusedCard(), 'body');
    expect(byKeyS('modeChooser.detailPanel'), findsNothing);
    expect(store.writes, isEmpty);
  });

  testWidgets('AC-LS-11/idle panel shows idle text', (tester) async {
    final l10n = l10nOf('en');
    await pumpRig(tester, store: _pending(), size: const Size(1100, 800));
    expect(tester.widget<Text>(byKeyS('modeChooser.description')).data,
        l10n.modeDetailIdle);
    expect(_continueEnabled(tester), isFalse);
    for (final m in AppMode.values) {
      expect(tester.widget<ModeCard>(_card(m.name)).selected, isFalse);
    }
    expect(
        find.descendant(
            of: byKeyS('modeChooser.detailPanel'), matching: find.byType(Image)),
        findsNothing);
  });

  testWidgets('AC-LS-11/touchSelect touch tap fills the panel', (tester) async {
    final l10n = l10nOf('en');
    await pumpRig(tester, store: _pending(), size: const Size(1100, 800));
    await _tapCard(tester, 'body');
    expect(tester.widget<ModeCard>(_card('body')).selected, isTrue);
    expect(tester.widget<Text>(byKeyS('modeChooser.description')).data,
        l10n.modeBodyDesc);
  });

  testWidgets('DT-08-1 arrow keys follow the grid', (tester) async {
    await pumpRig(tester, store: _pending(), size: const Size(360, 800));
    await _focusCard(tester, 'train');
    final seen = <String?>[_focusedCard()];
    for (final k in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
    ]) {
      await tester.sendKeyEvent(k);
      await tester.pump();
      seen.add(_focusedCard());
    }
    expect(seen, ['train', 'ride', 'body', 'explore', 'train']);
  });

  testWidgets('DT-08-1b Tab reaches all four cards once a card is selected (1100x800)',
      (tester) async {
    await pumpRig(tester, store: _pending(), size: const Size(1100, 800));
    await _tapCard(tester, 'train');
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final c = _focusedCard();
      if (c != null) seen.add(c);
    }
    expect(seen, {'train', 'ride', 'explore', 'body'},
        reason: 'Tab order skips cards: $seen');
  });

  testWidgets('DT-08-2 keyboard-only: Space selects, Enter on Continue confirms',
      (tester) async {
    final store = _pending();
    final rig = await pumpRig(tester, store: store, prefValues: _ctxAnswered);
    await _focusCard(tester, 'train');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<ModeCard>(_card('train')).selected, isTrue);
    for (var i = 0; i < 20; i++) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx?.findAncestorWidgetOfExactType<HudButton>()?.key ==
          const Key('modeChooser.continue')) {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleFrames(tester);
    expect(store.stored('uid-a')!.selectedMode, AppMode.train);
    expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.resolved);
    expect(rig.visits.last, '/home');
  });

  testWidgets('DT-08-3 delayed read: outlines at 300 ms, no spinner, no reorder',
      (tester) async {
    final store = FakeModeStore(readDelay: const Duration(milliseconds: 400))
      ..seed('uid-a', status: ChooserStatus.pending);
    await pumpRig(tester, store: store, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_card('train'), findsNothing, reason: 'blank before 300 ms');
    await tester.pump(const Duration(milliseconds: 210));
    for (final m in AppMode.values) {
      expect(_card(m.name), findsOneWidget);
      expect(tester.widget<ModeCard>(_card(m.name)).onTap, isNull);
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_continueEnabled(tester), isFalse);
    final before = {for (final m in AppMode.values) m: _r(tester, m.name)};
    await tester.pump(const Duration(milliseconds: 500));
    await settleFrames(tester, frames: 3);
    for (final m in AppMode.values) {
      expect(_r(tester, m.name).left, before[m]!.left, reason: m.name);
      expect(_r(tester, m.name).width, before[m]!.width, reason: m.name);
      expect(_r(tester, m.name).top > _r(tester, 'train').top,
          before[m]!.top > before[AppMode.train]!.top,
          reason: 'row membership of ${m.name}');
      expect(tester.widget<ModeCard>(_card(m.name)).onTap, isNotNull);
    }
  });

  testWidgets('DT-08-4 returning visit from the switcher shows body selected',
      (tester) async {
    final l10n = l10nOf('en');
    final store = FakeModeStore()..seed('uid-a', mode: AppMode.body);
    final rig = await pumpRig(tester,
        store: store,
        initial: '/home',
        replace: {
          '/home': (c) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('test.openSwitcher'),
                    onPressed: () => openModeSwitcher(c),
                    child: const Text('open'),
                  ),
                ),
              ),
        });
    await tester.tap(byKeyS('test.openSwitcher'));
    await settleFrames(tester);
    await tester.tap(byKeyS('modeSwitcher.seeAll'));
    await settleFrames(tester, frames: 12);
    expect(_card('body'), findsOneWidget);
    expect(tester.widget<ModeCard>(_card('body')).selected, isTrue);
    expect(tester.widget<Text>(byKeyS('modeChooser.description')).data,
        l10n.modeBodyDesc);
    expect(rig.router, isNotNull);
  });

  testWidgets('DT-08-5 coming-later card semantics', (tester) async {
    final h = tester.ensureSemantics();
    final l10n = l10nOf('en');
    await pumpRig(tester, store: _pending());
    final card = tester.widget<ModeCard>(_card('ride'));
    expect(card.comingLater, isTrue);
    expect(card.onTap, isNotNull, reason: 'enabled and focusable');
    final n = tester.getSemantics(find.descendant(
        of: _card('ride'), matching: find.byType(Semantics)).first);
    expect(allText(n), contains(l10n.modeComingLater));
    await _tapCard(tester, 'ride');
    await _closeSurfaces(tester);
    expect(tester.widget<ModeCard>(_card('ride')).selected, isFalse);
    h.dispose();
  });

  testWidgets('DT-08-6 Decide later only while pending', (tester) async {
    await pumpRig(tester,
        store: FakeModeStore()..seed('uid-a', status: ChooserStatus.resolved));
    expect(byKeyS('modeChooser.decideLater'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpRig(tester, store: _pending());
    expect(byKeyS('modeChooser.decideLater'), findsOneWidget);
  });

  testWidgets('DT-08-10 account switch discards the unsaved selection',
      (tester) async {
    final store = FakeModeStore()
      ..seed('uid-a', status: ChooserStatus.pending)
      ..seed('uid-b', status: ChooserStatus.pending);
    final rig = await pumpRig(tester, store: store);
    await _tapCard(tester, 'body');
    expect(_continueEnabled(tester), isTrue);
    rig.auth.emit(kUserB);
    await settleFrames(tester, frames: 10);
    expect(store.readUids, contains('uid-b'));
    expect(store.writes, isEmpty);
    expect(tester.widget<ModeCard>(_card('body')).selected, isFalse);
    expect(_continueEnabled(tester), isFalse);
  });

  group('Home offers the chooser (real HomePage)', () {
    Future<Rig> homeRig(WidgetTester t, FakeModeStore store,
        {List<Override> extra = const []}) {
      return pumpRig(t,
          store: store,
          initial: '/home',
          overrides: extra,
          replace: {'/home': (c) => const HomePage()});
    }

    for (final status in [
      ChooserStatus.pending,
      ChooserStatus.resolved,
      ChooserStatus.migrated,
    ]) {
      testWidgets('AC-CH-5/${status.name} chooser offered only for pending',
          (tester) async {
        final store = FakeModeStore()..seed('uid-a', status: status);
        await homeRig(tester, store);
        await settleFrames(tester, frames: 15);
        expect(byKeyS('modeChooser.grid'),
            status == ChooserStatus.pending ? findsOneWidget : findsNothing);
        if (status == ChooserStatus.migrated) {
          expect(byKeyS('home.modeIntro'), findsOneWidget);
        }
        expect(store.writes, isEmpty, reason: 'offering writes nothing');
      });
    }

    testWidgets('AC-CH-5/restart: pending is offered again after a kill',
        (tester) async {
      final store = _pending();
      await homeRig(tester, store);
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await homeRig(tester, store);
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsOneWidget);
    });

    testWidgets('AC-CH-4/restart after Decide later: chooser not offered',
        (tester) async {
      final store = _pending();
      await homeRig(tester, store);
      await settleFrames(tester, frames: 15);
      await tester.tap(byKeyS('modeChooser.decideLater'));
      await settleFrames(tester, frames: 15);
      expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.resolved);
      await tester.pumpWidget(const SizedBox());
      await homeRig(tester, store);
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsNothing);
    });

    testWidgets('DT-08-8 offered once per run and uid', (tester) async {
      final store = _pending()..throwOnWrite = true; // status stays pending
      final rig = await homeRig(tester, store);
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsOneWidget);
      await tester.binding.handlePopRoute(); // Back = Decide later (fails)
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsNothing);
      expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.pending);
      rig.router.go('/profile');
      await settleFrames(tester, frames: 8);
      rig.router.go('/home');
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsNothing,
          reason: 'second Home build must not offer again');
      expect(rig.container.read(offeredThisRunProvider), contains('uid-a'));
    });

    testWidgets('DT-08-9 chooser waits for the Day-3 decision and modal',
        (tester) async {
      final gate = Completer<bool>();
      final store = _pending();
      await homeRig(tester, store, extra: [
        momentRepositoryProvider.overrideWithValue(_GatedMoments(gate.future)),
      ]);
      await settleFrames(tester, frames: 15);
      expect(byKeyS('modeChooser.grid'), findsNothing,
          reason: 'Day-3 decision pending');
      gate.complete(false); // not shown yet -> the modal will show
      await settleFrames(tester, frames: 15);
      expect(find.byType(Day3WelcomeModal), findsOneWidget);
      expect(byKeyS('modeChooser.grid'), findsNothing,
          reason: 'modal on screen');
      await tester.tapAt(const Offset(180, 20)); // scrim
      await settleFrames(tester, frames: 20);
      expect(find.byType(Day3WelcomeModal), findsNothing);
      expect(byKeyS('modeChooser.grid'), findsOneWidget);
    });
  });

  testWidgets('RV-9b Coming-later Back closes the sheet without any write',
      (tester) async {
    final store = _pending();
    await pumpRig(tester, store: store);
    await _tapCard(tester, 'ride');
    expect(byKeyS('comingLater.sheet'), findsOneWidget);
    await tester.tap(byKeyS('comingLater.back'));
    await settleFrames(tester);
    expect(byKeyS('comingLater.sheet'), findsNothing);
    expect(store.writes, isEmpty);
    expect(tester.widget<ModeCard>(_card('train')).selected, isFalse,
        reason: 'Back is not "Choose Train"');
    expect(_continueEnabled(tester), isFalse);
    expect(byKeyS('modeChooser.grid'), findsOneWidget);
  });

  testWidgets('RV-9c wrapped buttons show the full ru label at scale 2.0 on 360 dp',
      (tester) async {
    final l10n = l10nOf('ru');
    await pumpRig(tester,
        store: _pending(), locale: const Locale('ru'), textScale: 2.0);
    Future<void> expectFull(Finder button, String label) async {
      final text = find.descendant(of: button, matching: find.text(label));
      expect(text, findsOneWidget, reason: 'label "$label" must be in the button');
      final p = tester.renderObject<RenderParagraph>(text);
      expect(p.didExceedMaxLines, isFalse, reason: label);
      expect(p.text.toPlainText(), label);
      expect(tester.takeException(), isNull);
    }

    await tester.scrollUntilVisible(_continue(), 100,
        scrollable: find.byType(Scrollable).first);
    await expectFull(_continue(), l10n.modeContinue);
    await tester.scrollUntilVisible(_card('ride'), -100,
        scrollable: find.byType(Scrollable).first);
    await _tapCard(tester, 'ride');
    await expectFull(byKeyS('comingLater.chooseTrain'), l10n.modeComingLaterSheetAction);
    await tester.tap(byKeyS('comingLater.back'));
    await settleFrames(tester);
  });

  testWidgets('RV-chip wide card: Coming-later chip at the inner right end, same line as the icon',
      (tester) async {
    await pumpRig(tester, store: _pending(), size: const Size(1100, 800));
    final card = tester.getRect(_card('ride'));
    final chip = tester.getRect(find.descendant(
        of: _card('ride'), matching: find.byType(HudChip)));
    final icon = tester.getRect(find.descendant(
        of: _card('ride'), matching: find.byIcon(Icons.directions_bike_rounded)));
    const inner = 14.0; // HudPanel padding of the card
    expect(chip.right, closeTo(card.right - inner, 4),
        reason: 'chip=$chip card=$card');
    expect((chip.center.dy - icon.center.dy).abs(), lessThan(6),
        reason: 'same line: chip=$chip icon=$icon');
    expect(chip.left, greaterThan(icon.right));
    expect(tester.takeException(), isNull);
  });

  for (final lang in ['en', 'ru']) {
    testWidgets('RV-chip/$lang scale 2.0 on 360 dp: chip under the icon, not clipped',
        (tester) async {
      await pumpRig(tester,
          store: _pending(), locale: Locale(lang), textScale: 2.0);
      final card = tester.getRect(_card('ride'));
      final chipFinder = find.descendant(
          of: _card('ride'), matching: find.byType(HudChip));
      final chip = tester.getRect(chipFinder);
      final icon = tester.getRect(find.descendant(
          of: _card('ride'),
          matching: find.byIcon(Icons.directions_bike_rounded)));
      // The Wrap rule: beside the icon (at the inner right end) while both
      // fit in the inner width, otherwise below the icon.
      final innerWidth = card.width - 28;
      final fits = icon.width + 8 + chip.width <= innerWidth + 0.5;
      if (fits) {
        expect(chip.right, closeTo(card.right - 14, 4), reason: 'chip=$chip');
        expect((chip.center.dy - icon.center.dy).abs(), lessThan(6));
      } else {
        expect(chip.top, greaterThanOrEqualTo(icon.bottom - 0.5),
            reason: 'chip must be below the icon: chip=$chip icon=$icon');
      }
      if (lang == 'en') {
        expect(fits, isFalse,
            reason: 'the English word at scale 2.0 does not fit beside the icon');
        expect(chip.top, greaterThanOrEqualTo(icon.bottom - 0.5));
      }
      expect(chip.left, greaterThanOrEqualTo(card.left));
      expect(chip.right, lessThanOrEqualTo(card.right));
      final word = lang == 'en'
          ? l10nOf('en').modeComingLater
          : l10nOf('ru').modeComingLater;
      final text = find.descendant(of: chipFinder, matching: find.text(word));
      expect(text, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  group('DT-08-7 system Back on the chooser', () {
    Future<Rig> openFromHome(WidgetTester t, FakeModeStore store) async {
      final rig = await pumpRig(t, store: store, prefValues: _ctxAnswered, initial: '/home');
      rig.router.go('/mode-chooser');
      await settleFrames(t, frames: 10);
      expect(byKeyS('modeChooser.grid'), findsOneWidget);
      return rig;
    }

    testWidgets('pending: Back = Decide later, lands on /home', (tester) async {
      final store = _pending();
      final rig = await openFromHome(tester, store);
      expect(rig.visits.count('/home'), 1);
      await tester.binding.handlePopRoute();
      await settleFrames(tester);
      final s = store.stored('uid-a')!;
      expect(s.selectedMode, AppMode.train);
      expect(s.chooserStatus, ChooserStatus.resolved);
      expect(rig.visits.count('/home'), 2);
      expect(rig.visits.last, '/home');
    });

    testWidgets('pending + failing write: stays pending, still lands on /home',
        (tester) async {
      final store = _pending()..throwOnWrite = true;
      final rig = await openFromHome(tester, store);
      await tester.binding.handlePopRoute();
      await settleFrames(tester);
      expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.pending);
      expect(rig.visits.last, '/home');
      expect(rig.visits.count('/home'), 2);
    });

    testWidgets('process kill without Back leaves pending', (tester) async {
      final store = _pending();
      await openFromHome(tester, store);
      await tester.pumpWidget(const SizedBox());
      expect(store.stored('uid-a')!.chooserStatus, ChooserStatus.pending);
      expect(store.writes, isEmpty);
    });

    testWidgets('resolved + pushed: Back just pops, zero writes', (tester) async {
      final store = FakeModeStore()..seed('uid-a', mode: AppMode.body);
      final rig = await pumpRig(tester, store: store, initial: '/home');
      unawaited(rig.router.push('/mode-chooser'));
      await settleFrames(tester, frames: 10);
      expect(byKeyS('modeChooser.grid'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settleFrames(tester);
      expect(byKeyS('modeChooser.grid'), findsNothing);
      expect(store.writes, isEmpty);
    });
  });
}

class _GatedMoments extends MockMomentRepository {
  _GatedMoments(this._gate);
  final Future<bool> _gate;
  @override
  Future<bool> hasShown(MomentId id) => _gate;
  @override
  Future<int> launchCount() async => 5;
  @override
  Future<DateTime?> firstLaunchAt() async =>
      DateTime.now().subtract(const Duration(days: 10));
  @override
  Future<void> bumpLaunchCount() async {}
}
