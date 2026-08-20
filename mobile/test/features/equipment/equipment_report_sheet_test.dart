import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/mock_equipment_report_service.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/widgets/equipment_report_sheet.dart';

/// codex review, round 3, Gate F cherry-pick, 2026-08-21: the resolved gymId
/// from the profile must never be forwarded silently -- the sheet has to ask
/// per report, default to not asking, and fall back to 'unknown' unless the
/// user actively confirms.
Widget _harness(ProviderContainer c, {String gymId = 'unknown'}) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => EquipmentReportSheet.show(
                context,
                equipmentId: 'leg_press',
                equipmentName: 'Leg Press',
                gymId: gymId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

/// `_submit` only `ref.read`s authUserProvider -- nothing else in the sheet
/// watches it, so without warming it up here the StreamProvider is still
/// AsyncLoading (valueOrNull == null) at the exact moment the button handler
/// fires, and every submission hits the "sign in" error path instead of the
/// mock service. Same pattern as cross_gate_matrix_test.dart.
Future<ProviderContainer> _container() async {
  final mock = MockEquipmentReportService();
  final c = ProviderContainer(overrides: [
    authUserProvider.overrideWith(
        (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
    equipmentReportServiceProvider.overrideWithValue(mock),
  ]);
  addTearDown(c.dispose);
  await c.read(authUserProvider.future);
  return c;
}

MockEquipmentReportService _service(ProviderContainer c) =>
    c.read(equipmentReportServiceProvider) as MockEquipmentReportService;

void main() {
  testWidgets('no gym on the profile: no checkbox, submits unknown',
      (tester) async {
    final c = await _container();
    await tester.pumpWidget(_harness(c));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment-report-confirm-gym')), findsNothing);

    await tester.tap(find.text('Send to maintenance'));
    await tester.pumpAndSettle();

    expect(_service(c).submitted.single.gymId, 'unknown');
  });

  testWidgets(
      'BLOCKER (codex round 3): a saved gym is NOT forwarded unless the '
      'user actively confirms it -- the checkbox defaults unchecked',
      (tester) async {
    final c = await _container();
    await tester.pumpWidget(_harness(c, gymId: 'Iron Temple'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment-report-confirm-gym')), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox)).value,
      false,
      reason: 'must not default to trusting the saved gym',
    );

    // Submit WITHOUT checking the box.
    await tester.tap(find.text('Send to maintenance'));
    await tester.pumpAndSettle();

    expect(_service(c).submitted.single.gymId, 'unknown',
        reason: 'an unconfirmed gym must never reach the backend');
  });

  testWidgets('checking the confirmation forwards the real gymId',
      (tester) async {
    final c = await _container();
    await tester.pumpWidget(_harness(c, gymId: 'Iron Temple'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('equipment-report-confirm-gym')));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);

    await tester.tap(find.text('Send to maintenance'));
    await tester.pumpAndSettle();

    expect(_service(c).submitted.single.gymId, 'Iron Temple');
  });

  testWidgets('the confirmation label names the actual saved gym',
      (tester) async {
    final c = await _container();
    await tester.pumpWidget(_harness(c, gymId: 'Iron Temple'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Iron Temple'), findsOneWidget);
  });
}
