/**
 * Invocation-bound identity of the activity callables (S02 design 17 item 25).
 *
 * The client names the account it believes it is acting for in `expectedUid`;
 * the handler compares it with `request.auth.uid` BEFORE anything else happens.
 * This guards an honest client that races its own sign-in transition (account A
 * starts a call, the Firebase user flips to B before the token is read). It is a
 * consistency check, NOT the authorization boundary: authorization stays
 * `request.auth`, and a hostile client can send whatever it likes.
 *
 * Pure: no I/O, no logging. The caller logs the outcome (never a uid).
 */

/** Longest accepted `expectedUid` (Firebase uids are at most 128 characters). */
export const EXPECTED_UID_MAX_LENGTH = 128;

/** The request key that carries the initiating account. */
export const EXPECTED_UID_KEY = "expectedUid";

/** `invalid_request`: key missing or malformed; `account_changed`: it names another account. */
export type ExpectedUidFailure = "invalid_request" | "account_changed";

/** A failed binding check; `code` is the only thing the handler maps. */
export class ExpectedUidError extends Error {
  constructor(readonly code: ExpectedUidFailure) {
    super(code);
    this.name = "ExpectedUidError";
  }
}

/**
 * Verifies `data.expectedUid === uid` and returns a shallow copy of `data`
 * WITHOUT that key, so the strict request parsers never see it. Non-object data
 * (null, array, primitive) is returned unchanged so the handler's own parser
 * refuses it with its existing error.
 */
export function verifyExpectedUid(uid: string, data: unknown): unknown {
  if (typeof data !== "object" || data === null || Array.isArray(data)) return data;
  const { [EXPECTED_UID_KEY]: expected, ...rest } = data as Record<string, unknown>;
  if (typeof expected !== "string" || expected.length === 0 || expected.length > EXPECTED_UID_MAX_LENGTH) {
    throw new ExpectedUidError("invalid_request");
  }
  if (expected !== uid) throw new ExpectedUidError("account_changed");
  return rest;
}
