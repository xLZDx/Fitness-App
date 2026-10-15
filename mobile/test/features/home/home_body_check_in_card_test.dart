// C17 part 3: the compact "Body check-in" card is mounted on the Home page
// (after the quick-scan row), follows the access state and opens /body-scan.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/widgets/body_scan_entry_card.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

import '../../helpers/test_app.dart';

class _Repo implements ScanRepository {
  _Repo(this.items);
  final List<ScanRecord> items;
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async => items.removeWhere((r) => r.id == id);
}

class _Ctx extends TrainingContextNotifier {
  @override
  Future<TrainingContextAnswer> build() async => TrainingContextAnswer.skipped;
  @override
  Future<void> select(TrainingContextAnswer answer) async =>
      state = AsyncData(answer);
}

Future<void> _pump(
  WidgetTester tester, {
  ScanAccess access = ScanAccess.allowed,
  List<ScanRecord> history = const [],
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/body-scan',
          builder: (_, __) => const Scaffold(body: Text('route:/body-scan'))),
      GoRoute(
          path: '/subscription',
          builder: (_, __) =>
              const Scaffold(body: Text('route:/subscription'))),
      GoRoute(
          path: '/scan',
          builder: (_, __) => const Scaffold(body: Text('scan-stub'))),
      GoRoute(
          path: '/plan',
          builder: (_, __) => const Scaffold(body: Text('plan-stub'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      scanAccessProvider.overrideWithValue(access),
      scanRepositoryProvider.overrideWithValue(_Repo([...history])),
      trainingContextProvider.overrideWith(() => _Ctx()),
      safetyContextProvider.overrideWith((_) async => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}))),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => Material(
          type: MaterialType.transparency,
          child: AuroraBackground(child: child ?? const SizedBox.shrink())),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('Home mounts exactly one compact Body check-in card',
      (tester) async {
    await _pump(tester);
    final card = find.byType(BodyScanEntryCard, skipOffstage: false);
    expect(card, findsOneWidget);
    expect(tester.widget<BodyScanEntryCard>(card).compact, isTrue);
    expect(find.byKey(const Key('bodyCheckIn.card.home'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const Key('bodyCheckIn.card.progress'), skipOffstage: false),
        findsNothing);
    expect(find.text('Body check-in', skipOffstage: false), findsOneWidget);
  });

  testWidgets('it sits after the quick-scan row on the page', (tester) async {
    await _pump(tester);
    final quick = tester.getTopLeft(find.byKey(const Key('home.quickScan')));
    final card = tester.getTopLeft(find.byKey(const Key('bodyCheckIn.card.home')));
    expect(card.dy, greaterThan(quick.dy));
  });

  testWidgets('shows the last check-in line and only the Open action',
      (tester) async {
    await _pump(tester, history: [
      ScanRecord(
          id: 'a',
          createdAt: DateTime.now().subtract(const Duration(days: 4, hours: 1)),
          shots: const {}),
    ]);
    expect(find.text('Last check-in: 4 days ago'), findsOneWidget);
    expect(find.byKey(const Key('bodyCheckIn.history')), findsNothing);
    expect(find.byKey(const Key('bodyCheckIn.privacy')), findsNothing);
    expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Open from Home reaches /body-scan', (tester) async {
    await _pump(tester);
    final btn = find.byKey(const Key('bodyCheckIn.start'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.text('route:/body-scan'), findsOneWidget);
  });

  testWidgets('a free-tier user is sent to the subscription page',
      (tester) async {
    await _pump(tester, access: ScanAccess.needsSupporter);
    // The compact card keeps its fixed shape; the gate shows on the action.
    expect(find.text('Start check-in'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    final btn = find.byKey(const Key('bodyCheckIn.start'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.text('route:/subscription'), findsOneWidget);
  });

  testWidgets('signed out: the card is absent from Home', (tester) async {
    await _pump(tester, access: ScanAccess.signedOut);
    expect(find.byKey(const Key('bodyCheckIn.card.home'), skipOffstage: false),
        findsNothing);
    expect(find.byKey(const Key('home.quickScan')), findsOneWidget);
  });
}
