/**
 * P1f — `deleteAccount` against a real Firestore, with a second account
 * watching.
 *
 * `delete_account.test.ts` already covers this function, and covers it well:
 * step ordering, Stripe idempotency, the anonymise-vs-delete decision per
 * shared record. But it replaces `db.recursiveDelete` with `jest.fn()`. That
 * one substitution removes the two claims that matter most and neither of which
 * a mock can make:
 *
 *   1. **Completeness.** `recursiveDelete` is a server-side traversal. Whether
 *      it reaches `users/{uid}/programme/{id}/weeks/{id}/days/{id}` is a fact
 *      about Firestore, not about this repo, and asserting `recursiveDelete`
 *      was CALLED with a reference proves nothing about what it removed.
 *   2. **Isolation.** Every collection here is written by more than one person.
 *      A `where` clause with the wrong field, a `recursiveDelete` aimed one
 *      level too high, a batch built over the wrong snapshot — each deletes
 *      somebody ELSE's account, and each looks completely correct in a test
 *      where only one user exists. So Bob exists in every test below, holds
 *      the same shapes of data as Alice, and is re-read afterwards.
 *
 * Only `stripe` is mocked. It is a third-party billing API; calling it for real
 * from a test suite is not fidelity, it is a network dependency and, on the
 * wrong key, a refund. Everything else — Firestore, the Auth user, the batched
 * sweep — is the real thing running in the emulator.
 *
 *     npm --prefix functions run test:e2e
 */

// Hoisted above the `index.ts` import by jest: `stripeClient()` does a dynamic
// `import("stripe")`, which resolves through the module registry like any
// require.
const subscriptionsCancel = jest.fn(async (id: string) => ({ id }));
const subscriptionsRetrieve = jest.fn(async (id: string) => ({
  id,
  status: "active",
}));
const subscriptionsList = jest.fn(async () => ({ data: [], has_more: false }));

jest.mock("stripe", () => ({
  __esModule: true,
  default: jest.fn(() => ({
    subscriptions: {
      cancel: subscriptionsCancel,
      retrieve: subscriptionsRetrieve,
      list: subscriptionsList,
    },
  })),
}));

import * as admin from "firebase-admin";
import { deleteAccount } from "../index";

const db = admin.firestore();
const auth = admin.auth();

const ALICE = "alice_e2e";
const BOB = "bob_e2e";
const DELETED_UID = "deleted_user";

/** What `onCall`'s `.run()` wants: the auth context and nothing else here. */
const callAs = (uid: string) =>
  (deleteAccount as unknown as {
    run: (r: unknown) => Promise<{ success: boolean }>;
  }).run({ auth: { uid }, data: {} });

/**
 * One user's worth of data, in every shape the app really writes: the uid-keyed
 * document, a nested subcollection three levels down, the two top-level
 * uid-keyed collections outside `users/`, and the three collections that only
 * MENTION a uid.
 */
async function seedUser(uid: string): Promise<void> {
  await db.doc(`users/${uid}`).set({ displayName: uid, tier: "standard" });
  await db.doc(`users/${uid}/subscription/main`).set({ tier: "standard" });
  await db
    .doc(`users/${uid}/programme/current/weeks/w1/days/d1`)
    .set({ exercise: "squat", sets: 5 });
  await db.doc(`users/${uid}/health/latest`).set({ restingHr: 58 });
  await db.doc(`donor_wall/${uid}`).set({ name: uid, amount: 25 });
  await db.doc(`coach_listings/${uid}`).set({ bio: "coach", active: true });
  await db.doc(`debug_sessions/session_${uid}`).set({ uid, events: [] });
  await db
    .doc(`equipment_reports/report_${uid}`)
    .set({ reporterUid: uid, machine: "rack-3", fault: "torn pad" });
}

/** Everything under and about a uid, as a plain snapshot for comparison. */
async function readUser(uid: string) {
  const [root, sub, deep, health, donor, listing, session, report] =
    await Promise.all([
      db.doc(`users/${uid}`).get(),
      db.doc(`users/${uid}/subscription/main`).get(),
      db.doc(`users/${uid}/programme/current/weeks/w1/days/d1`).get(),
      db.doc(`users/${uid}/health/latest`).get(),
      db.doc(`donor_wall/${uid}`).get(),
      db.doc(`coach_listings/${uid}`).get(),
      db.doc(`debug_sessions/session_${uid}`).get(),
      db.doc(`equipment_reports/report_${uid}`).get(),
    ]);
  return {
    root: root.exists,
    subscription: sub.exists,
    deep: deep.exists,
    health: health.exists,
    donor: donor.exists,
    listing: listing.exists,
    debugSession: session.exists,
    report: report.exists,
    reporterUid: report.data()?.reporterUid,
  };
}

/** Emulator state does not reset between tests on its own. */
async function wipeAll(): Promise<void> {
  await Promise.all(
    ["users", "donor_wall", "coach_listings", "debug_sessions",
      "equipment_reports", "coach_bookings"].map((c) =>
      db.recursiveDelete(db.collection(c)),
    ),
  );
  for (const uid of [ALICE, BOB]) {
    await auth.deleteUser(uid).catch(() => undefined);
  }
}

beforeEach(async () => {
  jest.clearAllMocks();
  await wipeAll();
  await seedUser(ALICE);
  await seedUser(BOB);
  await auth.createUser({ uid: ALICE });
  await auth.createUser({ uid: BOB });
});

afterAll(async () => {
  await wipeAll();
  await admin.app().delete();
});

describe("deleteAccount, end to end", () => {
  it("removes every document the departing user owns, at any depth", async () => {
    await callAs(ALICE);

    expect(await readUser(ALICE)).toMatchObject({
      root: false,
      subscription: false,
      // The claim the mocked suite structurally cannot make: `recursiveDelete`
      // reached three subcollection levels below `users/alice`.
      deep: false,
      health: false,
      donor: false,
      listing: false,
      debugSession: false,
    });
  });

  it("leaves the other account completely untouched", async () => {
    await callAs(ALICE);

    expect(await readUser(BOB)).toMatchObject({
      root: true,
      subscription: true,
      deep: true,
      health: true,
      donor: true,
      listing: true,
      debugSession: true,
      report: true,
      reporterUid: BOB,
    });
  });

  it("keeps the equipment report but stops it naming anyone", async () => {
    // A broken rack is still broken after the person who reported it leaves.
    // The record survives; the reporter does not.
    await callAs(ALICE);

    const report = await db.doc(`equipment_reports/report_${ALICE}`).get();
    expect(report.exists).toBe(true);
    expect(report.data()).toMatchObject({
      reporterUid: DELETED_UID,
      machine: "rack-3",
      fault: "torn pad",
    });
  });

  it("anonymises the departing side of a booking and keeps the other's", async () => {
    await db.doc("coach_bookings/shared").set({
      clientUid: ALICE,
      coachUid: BOB,
      startsAt: "2026-09-01T10:00:00Z",
    });

    await callAs(ALICE);

    const booking = await db.doc("coach_bookings/shared").get();
    expect(booking.exists).toBe(true);
    expect(booking.data()).toMatchObject({
      clientUid: DELETED_UID,
      // Bob's own record of a session they really taught, intact.
      coachUid: BOB,
      startsAt: "2026-09-01T10:00:00Z",
    });
  });

  it("deletes a booking the user made with themselves", async () => {
    // Reachable, not hypothetical: `bookCoachSession` (index.ts:1150-1199)
    // never compares `coachUid` to `auth.uid`, so a coach with a listing can
    // book themselves. The document then comes back from BOTH queries in
    // `sweepSharedRecords`, and before the act gate that queued two updates
    // against one ref — leaving a row alive whose every side reads
    // `deleted_user`, which nobody can ever read again.
    await db.doc("coach_bookings/self").set({
      clientUid: ALICE,
      coachUid: ALICE,
      startsAt: "2026-09-02T09:00:00Z",
    });

    await callAs(ALICE);

    expect((await db.doc("coach_bookings/self").get()).exists).toBe(false);
  });

  it("sweeps past the 450-write batch cap", async () => {
    // `commitInChunks` splits at 450 because Firestore refuses a batch of
    // more than 500 writes. The mocked suite drives that split against a fake
    // `commit()`, which cannot fail the way a real one would — and the caller's
    // error message tells the user the step "is safe to repeat", which for a
    // real cap breach would be false: it fails identically every time and
    // leaves the account permanently half-deleted.
    const total = 470;
    for (let i = 0; i < total; i += 400) {
      const batch = db.batch();
      for (let j = i; j < Math.min(i + 400, total); j++) {
        batch.set(db.doc(`debug_sessions/bulk_${j}`), { uid: ALICE, events: [] });
      }
      await batch.commit();
    }

    await callAs(ALICE);

    const left = await db
      .collection("debug_sessions")
      .where("uid", "==", ALICE)
      .get();
    expect(left.size).toBe(0);
    // Bob's telemetry sits in the same collection and must survive a sweep
    // large enough to span three batches.
    expect((await db.doc(`debug_sessions/session_${BOB}`).get()).exists).toBe(
      true,
    );
  });

  it("cancels subscriptions found on the second page of Stripe results", async () => {
    // `listAllSubscriptions` pages with `starting_after`, and its own comment
    // names a webhook retry storm producing >100 subscriptions as the reason.
    // Nothing exercised the second page, so a broken cursor would have looked
    // exactly like a customer with one page of subscriptions.
    subscriptionsList
      .mockResolvedValueOnce({
        data: [{ id: "sub_page1_a" }, { id: "sub_page1_b" }] as never,
        has_more: true,
      })
      .mockResolvedValueOnce({
        data: [{ id: "sub_page2" }] as never,
        has_more: false,
      });
    await db.doc(`users/${ALICE}/subscription/main`).set({
      stripeCustomerId: "cus_alice",
    });

    await callAs(ALICE);

    expect(subscriptionsList).toHaveBeenCalledTimes(2);
    // The cursor is the LAST id of the previous page; sending the first would
    // re-read page one forever.
    expect(subscriptionsList).toHaveBeenLastCalledWith(
      expect.objectContaining({ starting_after: "sub_page1_b" }),
    );
    for (const id of ["sub_page1_a", "sub_page1_b", "sub_page2"]) {
      expect(subscriptionsCancel).toHaveBeenCalledWith(id);
    }
  });

  it("deletes a booking once both sides are gone", async () => {
    // The second deletion of a pair. Nobody can read this row again, so
    // keeping it would only accumulate unreadable history.
    await db.doc("coach_bookings/both_gone").set({
      clientUid: ALICE,
      coachUid: DELETED_UID,
    });

    await callAs(ALICE);

    expect((await db.doc("coach_bookings/both_gone").get()).exists).toBe(false);
  });

  it("deletes the Auth user, and only that one", async () => {
    await callAs(ALICE);

    await expect(auth.getUser(ALICE)).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
    expect((await auth.getUser(BOB)).uid).toBe(BOB);
  });

  it("cancels every Stripe subscription on the customer before deleting", async () => {
    subscriptionsList.mockResolvedValueOnce({
      data: [{ id: "sub_remembered" }, { id: "sub_forgotten" }] as never,
      has_more: false,
    });
    await db.doc(`users/${ALICE}/subscription/main`).set({
      tier: "standard",
      stripeSubscriptionId: "sub_remembered",
      stripeCustomerId: "cus_alice",
    });

    await callAs(ALICE);

    // The second one is the whole point: it bills, and the user's own document
    // has no idea it exists.
    expect(subscriptionsCancel).toHaveBeenCalledWith("sub_remembered");
    expect(subscriptionsCancel).toHaveBeenCalledWith("sub_forgotten");
    expect((await db.doc(`users/${ALICE}`).get()).exists).toBe(false);
  });

  it("is safe to run twice", async () => {
    // The client retries on a dropped response, and the Auth user is already
    // gone by then. A second call must converge, not error.
    await callAs(ALICE);
    await expect(callAs(ALICE)).resolves.toMatchObject({ success: true });

    expect(await readUser(BOB)).toMatchObject({ root: true, deep: true });
  });
});
