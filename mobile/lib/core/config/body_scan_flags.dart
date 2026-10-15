import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time switches for the operator-blocked parts of Body Scan and
/// Nutrition Coach (sprint plan section 4, SD-2).
///
/// Every flag is OFF unless the build says otherwise, and every flagged path
/// has a working fallback, so the default build depends on no operator action:
///
///  * [cloudPhotos] (`--dart-define=BODY_SCAN_CLOUD=true`): any photo upload,
///    the cloud consent sheet and the signed-URL path. Off: the provisional
///    estimator runs on the device and no photo ever leaves it.
///  * [foodAi] (`--dart-define=FOOD_AI=true`): meal photo, describe-in-text and
///    label recognition (server-side Vertex AI). Off: bundled search, quick
///    log and saved foods still work.
///  * [foodLookup] (`--dart-define=FOOD_LOOKUP=true`): barcode lookup and
///    server food search. Off: the barcode tile and server search are hidden.
///
/// Turning one on is an operator action (the matching server flag, secrets and
/// the privacy text first, sprint plan SD-15) and needs no code change. The
/// client flag only decides what the UI offers; the server enforces its own
/// flag and answers `failed-precondition: feature-disabled` when it is off.
///
/// `bool.fromEnvironment` must be a compile-time constant, so the values live
/// in [BodyScanFlags.compileTime]; widgets and notifiers read the flags through
/// [bodyScanFlagsProvider], which a test overrides to drive both states.
class BodyScanFlags {
  const BodyScanFlags({
    this.cloudPhotos = false,
    this.foodAi = false,
    this.foodLookup = false,
  });

  /// Photo upload to the private bucket and everything that needs it.
  final bool cloudPhotos;

  /// Meal photo, describe-in-text and nutrition-label AI recognition.
  final bool foodAi;

  /// Barcode lookup and server-side food search.
  final bool foodLookup;

  /// The flags this build was compiled with; all false unless `--dart-define`d.
  static const BodyScanFlags compileTime = BodyScanFlags(
    cloudPhotos: bool.fromEnvironment('BODY_SCAN_CLOUD'),
    foodAi: bool.fromEnvironment('FOOD_AI'),
    foodLookup: bool.fromEnvironment('FOOD_LOOKUP'),
  );

  BodyScanFlags copyWith({
    bool? cloudPhotos,
    bool? foodAi,
    bool? foodLookup,
  }) =>
      BodyScanFlags(
        cloudPhotos: cloudPhotos ?? this.cloudPhotos,
        foodAi: foodAi ?? this.foodAi,
        foodLookup: foodLookup ?? this.foodLookup,
      );

  @override
  bool operator ==(Object other) =>
      other is BodyScanFlags &&
      other.cloudPhotos == cloudPhotos &&
      other.foodAi == foodAi &&
      other.foodLookup == foodLookup;

  @override
  int get hashCode => Object.hash(cloudPhotos, foodAi, foodLookup);

  @override
  String toString() => 'BodyScanFlags(cloudPhotos: $cloudPhotos, '
      'foodAi: $foodAi, foodLookup: $foodLookup)';
}

/// The flags as a provider. Defaults to the compile-time values; a test
/// overrides it to exercise the flag-on and flag-off paths.
final bodyScanFlagsProvider =
    Provider<BodyScanFlags>((ref) => BodyScanFlags.compileTime);
