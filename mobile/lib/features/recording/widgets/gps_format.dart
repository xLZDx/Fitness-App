/// Pure formatting helpers of the GPS recording screens (S04-D 8.1, 15).
///
/// Metric units only (S03D 13). Missing values read "No data" at the call site,
/// never zero (S04-R-033, S04-R-034). Spoken forms use ARB keys with plural
/// forms so a screen reader never reads a bare number.
library;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../activity/data/sport_type.dart';
import '../state/recorder_phase.dart';

/// `H:MM:SS` from one hour, `M:SS` below it.
String gpsFormatDuration(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Kilometres with two decimals, for example `3.20 km`.
String gpsFormatDistance(double meters) =>
    '${(meters / 1000).toStringAsFixed(2)} km';

/// `m:ss /km`; null when there is no pace.
String? gpsFormatPace(double? secPerKm) {
  if (secPerKm == null || !secPerKm.isFinite || secPerKm <= 0) return null;
  final total = secPerKm.round();
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s /km';
}

/// `12.4 km/h`; null when there is no speed.
String? gpsFormatSpeed(double? mps) {
  if (mps == null || !mps.isFinite || mps < 0) return null;
  return '${(mps * 3.6).toStringAsFixed(1)} km/h';
}

/// Local wall-clock `HH:mm` for the "saved up to" line.
String gpsFormatClock(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';

/// Spoken duration: "1 hour 5 minutes 3 seconds".
String gpsSpokenDuration(AppLocalizations l10n, int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final parts = <String>[
    if (h > 0) l10n.gpsUnitHours(h),
    if (m > 0) l10n.gpsUnitMinutes(m),
    if (s > 0 || (h == 0 && m == 0)) l10n.gpsUnitSeconds(s),
  ];
  return parts.join(' ');
}

/// Spoken distance in kilometres, one decimal.
String gpsSpokenDistance(AppLocalizations l10n, double meters) =>
    l10n.gpsUnitKm(double.parse((meters / 1000).toStringAsFixed(1)));

/// Spoken "age of the last point": days, hours, minutes or seconds.
String gpsSpokenAge(AppLocalizations l10n, int ms) {
  final s = ms < 0 ? 0 : ms ~/ 1000;
  if (s >= 86400) return l10n.gpsUnitDays(s ~/ 86400);
  if (s >= 3600) return l10n.gpsUnitHours(s ~/ 3600);
  if (s >= 60) return l10n.gpsUnitMinutes(s ~/ 60);
  return l10n.gpsUnitSeconds(s);
}

/// The sports of the Start screen, in display order (S04-D 6).
const List<SportType> kGpsStartSports = <SportType>[
  SportType.walking,
  SportType.running,
  SportType.hiking,
  SportType.cycling,
];

String gpsSportLabel(AppLocalizations l10n, SportType? sport) =>
    switch (sport) {
      SportType.walking => l10n.gpsSportWalk,
      SportType.running || SportType.trailRunning => l10n.gpsSportRun,
      SportType.hiking => l10n.gpsSportHike,
      SportType.cycling ||
      SportType.indoorCycling ||
      SportType.mountainBiking =>
        l10n.gpsSportRide,
      _ => l10n.gpsStartTitle,
    };

/// Ride shows speed; Walk, Run and Hike show pace (S04-D 8.1).
bool gpsUsesSpeed(SportType? sport) =>
    sport == SportType.cycling ||
    sport == SportType.indoorCycling ||
    sport == SportType.mountainBiking;

/// The visible "stopped: ..." line for an automatic stop; null for a user stop.
String? gpsStopReasonLine(AppLocalizations l10n, StopReason? reason) =>
    switch (reason) {
      StopReason.battery => l10n.gpsReasonBattery,
      StopReason.storage => l10n.gpsReasonStorage,
      StopReason.sampleCap => l10n.gpsReasonSampleCap,
      StopReason.consentWithdrawn => l10n.gpsReasonConsent,
      StopReason.account => l10n.gpsReasonAccount,
      StopReason.permissionRevoked => l10n.gpsReasonRevoked,
      StopReason.user || null => null,
    };
