import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/account_deletion_service.dart';

final accountDeletionServiceProvider =
    Provider<AccountDeletionService>((_) => MockAccountDeletionService());

/// Runs L0b: calls the Cloud Function, then signs the local client out.
class AccountDeletionAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> deleteAccount() async {
    state = const AsyncValue.loading();
    try {
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
