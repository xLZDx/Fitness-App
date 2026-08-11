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
      port: 8080,
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
