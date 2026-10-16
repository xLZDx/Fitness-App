/// Pushes a local activity delete to the server through the `deleteActivity`
/// callable (S02 design 6.2): the callable writes the tombstone first, then
/// removes streams, the index row and the summary. Idempotent on the server,
/// so a repeated push after a lost answer is safe. Throws on any failure; the
/// sync layer keeps the local tombstone and retries at the next pass.
///
/// Remediation J2: the request carries `expectedUid` (the account the pass was
/// captured for). A null uid throws [ConsentAccountChangedException] before any
/// network call, and the server's `failed-precondition` / `account_changed`
/// refusal is mapped to the same exception, so the sync layer treats it as a
/// stopped pass, not as a failed push.
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import 'activity_cloud_settings_client.dart'
    show ConsentAccountChangedException, isAccountChangedRefusal;

class CloudFunctionsActivityTombstonePusher {
  CloudFunctionsActivityTombstonePusher({FirebaseFunctions? functions})
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  Future<void> push(String activityId, String? expectedUid) async {
    if (expectedUid == null) throw const ConsentAccountChangedException();
    final callable = _functions.httpsCallable('deleteActivity');
    try {
      await callable.call<Map<String, dynamic>>(
          {'activityId': activityId, 'expectedUid': expectedUid});
    } on FirebaseFunctionsException catch (e) {
      if (isAccountChangedRefusal(e)) {
        throw const ConsentAccountChangedException();
      }
      rethrow;
    }
  }
}
