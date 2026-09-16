import 'package:cloud_functions/cloud_functions.dart';

import '../../core/firebase/functions_region.dart';

/// A3 — the server half of the GDPR export.
///
/// The client can assemble profile, workouts, schedule, programmes and photo
/// metadata on its own, and does. It cannot assemble the rest: `debug_sessions`
/// is `allow read: if false` in `firestore.rules`, and `coach_bookings` /
/// `equipment_reports` have no client query for "all of mine". Those live
/// behind the `exportAccountData` callable, which runs with Admin credentials.
///
/// Returns `null` rather than throwing when the call fails. The export that
/// survives is the local one, marked incomplete — the same choice the photo
/// timeout already makes, and for the same reason: a partial export a user can
/// read beats an error they cannot.
abstract class ServerExport {
  Future<Map<String, dynamic>?> fetch();
}

class CloudFunctionsServerExport implements ServerExport {
  CloudFunctionsServerExport({FirebaseFunctions? functions})
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    try {
      final res = await _functions
          .httpsCallable('exportAccountData')
          .call<Map<String, dynamic>>()
          .timeout(const Duration(seconds: 20));
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      // One error class is not "there is no server part": a stale token means
      // the user must sign in again, and the export file's own note would tell
      // them to "re-run the export", which fails identically every time. Let
      // it out so the export reports a failure the user can actually act on.
      if (e.code == 'unauthenticated') rethrow;
      return null;
    } catch (_) {
      // Everything else stays opaque: the caller only needs "there is no
      // server part", and the failure is already logged server-side with the
      // uid that produced it.
      return null;
    }
  }
}

/// Test double. Returns whatever it was constructed with.
class FakeServerExport implements ServerExport {
  FakeServerExport([this.payload]);

  final Map<String, dynamic>? payload;
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    calls++;
    return payload;
  }
}
