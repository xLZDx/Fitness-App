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

/** `ai_gateway.ts:312` -- the per-call structured observability event. */
export const AI_GATEWAY_CALL_EVENT = "ai_gateway: call";

/** `abuse_guard.ts:103` -- a caller was refused for exceeding its daily quota. */
export const QUOTA_EXCEEDED_EVENT = "quota exceeded";

/**
 * `abuse_guard.ts:124` -- the quota-enforcement check itself failed (fails
 * closed), distinct from `QUOTA_EXCEEDED_EVENT`: this is the backend being
 * unable to evaluate the quota at all, not a caller legitimately over it.
 */
export const QUOTA_CHECK_FAILED_EVENT = "quota check failed";

/** `canary_schedule.ts` -- the Step 9B production canary's scheduled run failed. */
export const CANARY_PROBE_FAILED_EVENT = "production canary probe failed";

/**
 * `enforcement_state_schedule.ts` -- MVP1.G3 Step 10A's live production
 * enforcement-state check found at least one section it could not read
 * (DEGRADED) or could read none at all (FAILED). Never fires for a clean
 * read -- silence is the "everything visible and enforced as expected" case,
 * exactly like every other monitor in this module.
 */
export const ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT =
  "enforcement state check degraded or failed";

/**
 * `abuse_guard.ts` -- MVP1.G4 Step 8's kill switch. A caller was refused
 * because the `ai-gateway-kill-switch` Secret Manager secret's latest version
 * decodes to `enabled: false` -- a deliberate operator disable. Distinct from
 * `AI_GATEWAY_CONTROL_READ_FAILED_EVENT`: this fires when the control plane
 * answered "disabled", not when it could not be consulted at all. (Round 1 of
 * this step used a Firestore document, `system/aiGateway`; superseded by
 * Secret Manager after GPT-PM's review found the runtime identity could
 * write back to a Firestore-backed switch -- see `abuse_guard.ts`'s own doc
 * comment on `enforceAiGatewayEnabled`.)
 */
export const AI_GATEWAY_DISABLED_REJECT_EVENT = "ai gateway disabled: call refused";

/**
 * `abuse_guard.ts` -- the kill-switch control secret itself could not be
 * consulted: a Secret Manager error (including a disabled/destroyed
 * version), an empty payload, or a payload that failed to parse as JSON.
 * Fails the same way as a deliberate disable -- an unreadable control plane
 * must never be silently treated as "enabled" -- but logged separately so an
 * operator can tell "I turned this off on purpose" apart from "the control
 * plane broke."
 */
export const AI_GATEWAY_CONTROL_READ_FAILED_EVENT = "ai gateway control read failed";
