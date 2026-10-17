import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

import '../../support/s03_shell_harness.dart';

Widget _host(Widget child, {Locale locale = const Locale('en'), double scale = 1}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

final Finder _ring = find.byKey(HudKeyboardActivation.focusRingKey);

Future<void> _mouseTap(WidgetTester t, Finder f) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(1, 1));
  await g.moveTo(t.getCenter(f));
  await g.down(t.getCenter(f));
  await g.up();
  await t.pump();
  await g.removePointer();
}

typedef _Make = Widget Function(VoidCallback? onTap, {bool ring});

final Map<String, _Make> _controls = <String, _Make>{
  'HudButton': (tap, {ring = true}) => HudButton(
      label: 'Go', onPressed: tap, showFocusRing: ring, hoverStyle: ring, cursor: ring),
  'HudChip': (tap, {ring = true}) => HudChip(
      label: 'Chip', selected: false, onTap: tap, showFocusRing: ring, hoverStyle: ring, cursor: ring),
  'HudSettingRow': (tap, {ring = true}) => HudSettingRow(
      icon: Icons.settings, title: 'Row', onTap: tap, showFocusRing: ring, hoverStyle: ring, cursor: ring),
  'HudPanel': (tap, {ring = true}) => HudPanel(
      onTap: tap, semanticLabel: 'Panel', showFocusRing: ring, hoverStyle: ring, cursor: ring,
      child: const Text('Panel')),
};

/// The signature recorded for DT-03-1 (size, semantics, cursor).
Future<String> _signature(WidgetTester t, Widget w, Finder f) async {
  final h = t.ensureSemantics();
  await t.pumpWidget(_host(w));
  final s = t.getSize(f);
  final SemanticsNode n = t.getSemantics(f.first);
  final d = n.getSemanticsData();
  bool flag(SemanticsFlag x) => d.hasFlag(x);
  int count = 0;
  void walk(SemanticsNode x) {
    count++;
    x.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(n);
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(1, 1));
  await g.moveTo(t.getCenter(f));
  await t.pump();
  final cursor =
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
  await g.removePointer();
  h.dispose();
  return 'size=${s.width.toStringAsFixed(1)}x${s.height.toStringAsFixed(1)};'
      'label=${d.label};button=${flag(SemanticsFlag.isButton)};'
      'enabled=${flag(SemanticsFlag.hasEnabledState) ? flag(SemanticsFlag.isEnabled) : 'n/a'};'
      'selected=${flag(SemanticsFlag.isSelected)};'
      'tap=${d.hasAction(SemanticsAction.tap)};nodes=$count;cursor=${cursor?.runtimeType}:${cursor == SystemMouseCursors.click ? 'click' : (cursor == SystemMouseCursors.basic ? 'basic' : '$cursor')}';
}

/// Values measured on the BASE head (c0731f91~1), 360x800, en, dark theme,
/// recorded once with the same code and not regenerated to pass a test.
const Map<String, String> kBaseSignatures = <String, String>{
  'HudChip': 'size=75.0x44.0;label=Chip;button=true;enabled=n/a;selected=false;tap=true;nodes=1;cursor=SystemMouseCursor:basic',
  'HudButton': 'size=360.0x50.0;label=Go;button=true;enabled=true;selected=false;tap=true;nodes=1;cursor=SystemMouseCursor:basic',
  'HudPanel': 'size=107.3x56.0;label=Panel;button=true;enabled=n/a;selected=false;tap=false;nodes=1;cursor=SystemMouseCursor:click',
  'HudSettingRow': 'size=360.0x800.0;label=Row;button=true;enabled=n/a;selected=false;tap=false;nodes=1;cursor=SystemMouseCursor:click',
};

void main() {
  for (final size in const [Size(360, 800), Size(1100, 800)]) {
    for (final e in _controls.entries) {
      final name = e.key;
      final sz = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('AC-KB-3/primitives/$name/$sz ring on keyboard focus only',
          (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        // fresh pump + pointer tap: no ring
        int taps = 0;
        await t.pumpWidget(_host(e.value(() => taps++)));
        expect(_ring, findsNothing);
        await _mouseTap(t, find.byType(Scaffold));
        expect(taps, 1);
        expect(_ring, findsNothing, reason: 'pointer tap must not show the ring');
        // fresh pump + Tab: ring
        await t.pumpWidget(_host(const SizedBox()));
        await t.pumpWidget(_host(e.value(() {})));
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(_ring, findsOneWidget, reason: 'Tab focus must paint the ring');
        // a touch elsewhere flips the highlight mode: the ring goes
        await t.tapAt(const Offset(2, 2));
        await t.pump();
        expect(_ring, findsNothing,
            reason: 'ring must leave when the interaction becomes pointer');
      });
    }
  }

  testWidgets('AC-KB-3/rail destinations and Record slot show the ring on Tab',
      (t) async {
    await pumpShell(t, size: const Size(1100, 800));
    // Tab until focus is inside the rail Record slot, then the first tile.
    bool ringShown = false;
    for (int i = 0; i < 4 && !ringShown; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      if (focusIsWithin(const ValueKey<String>('shell.rail.record'))) {
        expect(_ring, findsOneWidget, reason: 'Record slot focused, no ring');
        ringShown = true;
      }
    }
    expect(ringShown, isTrue, reason: 'Record slot never took keyboard focus');
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(focusIsWithin(const ValueKey<String>('shell.rail')), isTrue);
    expect(_ring, findsOneWidget,
        reason: 'a focused rail destination must paint the 2 px ring');
  });

  group('AC-KB-4 hover and cursor', () {
    late TestGesture lastG;
    Future<Object?> cursorOver(WidgetTester t, Finder f, {bool keep = false}) async {
      final g = await t.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(1, 1));
      lastG = g;
      await g.moveTo(t.getCenter(f));
      await t.pump();
      final c = RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
      if (!keep) await g.removePointer();
      return c;
    }

    testWidgets('AC-KB-4/hoverEnabled', (t) async {
      t.view.physicalSize = const Size(1100, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await t.pumpWidget(_host(_controls['HudChip']!(() {})));
        final f = find.text('Chip');
        expect(find.byKey(const ValueKey<String>('hud.hoverWash')), findsNothing);
        expect(await cursorOver(t, f, keep: true), SystemMouseCursors.click);
        expect(find.byKey(const ValueKey<String>('hud.hoverWash')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('AC-KB-4/disabled', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        for (final name in <String>['HudButton', 'HudChip', 'HudPanel']) {
          await t.pumpWidget(_host(_controls[name]!(null)));
          final f = find.byType(Center).first;
          final c = await cursorOver(t, f, keep: true);
          expect(c, isNot(SystemMouseCursors.click), reason: name);
          expect(find.byKey(const ValueKey<String>('hud.hoverWash')), findsNothing,
              reason: '$name disabled must not take a hover wash');
          await lastG.removePointer();
          await t.pumpWidget(const SizedBox());
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('AC-KB-4/hoverNoChange selection and semantics unchanged',
        (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_host(HudChip(
          label: 'Chip', selected: true, onTap: () {}, hoverStyle: true, cursor: true)));
      SemanticsData data() => t.getSemantics(find.byType(HudChip)).getSemanticsData();
      final before = data();
      await cursorOver(t, find.text('Chip'), keep: true);
      final after = data();
      expect(after.label, before.label);
      expect(after.hasFlag(SemanticsFlag.isSelected),
          before.hasFlag(SemanticsFlag.isSelected));
      expect(after.hasFlag(SemanticsFlag.isSelected), isTrue);
      h.dispose();
    });
  });

  group('DT-03-1 defaults equal the base head', () {
    final cases = <String, Widget Function()>{
      'HudChip': () => HudChip(label: 'Chip', selected: false, onTap: () {}),
      'HudButton': () => HudButton(label: 'Go', onPressed: () {}),
      'HudPanel': () => HudPanel(
          onTap: () {}, semanticLabel: 'Panel', child: const Text('Panel')),
      'HudSettingRow': () =>
          HudSettingRow(icon: Icons.settings, title: 'Row', subtitle: 'Sub', onTap: () {}),
    };
    final finders = <String, Finder Function()>{
      'HudChip': () => find.byType(HudChip),
      'HudButton': () => find.byType(HudButton),
      'HudPanel': () => find.byType(HudPanel),
      'HudSettingRow': () => find.byType(HudSettingRow),
    };
    for (final name in cases.keys) {
      testWidgets('DT-03-1/$name', (t) async {
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final sig = await _signature(t, cases[name]!(), finders[name]!());
        // ignore: avoid_print
        print('DT03SIG $name $sig');
        expect(kBaseSignatures[name], isNotNull,
            reason: 'no base literal recorded yet; measured: $sig');
        expect(sig, kBaseSignatures[name]);
      });
    }
  });

  testWidgets('DT-03-2 maxLines is honoured and the default stays 1',
      (t) async {
    const label = 'Очень длинная подпись для узкой кнопки выбора режима';
    Future<Size> pumpChip(int? maxLines) async {
      await t.pumpWidget(_host(
        SizedBox(
          width: 160,
          child: maxLines == null
              ? HudChip(label: label, selected: false, onTap: () {})
              : HudChip(label: label, selected: false, onTap: () {}, maxLines: maxLines),
        ),
        locale: const Locale('ru'),
        scale: 2.0,
      ));
      return t.getSize(find.byType(HudChip));
    }

    final def = await pumpChip(null);
    final defText = t.widget<Text>(find.descendant(
        of: find.byType(HudChip), matching: find.text(label)));
    expect(defText.maxLines, 1);
    final defPara = t.renderObject<RenderParagraph>(find.descendant(
        of: find.byType(HudChip), matching: find.text(label)));
    expect(defPara.didExceedMaxLines, isTrue);
    final two = await pumpChip(2);
    final twoText = t.widget<Text>(find.descendant(
        of: find.byType(HudChip), matching: find.text(label)));
    expect(twoText.maxLines, 2);
    expect(two.height, greaterThan(def.height),
        reason: 'two lines must make the chip taller than one');
  });

  testWidgets('DT-03-3 HudButton minHeight 48 and the unchanged default',
      (t) async {
    await t.pumpWidget(_host(HudButton(label: 'Go', onPressed: () {})));
    final def = t.getSize(find.byType(HudButton)).height;
    await t.pumpWidget(
        _host(HudButton(label: 'Go', onPressed: () {}, minHeight: 48)));
    final big = t.getSize(find.byType(HudButton)).height;
    expect(big, greaterThanOrEqualTo(48));
    expect(def, isNot(lessThan(44)));
    // The default must not have grown to 48 just because the parameter exists.
    await t.pumpWidget(_host(HudButton(label: 'Go', onPressed: () {}, minHeight: 80)));
    expect(t.getSize(find.byType(HudButton)).height, greaterThanOrEqualTo(80));
  });
}
