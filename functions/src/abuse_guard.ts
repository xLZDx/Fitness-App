import * as admin from "firebase-admin";
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  APP_CHECK_EVENT,
  QUOTA_EXCEEDED_EVENT,
  QUOTA_CHECK_FAILED_EVENT,
  AI_GATEWAY_DISABLED_REJECT_EVENT,
  AI_GATEWAY_CONTROL_READ_FAILED_EVENT,
} from "./monitoring/log_signals";

/**
 * A6-lite — the two cheap halves of abuse protection: see whether App Check is
 * actually being used, and stop one account draining a metered resource.
 *
 * Why this exists as its own module rather than inside `index.ts`: `video_urls`
 * needs it too, and that file is deliberately separate ("the one part that
 * exists to satisfy a contract rather than a feature request").
 *
 * ## What this is NOT
 *
 * It is not App Check enforcement. Enforcement is a live-console change plus
 * `enforceAppCheck: true` per callable, and turning it on before knowing how
 * many real installs would fail the check is how a working app is taken
 * offline by a security setting. That is A6-full. This module measures first:
 * every call records whether a valid App Check token arrived, so enforcement
 * can later be switched on against a number rather than a hope.
 */

/**
 * Resolved per call, not at module load.
 *
 * `video_urls.ts` imports this module and `video_urls.test.ts` imports that
 * one directly, without `index.ts` and therefore without
 * `admin.initializeApp()`. A module-scope `admin.firestore()` made merely
 * importing the module throw "The default Firebase app does not exist" — a
 * side effect on import is a dependency nobody declared.
 */
const db = () => admin.firestore();

/**
 * Logs whether this call carried a valid App Check token.
 *
 * `request.app` is populated by the runtime only when a token was sent AND it
 * verified — so an absent `app` means "unattested caller", which today is
 * allowed. The audit of 2026-08-11 found App Check `UNENFORCED` on every
 * service and `enforceAppCheck` absent from every function, so the true
 * proportion of unattested traffic is currently unknown. This is what makes it
 * knowable.
 *
 * Deliberately `logger.info`, not `warn`: at this stage an unattested call is
 * the expected state, and warning on the normal case trains the reader to
 * ignore the field. It becomes a warning when enforcement is staged.
 */
export function noteAppCheck(request: CallableRequest, fn: string): void {
  // No uid. The measurement this line exists for is "what share of calls
  // attest", and `fn` plus `attested` answers it completely -- the uid was
  // the one field it did not need.
  //
  // It was also the one field that could not be deleted. Cloud Logging sits
  // outside `users/{uid}`, so `deleteAccount`'s `recursiveDelete` never
  // reaches it, and its retention is the logging bucket's rather than the
  // account's. `public/privacy.html:88` promises there is "no separate
  // retention timer and no archive copy kept afterwards", and the function
  // twelve lines below this one stores quota under the user document ON
  // PURPOSE for exactly that reason. This line was doing the opposite in the
  // same file.
  //
  // Found by the privacy lens of the N-05 council, which also named why it
  // mattered more than it looked: N-05's Option 1 turns this from incidental
  // noise over 5-10 testers into a load-bearing dataset over a real Play
  // population. Removing it now costs nothing and later would be a migration.
  logger.info(APP_CHECK_EVENT, { fn, attested: request.app !== undefined });
}

/**
 * Per-user, per-day ceiling on a metered action.
 *
 * Stored at `users/{uid}/usage/{yyyy-mm-dd}` — under the user document ON
 * PURPOSE, so `deleteAccount`'s `recursiveDelete(users/{uid})` already erases
 * it and `core/DATA_INVENTORY_2026-08-11.md` does not gain a new orphan the
 * day this ships. A top-level `usage/{uid}` collection would have been the
 * fourth entry on that list.
 *
 * A transaction, not `FieldValue.increment`: the limit has to be read and
 * compared in the same atomic step it is written, or two concurrent calls both
 * read 499 and both proceed.
 *
 * @throws HttpsError('resource-exhausted') when the day's limit is reached.
 */
export async function enforceDailyQuota(
  uid: string,
  action: string,
  limit: number,
  cost = 1,
): Promise<void> {
  // UTC day, not the caller's local day. A device clock is attacker-controlled
  // and a timezone is not worth a second read; the cost is that the window
  // rolls at midnight UTC rather than midnight local, which for a ceiling this
  // size nobody legitimate will ever notice.
  const day = new Date().toISOString().slice(0, 10);
  const ref = db().doc(`users/${uid}/usage/${day}`);

  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.data()?.[action] as number | undefined) ?? 0;
      if (used + cost > limit) {
        logger.warn(QUOTA_EXCEEDED_EVENT, { uid, action, used, cost, limit });
        throw new HttpsError(
          "resource-exhausted",
          "You have reached today's limit for this action. It resets tomorrow.",
        );
      }
      tx.set(
        ref,
        { [action]: used + cost, updatedAt: new Date().toISOString() },
        { merge: true },
      );
    });
  } catch (e) {
    // The quota refusal above is already logged with everything needed to read
    // it, so it passes through untouched. Anything else -- Firestore
    // unavailable, contention retries exhausted -- used to leave this module
    // with zero log lines carrying the uid or the action, which is the one
    // failure here nobody could diagnose afterwards. It stays fail-CLOSED: the
    // transaction is atomic, so nothing was charged, and the caller does not
    // get its metered resource.
    if (e instanceof HttpsError) throw e;
    logger.error(QUOTA_CHECK_FAILED_EVENT, { uid, action, cost, limit, err: String(e) });
    throw new HttpsError("internal", "Could not check your usage limit.");
  }
}

/**
 * MVP1.G4 Step 8 -- the server-side kill switch for the four AI Gateway
 * callables. GPT-PM's binding DoD for this step (2026-08-29): a runtime
 * control an operator can flip live, "without a function redeploy", that a
 * "process restart/new instance must observe... rather than reverting to
 * enabled."
 *
 * Secret Manager-backed, not Firestore and not an env var. The first version
 * of this used a Firestore document -- GPT-PM's round-1 review of this same
 * step found that fundamentally unsound: `fn-ai-runtime` (the identity
 * running the very code being disabled) already holds project-wide
 * `roles/datastore.user` for quota accounting (`core/G4_STEP3_IAM_RUNTIME_
 * CONFIG_2026-08-28.md`), and Firestore has no collection-level IAM -- that
 * grant cannot be narrowed to exclude one document. `firestore.rules` does
 * not help either; the Admin SDK bypasses Security Rules entirely. So a
 * compromised or buggy `fn-ai-runtime` could simply write `enabled: true`
 * back to its own kill switch, defeating the one property this mechanism
 * exists for: an operator being able to turn AI off From The Outside.
 *
 * Secret Manager grants IAM per-secret, independent of Firestore's project
 * -wide grant. `fn-ai-runtime` holds `roles/secretmanager.secretAccessor`
 * scoped to exactly this one secret (`ai-gateway-kill-switch`) -- read-only,
 * verified by IAM policy inspection to carry no broader Secret Manager role
 * -- and nothing grants it version-add/update rights on it. Flipping the
 * switch means adding a new secret version, which only an operator identity
 * (or a future admin tool acting on the operator's behalf) can do. This is
 * the same secret-level IAM scoping pattern `fn-billing`'s `STRIPE_*` access
 * already uses in this codebase, applied for the first time as the
 * *authoritative* control rather than a credential the function merely reads
 * for its own use.
 *
 * Not `defineSecret` (the pattern `STRIPE_SECRET_KEY` etc. use): that binds a
 * secret's value into `process.env` once per container at cold start, so an
 * already-running warm instance keeps serving the OLD value until it
 * eventually recycles -- the opposite of what a kill switch needs. This
 * calls `accessSecretVersion` directly, through a short bounded cache (below)
 * rather than on every invocation.
 *
 * GPT-PM's round-2 review found the round-1 design's "fresh read every call"
 * choice still left an unmetered path even after round 1's auth-ordering fix:
 * a valid, non-anonymous, App-Check-attested caller can send malformed
 * payloads (rejected by `parseInput`, which runs AFTER this check in every
 * callable) or keep calling after exhausting its daily quota (checked AFTER
 * this too, by the DoD's own requirement) -- every such attempt still paid a
 * real Secret Manager access with no ceiling at all, which is both a
 * per-project Secret Manager quota/cost dependency and exactly the kind of
 * unbounded read this step's own design rationale claimed didn't exist.
 * GPT-PM offered two acceptable fixes: reorder validation and add a
 * non-charging rate pre-check, or "a short bounded cache with a documented
 * maximum disable-propagation interval." The cache is simpler and closes the
 * gap completely rather than partially -- reordering `parseInput` earlier
 * would not have helped the "well-formed but already-over-quota caller
 * retries" case at all, since that caller's payload passes validation and
 * only quota (deliberately checked after this switch, per the DoD) would
 * reject it.
 */
const AI_GATEWAY_SECRET_NAME =
  "projects/988522745882/secrets/ai-gateway-kill-switch/versions/latest";

let secretClient: SecretManagerServiceClient | undefined;
function secrets(): SecretManagerServiceClient {
  // Same lazy-per-call-not-module-load reasoning as `db()` above: constructing
  // the client eagerly at import time would make merely importing this module
  // reach for ADC, which every test file importing it would then have to mock
  // whether or not that test exercises this function.
  if (!secretClient) secretClient = new SecretManagerServiceClient();
  return secretClient;
}

interface AiGatewayControl {
  enabled?: unknown;
  reason?: unknown;
}

interface ResolvedControlState {
  /** `null` exactly when `readError` is set -- the two are mutually exclusive. */
  data: AiGatewayControl | null;
  readError: string | null;
}

/**
 * Documented maximum disable-propagation interval: an operator flipping the
 * switch mid-incident is observed by any given already-warm instance within
 * this many milliseconds of the flip, not instantly -- the trade this step's
 * round-2 remediation makes in exchange for bounding how many real Secret
 * Manager accesses an unbounded caller can generate. A brand-new instance
 * (durability point 7 of the DoD) always starts with an empty cache, so its
 * very first call is always a genuine fresh read regardless of this window.
 */
const CONTROL_CACHE_TTL_MS = 5_000;

/**
 * Caches the in-flight PROMISE, not just its eventually-resolved value.
 * Caching only the resolved value still lets a burst of concurrent calls
 * stampede Secret Manager: each one checks the cache before any of them has
 * awaited far enough to populate it, so all of them see "empty" and all of
 * them fetch. Storing the promise itself closes that -- it is written
 * synchronously before the first `await`, so every concurrent caller within
 * the same tick shares the one in-flight request.
 */
let cachedControl: { promise: Promise<ResolvedControlState>; expiresAt: number } | undefined;

/**
 * Test-only escape hatch: `cachedControl` is module-scope state, so without
 * this a cache hit in one test would leak into the next test in the same
 * file (the module is `require`d once per file, not once per test). Not
 * called anywhere outside `__tests__/*.test.ts`.
 */
export function __resetAiGatewayControlCacheForTests(): void {
  cachedControl = undefined;
}

/**
 * The one place that actually calls Secret Manager, at most once per
 * `CONTROL_CACHE_TTL_MS` per warm instance regardless of caller volume.
 * `enforceAiGatewayEnabled` below still logs its own structured event on
 * EVERY call -- only the network access is throttled, not the per-call
 * observability the DoD's proof point 5 requires.
 */
function resolveControlState(): Promise<ResolvedControlState> {
  const now = Date.now();
  if (cachedControl && cachedControl.expiresAt > now) return cachedControl.promise;

  const promise = (async (): Promise<ResolvedControlState> => {
    let payload: string | undefined;
    try {
      const [version] = await secrets().accessSecretVersion({ name: AI_GATEWAY_SECRET_NAME });
      payload = version.payload?.data?.toString();
    } catch (e) {
      return { data: null, readError: String(e) };
    }
    if (!payload) {
      return { data: null, readError: "control secret payload empty" };
    }
    try {
      return { data: JSON.parse(payload) as AiGatewayControl, readError: null };
    } catch (e) {
      return { data: null, readError: `unparseable payload: ${String(e)}` };
    }
  })();
  cachedControl = { promise, expiresAt: now + CONTROL_CACHE_TTL_MS };
  return promise;
}

/**
 * @throws HttpsError('unavailable') when AI is administratively disabled, OR
 * when the control secret cannot be read/parsed at all -- an unreadable
 * control plane must never be silently treated as "enabled" (the DoD's own
 * "fail toward the safer state" requirement). Both cases use the identical
 * client-visible contract on purpose: a caller cannot distinguish "an
 * operator turned this off" from "the control plane is broken" and does not
 * need to -- only the structured log (`AI_GATEWAY_DISABLED_REJECT_EVENT` vs.
 * `AI_GATEWAY_CONTROL_READ_FAILED_EVENT`) carries that distinction, for an
 * operator reading Cloud Logging, not for the client.
 *
 * Called after the auth/non-anonymous checks but before `enforceDailyQuota`/
 * `generate` in every AI callable. GPT-PM's round-1 review found the earlier
 * "before auth" placement let an unauthenticated caller trigger a read on
 * every retry; round-2 review found auth alone did not bound a valid caller
 * retrying with bad input or past its quota either -- see
 * `resolveControlState`'s own doc comment for why a short cache, not further
 * reordering, is what actually closes that.
 */
export async function enforceAiGatewayEnabled(fn: string): Promise<void> {
  const { data, readError } = await resolveControlState();
  if (readError !== null) {
    logger.error(AI_GATEWAY_CONTROL_READ_FAILED_EVENT, { fn, err: readError });
    throw new HttpsError(
      "unavailable",
      "AI features are temporarily unavailable. Please try again later.",
    );
  }
  const enabled = data!.enabled === true;
  if (!enabled) {
    const reason = typeof data!.reason === "string" ? data!.reason : null;
    logger.warn(AI_GATEWAY_DISABLED_REJECT_EVENT, { fn, reason });
    throw new HttpsError(
      "unavailable",
      "AI features are temporarily unavailable. Please try again later.",
    );
  }
}

/**
 * Gives back part of a charge that turned out not to be used.
 *
 * `clipUrls` has to charge before it signs -- charging afterwards would let a
 * caller consume IAM signing operations for free by requesting objects that
 * fail. But a batch where half the objects do not exist would then bill the
 * user for work that never happened. This returns the difference.
 *
 * Deliberately silent on failure: a refund that fails is a user who kept a
 * charge they should not have, which is a smaller harm than turning a
 * successful prefetch into an error.
 */
export async function refundQuota(
  uid: string,
  action: string,
  amount: number,
): Promise<void> {
  if (amount <= 0) return;
  const day = new Date().toISOString().slice(0, 10);
  const ref = db().doc(`users/${uid}/usage/${day}`);
  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.data()?.[action] as number | undefined) ?? 0;
      tx.set(
        ref,
        {
          // Never below zero: a refund racing the day boundary must not hand
          // out tomorrow's budget as a negative starting balance.
          [action]: Math.max(0, used - amount),
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
    });
  } catch (e) {
    logger.warn("quota refund failed", { uid, action, amount, err: String(e) });
  }
}

/**
 * The ceilings themselves, in one place so they can be read as a policy rather
 * than found one call site at a time.
 *
 * Sized against real use, not against a round number. A user working through a
 * planned session opens on the order of ten clips; a week's offline prefetch is
 * a handful of `clipUrls` calls of up to 60 objects each. Both limits sit an
 * order of magnitude above that, so a legitimate heavy user never meets them,
 * while a script looping the whole 2,539-clip library does — which is the
 * "public storage folder" the licence prohibits, spelled differently.
 */
export const QUOTAS = {
  /** Single signed clip URLs per user per day. */
  clipUrl: 400,
  /** Objects signed through the batch endpoint per user per day. */
  clipUrlsObjects: 1200,
  /**
   * Broken-equipment reports per user per day.
   *
   * N-04. This endpoint had no ceiling at all, and it writes a document whose
   * id the client chooses and whose free-text note it also supplies — so the
   * loop that fills a bucket with ~1 MB documents costs an attacker nothing.
   * Generous against real use: filing thirty faults in one day is already an
   * implausible gym visit.
   */
  equipmentReport: 30,
  /**
   * GDPR data exports per user per day.
   *
   * N-06. Each call fans out into sixteen concurrent collection reads, each
   * bounded at MAX_ROWS + 1, and the collections it reads are ones the client
   * may write freely — so a user who seeds their own tree turns one callable
   * invocation into tens of thousands of billed reads. An export is a
   * once-in-a-while action; three a day is already indulgent.
   */
  accountExport: 3,
  /**
   * AI coach advice requests per user per day.
   *
   * G1. This is the first of four independent AI-surface quotas — one per
   * `ai_gateway.ts` callable, not a shared pool — because the four surfaces
   * have unrelated usage shapes (a coach question is a deliberate ask; an
   * equipment scan can fire once per machine in a session) and a shared pool
   * would let one surface starve another. Sized against a real workout
   * session: a handful of coach questions per visit, with room for a curious
   * user asking many more.
   */
  aiCoachAdvice: 40,
  /** AI equipment-recognition requests (camera scan) per user per day. */
  aiEquipmentRecognition: 60,
  /** AI machine-description requests per user per day. */
  aiMachineDescription: 60,
  /** AI exercise-generation requests per user per day. */
  aiExerciseGeneration: 40,
} as const;

/**
 * The share of a quota an anonymous caller gets.
 *
 * N-05, and this is a MITIGATION rather than a fix — say so plainly.
 *
 * A per-uid quota binds only if a uid costs something. An anonymous uid costs
 * nothing: the Firebase Web API key ships in the app, Identity Toolkit will
 * mint another on request, and the counter starts again at zero. Three
 * throwaway accounts covered the entire clip library under the previous
 * limits, so the module's own stated goal — that a script looping the library
 * hits the ceiling — was not being met.
 *
 * What this does: raises the number of rotations needed by 8x. What it does
 * NOT do: make rotation expensive, because nothing here can.
 *
 * The control that actually binds a caller to a real install is App Check, and
 * `APP_CHECK_ENFORCED` defaults to off — an operator/deployment decision, not
 * a code one. Refusing anonymous callers outright was the other candidate and
 * was rejected here: anonymous sign-in is a first-class login button in this
 * app, and removing video from it is a product decision that belongs to the
 * operator too. Both are recorded in the decision log rather than silently
 * chosen.
 */
export const ANONYMOUS_QUOTA_DIVISOR = 8;

/** The quota `action` allows this caller, given how they signed in. */
export function quotaFor(
  limit: number,
  signInProvider: string | undefined,
): number {
  if (signInProvider !== "anonymous") return limit;
  return Math.max(1, Math.floor(limit / ANONYMOUS_QUOTA_DIVISOR));
}

/**
 * MVP1.G4 Step 2: unlike video (where refusing anonymous callers outright was
 * rejected — see `ANONYMOUS_QUOTA_DIVISOR`'s own doc above), the 4 AI callables pay for
 * a real Vertex AI invocation per call, not bandwidth. GPT-PM's ruling on this exact
 * question (`core/G4_STEP2_APP_CHECK_BOUNDARY_2026-08-28.md`): App Check enforcement
 * does not close the anonymous-rotation exposure at all — it attests the client, not
 * the account, so a genuine attested install remains free to mint unlimited fresh
 * anonymous uids. The `ANONYMOUS_QUOTA_DIVISOR` mitigation above only raises rotation
 * cost by 8x; it does not remove it. Recommendation, adopted: require a persistent,
 * non-anonymous account for the 4 AI callables specifically at initial launch, leaving
 * every non-AI feature (including video) open to anonymous users as before.
 *
 * Default is the RESTRICTIVE state — opposite of `scaling.ts`'s `envFlag` pattern,
 * where unset/off is always the safe default. Here or unset means anonymous callers are
 * REFUSED; the flag is the escape hatch for relaxing that once real usage/cost data
 * supports it, not a way to opt into enforcement. A typo therefore fails toward the
 * more conservative behavior (blocking anonymous AI use), matching this being a
 * deliberate initial-launch policy rather than a measured rollout like App Check.
 */
export const AI_ALLOW_ANONYMOUS = process.env.AI_ALLOW_ANONYMOUS === "true";

/** Throws if this caller is anonymous and `AI_ALLOW_ANONYMOUS` has not been set. */
export function enforceNonAnonymousForAi(signInProvider: string | undefined): void {
  if (AI_ALLOW_ANONYMOUS) return;
  if (signInProvider === "anonymous") {
    throw new HttpsError(
      "permission-denied",
      "Sign in with a real account to use AI features.",
    );
  }
}
