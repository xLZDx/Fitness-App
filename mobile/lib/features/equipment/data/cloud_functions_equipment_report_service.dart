import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'equipment_report.dart';
import 'equipment_report_service.dart';

/// Production impl. Calls the `reportEquipment` Cloud Function which
/// writes to `equipment_reports/{id}` in Firestore and dispatches a
/// webhook to whatever endpoint the gym chain registered (Slack /
/// Teams / email / custom). Same auth-token pattern as the Stripe
/// service: force-refresh the user's ID token before the callable so
/// stale anonymous tokens never surface as UNAUTHENTICATED.
class CloudFunctionsEquipmentReportService implements EquipmentReportService {
  CloudFunctionsEquipmentReportService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _functions = functions ??
            functionsForRegion,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  @override
  Future<void> submit(EquipmentReport report) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw EquipmentReportException('Not signed in.');
    }
    // The cached token, not a forced refresh. `getIdToken(true)` on every
    // call cost a second round trip against a shared Google token endpoint
    // for a token that was usually still valid for the best part of an hour,
    // and made this button fail whenever that extra call did. The stale-token
    // case is answered where it actually shows up, below.
    await user.getIdToken();

    final callable = _functions.httpsCallable('reportEquipment');
    try {
      await callable.call<Map<String, dynamic>>(report.toJson());
    } on FirebaseFunctionsException catch (e) {
      if (e.code != 'unauthenticated') {
        throw EquipmentReportException('Could not submit report: $e');
      }
      // One retry, on the one error a stale token produces.
      try {
        await user.getIdToken(true);
        await callable.call<Map<String, dynamic>>(report.toJson());
      } on Exception catch (e) {
        throw EquipmentReportException('Could not submit report: $e');
      }
    } on Exception catch (e) {
      throw EquipmentReportException('Could not submit report: $e');
    }
  }
}
