import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:fitness_app/features/body_scan/state/scan_result_source.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';

/// Minimal localized host for C15 widget tests. [locale] defaults to English.
Widget scanHost(
  Widget child, {
  Locale locale = const Locale('en'),
  bool disableAnimations = false,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: c!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

const String kProvisionalModelId = 'provisional-anthropometric';
const String kPhotoModelId = 'photo-model';

BodyFatEstimate estimate({
  double value = 20.0,
  double halfWidth = 2.0,
  bool provisional = false,
  EstimateConfidence confidence = EstimateConfidence.medium,
  List<CheckCode> checks = const [],
}) =>
    BodyFatEstimate(
      value: value,
      low: value - halfWidth,
      high: value + halfWidth,
      confidence: confidence,
      modelId: provisional ? kProvisionalModelId : kPhotoModelId,
      modelVersion: '1',
      provisional: provisional,
      checkCodes: checks,
    );

ScanReading reading(DateTime at, double value,
        {double halfWidth = 2.0,
        bool provisional = false,
        String? scanId}) =>
    ScanReading(
      at: at,
      value: value,
      halfWidth: halfWidth,
      modelId: provisional ? kProvisionalModelId : kPhotoModelId,
      modelVersion: '1',
      scanId: scanId,
    );

final DateTime kScanDay = DateTime(2026, 10, 1, 9);

/// Weekly readings starting at [kScanDay].
List<ScanReading> weeklyReadings(List<double> values,
        {double halfWidth = 2.0, bool provisional = false}) =>
    [
      for (var i = 0; i < values.length; i++)
        reading(kScanDay.add(Duration(days: 7 * i)), values[i],
            halfWidth: halfWidth, provisional: provisional),
    ];

ScanResultData scanData({
  required List<double> values,
  bool provisional = false,
  double halfWidth = 2.0,
  double? weightKg = 80,
  double? slope,
  int? strength,
  List<CheckCode> checks = const [],
  EstimateConfidence confidence = EstimateConfidence.medium,
}) {
  final readings =
      weeklyReadings(values, halfWidth: halfWidth, provisional: provisional);
  return ScanResultData(
    scanId: 'scan-1',
    takenAt: readings.last.at,
    estimate: estimate(
      value: values.last,
      halfWidth: halfWidth,
      provisional: provisional,
      confidence: confidence,
      checks: checks,
    ),
    readings: readings,
    weightKg: weightKg,
    weightSlopeKgPerWeek: slope,
    strengthSessionsLast4Weeks: strength,
  );
}

const WeeklyReviewDecision kDecision = WeeklyReviewDecision(
  kind: ReviewDecisionKind.keep,
  reasonCodes: [],
  application: ReviewApplication.proposed,
  basePlanVersion: 1,
  inputs: ReviewInputsRecord(
    weightSlopeKgPerWeek: -0.4,
    intendedKgPerWeek: 0.5,
    dataPoints: 8,
  ),
);

const ScanPlanContext kFullPlan = ScanPlanContext(
  surfaceMode: ScanSurfaceMode.full,
  decision: kDecision,
  targetBodyFatPct: 15,
);

const ScanPlanContext kFullPlanNoDecision = ScanPlanContext(
  surfaceMode: ScanSurfaceMode.full,
  targetBodyFatPct: 15,
);
