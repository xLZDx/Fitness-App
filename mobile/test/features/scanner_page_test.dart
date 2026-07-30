import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/live_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/live_recognition.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';

void main() {
  group('ScannerPage', () {
    testWidgets('leads with machine recognition, QR is the background job',
        (tester) async {
      // MUST pump with the real app theme: it sets button minimumSize to
      // Size.fromHeight(54) (minWidth == infinity), which crashed layout on
      // a Row-placed button while a default-theme test stayed green.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ScannerPage(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Primary action is recognising a machine from a photo.
      expect(find.byKey(const Key('scan-recognise-camera')), findsOneWidget);
      expect(find.text('Recognise machine'), findsOneWidget);
      expect(find.byKey(const Key('scan-recognise-gallery')), findsOneWidget);
      // QR is described as automatic, not as the thing the user must do.
      expect(find.textContaining('QR stickers are picked up automatically'),
          findsOneWidget);
    });

    testWidgets('renders classifier matches with confidence', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            visualEquipmentServiceProvider.overrideWithValue(
              MockVisualEquipmentService(fixedResults: const [
                VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
                VisualMatch(equipmentId: 'treadmill', confidence: 0.2),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ScannerPage(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Drive the controller directly: tapping the button would open the
      // real platform image picker, which has no test binding.
      final element = tester.element(find.byType(ScannerPage));
      final container = ProviderScope.containerOf(element);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      expect(find.text('Best matches'), findsOneWidget);
      expect(find.text('leg press'), findsOneWidget);
      expect(find.text('80% confidence'), findsOneWidget);
      expect(find.text('treadmill'), findsOneWidget);
    });

    testWidgets('live mode is off by default and shows no live card',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ScannerPage(),
          ),
        ),
      );
      await tester.pump();

      final toggle = tester.widget<Switch>(
          find.byKey(const Key('scan-live-toggle')));
      expect(toggle.value, isFalse);
      expect(find.byKey(const Key('scan-live-searching')), findsNothing);
      expect(find.byKey(const Key('scan-live-result')), findsNothing);
    });

    testWidgets('live mode shows searching, then the settled recognition',
        (tester) async {
      final svc = MockLiveEquipmentService(
        smoother: RecognitionSmoother(window: 2, minConfidence: 0.1),
      );
      addTearDown(svc.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveEquipmentServiceProvider.overrideWithValue(svc),
            liveModeEnabledProvider.overrideWith((_) => true),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ScannerPage(),
          ),
        ),
      );
      await tester.pump();

      // Nothing settled yet.
      expect(find.byKey(const Key('scan-live-searching')), findsOneWidget);

      // Two agreeing frames fill the window and settle on one machine.
      svc.feed(const VisualMatch(equipmentId: 'rowing_machine', confidence: 0.8));
      svc.feed(const VisualMatch(equipmentId: 'rowing_machine', confidence: 0.6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('scan-live-result')), findsOneWidget);
      expect(find.text('rowing machine'), findsOneWidget);
      expect(find.textContaining('100% of frames agree'), findsOneWidget);
    });

    testWidgets('opening a photo match releases the camera first',
        (tester) async {
      // Regression: the match list pushed `/equipment/:id` directly, skipping
      // the live-mode teardown the live card did. `/equipment/:id` renders above
      // the shell so this page is never disposed and autoDispose cannot fire —
      // the stream kept running, camera indicator lit, behind the page the user
      // was reading.
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const ScannerPage()),
          GoRoute(
            path: '/equipment/:id',
            builder: (_, s) =>
                Scaffold(body: Text('equipment ${s.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveModeEnabledProvider.overrideWith((_) => true),
            visualEquipmentServiceProvider.overrideWithValue(
              MockVisualEquipmentService(fixedResults: const [
                VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
              ]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      container = ProviderScope.containerOf(
          tester.element(find.byType(ScannerPage)));

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();
      expect(container.read(liveModeEnabledProvider), isTrue);

      // Live mode adds a card above the results, pushing them below the fold.
      await tester.scrollUntilVisible(find.text('leg press'), 120);
      await tester.tap(find.text('leg press'));
      await tester.pump();
      expect(container.read(liveModeEnabledProvider), isFalse,
          reason: 'camera must be released before navigating away');

      // The handover waits 250ms before handing the camera back to the QR
      // scanner, and only then pushes. A plain pumpAndSettle does not advance
      // a pending Future.delayed.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('equipment leg_press'), findsOneWidget,
          reason: 'releasing the camera must not swallow the navigation');
    });
  });
}
