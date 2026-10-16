/**
 * P1a — the Firestore security rules, exercised against the real emulator.
 *
 * `firestore.rules` is the boundary between one user's data and everybody
 * else's, and until this file it had **no tests at all**. Every claim its
 * comments make — "server-only", "read: if false", "the user's own to read and
 * write" — was an assertion nothing checked. A rules file is also the one part
 * of this system where a single wrong character silently grants the world read
 * access to every account, and where the mistake is invisible in code review
 * because the failure is an absence of denial.
 *
 * These run against the Firestore emulator, NOT the mocked jest environment
 * the rest of `functions/src/__tests__` uses — which is why they live in their
 * own directory with their own config. Run them with:
 *
 *     npm --prefix functions run test:rules
 *
 * The Admin SDK bypasses rules entirely, so nothing here says anything about
 * what the Cloud Functions can do. That is the point: these tests describe the
 * CLIENT's reach.
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  doc,
  getDoc,
  setDoc,
  addDoc,
  collection,
  deleteDoc,
  updateDoc,
  setDoc as rawSetDoc,
  type DocumentData,
  type DocumentReference,
  deleteField,
  getDocs,
  serverTimestamp,
  Timestamp,
} from "firebase/firestore";

let env: RulesTestEnvironment;

const ALICE = "alice";
const BOB = "bob";

/** A payload matching what `debug_telemetry_sink.dart:36-40` actually sends. */
const session = (uid: string, events: unknown[] = [{ m: "hi" }]) => ({
  identity: { sha: "abc123" },
  droppedCount: 0,
  events,
  uid,
});

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-fitness-rules",
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      // 8080 is the emulator's default and what `firebase.json` and CI use.
      // Overridable because a developer machine can easily have something
      // else on that port -- Docker Desktop does, on this one -- and the
      // alternative was editing this line and `firebase.json` by hand for
      // every local run, which is how a temporary edit ends up committed.
      // Pair with FIREBASE_EMULATOR_CONFIG so both halves agree.
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});

afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const asBob = () => env.authenticatedContext(BOB).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

describe("per-user data", () => {
  test("a user reads and writes their own documents", async () => {
    const db = asAlice();
    await assertSucceeds(
      setDoc(doc(db, `users/${ALICE}/profile/main`), { goal: "strength" }),
    );
    await assertSucceeds(getDoc(doc(db, `users/${ALICE}/profile/main`)));
  });

  test("a user cannot read another user's documents", async () => {
    // The single most important assertion in this file.
    await assertFails(getDoc(doc(asBob(), `users/${ALICE}/profile/main`)));
  });

  test("a user cannot write another user's documents", async () => {
    await assertFails(
      setDoc(doc(asBob(), `users/${ALICE}/workout_logs/l1`), { reps: 8 }),
    );
  });

  test("signed out reaches nothing", async () => {
    await assertFails(getDoc(doc(signedOut(), `users/${ALICE}/profile/main`)));
  });

  test("nested subcollection documents are covered too", async () => {
    // The rule uses `{document=**}`; if that recursion were dropped, deep
    // paths would fall through to default-deny for the OWNER as well.
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/programmes/p1/weeks/w1`), {
        n: 1,
      }),
    );
    await assertFails(
      getDoc(doc(asBob(), `users/${ALICE}/programmes/p1/weeks/w1`)),
    );
  });
});

describe("subscription is server-only", () => {
  test("the owner can read their subscription", async () => {
    await assertSucceeds(
      getDoc(doc(asAlice(), `users/${ALICE}/subscription/main`)),
    );
  });

  test("the owner CANNOT write it", async () => {
    // Otherwise a client grants itself a paid tier with one write, and every
    // entitlement check in the app is decoration.
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/subscription/main`), {
        tier: "celebrityTrainer",
        status: "active",
      }),
    );
  });
});

describe("G-D: usage quota is closed to clients (F005)", () => {
  test("no read, no write, even for the owner", async () => {
    // abuse_guard.ts's whole point is a server-atomic ceiling; a client that
    // can write its own counter can reset it to zero directly, no race
    // needed.
    await assertFails(getDoc(doc(asAlice(), `users/${ALICE}/usage/2026-08-17`)));
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/usage/2026-08-17`), { aiCoach: 0 }),
    );
  });
});

describe("G-D: receipts are closed to clients (F006)", () => {
  test("no read, no write, even for the owner", async () => {
    // generateAnnualReceipt computes this from Stripe invoices directly; a
    // client that can edit it after the fact can hand itself a fabricated
    // tax record.
    await assertFails(getDoc(doc(asAlice(), `users/${ALICE}/receipts/2026`)));
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/receipts/2026`), {
        totalCents: 999999,
      }),
    );
  });
});

describe("G-D: profile health block cannot reach the server unstripped (N03)", () => {
  const strippedHealth = () => ({
    conditions: [],
    allergies: [],
    medications: [],
    injuries: [],
    physicalLimitations: [],
    recentSurgeries: [],
    bloodPressure: null,
    otherConcerns: null,
    screening: {},
    flags: { restrictions: [], bloodPressure: null, surgery: null, clinicianAdvice: null },
  });

  test("a profile write with no health/lifestyle field at all succeeds", async () => {
    // A minimal or partial-field write — nothing here claims anything about
    // health one way or the other, so nothing to reject.
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { goal: "strength" }),
    );
  });

  test("a profile write carrying the stripped (empty) health block succeeds",
    async () => {
      await assertSucceeds(
        setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: strippedHealth(),
          lifestyle: { smoking: null, alcohol: null, diet: [] },
        }),
      );
    });

  test("a profile write carrying a real condition is refused", async () => {
    // This is the exact bypass the client-side split (device_health_profile_
    // repository.dart) exists to prevent — a compromised or buggy client
    // sending the real health block straight to Firestore.
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: { ...strippedHealth(), conditions: ["type 2 diabetes"] },
      }),
    );
  });

  test("a profile write carrying a real injury is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: {
          ...strippedHealth(),
          injuries: [{ bodyPart: "knee", confirmed: true }],
        },
      }),
    );
  });

  test("a profile write carrying smoking/alcohol answers is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        lifestyle: { smoking: "current", alcohol: "none", diet: [] },
      }),
    );
  });

  // The eight fields above were the whole of the rule while the model had
  // grown to ten. `HealthHistory.toJson` puts the PAR-Q+ answers and the
  // normalised flags inside this same `health` map, so every case below used
  // to SUCCEED: the fixture already carried `screening: {}` and `flags: {...}`,
  // and no test ever populated either. The most structured health data the app
  // holds was the part the backstop did not inspect.
  test("a profile write carrying PAR-Q screening answers is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: {
          ...strippedHealth(),
          screening: { chestPainAtRest: true, heartCondition: true },
        },
      }),
    );
  });

  test("a profile write carrying movement restrictions is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: {
          ...strippedHealth(),
          flags: { ...strippedHealth().flags, restrictions: ["overhead"] },
        },
      }),
    );
  });

  test("a profile write carrying a surgery status is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: {
          ...strippedHealth(),
          flags: { ...strippedHealth().flags, surgery: "underRestrictions" },
        },
      }),
    );
  });

  // F014. Deliberately generic on the wire -- but "generic" is not "not health
  // data", and this is still a disclosure that must stay on the device.
  test("a profile write carrying the F014 answer is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: {
          ...strippedHealth(),
          flags: { ...strippedHealth().flags, professionalGuidance: "reported" },
        },
      }),
    );
  });

  // The tolerance half of the same change: a build that predates a field omits
  // the key entirely. That must still be accepted, or the rule rejects
  // legitimate writes from installed clients instead of the attack it targets.
  test("a health block omitting screening and flags entirely still succeeds",
    async () => {
      const { screening, flags, ...older } = strippedHealth();
      void screening;
      void flags;
      await assertSucceeds(
        setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { health: older }),
      );
    });

  // GPT-PM review, 2026-08-30: healthIsStripped/flagsAreStripped originally
  // enumerated known fields only, with no keys().hasOnly(...) constraint on
  // the map itself -- an unrecognised key inside `health` (or inside
  // `flags`) was checked by nothing and passed through unstripped. Same shape
  // of miss as F014/N-01 above, just in the guard itself this time. Fixed by
  // adding hasOnly(...) to both functions; these two cases are the ones that
  // fix closes.
  test("a health block carrying an unrecognised key is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: { ...strippedHealth(), privateDiagnosis: "type 2 diabetes" },
      }),
    );
  });

  test("a flags block carrying an unrecognised key is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: {
          ...strippedHealth(),
          flags: { ...strippedHealth().flags, freeText: "diabetic, on metformin" },
        },
      }),
    );
  });
});

describe("catalogs are read-only", () => {
  for (const c of ["equipment", "exercises", "gyms"]) {
    test(`${c}: signed-in reads, nobody writes`, async () => {
      await assertSucceeds(getDoc(doc(asAlice(), `${c}/x1`)));
      await assertFails(setDoc(doc(asAlice(), `${c}/x1`), { a: 1 }));
    });

    test(`${c}: signed out cannot read`, async () => {
      await assertFails(getDoc(doc(signedOut(), `${c}/x1`)));
    });
  }
});

describe("donor wall", () => {
  test("is readable signed out, because /donors is a public route", async () => {
    await assertSucceeds(getDoc(doc(signedOut(), `donor_wall/${ALICE}`)));
  });

  test("cannot be written by a client", async () => {
    // A client that could write here lists itself as a donor without paying;
    // `optInDonorWall` checks for an active subscription first.
    await assertFails(
      setDoc(doc(asAlice(), `donor_wall/${ALICE}`), { name: "Alice" }),
    );
  });
});

describe("equipment reports are closed to clients", () => {
  test("no read, no write, even for the reporter", async () => {
    await assertFails(getDoc(doc(asAlice(), "equipment_reports/r1")));
    await assertFails(
      setDoc(doc(asAlice(), "equipment_reports/r1"), { reporterUid: ALICE }),
    );
  });
});

describe("coach bookings are closed to clients", () => {
  test("no read and no write, both parties included", async () => {
    // A booking names both people and carries a payment-intent id. The block
    // granting nothing is deliberate; this is what makes that checkable.
    await assertFails(getDoc(doc(asAlice(), "coach_bookings/b1")));
    await assertFails(
      setDoc(doc(asAlice(), "coach_bookings/b1"), {
        clientUid: ALICE,
        coachUid: BOB,
      }),
    );
  });
});

// MVP1.G3-CI-8. Before this collection had its own explicit-deny block, it
// had NO rule at all -- so this test would have passed anyway, on the
// implicit deny-everything-unmatched default. That is exactly the gap the
// rules file now closes explicitly: the same behaviour, but as a decision a
// reader (or this test) can point at, not an accident of omission.
describe("coach listings are closed to clients", () => {
  test("no read and no write, even for the coach who owns the listing", async () => {
    await assertFails(getDoc(doc(asAlice(), `coach_listings/${ALICE}`)));
    await assertFails(
      setDoc(doc(asAlice(), `coach_listings/${ALICE}`), { bio: "hi" }),
    );
  });
});

// Durable account-deletion retry records: Admin SDK only. Nobody -- not a
// signed-in user, not the (already deleted) uid's old token, not a signed-out
// caller -- may read or write one.
describe("account deletion retry records are closed to clients", () => {
  test("no read and no write, signed in or signed out", async () => {
    await assertFails(getDoc(doc(asAlice(), `accountDeletionRetries/${ALICE}`)));
    await assertFails(
      setDoc(doc(asAlice(), `accountDeletionRetries/${ALICE}`), {
        uid: ALICE,
        status: "pending",
      }),
    );
    await assertFails(getDoc(doc(signedOut(), `accountDeletionRetries/${ALICE}`)));
    await assertFails(
      setDoc(doc(signedOut(), `accountDeletionRetries/${ALICE}`), {
        status: "pending",
      }),
    );
  });
});

// MVP1.G3 Step 8/9 -- the synthetic canary identity's whole permission
// surface (core/G3_STEP8_RUNTIME_PREREQUISITES.md Sec 3/9). `canary: true`
// mirrors the custom claim `admin.auth().createCustomToken(uid, {canary:
// true})` sets in production; `authenticatedContext`'s second argument sets
// the same claim in the emulator, so this exercises the real rule text, not
// a stand-in for it.
const CANARY_UID = "canary-fixed-uid";
const asCanary = () =>
  env.authenticatedContext(CANARY_UID, { canary: true }).firestore();

describe("canary identity: _canary/ namespace", () => {
  test("can read, write and delete its own document", async () => {
    await assertSucceeds(
      setDoc(doc(asCanary(), `_canary/${CANARY_UID}`), { probe: true }),
    );
    await assertSucceeds(getDoc(doc(asCanary(), `_canary/${CANARY_UID}`)));
    await assertSucceeds(deleteDoc(doc(asCanary(), `_canary/${CANARY_UID}`)));
  });

  test("an ordinary authenticated user (no canary claim) is denied", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `_canary/${ALICE}`), { probe: true }),
    );
    await assertFails(getDoc(doc(asAlice(), `_canary/${ALICE}`)));
  });

  test("a canary-claimed token cannot reach a DIFFERENT canary document", async () => {
    // Guards against a future second canary identity reading/overwriting the
    // first one's probe doc -- uid-equals-docId is required, not the claim
    // alone.
    await assertFails(
      setDoc(doc(asCanary(), "_canary/some-other-canary-uid"), {
        probe: true,
      }),
    );
  });
});

// This is the test that matters most, per GPT-PM's own review: proving the
// canary claim does NOT quietly inherit the ordinary per-user grant just
// because `request.auth.uid` happens to equal the wildcard's `{uid}`
// segment. Before `isCanaryToken()`'s exclusion existed, this would have
// SUCCEEDED (the canary uid looks like any other authenticated uid to the
// wildcard) -- the fix's whole point is that this must fail instead.
describe("canary identity: excluded from ordinary per-user data", () => {
  test("cannot read or write under /users/{canaryUid}/... via the general wildcard", async () => {
    await assertFails(
      setDoc(doc(asCanary(), `users/${CANARY_UID}/workout_logs/w1`), {
        reps: 8,
      }),
    );
    await assertFails(
      getDoc(doc(asCanary(), `users/${CANARY_UID}/workout_logs/w1`)),
    );
  });

  test("cannot read or write another real user's data either", async () => {
    await assertFails(
      setDoc(doc(asCanary(), `users/${ALICE}/workout_logs/w1`), { reps: 8 }),
    );
  });
});

// CR-05. The canary's contract is "its own `_canary/{uid}` document and
// NOTHING else". Firestore ORs every matching rule, so the wildcard's
// `!isCanaryToken()` is worthless if a separate, more specific grant for the
// same path omits it. Each case below targets one such grant individually,
// with the owner (non-canary) shown succeeding so a rule that simply denied
// everyone would not pass.
describe("canary identity: no other grant applies to it (CR-05)", () => {
  const seed = async (path: string, data: Record<string, unknown>) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), data);
    });

  test("its own profile is NOT readable or writable", async () => {
    await seed(`users/${CANARY_UID}/profile/main`, { goal: "x" });
    await assertFails(getDoc(doc(asCanary(), `users/${CANARY_UID}/profile/main`)));
    await assertFails(
      setDoc(doc(asCanary(), `users/${CANARY_UID}/profile/main`), { goal: "y" }),
    );
    // the same shape for an ordinary owner still works
    await seed(`users/${ALICE}/profile/main`, { goal: "x" });
    await assertSucceeds(getDoc(doc(asAlice(), `users/${ALICE}/profile/main`)));
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { goal: "y" }),
    );
  });

  test("its own recognised_models are NOT readable", async () => {
    await seed(`users/${CANARY_UID}/recognised_models/m1`, { id: "m1" });
    await assertFails(
      getDoc(doc(asCanary(), `users/${CANARY_UID}/recognised_models/m1`)),
    );
    await seed(`users/${ALICE}/recognised_models/m1`, { id: "m1" });
    await assertSucceeds(
      getDoc(doc(asAlice(), `users/${ALICE}/recognised_models/m1`)),
    );
  });

  test("the equipment, exercise and gym catalogues are NOT readable", async () => {
    for (const path of ["equipment/e1", "exercises/x1", "gyms/g1"]) {
      await seed(path, { name: "n" });
      await assertFails(getDoc(doc(asCanary(), path)));
      await assertSucceeds(getDoc(doc(asAlice(), path)));
    }
  });

  test("it cannot create a debug session", async () => {
    await assertFails(
      addDoc(collection(asCanary(), "debug_sessions"), session(CANARY_UID)),
    );
    // S02-09: no client can create a debug session any more (Admin callable only).
    await assertFails(
      addDoc(collection(asAlice(), "debug_sessions"), session(ALICE)),
    );
  });

  test("the explicitly public donor wall stays public", async () => {
    // Deliberately NOT closed to the canary: it is `allow read: if true` by
    // product decision, so denying it here would contradict that block.
    await seed("donor_wall/d1", { name: "n" });
    await assertSucceeds(getDoc(doc(asCanary(), "donor_wall/d1")));
    await assertSucceeds(getDoc(doc(signedOut(), "donor_wall/d1")));
  });
});

describe("debug sessions", () => {
  test("a signed-in user can no longer create one, not even stamped with their own uid (S02-09)", async () => {
    await assertFails(
      addDoc(collection(asAlice(), "debug_sessions"), session(ALICE)),
    );
  });

  test("cannot be created under someone else's uid", async () => {
    await assertFails(
      addDoc(collection(asAlice(), "debug_sessions"), session(BOB)),
    );
  });

  test("cannot be read back, not even by its author", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "debug_sessions/s1"), session(ALICE));
    });
    await assertFails(getDoc(doc(asAlice(), "debug_sessions/s1")));
  });

  test("cannot be edited or deleted after the fact", async () => {
    // A session log a client can rewrite is a note, not evidence.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "debug_sessions/s1"), session(ALICE));
    });
    await assertFails(
      updateDoc(doc(asAlice(), "debug_sessions/s1"), { droppedCount: 99 }),
    );
    await assertFails(deleteDoc(doc(asAlice(), "debug_sessions/s1")));
  });

  describe("shape and size validation (P1a)", () => {
    test("an unknown key is refused", async () => {
      // This is what turned the collection into an open-ended dump: any key,
      // any value, up to 1 MB, unlimited documents.
      await assertFails(
        addDoc(collection(asAlice(), "debug_sessions"), {
          ...session(ALICE),
          payload: "x".repeat(1000),
        }),
      );
    });

    test("more events than the writer's own buffer holds is refused",
      async () => {
        const tooMany = Array.from({ length: 501 }, (_, i) => ({ m: i }));
        await assertFails(
          addDoc(collection(asAlice(), "debug_sessions"),
            session(ALICE, tooMany)),
        );
      });

    test("exactly the buffer capacity is refused too since clients cannot create (S02-09)", async () => {
      // Formerly "accepted" (the ceiling mirrors `debug_telemetry.dart:141`);
      // S02-09 moved the only writer to the sanitising callable.
      const full = Array.from({ length: 500 }, (_, i) => ({ m: i }));
      await assertFails(
        addDoc(collection(asAlice(), "debug_sessions"), session(ALICE, full)),
      );
    });

    test("events must be a list, not a scalar", async () => {
      await assertFails(
        addDoc(collection(asAlice(), "debug_sessions"), {
          ...session(ALICE),
          events: "not-a-list",
        }),
      );
    });

    test("a document with no events is refused", async () => {
      const { events: _drop, ...noEvents } = session(ALICE);
      await assertFails(
        addDoc(collection(asAlice(), "debug_sessions"), noEvents),
      );
    });
  });
});

describe("a collection nobody wrote a rule for", () => {
  test("is denied by default", async () => {
    // Guards the day someone adds a feature and forgets the rules file: the
    // failure must be denial, never an open collection.
    await assertFails(getDoc(doc(asAlice(), "some_new_collection/x")));
    await assertFails(
      setDoc(doc(asAlice(), "some_new_collection/x"), { a: 1 }),
    );
  });
});

/* ==================================================================== */
/* RE-ATTACK - novel payloads, not a rerun of the G-D suite              */
/* ==================================================================== */

/**
 * The G-D suite proved the controls it was written for. That is not the same
 * as proving they hold against an attacker who did not read it, so this
 * describes attacks the earlier file does not make: partial updates instead
 * of whole-document writes, wrong types where a rule reads a field, sibling
 * fields the rule never mentions, deeper paths under a closed collection, and
 * merges that try to smuggle a value into a document written a moment earlier.
 *
 * `update` rather than `set` is the sharpest of these. `setDoc` sends the
 * whole document, so `request.resource.data` carries every field the rule
 * looks at; `updateDoc` sends a patch, and a rule written as "field absent OR
 * field is empty" can read absence in a patch and allow a write that adds a
 * forbidden value.
 */
describe("re-attack: profile health, by patch rather than by whole document", () => {
  const strippedHealth = () => ({
    conditions: [],
    allergies: [],
    medications: [],
    injuries: [],
    physicalLimitations: [],
    recentSurgeries: [],
    bloodPressure: null,
    otherConcerns: null,
    screening: {},
    flags: { restrictions: [], bloodPressure: null, surgery: null, clinicianAdvice: null },
  });

  test("updateDoc cannot add a condition to a legitimately-written profile", async () => {
    // Write a clean profile first, which is allowed, then PATCH the health
    // block. If the rule reasoned about absence in a patch, this is where it
    // would let one through.
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: strippedHealth(),
      }),
    );
    await assertFails(
      updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: { ...strippedHealth(), conditions: ["hypertension"] },
      }),
    );
  });

  test("a dotted-path patch into the health map is refused", async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: strippedHealth(),
      }),
    );
    await assertFails(
      updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        "health.conditions": ["asthma"],
      }),
    );
  });

  test("a dotted-path patch into lifestyle is refused", async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { goal: "strength" }),
    );
    await assertFails(
      updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        "lifestyle.smoking": "current",
      }),
    );
  });

  test("a health block of the WRONG TYPE is refused, not waved through", async () => {
    // `healthIsStripped` reads `.size()` off list fields. A string or a number
    // where a list belongs is the classic way to make a helper throw, and a
    // rule that errors denies -- which is the outcome wanted, but it has to be
    // confirmed rather than assumed.
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: "not a map at all",
      }),
    );
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: { ...strippedHealth(), conditions: "diabetes" },
      }),
    );
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: { ...strippedHealth(), conditions: 3 },
      }),
    );
  });

  test("a health block MISSING the fields the rule reads is refused", async () => {
    // Removing a field is the mirror image of adding one: if the helper reads
    // `h.conditions.size()` on a map with no `conditions`, the rule must deny
    // rather than evaluate to true.
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: { conditions: [] },
      }),
    );
  });

  test("an unknown sibling field alongside a clean health block is allowed", async () => {
    // The control. The rule constrains health and lifestyle; it is not an
    // allow-list over the whole profile, and asserting otherwise would assert
    // a restriction the product does not have.
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
        health: strippedHealth(),
        somethingNew: { added: "by a later app version" },
      }),
    );
  });

  test("Bob cannot write Alice's profile even with a stripped block", async () => {
    await assertFails(
      setDoc(doc(asBob(), `users/${ALICE}/profile/main`), {
        health: strippedHealth(),
      }),
    );
  });
});

describe("re-attack: usage and receipts, every verb", () => {
  // G-D closed these to read AND write. The earlier suite checks get/set;
  // these check the verbs an attacker would reach for next.
  for (const coll of ["usage", "receipts"]) {
    test(`${coll}: update is refused`, async () => {
      await assertFails(
        updateDoc(doc(asAlice(), `users/${ALICE}/${coll}/2026`), { n: 1 }),
      );
    });

    test(`${coll}: delete is refused`, async () => {
      // Deleting a quota row resets it. A control that stops writes but not
      // deletes is not a quota.
      await assertFails(deleteDoc(doc(asAlice(), `users/${ALICE}/${coll}/2026`)));
    });

    test(`${coll}: addDoc into the collection is refused`, async () => {
      await assertFails(
        addDoc(collection(asAlice(), `users/${ALICE}/${coll}`), { n: 1 }),
      );
    });

    test(`${coll}: a DEEPER path is refused too`, async () => {
      // The exclusion is by collection name at one level. A nested document is
      // the obvious way to test whether it reaches further down.
      await assertFails(
        setDoc(doc(asAlice(), `users/${ALICE}/${coll}/2026/detail/x`), { n: 1 }),
      );
      await assertFails(
        getDoc(doc(asAlice(), `users/${ALICE}/${coll}/2026/detail/x`)),
      );
    });

    test(`${coll}: Bob cannot read Alice's`, async () => {
      await assertFails(getDoc(doc(asBob(), `users/${ALICE}/${coll}/2026`)));
    });
  }
});

describe("re-attack: subscription cannot be reached sideways", () => {
  test("update and delete are both refused", async () => {
    await assertFails(
      updateDoc(doc(asAlice(), `users/${ALICE}/subscription/main`), {
        tier: "celebrityTrainer",
      }),
    );
    await assertFails(
      deleteDoc(doc(asAlice(), `users/${ALICE}/subscription/main`)),
    );
  });

  test("a document under a DIFFERENT id in the same collection is refused", async () => {
    // The rule names `subscription` as a collection, not `main` as a document.
    // `subscription/mine` is the way past a rule written the other way round.
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/subscription/mine`), {
        tier: "celebrityTrainer",
      }),
    );
  });

  test("a nested path under subscription is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/subscription/main/x/y`), {
        tier: "celebrityTrainer",
      }),
    );
  });

  test("reading it is still allowed, because the app renders it", async () => {
    // The control. Subscription is server-WRITTEN, not server-secret.
    await assertSucceeds(
      getDoc(doc(asAlice(), `users/${ALICE}/subscription/main`)),
    );
  });
});

describe("re-attack: ownership cannot be transferred or forged", () => {
  test("Alice cannot create a document under Bob's user tree", async () => {
    await assertFails(setDoc(doc(asAlice(), `users/${BOB}/workouts/w1`), { x: 1 }));
  });

  test("a signed-out client reaches nothing under any user", async () => {
    await assertFails(getDoc(doc(signedOut(), `users/${ALICE}/profile/main`)));
    await assertFails(
      setDoc(doc(signedOut(), `users/${ALICE}/workouts/w1`), { x: 1 }),
    );
  });

  test("a uid-shaped prefix is not the same uid", async () => {
    // `alice` vs `alice2`: a rule comparing with `startsWith` rather than
    // equality would let this through.
    await assertFails(
      getDoc(
        doc(
          env.authenticatedContext("alice2").firestore(),
          `users/${ALICE}/profile/main`,
        ),
      ),
    );
  });

  test("Alice's own ordinary collection still works", async () => {
    // The control for this whole describe: isolation must not be isolation
    // from yourself.
    await assertSucceeds(
      setDoc(doc(asAlice(), `users/${ALICE}/workouts/w1`), { x: 1 }),
    );
    await assertSucceeds(getDoc(doc(asAlice(), `users/${ALICE}/workouts/w1`)));
  });
});

// P1.G1 T2/T4 (SPTR Equipment Recognition v4.4). This is the gate's Story AC
// mutation-test suite: client CREATE/UPDATE of authority fields DENY,
// server/admin write ALLOW, cross-account DENY. `recognised_models` is the
// one collection here with a client-read grant; the other two are closed to
// the client on both axes.
describe("P1.G1: recognised_models — server-written, owner-readable only", () => {
  const recognition = (extra: Record<string, unknown> = {}) => ({
    modelId: "11111111-1111-4111-8111-111111111111",
    canonicalSlug: "technogym-selection-leg-press",
    recognitionAuthorityTuple: {
      catalogVersion: "catalog-v1-deadbeef",
      ocrVersion: "ocr-1",
      textPolicyVersion: "text-1",
      fusionPolicyVersion: "fusion-1",
      identityPolicyVersion: "identity-1",
    },
    ...extra,
  });

  test("client create is refused, even under the owner's own uid", async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), `users/${ALICE}/recognised_models/m1`),
        recognition(),
      ),
    );
  });

  test("server/admin write succeeds (Admin SDK bypasses rules, as expected)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/recognised_models/m1`),
        recognition(),
      );
    });
    await assertSucceeds(
      getDoc(doc(asAlice(), `users/${ALICE}/recognised_models/m1`)),
    );
  });

  test("owner can read a server-written record", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/recognised_models/m1`),
        recognition(),
      );
    });
    await assertSucceeds(
      getDoc(doc(asAlice(), `users/${ALICE}/recognised_models/m1`)),
    );
  });

  test("cross-account read is refused", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/recognised_models/m1`),
        recognition(),
      );
    });
    await assertFails(
      getDoc(doc(asBob(), `users/${ALICE}/recognised_models/m1`)),
    );
  });

  test("client update of the authority tuple is refused, even by the owner", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/recognised_models/m1`),
        recognition(),
      );
    });
    await assertFails(
      updateDoc(doc(asAlice(), `users/${ALICE}/recognised_models/m1`), {
        "recognitionAuthorityTuple.catalogVersion": "catalog-v2-forged",
      }),
    );
  });

  test("client delete is refused, even by the owner", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/recognised_models/m1`),
        recognition(),
      );
    });
    await assertFails(
      deleteDoc(doc(asAlice(), `users/${ALICE}/recognised_models/m1`)),
    );
  });

  test("the per-user wildcard cannot override this denial", async () => {
    // Firestore grants a request if ANY matching rule permits it, so the
    // carve-out in the wildcard match itself is what this test actually
    // proves — a wildcard that forgot `coll != 'recognised_models'` would
    // pass every test above except this one, since the specific block's own
    // `allow write: if false` never GRANTS anything either way.
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/recognised_models/m2`), {
        modelId: "forged",
      }),
    );
  });
});

describe("P1.G1: equipment_identity_sessions — fully server-internal", () => {
  test("client read is refused", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/equipment_identity_sessions/s1`),
        { status: "RESOLVING" },
      );
    });
    await assertFails(
      getDoc(doc(asAlice(), `users/${ALICE}/equipment_identity_sessions/s1`)),
    );
  });

  test("client create is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/equipment_identity_sessions/s1`), {
        status: "RESOLVING",
      }),
    );
  });

  test("server/admin write succeeds", async () => {
    await assertSucceeds(
      env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `users/${ALICE}/equipment_identity_sessions/s1`),
          { status: "RESOLVING" },
        );
      }),
    );
  });
});

describe("P2.G3: equipment_identity_latest_session — fully server-internal", () => {
  test("client read is refused", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/equipment_identity_latest_session/current`),
        { recognitionSessionId: "s1" },
      );
    });
    await assertFails(
      getDoc(doc(asAlice(), `users/${ALICE}/equipment_identity_latest_session/current`)),
    );
  });

  test("client create is refused", async () => {
    await assertFails(
      setDoc(doc(asAlice(), `users/${ALICE}/equipment_identity_latest_session/current`), {
        recognitionSessionId: "s1",
      }),
    );
  });

  test("server/admin write succeeds", async () => {
    await assertSucceeds(
      env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `users/${ALICE}/equipment_identity_latest_session/current`),
          { recognitionSessionId: "s1" },
        );
      }),
    );
  });
});

describe("P1.G1: equipment_identity_telemetry — fully server-internal", () => {
  test("client read is refused", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${ALICE}/equipment_identity_telemetry/t1`),
        { latencyMs: 240 },
      );
    });
    await assertFails(
      getDoc(doc(asAlice(), `users/${ALICE}/equipment_identity_telemetry/t1`)),
    );
  });

  test("client create is refused", async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), `users/${ALICE}/equipment_identity_telemetry/t1`),
        { latencyMs: 240 },
      ),
    );
  });

  test("server/admin write succeeds", async () => {
    await assertSucceeds(
      env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `users/${ALICE}/equipment_identity_telemetry/t1`),
          { latencyMs: 240 },
        );
      }),
    );
  });
});

describe("P1.G1: top-level catalog authority collections — server/admin only", () => {
  const catalogCollections = [
    "equipment_brands",
    "equipment_product_lines",
    "equipment_models",
    "equipment_model_setup_specs",
    "equipment_external_mappings",
    "equipment_sources",
    "equipment_assets",
    "equipment_catalog_publish_jobs",
    "equipment_catalog_versions",
    "equipment_catalog_active",
    // P2.G3: derived lookup-key index (functions-equipment-identity/src/p2/text_key_index.ts).
    // Same server/admin-only posture as every other catalog collection above.
    "equipment_model_text_keys",
  ];

  for (const coll of catalogCollections) {
    test(`${coll}: client read is refused`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `${coll}/catalog-v1--seed`), {
          seeded: true,
        });
      });
      await assertFails(getDoc(doc(asAlice(), `${coll}/catalog-v1--seed`)));
    });

    test(`${coll}: client write is refused`, async () => {
      await assertFails(
        setDoc(doc(asAlice(), `${coll}/catalog-v1--seed`), { seeded: true }),
      );
    });

    test(`${coll}: server/admin write succeeds`, async () => {
      await assertSucceeds(
        env.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), `${coll}/catalog-v1--seed`), {
            seeded: true,
          });
        }),
      );
    });
  }
});

/* ====================================================================== */
/* E0 / C01: Body Scan + Nutrition Coach rules (T03)                       */
/* RULES-01..11, 13, 17..20, PRIV-16, ONB-16, SAFE-19                      */
/*                                                                         */
/* Every case states its failing condition: an `assertFails` proves a rule */
/* is closed, and each is paired with an `assertSucceeds` for the nearest  */
/* valid input so a rule that simply denies everything cannot pass.        */
/* ====================================================================== */

describe("E0 body scan + nutrition rules", () => {
  const T0 = Timestamp.fromDate(new Date("2026-10-15T08:00:00Z"));
  const OLD = Timestamp.fromDate(new Date("2020-01-01T00:00:00Z"));
  const CANARY = "canary-fixed-uid";
  const asCan = () => env.authenticatedContext(CANARY, { canary: true }).firestore();

  const put = (path: string, data: Record<string, unknown>) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), data);
    });
  const ref = (db: ReturnType<typeof asAlice>, path: string) => doc(db, path);
  const u = (rest: string, uid = ALICE) => `users/${uid}/${rest}`;

  /* ---------------- valid fixtures, one per new collection ---------------- */
  const bodyScan = () => ({
    schema: 1,
    status: "done",
    provider: "licensed-api",
    weightKg: 80,
    clientNote: "morning",
    estimate: { bodyFatPct: 20 },
    photosState: "stored",
    photosExpireAt: T0,
    isBaseline: false,
    takenAt: T0,
  });
  const settings = () => ({ schema: 1, retentionDays: 90, paused: false });
  const weightEntry = () => ({ kg: 80, at: T0, source: "manual" });
  const plan = () => ({ status: "active", planVersion: 1, kcalRange: { low: 1800, high: 2100 }, stepsGoal: 8000 });
  const review = () => ({ decision: "keep" });
  const item = (name = "Oats") => ({ name, grams: 50 });
  const rng = (v: number) => ({ low: v, mid: v, high: v });
  const totals = () => ({ kcal: rng(500), proteinG: rng(20), carbsG: rng(60), fatG: rng(10) });
  const foodEntry = () => ({
    day: "2026-10-15",
    slot: "breakfast",
    loggedAt: T0,
    name: "Porridge",
    source: "manual",
    items: [item()],
    totals: totals(),
  });
  const savedFood = () => ({ name: "Oats", per100g: { kcal: 370, proteinG: 13, carbsG: 60, fatG: 7 } });

  const COLLECTIONS: Array<{ coll: string; id: string; valid: () => Record<string, unknown> }> = [
    { coll: "body_scans", id: "s1", valid: bodyScan },
    { coll: "body_scan_settings", id: "main", valid: settings },
    { coll: "weight_entries", id: "2026-10-15", valid: weightEntry },
    { coll: "nutrition_plan", id: "main", valid: plan },
    { coll: "nutrition_plan_reviews", id: "2026-W42", valid: review },
    { coll: "food_entries", id: "e1", valid: foodEntry },
    { coll: "saved_foods", id: "f1", valid: savedFood },
  ];

  /* ====================== RULES-01: body_scans read ====================== */
  describe("body_scans read (RULES-01)", () => {
    beforeEach(() => put(u("body_scans/s1"), bodyScan()));

    test("owner reads their own scan", async () => {
      await assertSucceeds(getDoc(ref(asAlice(), u("body_scans/s1"))));
    });
    test("another user, a signed-out caller and the canary identity are refused", async () => {
      await assertFails(getDoc(ref(asBob(), u("body_scans/s1"))));
      await assertFails(getDoc(ref(signedOut(), u("body_scans/s1"))));
      await put(u("body_scans/s1", CANARY), bodyScan());
      await assertFails(getDoc(ref(asCan(), u("body_scans/s1", CANARY))));
    });
  });

  /* ================ RULES-02 / RULES-19: body_scans write ================ */
  describe("body_scans write surface (RULES-02, RULES-19)", () => {
    beforeEach(() => put(u("body_scans/s1"), bodyScan()));
    const scan = () => ref(asAlice(), u("body_scans/s1"));

    test("owner CREATE is refused, even with a perfectly valid document", async () => {
      await assertFails(setDoc(ref(asAlice(), u("body_scans/new")), bodyScan()));
      await assertFails(setDoc(ref(asAlice(), u("body_scans/new2")), { weightKg: 80 }));
    });
    test("owner DELETE is refused (the tombstone and purge rely on it)", async () => {
      await assertFails(deleteDoc(scan()));
    });
    test.each([30, 300, 80.5, 123])("weightKg %p is accepted", async (kg) => {
      await assertSucceeds(updateDoc(scan(), { weightKg: kg }));
    });
    test.each([29.9, 300.1, 0, -5, 10, 400])("weightKg %p is refused", async (kg) => {
      await assertFails(updateDoc(scan(), { weightKg: kg }));
    });
    test("weightKg of the wrong type is refused", async () => {
      await assertFails(updateDoc(scan(), { weightKg: "80" }));
      await assertFails(updateDoc(scan(), { weightKg: null }));
    });
    test("weightKg cannot be removed", async () => {
      await assertFails(updateDoc(scan(), { weightKg: deleteField() }));
    });
    test("clientNote of 200 characters is accepted, 201 is refused", async () => {
      await assertSucceeds(updateDoc(scan(), { clientNote: "a".repeat(200) }));
      await assertFails(updateDoc(scan(), { clientNote: "a".repeat(201) }));
    });
    test("clientNote of a non-string type is refused", async () => {
      await assertFails(updateDoc(scan(), { clientNote: 5 }));
    });
    test("clientNote may be removed (RULES-19 defined removal)", async () => {
      await assertSucceeds(updateDoc(scan(), { clientNote: deleteField() }));
    });
    test("an update touching only weightKg on a doc WITHOUT clientNote is accepted (no missing-key error)", async () => {
      const noNote: Record<string, unknown> = bodyScan();
      delete noNote.clientNote;
      await put(u("body_scans/s2"), noNote);
      await assertSucceeds(updateDoc(ref(asAlice(), u("body_scans/s2")), { weightKg: 81 }));
    });
    test("adding a clientNote to a doc that had none is accepted", async () => {
      const noNote: Record<string, unknown> = bodyScan();
      delete noNote.clientNote;
      await put(u("body_scans/s3"), noNote);
      await assertSucceeds(updateDoc(ref(asAlice(), u("body_scans/s3")), { clientNote: "hi" }));
    });
    test("weightKg and clientNote together are accepted", async () => {
      await assertSucceeds(updateDoc(scan(), { weightKg: 79, clientNote: "after" }));
    });

    const FORBIDDEN: Array<[string, unknown]> = [
      ["estimate", { bodyFatPct: 5 }],
      ["status", "failed"],
      ["provider", "forged"],
      ["photosState", "deleted"],
      ["photosExpireAt", Timestamp.fromDate(new Date("2099-01-01T00:00:00Z"))],
      ["isBaseline", true],
      ["takenAt", Timestamp.fromDate(new Date("2025-01-01T00:00:00Z"))],
    ];
    test.each(FORBIDDEN)("an update of %s alone is refused", async (key, value) => {
      await assertFails(updateDoc(scan(), { [key]: value }));
    });
    test.each(FORBIDDEN)("a write mixing a valid weightKg with a forbidden %s is refused", async (key, value) => {
      await assertFails(updateDoc(scan(), { weightKg: 81, [key]: value }));
    });
    test("removing a server-owned key is refused", async () => {
      await assertFails(updateDoc(scan(), { estimate: deleteField() }));
      await assertFails(updateDoc(scan(), { photosState: deleteField() }));
    });
    test("adding an unknown key is refused", async () => {
      await assertFails(updateDoc(scan(), { extra: 1 }));
    });
    test("another user, signed-out and canary cannot edit", async () => {
      await assertFails(updateDoc(ref(asBob(), u("body_scans/s1")), { weightKg: 81 }));
      await assertFails(updateDoc(ref(signedOut(), u("body_scans/s1")), { weightKg: 81 }));
      await put(u("body_scans/s1", CANARY), bodyScan());
      await assertFails(updateDoc(ref(asCan(), u("body_scans/s1", CANARY)), { weightKg: 81 }));
    });
    test("update of a missing document is refused (no create through update)", async () => {
      await assertFails(updateDoc(ref(asAlice(), u("body_scans/ghost")), { weightKg: 81 }));
    });
  });

  /* ====================== RULES-03: weight_entries ====================== */
  describe("weight_entries (RULES-03)", () => {
    const w = (day: string) => ref(asAlice(), u(`weight_entries/${day}`));
    test("a valid entry is accepted, read back by the owner, overwritten the same day, deleted", async () => {
      await assertSucceeds(setDoc(w("2026-10-15"), weightEntry()));
      await assertSucceeds(getDoc(w("2026-10-15")));
      await assertSucceeds(setDoc(w("2026-10-15"), { ...weightEntry(), kg: 79 }));
      await assertSucceeds(deleteDoc(w("2026-10-15")));
    });
    test("source 'scan' and an explicit schema int are accepted", async () => {
      await assertSucceeds(setDoc(w("2026-10-16"), { ...weightEntry(), source: "scan", schema: 1 }));
    });
    test.each(["2026-1-5", "2026-10-5", "26-10-15", "2026-10-15x", "x2026-10-15", "2026/10/15", "20261015", "2026-10-155", ""])(
      "day id %j is refused",
      async (day) => {
        if (day === "") return; // an empty id is not addressable in the SDK
        await assertFails(setDoc(w(day), weightEntry()));
      },
    );
    test.each([30, 300, 150, 80.25])("kg %p is accepted", async (kg) => {
      await assertSucceeds(setDoc(w("2026-10-15"), { ...weightEntry(), kg }));
    });
    test.each([29.9, 300.1, 10, 400, 0, -1])("kg %p is refused", async (kg) => {
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), kg }));
    });
    test("kg of the wrong type is refused", async () => {
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), kg: "80" }));
    });
    test("an unknown key is refused", async () => {
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), note: "x" }));
    });
    test("source outside the enum is refused", async () => {
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), source: "x" }));
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), source: "Manual" }));
    });
    test.each(["kg", "at", "source"])("a missing required key %s is refused", async (key) => {
      const d: Record<string, unknown> = weightEntry();
      delete d[key];
      await assertFails(setDoc(w("2026-10-15"), d));
    });
    test("`at` must be a timestamp", async () => {
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), at: "2026-10-15T08:00:00Z" }));
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), at: 1760515200000 }));
    });
    test("schema must be an int when present", async () => {
      await assertFails(setDoc(w("2026-10-15"), { ...weightEntry(), schema: "1" }));
    });
    test("another user, signed-out and canary are refused on read and write", async () => {
      await put(u("weight_entries/2026-10-15"), weightEntry());
      await assertFails(getDoc(ref(asBob(), u("weight_entries/2026-10-15"))));
      await assertFails(setDoc(ref(asBob(), u("weight_entries/2026-10-16")), weightEntry()));
      await assertFails(deleteDoc(ref(asBob(), u("weight_entries/2026-10-15"))));
      await assertFails(getDoc(ref(signedOut(), u("weight_entries/2026-10-15"))));
      await assertFails(setDoc(ref(asCan(), u("weight_entries/2026-10-15", CANARY)), weightEntry()));
    });
  });

  /* ======================= RULES-04 / 20: nutrition_plan ======================= */
  describe("nutrition_plan (RULES-04, RULES-20, SAFE-19)", () => {
    const p = (id = "main") => ref(asAlice(), u(`nutrition_plan/${id}`));
    // The plan document is a singleton and a SECOND write to it is an update,
    // which additionally needs planVersion + 1. To judge each shape rule on its own
    // (and never let a refusal come from the version rule by accident), every
    // write starts from an empty database unless the test sets `keep` after
    // seeding. This local `setDoc` shadows the module one.
    let keep = false;
    beforeEach(() => {
      keep = false;
    });
    const setDoc = async (r: DocumentReference<DocumentData>, d: DocumentData) => {
      if (!keep) await env.clearFirestore();
      return rawSetDoc(r, d);
    };
    const withPlan = (over: Record<string, unknown>) => ({ ...plan(), ...over });

    test("a valid plan is accepted and read by its owner", async () => {
      await assertSucceeds(setDoc(p(), plan()));
      await assertSucceeds(getDoc(p()));
    });
    test("the full designed document shape is accepted", async () => {
      await assertSucceeds(
        setDoc(
          p(),
          withPlan({
            schema: 1,
            ownership: "coached",
            goalDirection: "lose",
            ratePctPerWeek: 0.5,
            driftFromInitialKcal: -50,
            kcalBounds: { min: 1500, max: 2500 },
            autoAdjust: { steps: true, kcal: false },
            protein: { minG: 128, targetG: 160, maxG: 176 },
            fat: { minG: 48, maxG: 70 },
            carbs: { minG: 100, maxG: 300 },
            inputsDigest: { a: 1 },
            computedAt: T0,
            lastKcalAdjustAt: T0,
            reviewUndo: { week: "2026-W42", prevKcalRange: { low: 1800, high: 2100 }, prevStepsGoal: 8000, prevDrift: 0, expiresAt: T0, undone: false },
          }),
        ),
      );
    });
    test("status 'needsProfile' is accepted", async () => {
      await assertSucceeds(setDoc(p(), withPlan({ status: "needsProfile" })));
    });
    test("status 'referProfessional' is refused (an ineligible verdict is never persisted, D-55)", async () => {
      await assertFails(setDoc(p(), withPlan({ status: "referProfessional" })));
    });
    test.each(["bogus", "ACTIVE", "", 1, null])("status %p is refused", async (status) => {
      await assertFails(setDoc(p(), withPlan({ status })));
    });
    test("kcalRange.low: 1200 accepted, 1199 refused", async () => {
      await assertSucceeds(setDoc(p(), withPlan({ kcalRange: { low: 1200, high: 2100 } })));
      await assertFails(setDoc(p(), withPlan({ kcalRange: { low: 1199, high: 2100 } })));
    });
    test("kcalRange.high: 6000 accepted, 6001 refused", async () => {
      await assertSucceeds(setDoc(p(), withPlan({ kcalRange: { low: 1800, high: 6000 } })));
      await assertFails(setDoc(p(), withPlan({ kcalRange: { low: 1800, high: 6001 } })));
    });
    test("kcalRange.high < low is refused, equal is accepted", async () => {
      await assertFails(setDoc(p(), withPlan({ kcalRange: { low: 2100, high: 1800 } })));
      await assertSucceeds(setDoc(p(), withPlan({ kcalRange: { low: 1800, high: 1800 } })));
    });
    test("kcalRange values must be ints and the map has no other key", async () => {
      await assertFails(setDoc(p(), withPlan({ kcalRange: { low: 1800.5, high: 2100 } })));
      await assertFails(setDoc(p(), withPlan({ kcalRange: { low: 1800, high: 2100, mid: 1950 } })));
      await assertFails(setDoc(p(), withPlan({ kcalRange: { low: "1800", high: 2100 } })));
    });
    test("stepsGoal: 2000 and 30000 accepted, 1999 and 30001 refused", async () => {
      await assertSucceeds(setDoc(p(), withPlan({ stepsGoal: 2000 })));
      await assertSucceeds(setDoc(p(), withPlan({ stepsGoal: 30000 })));
      await assertFails(setDoc(p(), withPlan({ stepsGoal: 1999 })));
      await assertFails(setDoc(p(), withPlan({ stepsGoal: 30001 })));
      await assertFails(setDoc(p(), withPlan({ stepsGoal: 8000.5 })));
    });
    test("docId other than 'main' is refused", async () => {
      await assertFails(setDoc(p("other"), plan()));
      await assertFails(setDoc(p("Main"), plan()));
    });
    test("an unknown key is refused", async () => {
      await assertFails(setDoc(p(), withPlan({ bonus: 1 })));
    });
    test("ownership and goalDirection enums", async () => {
      for (const v of ["coached", "shared", "manual"]) await assertSucceeds(setDoc(p(), withPlan({ ownership: v })));
      await assertFails(setDoc(p(), withPlan({ ownership: "x" })));
      for (const v of ["lose", "maintain", "gain"]) await assertSucceeds(setDoc(p(), withPlan({ goalDirection: v })));
      await assertFails(setDoc(p(), withPlan({ goalDirection: "bulk" })));
    });
    test("planVersion must be an int >= 1; status and planVersion are required", async () => {
      await assertFails(setDoc(p(), withPlan({ planVersion: 0 })));
      await assertFails(setDoc(p(), withPlan({ planVersion: 1.5 })));
      await assertFails(setDoc(p(), withPlan({ planVersion: "1" })));
      await assertFails(setDoc(p(), { planVersion: 1, kcalRange: { low: 1800, high: 2100 } }));
      await assertFails(setDoc(p(), { status: "active", kcalRange: { low: 1800, high: 2100 } }));
    });
    test("macro grams: 1000 accepted, 1001 and negatives refused; macro maps take no extra key", async () => {
      await assertSucceeds(setDoc(p(), withPlan({ protein: { minG: 0, targetG: 1000, maxG: 1000 } })));
      await assertFails(setDoc(p(), withPlan({ protein: { minG: 0, targetG: 1001, maxG: 1000 } })));
      await assertFails(setDoc(p(), withPlan({ protein: { minG: -1, targetG: 10, maxG: 10 } })));
      await assertFails(setDoc(p(), withPlan({ fat: { minG: 48, maxG: 70, targetG: 60 } })));
      await assertFails(setDoc(p(), withPlan({ carbs: { minG: 1.5, maxG: 70 } })));
    });
    test("nested maps reject unknown keys (kcalBounds, autoAdjust, reviewUndo) and oversized digests", async () => {
      await assertFails(setDoc(p(), withPlan({ kcalBounds: { min: 1500, max: 2500, x: 1 } })));
      await assertFails(setDoc(p(), withPlan({ autoAdjust: { steps: true, kcal: true, x: 1 } })));
      await assertFails(setDoc(p(), withPlan({ reviewUndo: { week: "2026-W42", extra: 1 } })));
      const big: Record<string, number> = {};
      for (let i = 0; i < 13; i++) big[`k${i}`] = i;
      await assertFails(setDoc(p(), withPlan({ inputsDigest: big })));
      const ok: Record<string, number> = {};
      for (let i = 0; i < 12; i++) ok[`k${i}`] = i;
      await assertSucceeds(setDoc(p(), withPlan({ inputsDigest: ok })));
    });
    test("an update must carry exactly planVersion + 1", async () => {
      keep = true;
      await put(u("nutrition_plan/main"), plan());
      await assertFails(setDoc(p(), withPlan({ planVersion: 1 })));
      await assertFails(setDoc(p(), withPlan({ planVersion: 3 })));
      await assertFails(setDoc(p(), withPlan({ planVersion: 0 })));
      await assertSucceeds(setDoc(p(), withPlan({ planVersion: 2 })));
    });
    test("delete by the owner is accepted", async () => {
      await put(u("nutrition_plan/main"), plan());
      await assertSucceeds(deleteDoc(p()));
    });
    test("another user, signed-out and canary are refused", async () => {
      keep = true;
      await put(u("nutrition_plan/main"), plan());
      await assertFails(getDoc(ref(asBob(), u("nutrition_plan/main"))));
      await assertFails(setDoc(ref(asBob(), u("nutrition_plan/main")), withPlan({ planVersion: 2 })));
      await assertFails(deleteDoc(ref(asBob(), u("nutrition_plan/main"))));
      await assertFails(getDoc(ref(signedOut(), u("nutrition_plan/main"))));
      await assertFails(setDoc(ref(asCan(), u("nutrition_plan/main", CANARY)), plan()));
    });
  });

  /* ==================== RULES-05 / 20: nutrition_plan_reviews ==================== */
  describe("nutrition_plan_reviews (RULES-05, RULES-20, SAFE-19)", () => {
    const r = (week = "2026-W42") => ref(asAlice(), u(`nutrition_plan_reviews/${week}`));
    test("create is accepted; update is refused (immutable); delete is accepted", async () => {
      await assertSucceeds(setDoc(r(), review()));
      await assertFails(setDoc(r(), { decision: "adjustKcal", deltaKcal: -100 }));
      await assertFails(updateDoc(r(), { deltaKcal: -100 }));
      await assertSucceeds(deleteDoc(r()));
    });
    test("every legal decision is accepted", async () => {
      for (const decision of ["keep", "adjustKcal", "adjustSteps", "needMoreData", "needRecalculation"]) {
        await assertSucceeds(setDoc(r(`2026-W${10 + ["keep", "adjustKcal", "adjustSteps", "needMoreData", "needRecalculation"].indexOf(decision)}`), { decision }));
      }
    });
    test("decision outside the enum is refused, including 'referProfessional'", async () => {
      await assertFails(setDoc(r(), { decision: "referProfessional" }));
      await assertFails(setDoc(r(), { decision: "bogus" }));
      await assertFails(setDoc(r(), { decision: 1 }));
      await assertFails(setDoc(r(), {}));
    });
    test.each(["2026-W5", "2026-w05", "2026-05", "26-W05", "2026-W050", "2026-W5x", "2026W05"])("week id %j is refused", async (week) => {
      await assertFails(setDoc(r(week), review()));
    });
    test("week id 2026-W53 matches the pattern (53-week year)", async () => {
      await assertSucceeds(setDoc(r("2026-W53"), review()));
    });
    test("reasonCodes: 8 accepted, 9 refused", async () => {
      const codes = (n: number) => Array.from({ length: n }, (_, i) => `code_${i}`);
      await assertSucceeds(setDoc(r("2026-W01"), { decision: "keep", reasonCodes: codes(8) }));
      await assertFails(setDoc(r("2026-W02"), { decision: "keep", reasonCodes: codes(9) }));
    });
    test("reasonCodes elements must be strings of at most 40 characters (checked at every index)", async () => {
      await assertSucceeds(setDoc(r("2026-W03"), { decision: "keep", reasonCodes: ["a".repeat(40)] }));
      await assertFails(setDoc(r("2026-W04"), { decision: "keep", reasonCodes: ["a".repeat(41)] }));
      await assertFails(setDoc(r("2026-W06"), { decision: "keep", reasonCodes: [1] }));
      await assertFails(setDoc(r("2026-W07"), { decision: "keep", reasonCodes: ["ok", "ok", "ok", "ok", "ok", "ok", "ok", "a".repeat(41)] }));
      await assertFails(setDoc(r("2026-W08"), { decision: "keep", reasonCodes: "keep" }));
    });
    test("basePlanVersion, deltas and inputs have type checks; unknown keys refused", async () => {
      await assertSucceeds(setDoc(r("2026-W09"), { decision: "adjustKcal", basePlanVersion: 3, deltaKcal: -100, deltaSteps: 500, inputs: { a: 1 }, decidedAt: T0, schema: 1 }));
      await assertFails(setDoc(r("2026-W11"), { decision: "keep", basePlanVersion: "3" }));
      await assertFails(setDoc(r("2026-W12"), { decision: "keep", deltaKcal: 1.5 }));
      await assertFails(setDoc(r("2026-W13"), { decision: "keep", inputs: "x" }));
      await assertFails(setDoc(r("2026-W14"), { decision: "keep", extra: 1 }));
    });
    test("another user, signed-out and canary are refused", async () => {
      await put(u("nutrition_plan_reviews/2026-W42"), review());
      await assertFails(getDoc(ref(asBob(), u("nutrition_plan_reviews/2026-W42"))));
      await assertFails(setDoc(ref(asBob(), u("nutrition_plan_reviews/2026-W43")), review()));
      await assertFails(deleteDoc(ref(asBob(), u("nutrition_plan_reviews/2026-W42"))));
      await assertFails(getDoc(ref(signedOut(), u("nutrition_plan_reviews/2026-W42"))));
      await assertFails(setDoc(ref(asCan(), u("nutrition_plan_reviews/2026-W42", CANARY)), review()));
    });
  });

  /* ========================= RULES-06 / 19: food_entries ========================= */
  describe("food_entries (RULES-06, RULES-19)", () => {
    const f = (id = "e1") => ref(asAlice(), u(`food_entries/${id}`));
    const withEntry = (over: Record<string, unknown>) => ({ ...foodEntry(), ...over });
    const items = (n: number) => Array.from({ length: n }, (_, i) => item(`Item ${i}`));

    test("a valid entry is accepted, read, updated and deleted by the owner", async () => {
      await assertSucceeds(setDoc(f(), foodEntry()));
      await assertSucceeds(getDoc(f()));
      await assertSucceeds(setDoc(f(), withEntry({ name: "Porridge 2" })));
      await assertSucceeds(deleteDoc(f()));
    });
    test("the full designed shape (confidence, checkThese, model, schema) is accepted", async () => {
      await assertSucceeds(setDoc(f(), withEntry({ schema: 1, confidence: "medium", checkThese: ["portion"], model: { v: 1 }, source: "photo" })));
    });
    test("items: 1 and 30 accepted, 0 and 31 refused", async () => {
      await assertSucceeds(setDoc(f("a"), withEntry({ items: items(1) })));
      await assertSucceeds(setDoc(f("b"), withEntry({ items: items(30) })));
      await assertFails(setDoc(f("c"), withEntry({ items: [] })));
      await assertFails(setDoc(f("d"), withEntry({ items: items(31) })));
    });
    test("items must be a list", async () => {
      await assertFails(setDoc(f(), withEntry({ items: { name: "x" } })));
      await assertFails(setDoc(f(), withEntry({ items: "x" })));
    });
    test("every item is checked in all three index groups (index 0, 12, 25 and 29)", async () => {
      for (const bad of [0, 12, 25, 29]) {
        const list = items(30);
        (list as unknown[])[bad] = "not a map";
        await assertFails(setDoc(f(`bad-${bad}`), withEntry({ items: list })));
      }
      for (const bad of [0, 12, 25, 29]) {
        const list = items(30);
        list[bad] = item("n".repeat(81));
        await assertFails(setDoc(f(`long-${bad}`), withEntry({ items: list })));
      }
      const noName = items(30);
      (noName as unknown[])[25] = { grams: 5 };
      await assertFails(setDoc(f("noname"), withEntry({ items: noName })));
      const ok = items(30);
      ok[29] = item("n".repeat(80));
      await assertSucceeds(setDoc(f("edge"), withEntry({ items: ok })));
    });
    test("entry name: 80 accepted, 81 refused", async () => {
      await assertSucceeds(setDoc(f("a"), withEntry({ name: "n".repeat(80) })));
      await assertFails(setDoc(f("b"), withEntry({ name: "n".repeat(81) })));
    });
    test("unknown slot, source and confidence are refused; every legal one is accepted", async () => {
      for (const slot of ["breakfast", "lunch", "dinner", "snack"]) await assertSucceeds(setDoc(f(`s-${slot}`), withEntry({ slot })));
      for (const source of ["photo", "describe", "search", "barcode", "label", "manual"]) await assertSucceeds(setDoc(f(`o-${source}`), withEntry({ source })));
      await assertFails(setDoc(f("x1"), withEntry({ slot: "brunch" })));
      await assertFails(setDoc(f("x2"), withEntry({ source: "voice" })));
      await assertFails(setDoc(f("x3"), withEntry({ confidence: "certain" })));
    });
    test("an unknown key is refused", async () => {
      await assertFails(setDoc(f(), withEntry({ extra: 1 })));
    });
    test("checkThese: 8 accepted, 9 refused; must be a list", async () => {
      await assertSucceeds(setDoc(f("a"), withEntry({ checkThese: Array(8).fill("c") })));
      await assertFails(setDoc(f("b"), withEntry({ checkThese: Array(9).fill("c") })));
      await assertFails(setDoc(f("c"), withEntry({ checkThese: "portion" })));
    });
    test("totals missing any key is refused", async () => {
      for (const key of ["kcal", "proteinG", "carbsG", "fatG"]) {
        const t: Record<string, unknown> = totals();
        delete t[key];
        await assertFails(setDoc(f(`m-${key}`), withEntry({ totals: t })));
      }
      await assertFails(setDoc(f("none"), (() => { const d: Record<string, unknown> = foodEntry(); delete d.totals; return d; })()));
    });
    test("totals: ranges 0 and 100000 accepted, negative, 100001 and an extra key refused", async () => {
      await assertSucceeds(setDoc(f("a"), withEntry({ totals: { ...totals(), kcal: { low: 0, mid: 0, high: 100000 } } })));
      await assertFails(setDoc(f("b"), withEntry({ totals: { ...totals(), kcal: { low: -1, mid: 0, high: 10 } } })));
      await assertFails(setDoc(f("c"), withEntry({ totals: { ...totals(), kcal: { low: 0, mid: 0, high: 100001 } } })));
      await assertFails(setDoc(f("d"), withEntry({ totals: { ...totals(), sugarG: rng(1) } })));
      await assertFails(setDoc(f("e"), withEntry({ totals: { ...totals(), kcal: { low: 1, mid: 2 } } })));
      await assertFails(setDoc(f("f"), withEntry({ totals: { ...totals(), kcal: { low: 1, mid: 2, high: 3, extra: 4 } } })));
      // The range must be ordered low <= mid <= high (one comparison chain bounds all three).
      await assertFails(setDoc(f("g"), withEntry({ totals: { ...totals(), kcal: { low: 600, mid: 500, high: 700 } } })));
      await assertFails(setDoc(f("h"), withEntry({ totals: { ...totals(), kcal: { low: 400, mid: 700, high: 600 } } })));
      await assertFails(setDoc(f("i"), withEntry({ totals: { ...totals(), kcal: { low: "1", mid: 2, high: 3 } } })));
    });
    test("day format and loggedAt type are enforced; required keys are required", async () => {
      await assertFails(setDoc(f("a"), withEntry({ day: "2026-10-5" })));
      await assertFails(setDoc(f("b"), withEntry({ day: 20261015 })));
      await assertFails(setDoc(f("c"), withEntry({ loggedAt: "2026-10-15" })));
      for (const key of ["day", "slot", "loggedAt", "name", "source", "items", "totals"]) {
        const d: Record<string, unknown> = foodEntry();
        delete d[key];
        await assertFails(setDoc(f(`req-${key}`), d));
      }
    });
    test("another user, signed-out and canary are refused", async () => {
      await put(u("food_entries/e1"), foodEntry());
      await assertFails(getDoc(ref(asBob(), u("food_entries/e1"))));
      await assertFails(setDoc(ref(asBob(), u("food_entries/e2")), foodEntry()));
      await assertFails(deleteDoc(ref(asBob(), u("food_entries/e1"))));
      await assertFails(getDoc(ref(signedOut(), u("food_entries/e1"))));
      await assertFails(setDoc(ref(asCan(), u("food_entries/e1", CANARY)), foodEntry()));
    });
  });

  /* ============================ RULES-10: saved_foods ============================ */
  describe("saved_foods (RULES-10)", () => {
    const s = (id = "f1") => ref(asAlice(), u(`saved_foods/${id}`));
    test("a valid saved food is accepted, read, updated and deleted", async () => {
      await assertSucceeds(setDoc(s(), savedFood()));
      await assertSucceeds(getDoc(s()));
      await assertSucceeds(setDoc(s(), { ...savedFood(), servingG: 40, barcode: "3017620422003", createdAt: T0, schema: 1 }));
      await assertSucceeds(deleteDoc(s()));
    });
    test("name: 80 accepted, 81 refused", async () => {
      await assertSucceeds(setDoc(s("a"), { ...savedFood(), name: "n".repeat(80) }));
      await assertFails(setDoc(s("b"), { ...savedFood(), name: "n".repeat(81) }));
    });
    test("per100g values: 1000 and 0 accepted, 1001 and -1 refused (every macro)", async () => {
      for (const key of ["kcal", "proteinG", "carbsG", "fatG"]) {
        await assertSucceeds(setDoc(s(`ok-${key}`), { ...savedFood(), per100g: { ...savedFood().per100g, [key]: 1000 } }));
        await assertSucceeds(setDoc(s(`zero-${key}`), { ...savedFood(), per100g: { ...savedFood().per100g, [key]: 0 } }));
        await assertFails(setDoc(s(`hi-${key}`), { ...savedFood(), per100g: { ...savedFood().per100g, [key]: 1001 } }));
        await assertFails(setDoc(s(`neg-${key}`), { ...savedFood(), per100g: { ...savedFood().per100g, [key]: -1 } }));
      }
    });
    test("per100g with an unknown key or a non-map is refused; name and per100g are required", async () => {
      await assertFails(setDoc(s("a"), { ...savedFood(), per100g: { ...savedFood().per100g, sugarG: 1 } }));
      await assertFails(setDoc(s("b"), { ...savedFood(), per100g: 5 }));
      await assertFails(setDoc(s("c"), { per100g: savedFood().per100g }));
      await assertFails(setDoc(s("d"), { name: "Oats" }));
    });
    test("an unknown key is refused; servingG, barcode and createdAt are bounded", async () => {
      await assertFails(setDoc(s("a"), { ...savedFood(), extra: 1 }));
      await assertFails(setDoc(s("b"), { ...savedFood(), servingG: 100001 }));
      await assertFails(setDoc(s("c"), { ...savedFood(), barcode: "9".repeat(33) }));
      await assertSucceeds(setDoc(s("d"), { ...savedFood(), barcode: "9".repeat(32) }));
      await assertFails(setDoc(s("e"), { ...savedFood(), createdAt: "now" }));
    });
    test("another user, signed-out and canary are refused", async () => {
      await put(u("saved_foods/f1"), savedFood());
      await assertFails(getDoc(ref(asBob(), u("saved_foods/f1"))));
      await assertFails(setDoc(ref(asBob(), u("saved_foods/f2")), savedFood()));
      await assertFails(deleteDoc(ref(asBob(), u("saved_foods/f1"))));
      await assertFails(getDoc(ref(signedOut(), u("saved_foods/f1"))));
      await assertFails(setDoc(ref(asCan(), u("saved_foods/f1", CANARY)), savedFood()));
    });
  });

  /* ================== RULES-07 / RULES-17: body_scan_settings ================== */
  describe("body_scan_settings (RULES-07)", () => {
    const s = (id = "main") => ref(asAlice(), u(`body_scan_settings/${id}`));
    test("a valid settings document is accepted, read and deleted", async () => {
      await assertSucceeds(setDoc(s(), settings()));
      await assertSucceeds(getDoc(s()));
      await assertSucceeds(deleteDoc(s()));
    });
    test.each([0, 30, 90, 365])("retentionDays %p is accepted", async (retentionDays) => {
      await assertSucceeds(setDoc(s(), { ...settings(), retentionDays }));
    });
    test.each([7, 1, 29, 91, 366, -1, "90", 90.5])("retentionDays %p is refused", async (retentionDays) => {
      await assertFails(setDoc(s(), { ...settings(), retentionDays }));
    });
    test("reminder weekday: 1 and 7 accepted, 0 and 8 refused; minutes 0 and 1439 accepted, 1440 and -1 refused", async () => {
      const rem = (r: Record<string, unknown>) => ({ ...settings(), reminder: r });
      await assertSucceeds(setDoc(s(), rem({ enabled: true, weekday: 1, minutes: 0 })));
      await assertSucceeds(setDoc(s(), rem({ enabled: false, weekday: 7, minutes: 1439 })));
      await assertFails(setDoc(s(), rem({ weekday: 0 })));
      await assertFails(setDoc(s(), rem({ weekday: 8 })));
      await assertFails(setDoc(s(), rem({ minutes: 1440 })));
      await assertFails(setDoc(s(), rem({ minutes: -1 })));
      await assertFails(setDoc(s(), rem({ weekday: 2.5 })));
      await assertFails(setDoc(s(), rem({ enabled: "yes" })));
      await assertFails(setDoc(s(), rem({ extra: 1 })));
      await assertFails(setDoc(s(), { ...settings(), reminder: "weekly" }));
    });
    test("paused must be a bool; docId must be 'main'; unknown key refused", async () => {
      await assertSucceeds(setDoc(s(), { ...settings(), paused: true }));
      await assertFails(setDoc(s(), { ...settings(), paused: "true" }));
      await assertFails(setDoc(s("other"), settings()));
      await assertFails(setDoc(s(), { ...settings(), extra: 1 }));
      await assertFails(setDoc(s(), { ...settings(), schema: "1" }));
    });
    test("another user, signed-out and canary are refused", async () => {
      await put(u("body_scan_settings/main"), settings());
      await assertFails(getDoc(ref(asBob(), u("body_scan_settings/main"))));
      await assertFails(setDoc(ref(asBob(), u("body_scan_settings/main")), settings()));
      await assertFails(deleteDoc(ref(asBob(), u("body_scan_settings/main"))));
      await assertFails(getDoc(ref(signedOut(), u("body_scan_settings/main"))));
      await assertFails(setDoc(ref(asCan(), u("body_scan_settings/main", CANARY)), settings()));
    });

    describe("cloudConsent (RULES-17, D-56)", () => {
      const consent = (version: number, acceptedAt: unknown) => ({ cloudConsent: { version, acceptedAt } });
      test("a NEW consent stamped with the server time is accepted", async () => {
        await assertSucceeds(setDoc(s(), { ...settings(), ...consent(1, serverTimestamp()) }));
      });
      test("a new consent carrying an old (forged) timestamp is refused", async () => {
        await assertFails(setDoc(s(), { ...settings(), ...consent(1, OLD) }));
      });
      test("a consent whose acceptedAt is not a timestamp is refused", async () => {
        await assertFails(setDoc(s(), { ...settings(), ...consent(1, "now") }));
        await assertFails(setDoc(s(), { ...settings(), ...consent(1, null) }));
      });
      test("an UNCHANGED consent carried by a later retention/reminder write is accepted (even with the old timestamp)", async () => {
        await put(u("body_scan_settings/main"), { ...settings(), ...consent(1, OLD) });
        await assertSucceeds(setDoc(s(), { ...settings(), retentionDays: 30, ...consent(1, OLD) }));
        await assertSucceeds(setDoc(s(), { ...settings(), paused: true, reminder: { enabled: true, weekday: 7, minutes: 480 }, ...consent(1, OLD) }));
      });
      test("a changed VERSION carrying the old timestamp is refused", async () => {
        await put(u("body_scan_settings/main"), { ...settings(), ...consent(1, OLD) });
        await assertFails(setDoc(s(), { ...settings(), ...consent(2, OLD) }));
      });
      test("a version bump stamped with the server time is accepted", async () => {
        await put(u("body_scan_settings/main"), { ...settings(), ...consent(1, OLD) });
        await assertSucceeds(setDoc(s(), { ...settings(), ...consent(2, serverTimestamp()) }));
      });
      test("re-accepting the same version with a fresh server timestamp is accepted", async () => {
        await put(u("body_scan_settings/main"), { ...settings(), ...consent(2, OLD) });
        await assertSucceeds(setDoc(s(), { ...settings(), ...consent(2, serverTimestamp()) }));
      });
      test("a version DECREASE is refused even with a fresh timestamp", async () => {
        await put(u("body_scan_settings/main"), { ...settings(), ...consent(2, OLD) });
        await assertFails(setDoc(s(), { ...settings(), ...consent(1, serverTimestamp()) }));
      });
      test("version 0, a non-int version and an unknown consent key are refused", async () => {
        await assertFails(setDoc(s(), { ...settings(), ...consent(0, serverTimestamp()) }));
        await assertFails(setDoc(s(), { ...settings(), ...consent("1" as unknown as number, serverTimestamp()) }));
        await assertFails(setDoc(s(), { ...settings(), cloudConsent: { version: 1, acceptedAt: serverTimestamp(), extra: 1 } }));
        await assertFails(setDoc(s(), { ...settings(), cloudConsent: { version: 1 } }));
        await assertFails(setDoc(s(), { ...settings(), cloudConsent: "yes" }));
      });
      test("WITHDRAWAL (the key removed) is accepted and means no consent", async () => {
        await put(u("body_scan_settings/main"), { ...settings(), ...consent(1, OLD) });
        await assertSucceeds(setDoc(s(), settings()));
        await assertSucceeds(updateDoc(s(), { cloudConsent: deleteField() }));
      });
      test("a settings write with no consent on either side is accepted", async () => {
        await put(u("body_scan_settings/main"), settings());
        await assertSucceeds(setDoc(s(), { ...settings(), retentionDays: 365 }));
      });
      test("giving consent when the stored document had none requires the server time", async () => {
        await put(u("body_scan_settings/main"), settings());
        await assertFails(setDoc(s(), { ...settings(), ...consent(1, OLD) }));
        await assertSucceeds(setDoc(s(), { ...settings(), ...consent(1, serverTimestamp()) }));
      });
    });
  });

  /* ==================== RULES-08 / 18 / 19: profile writes ==================== */
  describe("profile: nutrition health flags and the nutrition map (RULES-08, RULES-18, RULES-19, PRIV-16, ONB-16)", () => {
    const prof = () => ref(asAlice(), u("profile/main"));
    const health = (flags: Record<string, unknown>) => ({
      conditions: [],
      allergies: [],
      medications: [],
      injuries: [],
      physicalLimitations: [],
      recentSurgeries: [],
      bloodPressure: null,
      otherConcerns: null,
      screening: {},
      flags: { restrictions: [], bloodPressure: null, surgery: null, clinicianAdvice: null, professionalGuidance: null, ...flags },
    });
    const legacyFlags = () => ({ restrictions: [], bloodPressure: null, surgery: null, clinicianAdvice: null, professionalGuidance: null });

    test("the LEGACY five-key flags shape is still accepted (old client / new rules rollout)", async () => {
      await assertSucceeds(setDoc(prof(), { health: { ...health({}), flags: legacyFlags() } }));
    });
    test("a profile with no nutrition key and no new flag keys is accepted", async () => {
      await assertSucceeds(setDoc(prof(), { goal: "strength" }));
    });
    test("nutritionGuidance = 'reported' is refused (device-only health answer)", async () => {
      await assertFails(setDoc(prof(), { health: health({ nutritionGuidance: "reported" }) }));
    });
    test("foodAllergens ['peanuts'] is refused", async () => {
      await assertFails(setDoc(prof(), { health: health({ foodAllergens: ["peanuts"] }) }));
    });
    test("both new keys empty are accepted: null, [] and the absent form", async () => {
      await assertSucceeds(setDoc(prof(), { health: health({ nutritionGuidance: null, foodAllergens: [] }) }));
      await assertSucceeds(setDoc(prof(), { health: health({ nutritionGuidance: null, foodAllergens: null }) }));
      await assertSucceeds(setDoc(prof(), { health: health({ foodAllergens: [] }) }));
    });
    test("a non-null nutritionGuidance of any value is refused; an empty-string-ish allergen list element is refused", async () => {
      for (const v of ["none", "", "clear", false, 0]) {
        await assertFails(setDoc(prof(), { health: health({ nutritionGuidance: v }) }));
      }
      await assertFails(setDoc(prof(), { health: health({ foodAllergens: [""] }) }));
    });
    test("an unknown key inside flags is still refused", async () => {
      await assertFails(setDoc(prof(), { health: health({ dietaryDiagnosis: "x" }) }));
    });
    test("a patch (update) cannot smuggle the new health answers either", async () => {
      await put(u("profile/main"), { health: health({}) });
      await assertFails(updateDoc(prof(), { "health.flags": { ...legacyFlags(), nutritionGuidance: "reported" } }));
      await assertFails(updateDoc(prof(), { "health.flags": { ...legacyFlags(), foodAllergens: ["milk"] } }));
      await assertSucceeds(updateDoc(prof(), { "health.flags": { ...legacyFlags(), nutritionGuidance: null, foodAllergens: [] } }));
    });

    const nutrition = (over: Record<string, unknown> = {}) => ({
      schema: 1,
      sexAtBirth: "female",
      goalDirection: "lose",
      targetBodyFatPct: 22.5,
      typicalDailySteps: 8000,
      mealsPerDay: 3,
      planOwnership: "coached",
      healthConnectChoice: "granted",
      completedAt: T0,
      ...over,
    });
    test("a valid nutrition map is accepted", async () => {
      await assertSucceeds(setDoc(prof(), { nutrition: nutrition() }));
    });
    test("nutrition: null and a map of explicit nulls are accepted (serializer tolerance)", async () => {
      await assertSucceeds(setDoc(prof(), { nutrition: null }));
      await assertSucceeds(
        setDoc(prof(), { nutrition: { sexAtBirth: null, goalDirection: null, planOwnership: null, mealsPerDay: null, targetBodyFatPct: null, typicalDailySteps: null } }),
      );
    });
    test("an empty nutrition map is accepted", async () => {
      await assertSucceeds(setDoc(prof(), { nutrition: {} }));
    });
    test("a nutrition map with an unknown key is refused", async () => {
      await assertFails(setDoc(prof(), { nutrition: nutrition({ bonus: 1 }) }));
    });
    test("excludedFoods in the server nutrition map is refused (device-only, D-55)", async () => {
      await assertFails(setDoc(prof(), { nutrition: nutrition({ excludedFoods: ["peanuts"] }) }));
      await assertFails(setDoc(prof(), { nutrition: nutrition({ excludedFoods: [] }) }));
    });
    test("nutrition that is not a map is refused", async () => {
      await assertFails(setDoc(prof(), { nutrition: "x" }));
      await assertFails(setDoc(prof(), { nutrition: ["a"] }));
      await assertFails(setDoc(prof(), { nutrition: 5 }));
    });
    test("sexAtBirth / goalDirection / planOwnership enums", async () => {
      for (const v of ["female", "male", "unspecified"]) await assertSucceeds(setDoc(prof(), { nutrition: nutrition({ sexAtBirth: v }) }));
      await assertFails(setDoc(prof(), { nutrition: nutrition({ sexAtBirth: "other" }) }));
      for (const v of ["lose", "maintain", "gain"]) await assertSucceeds(setDoc(prof(), { nutrition: nutrition({ goalDirection: v }) }));
      await assertFails(setDoc(prof(), { nutrition: nutrition({ goalDirection: "bulk" }) }));
      for (const v of ["coached", "shared", "manual"]) await assertSucceeds(setDoc(prof(), { nutrition: nutrition({ planOwnership: v }) }));
      await assertFails(setDoc(prof(), { nutrition: nutrition({ planOwnership: "auto" }) }));
    });
    test("mealsPerDay: 2 and 6 accepted; -1, 0, 1, 7 and 3.5 refused (RULES-19)", async () => {
      for (const v of [2, 3, 6]) await assertSucceeds(setDoc(prof(), { nutrition: nutrition({ mealsPerDay: v }) }));
      for (const v of [-1, 0, 1, 7, 3.5, "3"]) await assertFails(setDoc(prof(), { nutrition: nutrition({ mealsPerDay: v }) }));
    });
    test("targetBodyFatPct: 5 and 60 accepted; 4.9 and 60.1 refused", async () => {
      for (const v of [5, 60, 22.5]) await assertSucceeds(setDoc(prof(), { nutrition: nutrition({ targetBodyFatPct: v }) }));
      for (const v of [4.9, 60.1, 0, -1, "20"]) await assertFails(setDoc(prof(), { nutrition: nutrition({ targetBodyFatPct: v }) }));
    });
    test("typicalDailySteps: 0 and 100000 accepted; -1 and 100001 refused", async () => {
      for (const v of [0, 100000]) await assertSucceeds(setDoc(prof(), { nutrition: nutrition({ typicalDailySteps: v }) }));
      for (const v of [-1, 100001, 8000.5]) await assertFails(setDoc(prof(), { nutrition: nutrition({ typicalDailySteps: v }) }));
    });
    test("the new keys do not weaken the existing health refusals", async () => {
      await assertFails(setDoc(prof(), { health: { ...health({}), conditions: ["asthma"] }, nutrition: nutrition() }));
      await assertSucceeds(setDoc(prof(), { health: health({}), nutrition: nutrition() }));
    });
  });

  /* ================= RULES-09 / 11 / 13: carve-out proofs ================= */
  describe("wildcard carve-out proof (RULES-09) and canary (RULES-13)", () => {
    test.each(COLLECTIONS.map((c) => [c.coll, c.id] as [string, string]))(
      "%s: a write that satisfies only the generic wildcard shape is refused (the explicit block is not dead)",
      async (coll, id) => {
        // `{ x: 1 }` is what the wildcard would have accepted from the owner.
        await assertFails(setDoc(ref(asAlice(), u(`${coll}/${id}`)), { x: 1 }));
        await assertFails(setDoc(ref(asAlice(), u(`${coll}/wildcard-probe`)), { x: 1 }));
      },
    );

    test("body_scans: an UPDATE through the generic wildcard shape is refused on an existing scan", async () => {
      await put(u("body_scans/s1"), bodyScan());
      await assertFails(updateDoc(ref(asAlice(), u("body_scans/s1")), { x: 1 }));
      await assertFails(setDoc(ref(asAlice(), u("body_scans/s1")), { x: 1 }));
    });

    test.each(COLLECTIONS.map((c) => [c.coll, c.id] as [string, string]))(
      "%s: nested sub-paths fall out of the wildcard entirely (read and write refused for the owner)",
      async (coll, id) => {
        await put(u(`${coll}/${id}/sub/deep`), { x: 1 });
        await assertFails(getDoc(ref(asAlice(), u(`${coll}/${id}/sub/deep`))));
        await assertFails(setDoc(ref(asAlice(), u(`${coll}/${id}/sub/deep`)), { x: 1 }));
      },
    );

    test("a sibling collection that is NOT carved out still works through the wildcard (the carve-out list is not over-broad)", async () => {
      await assertSucceeds(setDoc(ref(asAlice(), u("workout_logs/l1")), { reps: 8 }));
      await assertSucceeds(setDoc(ref(asAlice(), u("body_scans_archive/a1")), { x: 1 }));
      await assertSucceeds(setDoc(ref(asAlice(), u("food_entries_old/a1")), { x: 1 }));
    });

    test.each(COLLECTIONS.map((c) => [c.coll, c.id] as [string, string]))(
      "%s: the canary identity gets NOTHING (read and write refused) while the owner succeeds",
      async (coll, id) => {
        const valid = COLLECTIONS.find((c) => c.coll === coll)!.valid();
        await put(u(`${coll}/${id}`, CANARY), valid);
        await put(u(`${coll}/${id}`), valid);
        await assertSucceeds(getDoc(ref(asAlice(), u(`${coll}/${id}`))));
        await assertFails(getDoc(ref(asCan(), u(`${coll}/${id}`, CANARY))));
        if (coll === "body_scans") {
          await assertFails(updateDoc(ref(asCan(), u(`${coll}/${id}`, CANARY)), { weightKg: 81 }));
        } else {
          await assertFails(setDoc(ref(asCan(), u(`${coll}/${id}`, CANARY)), valid));
          await assertFails(deleteDoc(ref(asCan(), u(`${coll}/${id}`, CANARY))));
        }
      },
    );

    test.each(COLLECTIONS.map((c) => [c.coll, c.id] as [string, string]))(
      "%s: another user cannot read or write the owner's document",
      async (coll, id) => {
        const valid = COLLECTIONS.find((c) => c.coll === coll)!.valid();
        await put(u(`${coll}/${id}`), valid);
        await assertFails(getDoc(ref(asBob(), u(`${coll}/${id}`))));
        await assertFails(setDoc(ref(asBob(), u(`${coll}/${id}`)), valid));
        await assertFails(deleteDoc(ref(asBob(), u(`${coll}/${id}`))));
        await assertFails(getDoc(ref(signedOut(), u(`${coll}/${id}`))));
      },
    );

    test("the owner gets a successful valid write on every collection except body_scans (positive control)", async () => {
      for (const c of COLLECTIONS.filter((x) => x.coll !== "body_scans")) {
        await assertSucceeds(setDoc(ref(asAlice(), u(`${c.coll}/${c.id}`)), c.valid()));
      }
    });
  });

  /* ======================= RULES-11 / 20: server-only top level ======================= */
  describe("nutrition_cache and body_scan_purge_state are server-only (RULES-11, RULES-20)", () => {
    const paths = ["nutrition_cache/off_3017620422003", "nutrition_cache/budget_off_read_202610151407", "body_scan_purge_state/sweep"];
    test.each(paths)("%s: owner, other user, signed-out and canary are refused on read and write", async (path) => {
      await put(path, { count: 1 });
      for (const db of [asAlice(), asBob(), signedOut(), asCan()]) {
        await assertFails(getDoc(ref(db, path)));
        await assertFails(setDoc(ref(db, path), { count: 99 }));
        await assertFails(updateDoc(ref(db, path), { count: 99 }));
        await assertFails(deleteDoc(ref(db, path)));
      }
    });
    test.each(paths)("%s: the server (rules bypass) can still write it", async (path) => {
      await assertSucceeds(put(path, { count: 1 }));
    });
    test("a collection-level read of nutrition_cache is refused too", async () => {
      await assertFails(getDocs(collection(asAlice(), "nutrition_cache")));
    });
  });
});
