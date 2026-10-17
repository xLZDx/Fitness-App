import '../data/mode_models.dart';

/// Build-time switches for the new modes (design 4.2). Same pattern as
/// `BodyScanFlags`: `bool.fromEnvironment` must be a compile-time constant, so
/// it lives here and widgets read it through `modeFlagsProvider`. Train and Body
/// are always available (no flag); there is no paywall or entitlement check.
class ModeFlags {
  const ModeFlags({this.rideEnabled = false, this.exploreEnabled = false});

  /// `--dart-define=MODE_RIDE=true` (S05/S06 flip it).
  final bool rideEnabled;

  /// `--dart-define=MODE_EXPLORE=true`.
  final bool exploreEnabled;

  static const ModeFlags compileTime = ModeFlags(
    rideEnabled: bool.fromEnvironment('MODE_RIDE'),
    exploreEnabled: bool.fromEnvironment('MODE_EXPLORE'),
  );

  /// The availability table (contract 4.1) these flags produce.
  Map<AppMode, ModeAvailability> get availabilityTable => {
        AppMode.train: ModeAvailability.available,
        AppMode.body: ModeAvailability.available,
        AppMode.ride:
            rideEnabled ? ModeAvailability.available : ModeAvailability.comingLater,
        AppMode.explore: exploreEnabled
            ? ModeAvailability.available
            : ModeAvailability.comingLater,
      };
}
