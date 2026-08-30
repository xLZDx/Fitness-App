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

describe("debug sessions", () => {
  test("a signed-in user creates one stamped with their own uid", async () => {
    await assertSucceeds(
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

    test("exactly the buffer capacity is accepted", async () => {
      // The ceiling mirrors `debug_telemetry.dart:141`, so a full, legitimate
      // buffer must not be refused.
      const full = Array.from({ length: 500 }, (_, i) => ({ m: i }));
      await assertSucceeds(
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
