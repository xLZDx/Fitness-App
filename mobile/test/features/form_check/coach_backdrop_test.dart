import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show oneSquat;

/// The scene the avatar stands in.
///
/// Two things are worth pinning here and they are different in kind. One is
/// mechanical — the ten files this list names have to exist, or the screen is
/// blank on a phone while every widget test passes. The other is the reason the
/// scrim exists: the figure is drawn near-black with a lit skeleton, and three
/// of the ten scenes are bright exactly where the body stands.

Widget _page(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    );

ProviderContainer _container({int seed = 7}) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(oneSquat(0))),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    // Seeded: a screen that pumps one random scene of ten is a test that fails
    // one run in ten for a reason nobody can reproduce.
    coachBackdropRandomProvider.overrideWithValue(math.Random(seed)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  test('every scene this app can pick actually exists', () {
    // The list is const and the files are on disk; nothing else checks that the
    // two agree. A rename would leave a screen that is blank on a phone and
    // green in every widget test here, because `Image.asset`'s errorBuilder is
    // deliberately quiet.
    expect(kCoachBackdrops, hasLength(10));
    for (final path in kCoachBackdrops) {
      expect(File(path).existsSync(), isTrue, reason: '$path is not on disk');
      expect(path, startsWith('assets/coach_bg/'),
          reason: 'the pubspec declares that directory and only that one');
    }
  });

  test('the pubspec actually ships the directory', () {
    // A file on disk that pubspec does not declare is not in the APK. This
    // project has shipped exactly that bug before, with the poster directories.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/coach_bg/'));
  });

  testWidgets('the coach opens on a photograph, not on a painted gradient',
      (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('form_check.backdrop')), findsOneWidget);
    final photo = t.widget<Image>(
      find.byKey(const Key('form_check.backdrop_photo')),
    );
    expect(photo.fit, BoxFit.cover);
    final provider = photo.image as AssetImage;
    expect(kCoachBackdrops, contains(provider.assetName));
  });

  testWidgets('the scrim is there, and darkens towards the feet', (t) async {
    // Not decoration. `04_fuji_sakura` measures mean luminance 147 of 255 in
    // the band the body occupies, 95th percentile 244; a white skeleton over
    // pale sakura is unreadable without this layer.
    _phoneSized(t);
    await t.pumpWidget(_page(_container()));
    await t.pump();
    // The backdrop only mounts once the detector's start future resolves, so a
    // single pump finds nothing at all.
    await t.pump(const Duration(seconds: 2));

    final scrim = t.widget<DecoratedBox>(
      find.byKey(const Key('form_check.backdrop_scrim')),
    );
    final gradient =
        (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    final alphas = [for (final c in gradient.colors) c.a];
    expect(alphas.first, lessThan(alphas.last),
        reason: 'the top is where sky sits behind the chrome; the bottom is '
            'where the body stands, and that is the end that has to be dark');
    for (var i = 1; i < alphas.length; i++) {
      expect(alphas[i], greaterThanOrEqualTo(alphas[i - 1]),
          reason: 'a scrim that lightens partway down would put a bright band '
              'across the middle of the figure');
    }
  });

  group('a different scene each time the coach is opened', () {
    test('shuffle never lands on the scene already showing', () {
      // Uniform choice over ten repeats one open in ten, and a repeat does not
      // read as chance — it reads as the shuffle being broken. Walked over many
      // seeds rather than one, because a single seed proves nothing about a
      // rule that only fires on a collision.
      for (var seed = 0; seed < 50; seed++) {
        final c = ProviderContainer(overrides: [
          coachBackdropRandomProvider.overrideWithValue(math.Random(seed)),
        ]);
        addTearDown(c.dispose);
        final before = c.read(coachBackdropProvider);
        c.read(coachBackdropProvider.notifier).shuffle();
        final after = c.read(coachBackdropProvider);
        expect(after, isNot(before), reason: 'seed $seed repeated $before');
        expect(kCoachBackdrops, contains(after));
      }
    });

    test('and it does move — it is not pinned to one other scene', () {
      // The positive control for the test above. "Never equal to the previous
      // one" is also satisfied by a shuffle that alternates between exactly two
      // pictures forever, which would look just as broken.
      final seen = <String>{};
      for (var seed = 0; seed < 50; seed++) {
        final c = ProviderContainer(overrides: [
          coachBackdropRandomProvider.overrideWithValue(math.Random(seed)),
        ]);
        addTearDown(c.dispose);
        c.read(coachBackdropProvider.notifier).shuffle();
        seen.add(c.read(coachBackdropProvider));
      }
      expect(seen.length, greaterThan(5),
          reason: 'over 50 seeds this reached only ${seen.length} of the ten '
              'scenes');
    });

    testWidgets('opening the page re-rolls it', (t) async {
      _phoneSized(t);
      final c = _container();
      final atLaunch = c.read(coachBackdropProvider);
      await t.pumpWidget(_page(c));
      await t.pump();
      await t.pump(const Duration(seconds: 2));

      expect(c.read(coachBackdropProvider), isNot(atLaunch),
          reason: 'the provider is app-scoped, so without the re-roll on mount '
              'a whole day of training would show one picture');
    });
  });
}
