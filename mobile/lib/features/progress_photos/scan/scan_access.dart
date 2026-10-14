import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/state/subscription_providers.dart';
import '../state/progress_photos_providers.dart';
import 'scan_session.dart';

/// Why the guided scan may or may not be opened. Evaluated in priority order:
/// signedOut, ageUnknown/underage, needsSupporter, needsConsent.
enum ScanAccess {
  allowed,
  signedOut,
  underage,
  ageUnknown,
  needsSupporter,
  needsConsent,
}

/// Whether this account has already accepted the EXISTING photo consent.
/// Not asked again for scans. Loading or failed reads count as not accepted.
/// Invalidate after the consent sheet records an answer.
final scanConsentAcceptedProvider = FutureProvider<bool>((ref) async {
  final store = await ref.watch(photoConsentStoreProvider.future);
  return store.isAccepted();
});

/// Pure priority table, kept separate so it is testable without providers.
ScanAccess evaluateScanAccess({
  required bool signedIn,
  required int? age,
  required bool supporter,
  required bool consentAccepted,
}) {
  if (!signedIn) return ScanAccess.signedOut;
  if (age == null) return ScanAccess.ageUnknown;
  if (!scanAllowedForAge(age)) return ScanAccess.underage;
  if (!supporter) return ScanAccess.needsSupporter;
  if (!consentAccepted) return ScanAccess.needsConsent;
  return ScanAccess.allowed;
}

/// Clock seam for the age calculation; tests override it with a fixed time.
final scanAccessClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

final scanAccessProvider = Provider<ScanAccess>((ref) {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  final year = ref.watch(scanAccessClockProvider)().year;
  // The LOWEST age the stored birth year allows, not the calendar-year
  // difference: someone who turns 18 in December must not pass the adults-only
  // gate on 1 January (`PersonalInfo.lowestAgeAt`).
  final age = ref
      .watch(currentProfileProvider)
      .valueOrNull
      ?.personal
      .lowestAgeAt(year);
  final tier = ref.watch(effectiveTierProvider);
  final consent = ref.watch(scanConsentAcceptedProvider).valueOrNull ?? false;
  return evaluateScanAccess(
    signedIn: uid != null && uid.isNotEmpty,
    age: age,
    supporter: tier != SubscriptionTier.free,
    consentAccepted: consent,
  );
});
