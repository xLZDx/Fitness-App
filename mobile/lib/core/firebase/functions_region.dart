import 'package:cloud_functions/cloud_functions.dart';

/// The region every Cloud Function in this project is deployed to.
///
/// One constant instead of the string literal that used to be repeated in six
/// service classes (account deletion, donor wall, clip URLs, equipment
/// reports, marketplace, Stripe checkout). That duplication is why the region
/// mismatch behind this change went unnoticed for so long: nothing tied the
/// six copies to the server's own `REGION` in `functions/src/scaling.ts`, so
/// there was no single place where "the client calls X, the server lives in
/// Y" could be read off.
///
/// Must match `REGION` in `functions/src/scaling.ts`. A mismatch does not fail
/// at build time — it fails at call time, as `NOT_FOUND` on every callable,
/// because the SDK builds the endpoint URL from this value.
const kFunctionsRegion = 'europe-west1';

/// Shared handle for the region above.
///
/// Not a singleton by choice — `FirebaseFunctions.instanceFor` already returns
/// a cached instance per (app, region), so calling this repeatedly is free.
FirebaseFunctions get functionsForRegion =>
    FirebaseFunctions.instanceFor(region: kFunctionsRegion);
