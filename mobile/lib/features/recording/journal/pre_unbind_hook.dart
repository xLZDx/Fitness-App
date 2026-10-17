/// The pre-unbind hook (S04 design 4.7, Y2, K2, S04-30 AC-2).
///
/// The repository layer defines the hook type and never imports the recorder:
/// the bind controller in `core/wiring/activity_wiring.dart` awaits ONE
/// registered hook, bounded by [kPreUnbindTimeout], before it unbinds on a
/// sign-out, a uid change or an account deletion. The recorder registers its
/// implementation at wiring time; the sign-out guard (lane R13) calls the same
/// registry. Pure Dart, no Flutter imports.
library;

import 'dart:async';

/// Why the account scope is about to be unbound.
enum UnbindReason {
  /// An explicit sign-out (the target uid is null).
  signOut,

  /// A confirmed different non-null uid appeared.
  uidChanged,

  /// An account deletion started for the bound uid.
  accountDeleted,
}

/// Bound for the whole hook (PROPOSED 5 s, Y2).
const Duration kPreUnbindTimeout = Duration(seconds: 5);

abstract class PreUnbindHook {
  /// Runs while the scope of [ownerUid] is still bound. Strict path: shut the
  /// recorder down, stop, seal and hand off into the owner's store, then delete
  /// the recording journal. On [UnbindReason.accountDeleted] only the shutdown
  /// runs; the wipe deletes `recording/` afterwards.
  Future<void> run(String ownerUid, UnbindReason reason);
}

/// What a bounded run did, for the sign-out guard's notice (S04-30 AC-3, AC-6).
enum PreUnbindOutcome {
  /// No hook is registered: nothing to do.
  noHook,

  /// The hook finished inside the bound.
  completed,

  /// The hook did not finish in time; the recording stays encrypted in its
  /// scope under the 30-day fallback and the user must be told.
  timedOut,

  /// The hook threw; same consequence as [timedOut].
  failed,
}

/// Holds the single registered hook.
class PreUnbindHookRegistry {
  PreUnbindHook? _hook;

  bool get hasHook => _hook != null;

  /// Replaces any earlier registration (one hook only).
  void register(PreUnbindHook hook) => _hook = hook;

  /// Removes [hook] when it is the registered one.
  void unregister(PreUnbindHook hook) {
    if (identical(_hook, hook)) _hook = null;
  }

  /// Runs the hook bounded by [timeout]. Never throws.
  Future<PreUnbindOutcome> runBounded(
    String ownerUid,
    UnbindReason reason, {
    Duration timeout = kPreUnbindTimeout,
  }) async {
    final hook = _hook;
    if (hook == null) return PreUnbindOutcome.noHook;
    try {
      await hook.run(ownerUid, reason).timeout(timeout);
      return PreUnbindOutcome.completed;
    } on TimeoutException {
      return PreUnbindOutcome.timedOut;
    } catch (_) {
      // Content-free: the type of the failure is not even needed here.
      return PreUnbindOutcome.failed;
    }
  }
}
