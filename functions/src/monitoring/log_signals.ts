/**
 * Single source of truth for the log message literals that a monitor
 * definition (see `alert_definitions.ts`) keys on. Production code imports
 * these constants instead of retyping the string, so renaming a message
 * here is a compile error at every call site instead of a monitor that
 * silently stops matching (the "drift guard" GPT-PM required at Rosetta
 * closure review for Step 9 groundwork, MVP1.G3 Step 9 groundwork DoD,
 * 2026-08-27).
 */

export const STRIPE_RECONCILE_DUPLICATE_FOUND = "duplicate subscriptions found";
export const STRIPE_RECONCILE_CANCEL_OK = "cancelled duplicate subscription";
export const STRIPE_RECONCILE_CANCEL_FAILED =
  "could not cancel duplicate subscription";
export const STRIPE_RECONCILE_FAILED = "duplicate reconciliation failed";

export const DELETE_ACCOUNT_STRIPE_CANCEL_FAILED =
  "account deletion: failed to cancel subscription";
export const DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED =
  "account deletion: failed to delete Firestore data";
export const DELETE_ACCOUNT_AUTH_DELETE_FAILED =
  "account deletion: failed to delete the Auth user";

export const EXPORT_ACCOUNT_FAILED = "account export failed";

/**
 * `firebase-functions/lib/common/providers/https.js:570` — every `onCall`
 * handler invocation is wrapped in one try/catch; anything the handler
 * throws that is not already an `HttpsError` is logged under this exact
 * message before being converted to a generic `HttpsError("internal", ...)`
 * for the client. `HttpsError` is how every EXPECTED refusal in this
 * codebase is thrown (unauthenticated, quota, App Check), so this message
 * only fires for a genuinely unclassified failure -- the platform-level
 * backstop for any failure path a function's own explicit catch blocks do
 * not name. See `functions/src/monitoring/README.md` for the audit that
 * established this for `deleteAccount` and `exportAccountData`.
 */
export const PLATFORM_UNHANDLED_ERROR = "Unhandled error";

/** `abuse_guard.ts:66` -- `noteAppCheck`'s structured attestation event. */
export const APP_CHECK_EVENT = "appcheck";
