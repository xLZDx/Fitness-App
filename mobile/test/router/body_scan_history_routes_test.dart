// C16 functional tests: /body-scan/history and /body-scan/privacy resolve to
// their pages through the REAL app router, and /photos/compare reads ?mode=.
import 'dart:convert';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/body_scan/body_scan_history_page.dart';
import 'package:fitness_app/features/body_scan/body_scan_privacy_page.dart';
import 'package:fitness_app/features/body_scan/widgets/retention_settings_view.dart';
import 'package:fitness_app/features/body_scan/widgets/scan_history_list.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_compare_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

ScanRecord _scan(String id, int day) => ScanRecord(
      id: id,
      createdAt: DateTime(2026, 9, day),
      shots: {
        for (final p in ScanPose.ordered)
          p: ScanShot(photoId: '$id-${p.name}', landmarks: const []),
      },
    );

class _Scans implements ScanRepository {
  _Scans(this.items);
  final List<ScanRecord> items;
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async => items.removeWhere((r) => r.id == id);
}

class _App {
  _App(this.router, this.auth, this.profiles);
  final GoRouter router;
  final MockAuthRepository auth;
  final MockProfileRepository profiles;
}

Future<_App> _boot(WidgetTester t, {required bool signedIn}) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final auth = MockAuthRepository(latency: Duration.zero);
  final profiles = MockProfileRepository(latency: Duration.zero);
  if (signedIn) {
    await t.runAsync(() async {
      final uid = (await auth.signInAnonymously()).uid;
      await profiles.save(
          UserProfile.empty(uid).copyWith(completedAt: DateTime.utc(2026, 9, 1)));
    });
  }
  late GoRouter router;
  await t.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) {
        ref.onDispose(auth.dispose);
        return auth;
      }),
      profileRepositoryProvider.overrideWith((ref) {
        ref.onDispose(profiles.dispose);
        return profiles;
      }),
      scanRepositoryProvider.overrideWithValue(
          _Scans([_scan('c', 28), _scan('b', 14), _scan('a', 1)])),
      scanAccessProvider.overrideWithValue(ScanAccess.allowed),
      scanShotBytesProvider.overrideWith((ref, id) async => _png),
    ],
    child: Consumer(builder: (context, ref, _) {
      router = ref.watch(appRouterProvider);
      return MaterialApp.router(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      );
    }),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 400));
  }
  return _App(router, auth, profiles);
}

Future<void> _go(WidgetTester t, _App app, String location) async {
  app.router.go(location);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 400));
  }
}

String _path(_App app) =>
    app.router.routerDelegate.currentConfiguration.uri.toString();

String? _picked(WidgetTester t, String which) => t
    .state<FormFieldState<String>>(find.byKey(Key('scan.compare.pick.$which')))
    .value;

void main() {
  testWidgets('/body-scan/history resolves to the history page with its list',
      (t) async {
    final app = await _boot(t, signedIn: true);
    await _go(t, app, '/body-scan/history');
    expect(_path(app), '/body-scan/history');
    expect(find.byType(BodyScanHistoryPage), findsOneWidget);
    expect(find.byType(ScanHistoryList), findsOneWidget);
    final l10n = AppLocalizations.of(t.element(find.byType(BodyScanHistoryPage)));
    expect(find.text(l10n.bodyScanHistoryTitle), findsOneWidget);
    expect(find.byType(BodyScanPrivacyPage), findsNothing);
  });

  testWidgets('/body-scan/privacy resolves to the privacy page with its view',
      (t) async {
    final app = await _boot(t, signedIn: true);
    await _go(t, app, '/body-scan/privacy');
    expect(_path(app), '/body-scan/privacy');
    expect(find.byType(BodyScanPrivacyPage), findsOneWidget);
    expect(find.byType(RetentionSettingsView), findsOneWidget);
    final l10n = AppLocalizations.of(t.element(find.byType(BodyScanPrivacyPage)));
    expect(find.text(l10n.bodyScanPrivacyTitle), findsOneWidget);
    expect(find.byType(BodyScanHistoryPage), findsNothing);
  });

  testWidgets('signed out: both routes are kept behind the login gate',
      (t) async {
    final app = await _boot(t, signedIn: false);
    for (final p in ['/body-scan/history', '/body-scan/privacy']) {
      await _go(t, app, p);
      expect(_path(app), isNot(p), reason: '$p must not open signed out');
      expect(find.byType(BodyScanHistoryPage), findsNothing);
      expect(find.byType(BodyScanPrivacyPage), findsNothing);
    }
  });

  testWidgets('/photos/compare?mode=previous opens on the previous pair',
      (t) async {
    final app = await _boot(t, signedIn: true);
    await _go(t, app, '/photos/compare?mode=previous');
    expect(find.byType(ScanCompareScreen), findsOneWidget);
    expect(_picked(t, 'later'), 'c');
    expect(_picked(t, 'earlier'), 'b');
  });

  testWidgets('/photos/compare?mode=baseline and no mode open on the baseline',
      (t) async {
    final app = await _boot(t, signedIn: true);
    await _go(t, app, '/photos/compare?mode=baseline');
    expect((_picked(t, 'earlier'), _picked(t, 'later')), ('a', 'c'));
    await _go(t, app, '/home');
    await _go(t, app, '/photos/compare');
    expect((_picked(t, 'earlier'), _picked(t, 'later')), ('a', 'c'));
  });

  testWidgets('an unknown mode value falls back to the baseline', (t) async {
    final app = await _boot(t, signedIn: true);
    await _go(t, app, '/photos/compare?mode=nonsense');
    expect((_picked(t, 'earlier'), _picked(t, 'later')), ('a', 'c'));
  });
}
