import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_compare_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_entry_card.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_landmark_mapper.dart';
import '../../../../helpers/test_app.dart';
import 'scan_fakes.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

ScanShot _shot(String id, {bool landmarks = true, double dx = 0, double s = 1}) {
  final f = body(cx: kAspect / 2 + dx, h: 0.75 * s, top: 0.10);
  return ScanShot(
    photoId: id,
    landmarks: landmarks ? landmarksFromFrame(f) : const [],
  );
}

ScanRecord _scan(String id, int day,
        {Map<ScanPose, ScanShot>? shots, bool landmarks = true, double dx = 0}) =>
    ScanRecord(
      id: id,
      createdAt: DateTime(2026, 9, day),
      shots: shots ??
          {
            for (final p in ScanPose.ordered)
              p: _shot('$id-${p.name}', landmarks: landmarks, dx: dx),
          },
    );

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  ScanAccess access = ScanAccess.allowed,
  List<ScanRecord> history = const [],
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      scanAccessProvider.overrideWithValue(access),
      scanHistoryProvider.overrideWith((_) async => history),
      scanShotBytesProvider.overrideWith((ref, id) async => _png),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('compare screen', () {
    final history = [
      _scan('new', 28, dx: 0.02),
      _scan('mid', 14),
      _scan('old', 1),
    ];

    testWidgets('needs two scans', (tester) async {
      await _pump(tester, const ScanCompareScreen(), history: [_scan('a', 1)]);
      expect(find.byKey(const Key('scan.compare.needTwo')), findsOneWidget);
    });

    testWidgets('defaults to oldest vs newest, side by side, aligned',
        (tester) async {
      await _pump(tester, const ScanCompareScreen(), history: history);
      expect(find.byKey(const Key('scan.compare.sideBySide')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.alignedNote')), findsOneWidget);
      expect(find.textContaining('Earlier'), findsWidgets);
      // Earlier column is dated 1 Sep, latest 28 Sep.
      expect(find.textContaining('Sep 1, 2026'), findsWidgets);
      expect(find.textContaining('Sep 28, 2026'), findsWidgets);
    });

    testWidgets('switches between slider and ghost overlay', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const ScanCompareScreen(), history: history);
      await tester.tap(find.text('Slider'));
      await tester.pump();
      expect(find.byKey(const Key('scan.compare.slider')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.sliderControl')), findsOneWidget);
      final control = find.byKey(const Key('scan.compare.sliderControl'));
      await tester.ensureVisible(control);
      await tester.pump();
      await tester.drag(control, const Offset(80, 0));
      await tester.pump();
      expect(tester.widget<Slider>(control).value, greaterThan(0.5));

      await tester.tap(find.text('Overlay'));
      await tester.pump();
      expect(find.byKey(const Key('scan.compare.ghost')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.ghostControl')), findsOneWidget);
    });

    testWidgets('pose tabs switch and a missing pose is explained',
        (tester) async {
      final partial = _scan('old', 1, shots: {
        ScanPose.front: _shot('old-front'),
        ScanPose.side: _shot('old-side'),
      });
      await _pump(tester, const ScanCompareScreen(),
          history: [_scan('new', 28), partial]);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('scan.compare.poses')),
          matching: find.text('Back')));
      await tester.pump();
      expect(find.byKey(const Key('scan.compare.missingPose')), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('scan.compare.poses')),
          matching: find.text('Side')));
      await tester.pump();
      expect(find.byKey(const Key('scan.compare.missingPose')), findsNothing);
    });

    testWidgets('no landmarks: unaligned fallback with a plain message',
        (tester) async {
      await _pump(tester, const ScanCompareScreen(),
          history: [_scan('n', 28, landmarks: false), _scan('o', 1, landmarks: false)]);
      expect(find.byKey(const Key('scan.compare.unalignedNote')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.sideBySide')), findsOneWidget);
    });

    testWidgets('a photo that is gone shows a placeholder, not a crash',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          scanAccessProvider.overrideWithValue(ScanAccess.allowed),
          scanHistoryProvider.overrideWith((_) async => history),
          scanShotBytesProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ScanCompareScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scan.compare.shotMissing')), findsWidgets);
    });

    testWidgets('underage never sees photos', (tester) async {
      await _pump(tester, const ScanCompareScreen(),
          access: ScanAccess.underage, history: history);
      expect(find.byKey(const Key('scan.gate.underage')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.sideBySide')), findsNothing);
    });
  });

  group('alignment view', () {
    test('usable for matching landmarks, null for none', () {
      final ok = ScanAlignmentView.compute(_shot('a'), _shot('b', dx: 0.03, s: 0.9));
      expect(ok.aligned, isTrue);
      final none = ScanAlignmentView.compute(
          _shot('a'), _shot('b', landmarks: false));
      expect(none.aligned, isFalse);
    });
  });

  group('entry card states', () {
    for (final c in {
      ScanAccess.allowed: 'scan.entry.start',
      ScanAccess.needsConsent: 'scan.entry.consent',
      ScanAccess.ageUnknown: 'scan.entry.profile',
    }.entries) {
      testWidgets('${c.key.name} offers its action', (tester) async {
        await _pump(
          tester,
          const Scaffold(body: SingleChildScrollView(child: ScanEntryCard())),
          access: c.key,
        );
        expect(find.byKey(Key(c.value)), findsOneWidget);
      });
    }

    testWidgets('underage: explanation only, no way in', (tester) async {
      await _pump(tester,
          const Scaffold(body: SingleChildScrollView(child: ScanEntryCard())),
          access: ScanAccess.underage);
      expect(find.textContaining('only available from age 18'), findsOneWidget);
      expect(find.byKey(const Key('scan.entry.start')), findsNothing);
      expect(find.byKey(const Key('scan.entry.consent')), findsNothing);
    });

    testWidgets('needsSupporter: message, no start', (tester) async {
      await _pump(tester,
          const Scaffold(body: SingleChildScrollView(child: ScanEntryCard())),
          access: ScanAccess.needsSupporter);
      expect(find.byKey(const Key('scan.entry.needsSupporter')), findsOneWidget);
      expect(find.byKey(const Key('scan.entry.start')), findsNothing);
    });
  });

  group('router redirects for the scan routes', () {
    for (final path in ['/photos/scan', '/photos/compare']) {
      test('$path: signed out goes to login', () {
        expect(
            resolveRedirect(
                isSignedIn: false,
                isOnboarded: false,
                location: path,
                isAnonymous: false),
            '/login');
      });
      test('$path: not onboarded goes to onboarding', () {
        expect(
            resolveRedirect(
                isSignedIn: true,
                isOnboarded: false,
                location: path,
                isAnonymous: false),
            '/onboarding');
      });
      test('$path: onboarded user stays', () {
        expect(
            resolveRedirect(
                isSignedIn: true,
                isOnboarded: true,
                location: path,
                isAnonymous: false),
            isNull);
      });
    }
  });
}
