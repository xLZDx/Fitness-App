/**
 * MVP1.G3 Step 9A — the canary auth→Firestore probe (GPT-PM's own naming,
 * `core/G3_STEP8_RUNTIME_PREREQUISITES.md` Sec 3/6.1/13).
 *
 * WHAT THIS PROVES, AND WHY IT HAS TO GO THROUGH THE REAL CLIENT PATH
 *
 * The question this probe answers is "can a real, ordinary user still reach
 * their own data through Auth and Security Rules right now" — not "is
 * Firestore reachable at all" (the Admin SDK could answer that, but it
 * bypasses Security Rules entirely, so a passing Admin-SDK probe would say
 * nothing about a rules regression that locks every real user out). So this
 * function deliberately does the more expensive, more real thing: mint a
 * custom token server-side (Admin SDK — the one thing only server code can
 * do), then EXCHANGE it for a real ID token via the Firebase Client SDK's
 * `signInWithCustomToken`, then read/write/delete through that exchanged
 * identity, the same way the mobile app's own Firestore calls do. Only the
 * Client SDK half is subject to `firestore.rules` — an Admin SDK write here
 * would prove nothing.
 *
 * WHAT THIS IS NOT
 *
 * Not a public endpoint. `runCanaryProbe()` is an internal service function
 * with a fixed, non-caller-controlled identity (`CANARY_UID`) and a fixed
 * claim (`{ canary: true }`) — nothing here accepts a uid, path, or claim
 * from a request. A generic "mint me a token for this uid" facility would be
 * a privilege-escalation primitive, not a monitor. Step 9B wires this into a
 * Cloud Scheduler job and an actual alert; this file does not create either.
 *
 * WHY IT LOOKS LIKE THE E2E SUITE'S OWN EMULATOR DETECTION
 *
 * Emulator connection is driven by the exact same env vars the Admin SDK
 * already auto-detects (`FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_
 * HOST` — see `jest.e2e.setup.js`), so this code has no test-only branch: in
 * a real deployment those vars are unset and the Client SDK talks to the
 * real services; in the e2e suite they are set and it talks to the same
 * emulators the Admin SDK half of every other e2e test already uses.
 */
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInWithCustomToken,
  signOut,
  type Auth,
} from "firebase/auth";
import {
  connectFirestoreEmulator,
  deleteDoc,
  doc,
  getDoc,
  getFirestore,
  setDoc,
  terminate,
  type Firestore,
} from "firebase/firestore";
import { randomUUID } from "crypto";

/**
 * Fixed and non-secret — see `firestore.rules`'s `isCanaryToken()`/`_canary/`
 * block and `functions/src/__rules__/firestore_rules.test.ts` (commit
 * `6e91b10`), which this probe's identity and document path must match
 * exactly. Neither the uid nor the `canary: true` claim is sensitive: a uid
 * is not a secret, and the claim is a boolean nobody could misuse without
 * already controlling this Function's own service account.
 */
export const CANARY_UID = "canary-fixed-uid";

/** Bounded on purpose — an unbounded taxonomy is not a usable log-based
 * metric dimension. Matches GPT-PM's own Step 9A DoD list exactly. */
export type CanaryFailureClass =
  | "TOKEN_MINT"
  | "AUTH_EXCHANGE"
  | "FIRESTORE_WRITE"
  | "FIRESTORE_READ"
  | "FIRESTORE_DELETE"
  | "RULES_DENIED"
  | "TIMEOUT"
  | "UNEXPECTED";

/**
 * What Step 9B's future alert will read. Deliberately carries nothing that
 * could leak a credential or another user's data: no token, no session, no
 * document payload — only classification and timing, per GPT-PM's DoD
 * ("no custom token, ID token, API key, credential, document payload, user
 * data or raw exception dump may be returned/logged").
 */
export interface CanaryProbeResult {
  success: boolean;
  latencyMs: number;
  /** The stage reached when the probe stopped, whether it succeeded or not. */
  stage?: string;
  failureClass?: CanaryFailureClass;
  /** False only when nothing needed cleaning up (the identity never even
   * authenticated, or the document was already confirmed deleted). */
  cleanupAttempted: boolean;
  cleanupSucceeded: boolean;
  cleanupFailureClass?: CanaryFailureClass;
}

/**
 * Whole-probe deadline. Bounded so a hung Auth/Firestore call cannot turn
 * into an indefinitely running invocation once Step 9B puts this on a
 * schedule — see `withTimeout` below for the honest limit of what this
 * actually guarantees.
 */
const PROBE_TIMEOUT_MS = 15_000;

/**
 * The Firebase Client SDK's `initializeAuth()` asserts an `apiKey` is present
 * on the app config before it will construct an `Auth` instance AT ALL —
 * even against the emulator, where the value is never actually checked
 * against a real Google backend (verified live against the Auth emulator:
 * any non-empty string satisfies the assertion once `connectAuthEmulator`
 * is called). Against REAL Firebase Auth, though, this has to be the
 * project's actual Web API key — an Android- or iOS-restricted key (the
 * only ones this repo currently has, in `mobile/lib/firebase_options.dart`)
 * would very likely be REJECTED by Google's own per-platform API key
 * restrictions when called from a Node.js server context with no package
 * name or bundle ID to present.
 *
 * NOT YET RESOLVED, stated rather than silently guessed: this sandboxed
 * session has no live GCP credentials to fetch or verify this project's real
 * Web API key against (same limitation `ai_gateway.ts` already documents for
 * its own Vertex location default). `FIREBASE_WEB_API_KEY` must be set to
 * that real key before this probe is ever deployed to run against
 * production Auth — the placeholder below is correct for the emulator only.
 */
const FIREBASE_WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY ?? "demo-emulator-key";

class ProbeTimeoutError extends Error {
  constructor() {
    super("canary probe step exceeded its deadline");
  }
}

/**
 * Races a step against the probe's remaining deadline. This is a LOGICAL
 * timeout, not a cancellation: unlike `ai_gateway.ts`'s `generate()`, which
 * has a request-level `AbortSignal` to actually stop the outbound call, the
 * Firebase Client SDK calls here accept no such signal. A step that times
 * out stops being AWAITED, but its underlying network call may still
 * complete in the background. Honest limit, stated rather than silently
 * assumed away — the same posture `ai_gateway.ts` documents for its own
 * location default.
 */
function withTimeout<T>(promise: Promise<T>, remainingMs: number): Promise<T> {
  if (remainingMs <= 0) return Promise.reject(new ProbeTimeoutError());
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) => {
      setTimeout(() => reject(new ProbeTimeoutError()), remainingMs);
    }),
  ]);
}

/** A Security Rules denial reads as `FirebaseError` with this code from the
 * Client SDK — distinguished from a generic Firestore failure at the same
 * stage, since "the rules deny it" and "Firestore is unreachable" call for
 * different responses from whoever reads this probe's result later. */
function classify(e: unknown, stageOnFailure: CanaryFailureClass): CanaryFailureClass {
  if (e instanceof ProbeTimeoutError) return "TIMEOUT";
  const code = (e as { code?: string } | undefined)?.code;
  if (code === "permission-denied") return "RULES_DENIED";
  return stageOnFailure;
}

function connectToEmulatorsIfConfigured(auth: Auth, db: Firestore): void {
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (firestoreHost) {
    const [host, portStr] = firestoreHost.split(":");
    connectFirestoreEmulator(db, host, Number(portStr));
  }
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (authHost) {
    connectAuthEmulator(auth, `http://${authHost}`, { disableWarnings: true });
  }
}

/** Test-only fault injection — see `RunCanaryProbeOptions` below. */
interface RunCanaryProbeOptions {
  /**
   * Test seam, not a caller-controlled identity/path/claim: throws a
   * synthetic failure immediately after the write step genuinely succeeds,
   * so the cleanup path (`finally`, below) can be proven against a REAL
   * leftover document rather than a state nothing could actually produce.
   * Never set by any production/Step-9B caller. Does not accept a uid, path,
   * or claim, so it cannot be used to target anything this probe would not
   * already touch.
   */
  injectFailureAfterWrite?: boolean;
}

/**
 * Runs one canary probe cycle: mint → exchange → write → read → delete →
 * verify, with fail-safe cleanup and a bounded result. Never throws — every
 * failure is captured in the returned `CanaryProbeResult` so a future
 * Scheduler-driven caller (Step 9B) can log/alert on it without its own
 * try/catch.
 */
export async function runCanaryProbe(
  opts: RunCanaryProbeOptions = {},
): Promise<CanaryProbeResult> {
  const startedAtMs = Date.now();
  const remaining = () => PROBE_TIMEOUT_MS - (Date.now() - startedAtMs);

  const result: CanaryProbeResult = {
    success: false,
    latencyMs: 0,
    cleanupAttempted: false,
    cleanupSucceeded: false,
  };

  // A fresh, uniquely-named app per call: initializeApp throws on a reused
  // name, and a probe that runs repeatedly (Step 9B's whole point) must
  // never collide with — or leak state into — its own previous run.
  const app: FirebaseApp = initializeApp(
    {
      apiKey: FIREBASE_WEB_API_KEY,
      projectId: process.env.GCLOUD_PROJECT ?? "fitness-app-korostelev",
    },
    `canary-probe-${randomUUID()}`,
  );
  const auth = getAuth(app);
  const db = getFirestore(app);
  connectToEmulatorsIfConfigured(auth, db);

  // Only meaningful once the canary identity has actually authenticated —
  // before that, there is no session to delete anything with, and (by
  // construction) nothing was written yet either.
  let authenticated = false;
  // Only true once a post-delete read has actually confirmed the document is
  // gone. Everything else routes through the `finally` cleanup below,
  // including "delete appeared to succeed but the document is somehow still
  // there" — deleteDoc on a non-existent document is a no-op success, so a
  // redundant cleanup attempt is always safe.
  let documentConfirmedGone = false;

  try {
    result.stage = "TOKEN_MINT";
    let customToken: string;
    try {
      customToken = await withTimeout(
        admin.auth().createCustomToken(CANARY_UID, { canary: true }),
        remaining(),
      );
    } catch (e) {
      result.failureClass = classify(e, "TOKEN_MINT");
      throw e;
    }

    result.stage = "AUTH_EXCHANGE";
    try {
      await withTimeout(signInWithCustomToken(auth, customToken), remaining());
      authenticated = true;
    } catch (e) {
      result.failureClass = classify(e, "AUTH_EXCHANGE");
      throw e;
    }

    const ref = doc(db, "_canary", CANARY_UID);
    // A fixed, non-sensitive sentinel — not a document payload worth hiding,
    // just a value the read-back step can positively confirm round-tripped.
    const sentinel = { probe: true, ranAtMs: startedAtMs };

    result.stage = "FIRESTORE_WRITE";
    try {
      await withTimeout(setDoc(ref, sentinel), remaining());
    } catch (e) {
      result.failureClass = classify(e, "FIRESTORE_WRITE");
      throw e;
    }

    if (opts.injectFailureAfterWrite) {
      result.failureClass = "UNEXPECTED";
      throw new Error("injected test failure after write (test seam, never set in production)");
    }

    result.stage = "FIRESTORE_READ";
    try {
      const snap = await withTimeout(getDoc(ref), remaining());
      if (!snap.exists() || snap.data()?.probe !== true) {
        result.failureClass = "FIRESTORE_READ";
        throw new Error("canary probe read-back did not match what was written");
      }
    } catch (e) {
      result.failureClass ??= classify(e, "FIRESTORE_READ");
      throw e;
    }

    result.stage = "FIRESTORE_DELETE";
    try {
      await withTimeout(deleteDoc(ref), remaining());
    } catch (e) {
      result.failureClass = classify(e, "FIRESTORE_DELETE");
      throw e;
    }

    result.stage = "FIRESTORE_READ";
    try {
      const postDeleteSnap = await withTimeout(getDoc(ref), remaining());
      if (postDeleteSnap.exists()) {
        result.failureClass = "FIRESTORE_DELETE";
        throw new Error("canary probe document still exists after delete");
      }
      documentConfirmedGone = true;
    } catch (e) {
      result.failureClass ??= classify(e, "FIRESTORE_READ");
      throw e;
    }

    result.success = true;
  } catch (e) {
    result.failureClass ??= classify(e, "UNEXPECTED");
    // Message-only, never the raw exception object: a Firestore/Auth SDK
    // error can carry request detail this probe's own DoD forbids logging.
    logger.warn("canary_probe: probe failed", {
      stage: result.stage,
      failureClass: result.failureClass,
      message: e instanceof Error ? e.message : String(e),
    });
  } finally {
    if (!documentConfirmedGone && authenticated) {
      result.cleanupAttempted = true;
      try {
        await deleteDoc(doc(db, "_canary", CANARY_UID));
        result.cleanupSucceeded = true;
      } catch (e) {
        result.cleanupSucceeded = false;
        result.cleanupFailureClass = classify(e, "FIRESTORE_DELETE");
        logger.error("canary_probe: cleanup failed, a synthetic document may remain", {
          uid: CANARY_UID,
        });
      }
    } else {
      // Either the document is already confirmed gone, or the identity never
      // authenticated in the first place (nothing could have been written).
      result.cleanupAttempted = false;
      result.cleanupSucceeded = true;
    }

    try {
      await signOut(auth);
    } catch {
      // Best-effort: the app instance is about to be deleted regardless.
    }
    try {
      // Closes the underlying gRPC channel explicitly. `deleteApp` alone
      // does not guarantee this — observed live while building this probe:
      // without it, Jest reported open handles after every e2e run, and
      // this function is meant to run repeatedly on a schedule (Step 9B),
      // where a leaked channel per invocation is a real, compounding cost.
      await terminate(db);
    } catch {
      // Best-effort — see below.
    }
    try {
      await deleteApp(app);
    } catch {
      // Best-effort: a leaked client app object outlives this call at worst,
      // it does not leave anything in Firestore or Auth.
    }

    result.latencyMs = Date.now() - startedAtMs;
  }

  return result;
}
