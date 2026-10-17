/// The "offered this run" set of the first-run chooser (design 2.3, RV-7, F-39).
///
/// A keep-alive (non auto-dispose) provider, so a Home to Profile to Home round
/// trip in the same process never offers the chooser a second time. It is
/// in-memory only: a process kill clears it, and because the chooser status
/// stays `pending` on disk the next start offers the chooser again (AC-CH-5).
///
/// The chooser page marks the current uid when it is opened. Home calls
/// [OfferedThisRun.markOffered] too, right before it opens the chooser, and
/// reads [OfferedThisRun.wasOffered] before offering.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class OfferedThisRun extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Whether the chooser was already opened for [uid] in this run.
  bool wasOffered(String uid) => state.contains(uid);

  /// Records that the chooser was opened for [uid]. An empty uid is ignored.
  void markOffered(String uid) {
    if (uid.isEmpty || state.contains(uid)) return;
    state = <String>{...state, uid};
  }
}

/// Uids the chooser was offered to in this run.
final offeredThisRunProvider =
    NotifierProvider<OfferedThisRun, Set<String>>(OfferedThisRun.new);
