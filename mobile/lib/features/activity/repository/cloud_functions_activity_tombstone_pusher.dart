/// Pushes a local activity delete to the server through the `deleteActivity`
/// callable (S02 design 6.2): the callable writes the tombstone first, then
/// removes streams, the index row and the summary. Idempotent on the server,
/// so a repeated push after a lost answer is safe. Throws on any failure; the
/// sync layer keeps the local tombstone and retries at the next pass.
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';

class CloudFunctionsActivityTombstonePusher {
  CloudFunctionsActivityTombstonePusher({FirebaseFunctions? functions})
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  Future<void> push(String activityId) async {
    final callable = _functions.httpsCallable('deleteActivity');
    await callable.call<Map<String, dynamic>>({'activityId': activityId});
  }
}
