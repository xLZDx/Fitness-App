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
    // canary_probe.ts's own FIREBASE_WEB_API_KEY comment for why this is
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
