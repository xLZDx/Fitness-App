// FIX-B (U6, U7): the consent withdrawal result is surfaced, and a placeholder
// safety seam is stated on the Start screen.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/recording_defaults.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/recording/consent/location_consent.dart';
import 'package:fitness_app/features/recording/consent/location_consent_providers.dart';
import 'package:fitness_app/features/recording/state/battery_monitor.dart';
import 'package:fitness_app/features/recording/state/recorder_ports.dart';
import 'package:fitness_app/features/recording/widgets/gps_consent_row.dart';
import 'package:fitness_app/features/recording/widgets/gps_start_flow.dart';
import 'package:fitness_app/features/recording/widgets/gps_start_panels.dart';

class _FailingWithdraw extends LocationConsentNotifier {
  @override
  Future<LocationConsent> build() async => LocationConsent(
        <LocationConsentPurpose, ConsentRecord>{
          LocationConsentPurpose.locationWhileRecording: ConsentRecord(
            purpose: LocationConsentPurpose.locationWhileRecording,
            state: ConsentState.granted,
            textVersion: kLocationConsentTextVersion,
            timestampUtcMs: 1,
            grantedAtUtcMs: 1,
          ),
        },
      );

  @override
  Future<bool> withdraw({
    LocationConsentPurpose purpose =
        LocationConsentPurpose.locationWhileRecording,
    String textVersion = kLocationConsentTextVersion,
  }) async =>
      false;
}

Widget _host(List<Override> overrides, Widget child) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('U7: a failed withdrawal shows an error, not the success text',
      (t) async {
    await t.pumpWidget(_host(<Override>[
      locationConsentProvider.overrideWith(_FailingWithdraw.new),
    ], const GpsConsentRow()));
    await t.pump();
    await t.pump();
    final l10n = AppLocalizations.of(t.element(find.byType(GpsConsentRow)));

    await t.tap(find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'HudToggle'));
    await t.pump();
    expect(find.text(l10n.gpsConsentWithdrawConfirm), findsOneWidget);
    await t.tap(find.text(l10n.gpsConsentWithdraw).last);
    await t.pump();
    await t.pump();

    expect(find.text(l10n.gpsConsentWithdrawFailed), findsOneWidget);
  });

  testWidgets('U6: the Start screen states a placeholder safety seam',
      (t) async {
    await t.pumpWidget(_host(<Override>[
      batteryMonitorProvider.overrideWithValue(FakeBatteryMonitor()),
    ], const GpsSafetyGapNote()));
    final l10n = AppLocalizations.of(t.element(find.byType(GpsSafetyGapNote)));
    expect(find.text(l10n.gpsSafetyGapNote), findsOneWidget);
  });

  testWidgets('U6: no note when both seams are real', (t) async {
    await t.pumpWidget(_host(<Override>[
      gpsLocationServicesEnabledProvider.overrideWithValue(() async => true),
      batteryMonitorProvider.overrideWithValue(_RealLike()),
    ], const GpsSafetyGapNote()));
    expect(find.byType(Text), findsNothing);
  });
}

class _RealLike implements BatteryMonitor {
  @override
  Future<BatteryReading?> current() async => null;
  @override
  Stream<BatteryReading> get readings => const Stream<BatteryReading>.empty();
}
