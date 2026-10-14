import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'tracking_lost_test.dart' show nobody;
import 'unscorable_frame_test.dart' show oneSquat;

/// The target silhouette is on screen while the user's body is tracked.
///
/// Operator, 2026-10-14, real phone: the coach said «вы не дошли до силуэта»
/// while no silhouette was drawn (G17 had removed the outline). The layer
/// `form_check.layer.target` paints `poseTargetProvider` on the tracked body.

final _layer = find.byKey(const Key('form_check.layer.target'));
final _outline = find.byKey(const Key('form_check.target'));

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

ProviderContainer _container(List<PoseFrame> frames, {bool avatar = true}) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(frames)),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    avatarModeProvider.overrideWith((_) => avatar),
  ]);
  addTearDown(c.dispose);
  return c;
}

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

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 2));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

void main() {
  testWidgets('a tracked body: the target outline is painted (avatar mode)',
      (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(coachBodyDrawableProvider), isTrue,
        reason: 'positive control: a body is drawable');
    expect(c.read(poseTargetProvider), isNotNull);
    expect(_layer, findsOneWidget);
    expect(_outline, findsOneWidget);
  });

  testWidgets('a tracked body: the target outline is painted (camera mode)',
      (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0), avatar: false);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(coachBodyDrawableProvider), isTrue);
    expect(_outline, findsOneWidget);
  });

  testWidgets('nobody tracked: no outline, the demonstration owns the panel',
      (t) async {
    _phoneSized(t);
    final c = _container([for (var i = 0; i < 30; i++) nobody(i * 100)]);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(coachBodyDrawableProvider), isFalse);
    expect(_layer, findsOneWidget, reason: 'the layer slot is always mounted');
    expect(_outline, findsNothing);
  });

  testWidgets('losing the body removes the outline again', (t) async {
    _phoneSized(t);
    final c = _container([...oneSquat(0), nobody(9000)]);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(coachBodyDrawableProvider), isFalse);
    expect(_outline, findsNothing);
  });
}
