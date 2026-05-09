import 'package:cloud_functions/cloud_functions.dart';
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
            FirebaseFunctions.instanceFor(region: 'us-central1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  @override
  Future<void> submit(EquipmentReport report) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw EquipmentReportException('Not signed in.');
    }
    await user.getIdToken(true);

    final callable = _functions.httpsCallable('reportEquipment');
    try {
      await callable.call<Map<String, dynamic>>(report.toJson());
    } on Exception catch (e) {
      throw EquipmentReportException('Could not submit report: $e');
    }
  }
}
