import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'account_deletion_service.dart';

/// Production impl. Calls the `deleteAccount` Cloud Function.
///
/// Same cached-token-then-one-retry pattern as
/// `CloudFunctionsEquipmentReportService` (N4): a forced token refresh on
/// every call costs a round trip against a shared Google token endpoint for a
/// token that is usually still valid, and fails the button whenever that
/// extra call does. The one error a genuinely stale token produces is
/// `unauthenticated`, which is exactly the case this retries.
class CloudFunctionsAccountDeletionService implements AccountDeletionService {
  CloudFunctionsAccountDeletionService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AccountDeletionException('Not signed in.');
    }

    final callable = _functions.httpsCallable('deleteAccount');
    try {
      // getIdToken() moved inside the try, unlike its sibling in
      // CloudFunctionsEquipmentReportService (N4), which this otherwise
      // mirrors. There a FirebaseAuthException from the cached-token read
      // would have bypassed the mapping below and shown raw plugin text on
      // an equipment report; here the same gap sits in front of the one
      // irreversible action in the app, which is where it was caught and is
      // worth the one line of divergence from the pattern it copies.
      await user.getIdToken();
      await callable.call<Map<String, dynamic>>();
    } on FirebaseFunctionsException catch (e) {
      if (e.code != 'unauthenticated') {
        throw AccountDeletionException(
          e.message ?? 'Could not delete your account.',
        );
      }
      try {
        await user.getIdToken(true);
        await callable.call<Map<String, dynamic>>();
      } on FirebaseFunctionsException catch (e) {
        throw AccountDeletionException(
          e.message ?? 'Could not delete your account.',
        );
      }
    } on FirebaseAuthException catch (e) {
      throw AccountDeletionException(
        e.message ?? 'Could not verify your sign-in. Please try again.',
      );
    }
  }
}
