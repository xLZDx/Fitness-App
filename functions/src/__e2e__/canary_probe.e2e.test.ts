/**
 * MVP1.G3 Step 9A — the canary auth→Firestore probe, proven against real
 * Auth + Firestore emulators, not the rules-unit-testing harness.
 *
 * `firestore_rules.test.ts` (commit `6e91b10`) already proves the RULES
 * accept/deny the right shapes, using `@firebase/rules-unit-testing`'s
 * `authenticatedContext` — a simulated auth context that never goes through
 * a real Auth token exchange. GPT-PM's Step 9A DoD is explicit that this is
 * NOT sufficient proof for this item: "rules-unit tests are presented as
 * proof of the Auth exchange" is a listed rejection condition. This suite
 * exists to prove the thing `firestore_rules.test.ts` cannot: that
 * `admin.auth().createCustomToken()` → the real Firebase Client SDK's
 * `signInWithCustomToken()` → a real ID token → a real authenticated
 * Firestore client request, actually round-trips end to end.
 *
 *     npm --prefix functions run test:e2e
 *
 * Known, non-blocking: running this suite prints "Jest did not exit one
 * second after the test run has completed" even though every test passes
 * and the wrapper script still exits 0. Isolated live (temporarily removing
 * this file made the warning disappear; `account_deletion.e2e.test.ts` alone
 * exits clean) to confirm it originates here, not upstream. A documented
 * quirk of the Firebase JS Auth SDK's Node platform binding — its internal
 * token-refresh timer has no public teardown call, unlike Firestore's own
 * `terminate()` (used in both `canary_probe.ts` and this file's `signInAs`
 * to close the gRPC channel explicitly, which DID fix a real leak — this
 * remaining warning is Auth-side, not Firestore-side). Confined to the test
 * PROCESS failing to exit promptly; it says nothing about the deployed
 * function's runtime, since a Cloud Functions container is a fresh process
 * per cold start regardless.
 */
import * as admin from "firebase-admin";
// Side effect only: `index.ts` calls `admin.initializeApp()` at module load
// (see `jest.e2e.setup.js`'s own comment) -- `canary_probe.ts` itself does
// not, matching every other module in this codebase that assumes `index.ts`
// already ran. Not re-exported from `index.ts` itself (deliberately, per
// GPT-PM's "not a public endpoint" requirement), so nothing here is reachable
// through it -- this import exists only for the initialization side effect.
import "../index";
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInWithCustomToken,
  signOut,
} from "firebase/auth";
import {
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  setDoc,
  terminate,
} from "firebase/firestore";
import { CANARY_UID, runCanaryProbe } from "../canary_probe";

const db = admin.firestore();

/** Independent of `canary_probe.ts`'s own internals — a second, freshly-built
 * client identity, so a bug that only manifests on a SECOND app instance (a
 * stale connection, a leaked listener) is not hidden by reusing the probe's
 * own app. Mirrors `canary_probe.ts`'s own emulator-detection so it talks to
 * the same emulators `npm run test:e2e` already starts. */
async function signInAs(uid: string, claims: Record<string, unknown>) {
  const app: FirebaseApp = initializeApp(
    // Any non-empty apiKey satisfies the SDK against the emulator -- see
    // canary_probe.ts's own CANARY_WEB_API_KEY comment for why this is
    // required at all and why it must NOT be reused as-is against production.
    { apiKey: "demo-emulator-key", projectId: process.env.GCLOUD_PROJECT },
    `test-client-${uid}-${Math.random().toString(36).slice(2)}`,
  );
  const auth = getAuth(app);
  const clientDb = getFirestore(app);
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "").split(":");
  connectFirestoreEmulator(clientDb, host, Number(port));
  connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, {
    disableWarnings: true,
  });
  const token = await admin.auth().createCustomToken(uid, claims);
  await signInWithCustomToken(auth, token);
  return {
    db: clientDb,
    async close() {
      await signOut(auth).catch(() => undefined);
      await terminate(clientDb).catch(() => undefined);
      await deleteApp(app).catch(() => undefined);
    },
  };
}

async function wipeCanaryNamespace(): Promise<void> {
  await db.recursiveDelete(db.collection("_canary"));
  for (const uid of [CANARY_UID, "canary-negative-uid", "other-canary-uid"]) {
    await admin
      .auth()
      .deleteUser(uid)
      .catch(() => undefined);
  }
}

beforeEach(async () => {
  await wipeCanaryNamespace();
});

afterAll(async () => {
  await wipeCanaryNamespace();
  await admin.app().delete();
});

describe("runCanaryProbe — the real thing, end to end", () => {
  test("a full run mints, exchanges, writes, reads back, deletes, and verifies deletion", async () => {
    const result = await runCanaryProbe();

    expect(result.success).toBe(true);
    expect(result.failureClass).toBeUndefined();
    expect(result.latencyMs).toBeGreaterThanOrEqual(0);
    // Delete succeeded inside the probe itself -- nothing left for the
    // fail-safe cleanup path to do.
    expect(result.cleanupAttempted).toBe(false);
    expect(result.cleanupSucceeded).toBe(true);

    // Independent confirmation, via the Admin SDK, that nothing was left
    // behind -- not just trusting the probe's own self-report.
    const snap = await db.doc(`_canary/${CANARY_UID}`).get();
    expect(snap.exists).toBe(false);
  });

  test("no token/credential/document payload appears anywhere in the result", () => {
    // Static shape check, not a runtime one: the whole POINT is that these
    // fields must never exist on the type, not merely be empty at runtime.
    // (If this file fails to compile because a future edit adds one of
    // these keys to CanaryProbeResult, that IS this test doing its job.)
    const result: Awaited<ReturnType<typeof runCanaryProbe>> = {
      success: true,
      latencyMs: 1,
      cleanupAttempted: false,
      cleanupSucceeded: true,
    };
    expect(result).not.toHaveProperty("token");
    expect(result).not.toHaveProperty("idToken");
    expect(result).not.toHaveProperty("customToken");
    expect(result).not.toHaveProperty("document");
    expect(result).not.toHaveProperty("data");
  });

  test("a failure after a successful write still leaves no residue -- cleanup actually runs", async () => {
    const result = await runCanaryProbe({ injectFailureAfterWrite: true });

    expect(result.success).toBe(false);
    expect(result.stage).toBe("FIRESTORE_WRITE");
    expect(result.cleanupAttempted).toBe(true);
    expect(result.cleanupSucceeded).toBe(true);

    const snap = await db.doc(`_canary/${CANARY_UID}`).get();
    expect(snap.exists).toBe(false);
  });

  // GPT-PM's first remediation round (2026-08-27): a hung step must not
  // become a hung function. This is a real 15s wait, not a mocked one --
  // the whole point is proving `runCanaryProbe()` actually returns within
  // its own advertised budget against the real per-step timeout mechanism,
  // not that the mechanism is merely reasoned about in a comment.
  test(
    "a write that never resolves times out -- the function returns within budget, not indefinitely",
    async () => {
      const before = Date.now();
      const result = await runCanaryProbe({ injectNeverResolvingWrite: true });
      const wallClockMs = Date.now() - before;

      expect(result.success).toBe(false);
      expect(result.stage).toBe("FIRESTORE_WRITE");
      expect(result.failureClass).toBe("TIMEOUT");
      // PROBE_TIMEOUT_MS (15s) plus real margin for the cleanup/teardown
      // that still runs afterward -- comfortably under OVERALL_HARD_
      // DEADLINE_MS (45s), which is the actual guarantee this test exists
      // to prove is real and not just documented.
      expect(wallClockMs).toBeLessThan(30_000);
    },
    35_000,
  );

  test("missing CANARY_WEB_API_KEY outside emulator mode is refused immediately, not silently substituted", async () => {
    // Temporarily simulate "this is not an emulator run": the whole point of
    // GPT-PM's second finding was that the OLD code could not tell the
    // difference and would run anyway with a fake key. Restored in `finally`
    // so every other test in this file keeps talking to the real emulators.
    const savedFirestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
    const savedAuthHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const savedWebApiKey = process.env.CANARY_WEB_API_KEY;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
    delete process.env.CANARY_WEB_API_KEY;
    try {
      const before = Date.now();
      const result = await runCanaryProbe();
      const wallClockMs = Date.now() - before;

      expect(result.success).toBe(false);
      expect(result.failureClass).toBe("CONFIG");
      expect(result.stage).toBeUndefined(); // never even reached TOKEN_MINT
      expect(result.cleanupAttempted).toBe(false); // nothing was ever created
      expect(result.cleanupSucceeded).toBe(true);
      // Refused essentially instantly -- no network call was ever attempted.
      expect(wallClockMs).toBeLessThan(1_000);
    } finally {
      if (savedFirestoreHost !== undefined) {
        process.env.FIRESTORE_EMULATOR_HOST = savedFirestoreHost;
      }
      if (savedAuthHost !== undefined) {
        process.env.FIREBASE_AUTH_EMULATOR_HOST = savedAuthHost;
      }
      if (savedWebApiKey !== undefined) process.env.CANARY_WEB_API_KEY = savedWebApiKey;
    }
  });

  test("emulator mode still works with no CANARY_WEB_API_KEY set -- the placeholder path is unaffected", async () => {
    // The fix must not have broken the common case: no real key is ever
    // configured in this test suite, and every other test in this file
    // already proves the emulator path succeeds. This test exists only to
    // pin that emulator-mode detection, not "any key present", is what
    // permits the placeholder -- distinguishing it from the test above.
    expect(process.env.CANARY_WEB_API_KEY).toBeUndefined();
    expect(process.env.FIRESTORE_EMULATOR_HOST).toBeDefined();
    const result = await runCanaryProbe();
    expect(result.success).toBe(true);
    expect(result.failureClass).toBeUndefined();
  });

  // GPT-PM's second remediation round (2026-08-27): the first fix's OR
  // check accepted the placeholder key when only ONE of the two emulator
  // host vars was set -- meaning the OTHER service would have pointed at
  // real production while this probe believed it was running safely against
  // an emulator. Both tests below prove each PARTIAL configuration is
  // refused, not just the "neither set" case already covered above.
  test("only FIRESTORE_EMULATOR_HOST set (Auth would be real) is refused as CONFIG", async () => {
    const savedAuthHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const savedWebApiKey = process.env.CANARY_WEB_API_KEY;
    delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
    delete process.env.CANARY_WEB_API_KEY;
    try {
      expect(process.env.FIRESTORE_EMULATOR_HOST).toBeDefined();
      expect(process.env.FIREBASE_AUTH_EMULATOR_HOST).toBeUndefined();

      const result = await runCanaryProbe();

      expect(result.success).toBe(false);
      expect(result.failureClass).toBe("CONFIG");
      expect(result.stage).toBeUndefined();
      expect(result.cleanupAttempted).toBe(false);
    } finally {
      if (savedAuthHost !== undefined) {
        process.env.FIREBASE_AUTH_EMULATOR_HOST = savedAuthHost;
      }
      if (savedWebApiKey !== undefined) process.env.CANARY_WEB_API_KEY = savedWebApiKey;
    }
  });

  test("only FIREBASE_AUTH_EMULATOR_HOST set (Firestore would be real) is refused as CONFIG", async () => {
    const savedFirestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
    const savedWebApiKey = process.env.CANARY_WEB_API_KEY;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.CANARY_WEB_API_KEY;
    try {
      expect(process.env.FIRESTORE_EMULATOR_HOST).toBeUndefined();
      expect(process.env.FIREBASE_AUTH_EMULATOR_HOST).toBeDefined();

      const result = await runCanaryProbe();

      expect(result.success).toBe(false);
      expect(result.failureClass).toBe("CONFIG");
      expect(result.stage).toBeUndefined();
      expect(result.cleanupAttempted).toBe(false);
    } finally {
      if (savedFirestoreHost !== undefined) {
        process.env.FIRESTORE_EMULATOR_HOST = savedFirestoreHost;
      }
      if (savedWebApiKey !== undefined) process.env.CANARY_WEB_API_KEY = savedWebApiKey;
    }
  });
});

describe("runCanaryProbe — negative proofs (the real client path denies what it must)", () => {
  test("a token with no canary claim is denied on _canary/", async () => {
    const client = await signInAs("canary-negative-uid", {});
    try {
      await expect(
        setDoc(doc(client.db, "_canary", "canary-negative-uid"), { probe: true }),
      ).rejects.toMatchObject({ code: "permission-denied" });
      await expect(
        getDoc(doc(client.db, "_canary", "canary-negative-uid")),
      ).rejects.toMatchObject({ code: "permission-denied" });
    } finally {
      await client.close();
    }
  });

  test("a valid canary identity cannot reach a DIFFERENT canary uid's document", async () => {
    const client = await signInAs(CANARY_UID, { canary: true });
    try {
      await expect(
        setDoc(doc(client.db, "_canary", "other-canary-uid"), { probe: true }),
      ).rejects.toMatchObject({ code: "permission-denied" });
    } finally {
      await client.close();
    }
  });

  test("a valid canary identity is denied on an ordinary /users/{uid}/... path", async () => {
    const client = await signInAs(CANARY_UID, { canary: true });
    try {
      await expect(
        setDoc(doc(client.db, "users", CANARY_UID, "workout_logs", "w1"), {
          exercise: "squat",
        }),
      ).rejects.toMatchObject({ code: "permission-denied" });
    } finally {
      await client.close();
    }
  });
});
