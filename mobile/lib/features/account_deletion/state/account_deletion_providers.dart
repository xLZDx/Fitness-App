import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/account_deletion_service.dart';
import '../data/local_data_wipe.dart';

final accountDeletionServiceProvider =
    Provider<AccountDeletionService>((_) => MockAccountDeletionService());

/// A1 — the on-device half of "delete my account". Overridden in `main.dart`
/// with the real device implementation, exactly like the service above.
final localDataWipeProvider =
    Provider<LocalDataWipe>((_) => RecordingLocalDataWipe());

/// Runs L0b: calls the Cloud Function, then signs the local client out.
class AccountDeletionAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> deleteAccount() async {
    state = const AsyncValue.loading();
    try {
      // Read BEFORE the call, not after. `signOut()` below clears auth state,
      // and the on-device wipe needs the uid to find this user's health blob
      // (`profile.sensitive.{uid}`). Reading it afterwards would leave the
      // most sensitive local record on the phone precisely BECAUSE the
      // account was deleted successfully.
      //
      // From the repository, not `authUserProvider`: that one is a
      // `StreamProvider`, so its value is `AsyncLoading` until the auth
      // stream has emitted at least once. `currentUser` is synchronous and is
      // what the underlying SDK already knows. Using the stream would make
      // the wipe silently depend on emission timing — the class of bug where
      // it works on a warm app and skips on a cold one.
      final uid = ref.read(authRepositoryProvider).currentUser?.uid;

      // Sign-out sits AFTER this call succeeds, deliberately, rather than in
      // a `finally` that would run it on every path including a genuine
      // failure. Moving it out was reviewed and rejected: if Stripe
      // cancellation fails server-side, the account still exists and is
      // still usable, and signing the user out anyway would hide that
      // failure behind a redirect to /login instead of surfacing it where
      // they can retry.
      //
      // The residual gap this leaves -- a dropped response after the server
      // call actually succeeded, which throws here without reaching
      // sign-out -- no longer needs a client-side workaround. `deleteAccount`
      // on the server is now idempotent (cancel/delete/deleteUser each treat
      // "already done" as success rather than an error), so tapping the
      // button again converges cleanly instead of repeating the same failure.
      await ref.read(accountDeletionServiceProvider).deleteAccount();

      // A1 — the device half, between the server call and the sign-out.
      //
      // After the server succeeded, so a failed deletion never wipes a
      // still-live account's photos; before the sign-out, because the uid is
      // still readable here and because the router redirects to /login the
      // moment auth state clears, which would race a wipe started after it.
      //
      // Best-effort like the sign-out below: the account IS gone by now, and
      // surfacing "could not delete a local file" through the same error
      // state as "your account was not deleted" would misreport the outcome.
      if (uid != null) {
        try {
          await ref.read(localDataWipeProvider).wipe(uid);
        } catch (e) {
          debugPrint('local data wipe after account deletion failed: $e');
        }
      }

      // Explicit, not relied-upon. The server just deleted this Firebase
      // Auth user, but the local client doesn't know that yet — it would
      // only find out the next time it tries to refresh its ID token, which
      // could be close to an hour away. Signing out here forces local state
      // to catch up immediately: `authUserProvider` emits null, and the
      // router's existing redirect takes it from there to `/login`.
      //
      // Best-effort, and deliberately not what the caller's error state
      // reports on: the account IS deleted at this point. A client-side
      // sign-out hiccup afterward is a different, much smaller problem than
      // "your account was not deleted", and reporting it as the same kind of
      // failure would read as the deletion having failed when it didn't.
      try {
        await ref.read(authActionProvider.notifier).signOut();
      } catch (e) {
        debugPrint('sign-out after account deletion failed: $e');
      }

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final accountDeletionActionProvider =
    NotifierProvider<AccountDeletionAction, AsyncValue<void>>(
        AccountDeletionAction.new);
