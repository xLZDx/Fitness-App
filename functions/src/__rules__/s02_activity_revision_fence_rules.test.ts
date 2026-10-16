/**
 * S02 test epic 5 -- revision ordering, tombstone, account-deletion fence and
 * the batched-write access-call limit of the activity summary block.
 * Plan ids: R26, R32, R33, R34, R35, R36, R37.
 *
 * Decision recorded in S02_TEST_FINDINGS_EPIC5.md: the plan wording of R32 and
 * R34 is inverted relative to the design. The design (3.2, 4) and the rules say:
 * `create` requires rev == 1; `update` requires rev STRICTLY GREATER than the
 * stored value, so a resent identical rev (lost acknowledgement) and an older
 * rev are refused, and stored + 1 and stored + 5 are accepted. These tests
 * follow the design.
 *
 * Every refusal is paired with an accepted control write at the same id (the
 * same body once the blocker is gone), so a refusal is proven to come from the
 * `exists()` check or the rev rule and not from a body error.
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc, writeBatch } from "firebase/firestore";
import {
  ALICE,
  BOB,
  actId,
  activityPath,
  loadGolden,
  makeEnv,
  summary,
  toWireSummary,
  ts,
} from "./s02_rules_support";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await makeEnv("demo-s02-revision");
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const asBob = () => env.authenticatedContext(BOB).firestore();
const aliceRef = (id: string) => doc(asAlice(), activityPath(ALICE, id));

const seed = (path: string, data: Record<string, unknown>) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });

const adminRemove = (path: string) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), path));
  });

const adminRead = async (path: string): Promise<Record<string, any> | null> => {
  let out: Record<string, any> | null = null;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), path));
    out = snap.exists() ? (snap.data() as Record<string, any>) : null;
  });
  return out;
};

const tombstone = (uid: string, id: string) => `users/${uid}/activity_tombstones/${id}`;
const fencePath = (uid: string) => `activity_account_state/${uid}`;
const TOMB = { deletedAt: ts("2026-03-02T10:00:00Z"), expireAt: ts("2027-04-05T10:00:00Z") };
const FENCE = { fenceAt: ts("2026-03-02T10:00:00Z"), lateSweepAt: ts("2026-03-02T10:20:00Z") };

describe("R26 tombstone blocks resurrection (delete wins)", () => {
  test("create of a tombstoned id is refused; the same body for another id and after tombstone removal is accepted", async () => {
    const id = actId(1);
    await seed(tombstone(ALICE, id), TOMB);
    await assertFails(setDoc(aliceRef(id), summary()));
    expect(await adminRead(activityPath(ALICE, id))).toBeNull();
    await assertSucceeds(setDoc(aliceRef(actId(2)), summary())); // control: same body, no tombstone
    await adminRemove(tombstone(ALICE, id));
    await assertSucceeds(setDoc(aliceRef(id), summary())); // control: the denial was the exists() check
    expect((await adminRead(activityPath(ALICE, id)))?.rev).toBe(1);
  });

  test("update of a tombstoned id is refused, and is accepted again once the tombstone is gone", async () => {
    const id = actId(3);
    await seed(activityPath(ALICE, id), summary());
    await seed(tombstone(ALICE, id), TOMB);
    await assertFails(updateDoc(aliceRef(id), { rev: 2, distanceM: 11000 }));
    expect((await adminRead(activityPath(ALICE, id)))?.rev).toBe(1);
    await adminRemove(tombstone(ALICE, id));
    await assertSucceeds(updateDoc(aliceRef(id), { rev: 2, distanceM: 11000 }));
  });

  test("a tombstone of a different activity id or of a different user does not block this write", async () => {
    const id = actId(4);
    await seed(tombstone(ALICE, actId(5)), TOMB); // other id, same user
    await seed(tombstone(BOB, id), TOMB); // same id, other user
    await assertSucceeds(setDoc(aliceRef(id), summary()));
  });

  test("a batch of 8 summary writes (16 access calls) is accepted and all 8 documents exist", async () => {
    const db = asAlice();
    const batch = writeBatch(db);
    for (let i = 0; i < 8; i++) batch.set(doc(db, activityPath(ALICE, actId(100 + i))), summary({ distanceM: 1000 + i }));
    await assertSucceeds(batch.commit());
    for (let i = 0; i < 8; i++) {
      expect((await adminRead(activityPath(ALICE, actId(100 + i))))?.distanceM).toBe(1000 + i);
    }
  });

  test("one tombstoned id inside a batch refuses the WHOLE batch and nothing is written", async () => {
    await seed(tombstone(ALICE, actId(103)), TOMB);
    const db = asAlice();
    const batch = writeBatch(db);
    for (let i = 0; i < 8; i++) batch.set(doc(db, activityPath(ALICE, actId(100 + i))), summary());
    await assertFails(batch.commit());
    for (let i = 0; i < 8; i++) expect(await adminRead(activityPath(ALICE, actId(100 + i)))).toBeNull();
    // Control: without the tombstone the identical batch is accepted.
    await adminRemove(tombstone(ALICE, actId(103)));
    const db2 = asAlice();
    const again = writeBatch(db2);
    for (let i = 0; i < 8; i++) again.set(doc(db2, activityPath(ALICE, actId(100 + i))), summary());
    await assertSucceeds(again.commit());
  });
});

describe("R32 rev on update (strictly greater than the stored rev)", () => {
  const id = actId(10);
  beforeEach(async () => {
    await seed(activityPath(ALICE, id), summary({ rev: 3, distanceM: 3000 }));
  });

  test("equal and lower rev are refused, the stored document is unchanged", async () => {
    for (const rev of [3, 2, 1]) {
      await assertFails(setDoc(aliceRef(id), summary({ rev, distanceM: 9999 })));
      await assertFails(updateDoc(aliceRef(id), { rev, distanceM: 9999 }));
    }
    const stored = await adminRead(activityPath(ALICE, id));
    expect(stored?.rev).toBe(3);
    expect(stored?.distanceM).toBe(3000);
  });

  test("stored + 1 is accepted, then stored + 5 (a jump) is accepted", async () => {
    await assertSucceeds(setDoc(aliceRef(id), summary({ rev: 4, distanceM: 4000 })));
    expect((await adminRead(activityPath(ALICE, id)))?.rev).toBe(4);
    await assertSucceeds(updateDoc(aliceRef(id), { rev: 9, distanceM: 9000 }));
    expect((await adminRead(activityPath(ALICE, id)))?.rev).toBe(9);
  });

  test.each([
    ["0", 0],
    ["1000001", 1000001],
    ["1.5", 4.5],
    ["a string", "4"],
    ["a boolean", true],
    ["a list", [4]],
  ])("rev %s is refused on update next to an accepted control", async (_label, rev) => {
    await assertFails(updateDoc(aliceRef(id), { rev }));
    await assertSucceeds(updateDoc(aliceRef(id), { rev: 4 }));
  });

  test.each([
    ["0", 0],
    ["1000001", 1000001],
    ["1.5", 1.5],
    ["a string", "1"],
  ])("rev %s is refused on create next to an accepted control", async (_label, rev) => {
    const fresh = actId(11);
    await assertFails(setDoc(aliceRef(fresh), summary({ rev })));
    expect(await adminRead(activityPath(ALICE, fresh))).toBeNull();
    await assertSucceeds(setDoc(aliceRef(fresh), summary({ rev: 1 })));
  });
});

describe("R33 rev on create is exactly 1", () => {
  test("create with rev 2 or rev 5 is refused, rev 1 is accepted", async () => {
    const id = actId(20);
    await assertFails(setDoc(aliceRef(id), summary({ rev: 2 })));
    await assertFails(setDoc(aliceRef(id), summary({ rev: 5 })));
    expect(await adminRead(activityPath(ALICE, id))).toBeNull();
    await assertSucceeds(setDoc(aliceRef(id), summary({ rev: 1 })));
  });

  test("a create-shaped write for an id that already exists is evaluated as an update (stored rev 3, sent rev 1 is refused)", async () => {
    const id = actId(21);
    await seed(activityPath(ALICE, id), summary({ rev: 3, distanceM: 3000 }));
    await assertFails(setDoc(aliceRef(id), summary({ rev: 1, distanceM: 1 })));
    await assertFails(setDoc(aliceRef(id), summary({ rev: 3, distanceM: 1 })));
    const stored = await adminRead(activityPath(ALICE, id));
    expect(stored?.rev).toBe(3);
    expect(stored?.distanceM).toBe(3000);
    await assertSucceeds(setDoc(aliceRef(id), summary({ rev: 4, distanceM: 4000 }))); // read-first client path
  });
});

describe("R34 replay of a lost acknowledgement", () => {
  test("a resent identical body and an older body are refused; N+2 is accepted; the highest accepted rev is stored", async () => {
    const id = actId(30);
    await seed(activityPath(ALICE, id), summary({ rev: 1, distanceM: 1000 }));
    const n1 = summary({ rev: 2, distanceM: 2000 });
    await assertSucceeds(setDoc(aliceRef(id), n1)); // accepted at N+1 (lost ack on the client side)
    await assertFails(setDoc(aliceRef(id), n1)); // resent: same rev is refused (routine, not a defect)
    await assertFails(setDoc(aliceRef(id), summary({ rev: 1, distanceM: 1000 }))); // older replay
    expect((await adminRead(activityPath(ALICE, id)))?.distanceM).toBe(2000);
    await assertSucceeds(setDoc(aliceRef(id), summary({ rev: 4, distanceM: 4000 }))); // N+2 style jump
    await assertFails(setDoc(aliceRef(id), summary({ rev: 3, distanceM: 3000 }))); // late older write after the jump
    const stored = await adminRead(activityPath(ALICE, id));
    expect(stored?.rev).toBe(4);
    expect(stored?.distanceM).toBe(4000);
  });

  test("another user's identical body cannot replay into this document", async () => {
    const id = actId(31);
    await seed(activityPath(ALICE, id), summary({ rev: 1 }));
    await assertFails(setDoc(doc(asBob(), activityPath(ALICE, id)), summary({ rev: 2 })));
    await assertSucceeds(setDoc(aliceRef(id), summary({ rev: 2 })));
  });
});

describe("R35 batched-write access-call limit (discovered, design chose 8 summaries = 16 access calls)", () => {
  const SEARCH_FROM = 8;
  const SEARCH_TO = 60;

  async function tryBatch(size: number): Promise<{ ok: boolean; message: string; code: string }> {
    const db = asAlice();
    const batch = writeBatch(db);
    for (let i = 0; i < size; i++) batch.set(doc(db, activityPath(ALICE, actId(size * 1000 + i))), summary({ distanceM: i }));
    try {
      await batch.commit();
      return { ok: true, message: "", code: "" };
    } catch (e) {
      const err = e as { message?: string; code?: string };
      return { ok: false, message: String(err.message), code: String(err.code) };
    }
  }

  test("a batch of 8 is accepted (the repository maximum) and the first rejected size is greater than 8", async () => {
    let firstRejected = -1;
    let rejection = { message: "", code: "" };
    let lastAccepted = -1;
    for (let size = SEARCH_FROM; size <= SEARCH_TO; size++) {
      const result = await tryBatch(size);
      if (size === SEARCH_FROM) {
        expect(result.ok).toBe(true); // if the emulator rejects 8 the design limit must be lowered
      }
      if (result.ok) {
        lastAccepted = size;
        continue;
      }
      firstRejected = size;
      rejection = result;
      // A rejected batch is rejected whole: nothing from it was written.
      for (let i = 0; i < size; i++) {
        expect(await adminRead(activityPath(ALICE, actId(size * 1000 + i)))).toBeNull();
      }
      break;
    }
    console.log(
      `R35 discovered: last accepted batch = ${lastAccepted} summaries, first rejected = ${firstRejected} ` +
        `(nominal access calls = 2 x size = ${2 * firstRejected}); error code=${rejection.code}; message=${rejection.message}`,
    );
    expect(firstRejected).toBeGreaterThan(SEARCH_FROM);
    expect(lastAccepted).toBeGreaterThanOrEqual(SEARCH_FROM);
    expect(rejection.code).toBe("permission-denied");
    // All documents of the accepted sizes exist (the accepted batches really committed).
    expect((await adminRead(activityPath(ALICE, actId(SEARCH_FROM * 1000))))?.distanceM).toBe(0);
  });
});

describe("R36 account-deletion fence blocks client summary writes", () => {
  const golden = loadGolden()[0];
  const body = (rev = 1) => ({ ...toWireSummary(golden.summary), rev });
  const gid = golden.id;

  test("with the fence present an owner create and an owner update are refused; removing the fence accepts them", async () => {
    await seed(fencePath(ALICE), FENCE);
    await assertFails(setDoc(aliceRef(gid), body(1)));
    expect(await adminRead(activityPath(ALICE, gid))).toBeNull();
    await adminRemove(fencePath(ALICE));
    await assertSucceeds(setDoc(aliceRef(gid), body(1))); // control: create was blocked by the fence only
    await seed(fencePath(ALICE), FENCE);
    await assertFails(setDoc(aliceRef(gid), body(2)));
    await assertFails(updateDoc(aliceRef(gid), { rev: 2 }));
    expect((await adminRead(activityPath(ALICE, gid)))?.rev).toBe(1);
    await adminRemove(fencePath(ALICE));
    await assertSucceeds(setDoc(aliceRef(gid), body(2))); // control: update blocked by the fence only
  });

  test("a batch of 8 with the fence present is refused whole and nothing is written", async () => {
    await seed(fencePath(ALICE), FENCE);
    const db = asAlice();
    const batch = writeBatch(db);
    for (let i = 0; i < 8; i++) batch.set(doc(db, activityPath(ALICE, actId(200 + i))), summary());
    await assertFails(batch.commit());
    for (let i = 0; i < 8; i++) expect(await adminRead(activityPath(ALICE, actId(200 + i)))).toBeNull();
    await adminRemove(fencePath(ALICE));
    const db2 = asAlice();
    const again = writeBatch(db2);
    for (let i = 0; i < 8; i++) again.set(doc(db2, activityPath(ALICE, actId(200 + i))), summary());
    await assertSucceeds(again.commit()); // control: the identical batch passes without the fence
  });

  test("replay: a queued put that succeeded before the fence is refused after lateSweepDone is set, with the owner's still-valid token", async () => {
    const owner = env.authenticatedContext(ALICE).firestore(); // one token for the whole scenario
    const queuedRef = doc(owner, activityPath(ALICE, gid));
    await assertSucceeds(setDoc(queuedRef, body(1))); // before the fence
    await seed(fencePath(ALICE), { ...FENCE, lateSweepDone: true, authDeletedAt: ts("2026-03-02T10:05:00Z") });
    await assertFails(setDoc(queuedRef, body(2))); // the replayed queued put (same token)
    await assertFails(updateDoc(queuedRef, { rev: 3 }));
    expect((await adminRead(activityPath(ALICE, gid)))?.rev).toBe(1);
  });

  test("the check is keyed by uid: another uid's own fence absence lets that user write the identical body; a fence for another uid does not block this one", async () => {
    await seed(fencePath(ALICE), FENCE);
    await assertFails(setDoc(aliceRef(gid), body(1)));
    await assertSucceeds(setDoc(doc(asBob(), activityPath(BOB, gid)), body(1))); // Bob has no fence
    await adminRemove(fencePath(ALICE));
    await seed(fencePath(BOB), FENCE); // fence only for Bob
    await assertSucceeds(setDoc(aliceRef(gid), body(1))); // Alice is not blocked by Bob's fence
    await assertFails(setDoc(doc(asBob(), activityPath(BOB, actId(300))), body(1)));
  });

  test("while the fence exists the owner can still read an existing summary and still cannot delete it", async () => {
    await seed(activityPath(ALICE, gid), body(1));
    await seed(fencePath(ALICE), FENCE);
    await assertSucceeds(getDoc(aliceRef(gid)));
    await assertFails(deleteDoc(aliceRef(gid)));
    expect(await adminRead(activityPath(ALICE, gid))).not.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// R37: the numbered creation/removal order of design 6.1 as an integration
// sequence. Time is an explicit number (milliseconds) passed to the protocol
// guard; the timing DECISION itself belongs to the functions test F95. The
// guard below is the "order assertion" of the plan: it rejects out-of-order
// steps, and the emulator proves what the client can do after each step.
// ---------------------------------------------------------------------------
const HOUR = 3600 * 1000;
const MIN = 60 * 1000;

interface Protocol {
  fenceWritten: boolean;
  firstSweepDone: boolean;
  retryDocWritten: boolean;
  authDeletedAt: number | null;
  lateSweepDone: number | null;
}

const newProtocol = (): Protocol => ({
  fenceWritten: false,
  firstSweepDone: false,
  retryDocWritten: false,
  authDeletedAt: null,
  lateSweepDone: null,
});

/** Step 1: the fence must precede the first sweep and any accountDeletionRetries document. */
function guardWriteFence(p: Protocol): void {
  if (p.firstSweepDone) throw new Error("order violation: fence written after the first sweep");
  if (p.retryDocWritten) throw new Error("order violation: fence written after accountDeletionRetries");
  p.fenceWritten = true;
}

/** Step 6: the fence may be removed only at max(lateSweepDone + 1 h, authDeletedAt + 70 min). */
function guardRemoveFence(p: Protocol, now: number): void {
  if (p.lateSweepDone === null) throw new Error("order violation: fence removed before the late sweep is done");
  if (p.authDeletedAt === null) throw new Error("order violation: fence removed although authDeletedAt is not recorded");
  const at = Math.max(p.lateSweepDone + HOUR, p.authDeletedAt + 70 * MIN);
  if (now < at) throw new Error(`order violation: fence removed at ${now}, not before ${at}`);
}

describe("R37 numbered fence creation and removal order (design 6.1)", () => {
  const A = actId(400);
  const B = actId(401);

  test("the order guard itself rejects out-of-order steps (so the sequence below is meaningful)", () => {
    const early = newProtocol();
    early.firstSweepDone = true;
    expect(() => guardWriteFence(early)).toThrow(/after the first sweep/);
    const late = newProtocol();
    late.retryDocWritten = true;
    expect(() => guardWriteFence(late)).toThrow(/accountDeletionRetries/);

    const p = newProtocol();
    p.lateSweepDone = 1000 * HOUR;
    p.authDeletedAt = 1000 * HOUR - 30 * MIN;
    expect(() => guardRemoveFence(p, 1000 * HOUR + HOUR - 1)).toThrow(/not before/); // 1 ms early
    expect(() => guardRemoveFence(p, 1000 * HOUR + HOUR)).not.toThrow();
    // authDeletedAt dominates when it is later.
    p.authDeletedAt = 1000 * HOUR + 30 * MIN;
    expect(() => guardRemoveFence(p, 1000 * HOUR + HOUR)).toThrow(/not before/);
    expect(() => guardRemoveFence(p, 1000 * HOUR + 30 * MIN + 70 * MIN)).not.toThrow();
  });

  test("steps 0-6: the client is writable only before step 1 and after the removal instant", async () => {
    const p = newProtocol();
    const owner = env.authenticatedContext(ALICE).firestore();
    const ownerRef = (id: string) => doc(owner, activityPath(ALICE, id));

    // (0) Before the fence a client write succeeds; the slipped-in document A exists.
    await assertSucceeds(setDoc(ownerRef(A), summary()));
    expect(await adminRead(activityPath(ALICE, A))).not.toBeNull();

    // (1) Fence written BEFORE the first sweep and before any retries document.
    guardWriteFence(p);
    await seed(fencePath(ALICE), FENCE);
    await assertFails(setDoc(ownerRef(actId(402)), summary()));
    await assertFails(updateDoc(ownerRef(A), { rev: 2 }));

    // (2) Admin recursiveDelete-equivalent of users/{uid}: A is removed, the fence (outside users/{uid}) survives.
    p.firstSweepDone = true;
    await adminRemove(activityPath(ALICE, A));
    expect(await adminRead(activityPath(ALICE, A))).toBeNull();
    expect(await adminRead(fencePath(ALICE))).not.toBeNull();
    await assertFails(setDoc(ownerRef(A), summary()));

    // (3) authDeletedAt recorded; the token is still valid and the client is still refused.
    const authDeletedAt = 5000 * HOUR;
    p.authDeletedAt = authDeletedAt;
    await seed(fencePath(ALICE), { ...FENCE, authDeletedAt: ts(new Date(authDeletedAt)) });
    await assertFails(setDoc(ownerRef(A), summary()));

    // (4) Second sweep step: no effect on the fence.
    const before = await adminRead(fencePath(ALICE));
    await adminRemove(`users/${ALICE}/activity_settings/main`); // sweeping nothing is a no-op for the fence
    expect(await adminRead(fencePath(ALICE))).toEqual(before);
    await assertFails(setDoc(ownerRef(A), summary()));

    // (5) Late job: B slipped in before the fence took effect (Admin write) and is removed by the FINAL recursive delete.
    await seed(activityPath(ALICE, B), summary());
    await seed(`users/${ALICE}/activity_streams/${B}`, { state: "stored" });
    await seed(`users/${ALICE}/activity_settings/main`, { streamRetentionDays: 30 });
    await seed(tombstone(ALICE, B), TOMB);
    for (const path of [
      activityPath(ALICE, B),
      `users/${ALICE}/activity_streams/${B}`,
      `users/${ALICE}/activity_settings/main`,
      tombstone(ALICE, B),
    ]) {
      await adminRemove(path);
      expect(await adminRead(path)).toBeNull();
    }
    const lateSweepDone = authDeletedAt + 10 * MIN;
    p.lateSweepDone = lateSweepDone;
    await seed(fencePath(ALICE), { ...FENCE, authDeletedAt: ts(new Date(authDeletedAt)), lateSweepDone: ts(new Date(lateSweepDone)) });
    await assertFails(setDoc(ownerRef(A), summary())); // client STILL refused

    // (6) Removal only at max(lateSweepDone + 1 h, authDeletedAt + 70 min).
    const removeAt = Math.max(lateSweepDone + HOUR, authDeletedAt + 70 * MIN);
    expect(removeAt).toBe(authDeletedAt + 70 * MIN); // lateSweepDone + 1 h = +70 min as well; both agree here
    expect(() => guardRemoveFence(p, removeAt - 1)).toThrow(); // one millisecond early: the guard refuses, the fence stays
    await assertFails(setDoc(ownerRef(A), summary()));
    guardRemoveFence(p, removeAt);
    await adminRemove(fencePath(ALICE));
    await assertSucceeds(setDoc(ownerRef(A), summary())); // only now is a client write accepted
  });

  test("crash before authDeletedAt: the fence is not removed at lateSweepDone + 1 h alone and the client stays refused", async () => {
    const p = newProtocol();
    guardWriteFence(p);
    await seed(fencePath(ALICE), FENCE); // no authDeletedAt: the process crashed before Step 3b
    p.lateSweepDone = 2000 * HOUR;
    await seed(fencePath(ALICE), { ...FENCE, lateSweepDone: ts(new Date(p.lateSweepDone)) });
    expect(() => guardRemoveFence(p, p.lateSweepDone! + HOUR)).toThrow(/authDeletedAt is not recorded/);
    expect(() => guardRemoveFence(p, p.lateSweepDone! + 100 * HOUR)).toThrow(/authDeletedAt is not recorded/);
    await assertFails(setDoc(doc(env.authenticatedContext(ALICE).firestore(), activityPath(ALICE, A)), summary()));
    expect(await adminRead(fencePath(ALICE))).not.toBeNull();
  });
});
