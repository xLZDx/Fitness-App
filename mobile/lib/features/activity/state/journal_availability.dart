/// One availability value for the local activity journal (S03-0, design 2.1
/// item 3, RV-3). Dashboards show LOADING for [JournalBinding], the data for
/// [JournalOpen] and an error panel for [JournalGaveUp]. An empty list is never
/// "no activity" unless the availability is [JournalOpen].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/activity_flags.dart';
import '../../../core/wiring/activity_wiring.dart';
import '../../account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import '../../auth/state/auth_providers.dart';
import '../repository/uid_scoped_activity_journal.dart' show AccountScopedJournal;

/// Availability of the local journal. [ownerUid] and [generation] identify the
/// account and auth value the value was derived for (null / 0 where no account
/// applies), so a consumer can reject a stale value.
sealed class JournalAvailability {
  const JournalAvailability({this.ownerUid, this.generation = 0});

  final String? ownerUid;
  final int generation;
}

/// The journal flag is off (a build switch or a test override).
final class JournalNotEnabled extends JournalAvailability {
  const JournalNotEnabled();
}

/// A bind is in progress or not yet started, an automatic retry is armed, or
/// there is no bindable uid (signed out, empty uid, account being deleted).
final class JournalBinding extends JournalAvailability {
  const JournalBinding({super.ownerUid, super.generation});
}

/// The journal is bound AND its bound uid equals the signed-in uid.
final class JournalOpen extends JournalAvailability {
  const JournalOpen({super.ownerUid, super.generation});
}

/// The automatic retry schedule is exhausted; "Try again" is offered.
final class JournalGaveUp extends JournalAvailability {
  const JournalGaveUp({super.ownerUid, super.generation});
}

/// Defensive, not retriable: the journal flag is enabled but no journal object
/// was provided to the app. Production cannot reach it; tests do by override.
final class JournalFailedToOpen extends JournalAvailability {
  const JournalFailedToOpen();
}

/// Derived from the flags, the journal object, the auth user and the bind
/// status. It is never `open` merely because a journal object exists.
final journalAvailabilityProvider = Provider<JournalAvailability>((ref) {
  if (!ref.watch(activityFlagsProvider).journalEnabled) {
    return const JournalNotEnabled();
  }
  final journal = ref.watch(activityJournalProvider);
  if (journal == null) return const JournalFailedToOpen();

  final authUid = ref.watch(authUserProvider).valueOrNull?.uid;
  final deleting = ref.watch(accountBeingDeletedUidProvider);
  if (authUid == null || authUid.isEmpty || authUid == deleting) {
    return const JournalBinding();
  }

  // A journal without the account-binding surface has no bind machine and is
  // usable as it is (test harness journals).
  if (journal is! AccountScopedJournal) {
    return JournalOpen(ownerUid: authUid);
  }

  final status = ref.watch(activityBindStatusProvider);
  if (status.uid != authUid) {
    return JournalBinding(ownerUid: authUid, generation: status.generation);
  }
  switch (status.phase) {
    case BindPhase.bound:
      if (journal.isBound && journal.boundUid == authUid) {
        return JournalOpen(ownerUid: authUid, generation: status.generation);
      }
      return JournalBinding(ownerUid: authUid, generation: status.generation);
    case BindPhase.gaveUp:
      return JournalGaveUp(ownerUid: authUid, generation: status.generation);
    case BindPhase.binding:
    case BindPhase.none:
      return JournalBinding(ownerUid: authUid, generation: status.generation);
  }
});
