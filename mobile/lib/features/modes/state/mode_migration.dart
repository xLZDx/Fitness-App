import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../profile/data/profile_models.dart' show UserProfile;
import '../../profile/state/profile_providers.dart' show currentProfileProvider;
import 'mode_providers.dart';

/// Start-up migration (design 2.2, RV-1). Runs ONCE per process per uid and
/// decides only from the FIRST profile value loaded for that uid in this
/// process (`currentProfileProvider`, `profile_providers.dart:36`; onboarded =
/// `UserProfile.hasCompletedOnboarding`, `profile_models.dart:1132`). If that
/// first value is onboarded it asks the notifier to `initIfAbsent(migration)`,
/// which acts only on a missing store value. If the first value is not
/// onboarded (including "no profile"), the migration never runs for that uid in
/// this process, even when the profile flips later: that belongs to the
/// onboarding hook. While the profile has not loaded nothing happens. A failure
/// is logged (fixed message, exception type) and never blocks start-up.
final modeMigrationProvider = Provider<void>((ref) {
  final decided = <String>{};

  void consider(AsyncValue<UserProfile?> value) {
    // A loading value may carry the previous account's data: ignore it.
    if (value.isLoading || !value.hasValue) return;
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null) return;
    final profile = value.value;
    if (profile != null && profile.uid != uid) return;
    if (!decided.add(uid)) return; // not the first value for this uid
    if (profile == null || !profile.hasCompletedOnboarding) return;
    unawaited(_migrate(ref, uid));
  }

  ref.listen<AsyncValue<UserProfile?>>(
      currentProfileProvider, (_, next) => consider(next),
      fireImmediately: true);
});

Future<void> _migrate(Ref ref, String uid) async {
  try {
    await ref.read(modeStateProvider.future);
    if (ref.read(authUserProvider).valueOrNull?.uid != uid) return;
    await ref
        .read(modeStateProvider.notifier)
        .initIfAbsent(InitSource.migration, forUid: uid);
  } catch (e) {
    debugPrint('mode migration failed (${e.runtimeType})');
  }
}
