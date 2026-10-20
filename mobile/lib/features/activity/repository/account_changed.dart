/// The account-changed outcome shared by every activity call that is bound to
/// the initiating account (S02 design 17 item 25, remediation J).
///
/// Kept in its own file so the settings client, the stream uploader, the sync
/// repository and the tombstone pusher can share it without importing each other.
library;

import 'package:cloud_functions/cloud_functions.dart';

/// Thrown when the signed-in account changed while an operation was running, or
/// when the operation has no account to act for: nothing was recorded for, or
/// sent as, the new account.
class ConsentAccountChangedException implements Exception {
  const ConsentAccountChangedException();
  @override
  String toString() => 'ConsentAccountChangedException';
}

/// True when [e] is the server's account-changed refusal (remediation J1):
/// `failed-precondition` with the message `account_changed`. The message is the
/// discriminator, because `failed-precondition` also carries other refusals
/// (for example `account_deleting`).
bool isAccountChangedRefusal(FirebaseFunctionsException e) =>
    e.code == 'failed-precondition' && e.message == 'account_changed';
