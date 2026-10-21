import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether features that are still backed by demo (Mock) repositories may be
/// reached by the user.
///
/// The coach marketplace (outside the v1 scope), the community feed, celebrity
/// plans, team feed, video contribution and the moderation queue read their data from providers that default to a Mock
/// repository, and `main.dart` does not override them with a real backend.
/// In a release build the user would therefore see fake data and any
/// "submitted" post or video would silently never be persisted.
///
/// Debug and profile builds keep the features for development. A release build
/// hides every entry point and the router redirects deep links to `/home`,
/// unless it is built with `--dart-define=DEMO_FEATURES=true`.
///
/// Remove this flag (and the gating that reads it) once those providers are
/// wired to real repositories.
///
/// Stays a compile-time constant (router default parameters need one), so it
/// cannot call [demoFeaturesEnabledFor]; the test pins the two together.
const bool kDemoFeaturesEnabled =
    !kReleaseMode || bool.fromEnvironment('DEMO_FEATURES');

/// The flag as a provider, read by the router's redirect. It defaults to the
/// compile-time constant; a test overrides it to drive the LIVE router with
/// the flag off, which is the only way to prove a release build denies a
/// gated path (under `flutter test` the constant is always true).
final demoFeaturesEnabledProvider =
    Provider<bool>((ref) => kDemoFeaturesEnabled);

/// Pure twin of [kDemoFeaturesEnabled], so every input combination can be
/// tested (the constant itself is fixed at compile time).
bool demoFeaturesEnabledFor({
  required bool isRelease,
  required bool definedFlag,
}) =>
    !isRelease || definedFlag;
