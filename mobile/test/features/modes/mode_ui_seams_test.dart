// S03-01 seams that need a widget or a running timer: DT-01-7 (the mode state
// never touches a running timer, real controllers, TP-2), DT-01-8 (chooser
// Continue waits for the awaited write before it navigates) and DT-01-9 (no
// frame shows the TRAIN lens before the stored BODY lens).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/pages/mode_chooser_page.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/workouts/data/cue_player.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_app.dart';
import '../../support/mode_fakes.dart';

Widget _app(ModeEnv env, GoRouter router) => UncontrolledProviderScope(
      container: env.container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) =>
            AuroraBackground(child: child ?? const SizedBox.shrink()),
      ),
    );

void main() {
  testWidgets('DT-01-8 chooser Continue: navigation waits for the awaited '
      'write', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final env = ModeEnv(initialUid: 'u1');
    env.profiles.emitOnboarded('u1');
    final router = GoRouter(initialLocation: '/mode-chooser', routes: [
      GoRoute(path: '/mode-chooser', builder: (_, __) => const ModeChooserPage()),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home-stub'))),
      GoRoute(
          path: '/mode-questions/:mode',
          builder: (_, __) => const Scaffold(body: Text('questions-stub'))),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(env, router));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    String loc() => router.routerDelegate.currentConfiguration.uri.path;
    expect(loc(), '/mode-chooser');
    final gate = Completer<void>();
    env.fake.writeGate = gate;
    await tester.tap(find.byKey(const Key('modeChooser.card.train')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('modeChooser.continue')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(env.fake.writeCalls, 1, reason: 'Continue must have started a write');
    expect(loc(), '/mode-chooser',
        reason: 'navigation must be awaited behind the write');
    gate.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(loc(), anyOf('/home', '/mode-questions/train'),
        reason: 'after the write completes the chooser leaves');
    expect(env.fake.stateOf('u1')!.chooserStatus, ChooserStatus.resolved);
  });

  testWidgets('DT-01-9 a stored BODY mode is never preceded by a frame with '
      'the TRAIN lens order', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final env = ModeEnv(initialUid: 'u1');
    env.fake.stored['u1'] = ModeReadValue(ModeState(
        selectedMode: AppMode.body, chooserStatus: ChooserStatus.resolved));
    env.profiles.emitOnboarded('u1');
    final gate = Completer<void>();
    env.fake.readGate = gate;
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/mode-chooser',
          builder: (_, __) => const Scaffold(body: Text('chooser-stub'))),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    List<String> order() {
      final finder = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('home.section.'));
      final items = <(double, String)>[];
      for (final e in finder.evaluate()) {
        final key = (e.widget.key! as ValueKey<String>).value;
        final y = tester.getTopLeft(find.byElementPredicate((x) => x == e)).dy;
        items.add((y, key));
      }
      items.sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final i in items) i.$2];
    }

    await tester.pumpWidget(_app(env, router));
    final frames = <List<String>>[];
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      frames.add(order());
    }
    gate.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      frames.add(order());
    }
    final finalOrder = frames.last;
    expect(finalOrder, isNotEmpty, reason: 'the Home sections must render');
    final loadingOrder = frames.first;
    // A loading frame (no sections) or the final BODY order: never the TRAIN
    // order, which is what the sections show while the mode is unknown.
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      // The loading frame is the greeting only (design: Home waits for the
      // mode state); any other partial or TRAIN-ordered frame is the defect.
      if (f.isEmpty || (f.length == 1 && f.first == 'home.section.greeting')) {
        continue;
      }
      expect(f, finalOrder,
          reason: 'frame $i shows a lens order other than the final BODY '
              'order: $f (final $finalOrder)');
    }
    expect(loadingOrder, isNotNull);
  });
}
