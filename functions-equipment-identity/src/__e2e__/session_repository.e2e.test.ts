/**
 * P2.G3 T6 -- the real runtime session-mutation test that
 * `p1/authority_tuple.ts`'s own doc comment explicitly defers to this gate:
 * "The *runtime* session-mutation test (proving a live identity-resolution
 * session cannot have its authority tuple changed mid-flight) is P2.G3's
 * DoD item ... see that gate." Against a real Firestore emulator, not a
 * mock -- the property being proven is that the ADMIN SDK write path
 * itself (which bypasses Security Rules entirely) still refuses the
 * mutation, which only a real transaction can demonstrate.
 *
 * Redesigned around the admit/finalize two-phase lifecycle (GPT-PM MAJOR,
 * P2.G3 pre-commit review round 3, 2026-09-11) -- see session_repository.ts's
 * own header comment for why.
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import type { RecognitionAuthorityTuple } from "../p1/contracts";
import { userEquipmentIdentitySessionDocPath } from "../p1/firestore_paths";
import { userEquipmentIdentityLatestSessionDocPath } from "../p2/firestore_paths";
import {
  admitSessionClaim,
  finalizeSessionOutcome,
  readSession,
  readLatestSession,
} from "../p2/session_repository";
import { usageDocRef, IDENTITY_TEXT_LOOKUP_ACTION, IDENTITY_TEXT_LOOKUP_DAILY_LIMIT } from "../p2/quota";

function randomUid(): string {
  return `e2e-session-uid-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function authority(overrides: Partial<RecognitionAuthorityTuple> = {}): RecognitionAuthorityTuple {
  return {
    catalogVersion: "catalog-v1",
    ocrVersion: "ocr-1.0.0",
    textPolicyVersion: "text-policy-1",
    fusionPolicyVersion: "none",
    identityPolicyVersion: "identity-policy-1",
    ...overrides,
  };
}

const MODEL_ID = "11111111-1111-4111-8111-111111111111";

function matchOutcome(overrides: Partial<{ textSupportStatus: "EXPERIMENTAL" | "VERIFIED"; modelId: string }> = {}) {
  return {
    modelId: overrides.modelId ?? MODEL_ID,
    catalogVersion: "catalog-v1",
    textSupportStatus: overrides.textSupportStatus ?? ("VERIFIED" as const),
  };
}

async function todayUsage(uid: string): Promise<number> {
  const day = new Date().toISOString().slice(0, 10);
  const snap = await usageDocRef(uid, day).get();
  return (snap.data()?.[IDENTITY_TEXT_LOOKUP_ACTION] as number | undefined) ?? 0;
}

afterAll(async () => {
  await admin.app().delete();
});

describe("admitSessionClaim -- real Firestore admission semantics", () => {
  test("a fresh admission creates a PENDING claim and charges quota atomically", async () => {
    const uid = randomUid();
    const result = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    expect(result.outcome).toBe("ADMITTED");

    const session = await readSession(uid, "session-1");
    expect(session?.status).toBe("PENDING");

    expect(await todayUsage(uid)).toBe(1);
  });

  test("admission advances readLatestSession immediately, at claim time -- not only once finalized", async () => {
    const uid = randomUid();
    await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");

    const latest = await readLatestSession(uid);
    expect(latest?.recognitionSessionId).toBe("session-1");
    expect(latest?.scanId).toBe("scan-1");
  });

  test("a concurrent duplicate under the SAME fingerprint while the claim is still live -> WAIT, no second quota charge", async () => {
    const uid = randomUid();
    await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    const second = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    expect(second.outcome).toBe("WAIT");
    expect(await todayUsage(uid)).toBe(1);
  });

  test("a conflicting fingerprint under the SAME scanId while the claim is still live -> STALE, no quota charge", async () => {
    const uid = randomUid();
    await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    const second = await admitSessionClaim(uid, "session-1", "scan-1", "fp-2");
    expect(second.outcome).toBe("STALE");
    expect(await todayUsage(uid)).toBe(1);
  });

  test("after RESOLVED, re-admission with the IDENTICAL fingerprint -> REPLAY with the resolved record", async () => {
    const uid = randomUid();
    const admitted = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    if (admitted.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    await finalizeSessionOutcome(uid, "session-1", authority(), {
      requestFingerprint: "fp-1",
      claimId: admitted.claimId,
      matchOutcome: matchOutcome(),
    });

    const retry = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    expect(retry.outcome).toBe("REPLAY");
    if (retry.outcome === "REPLAY") {
      expect(retry.record.matchOutcome).toEqual(matchOutcome());
    }
    expect(await todayUsage(uid)).toBe(1); // the replay never re-charges
  });

  test("after RESOLVED, re-admission with a DIFFERENT fingerprint -> STALE", async () => {
    const uid = randomUid();
    const admitted = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    if (admitted.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    await finalizeSessionOutcome(uid, "session-1", authority(), {
      requestFingerprint: "fp-1",
      claimId: admitted.claimId,
      matchOutcome: matchOutcome(),
    });

    const conflicting = await admitSessionClaim(uid, "session-1", "scan-1", "fp-2");
    expect(conflicting.outcome).toBe("STALE");
  });

  test("RATE_LIMITED once the daily limit is already reached, no claim written", async () => {
    const uid = randomUid();
    const day = new Date().toISOString().slice(0, 10);
    await usageDocRef(uid, day).set({ [IDENTITY_TEXT_LOOKUP_ACTION]: IDENTITY_TEXT_LOOKUP_DAILY_LIMIT });

    const result = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    expect(result.outcome).toBe("RATE_LIMITED");
    expect(await readSession(uid, "session-1")).toBeNull();
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review round 4, 2026-09-11 (correcting
  // round 3's own remediation): reclaiming an expired lease is fenced by a
  // NEW claimId generation, and is only ever allowed for the identical
  // logical request the expired claim itself recorded, while this session
  // is still this uid's latest admission. A genuine crash-recovery retry --
  // same fingerprint, still latest -- IS reclaimable.
  test("a PENDING claim past its lease is safely reclaimed by a genuine retry of the SAME request -- no separate sweeper needed", async () => {
    const uid = randomUid();
    const ref = admin.firestore().doc(userEquipmentIdentitySessionDocPath(uid, "session-1"));
    // Seed a PENDING claim directly, with a lease already in the past --
    // simulates a request that crashed or hung before ever finalizing --
    // and its OWN latest pointer, exactly as a real admission would have
    // written both.
    await ref.set({
      schemaVersion: 1,
      status: "PENDING",
      scanId: "scan-1",
      requestFingerprint: "fp-retry",
      claimId: "claim-dead",
      createdAt: new Date(Date.now() - 60_000).toISOString(),
      leaseExpiresAt: new Date(Date.now() - 1_000).toISOString(),
    });
    await admin
      .firestore()
      .doc(userEquipmentIdentityLatestSessionDocPath(uid))
      .set({ recognitionSessionId: "session-1", scanId: "scan-1", pinnedAt: new Date(Date.now() - 60_000).toISOString() });

    // A genuine retry of the SAME original request -- identical fingerprint.
    const result = await admitSessionClaim(uid, "session-1", "scan-1", "fp-retry");
    expect(result.outcome).toBe("ADMITTED");
    if (result.outcome === "ADMITTED") {
      expect(result.claimId).not.toBe("claim-dead");
    }

    const session = await readSession(uid, "session-1");
    expect(session?.status).toBe("PENDING");
    if (session?.status === "PENDING") {
      expect(session.requestFingerprint).toBe("fp-retry");
    }
    // The reclaim itself must not re-charge quota -- this (uid, sessionId)
    // already paid for itself at its original (seeded) admission.
    expect(await todayUsage(uid)).toBe(0);
  });

  test("an expired claim for a scan a genuinely NEWER scan has already superseded -> STALE, never resurrects itself as latest again", async () => {
    const uid = randomUid();
    // A is admitted first, then its lease is allowed to lapse (simulated by
    // seeding it directly already-expired, exactly like the reclaim test
    // above -- this IS what a real expired PENDING claim looks like).
    const refA = admin.firestore().doc(userEquipmentIdentitySessionDocPath(uid, "session-a"));
    await refA.set({
      schemaVersion: 1,
      status: "PENDING",
      scanId: "scan-a",
      requestFingerprint: "fp-a",
      claimId: "claim-a-dead",
      createdAt: new Date(Date.now() - 60_000).toISOString(),
      leaseExpiresAt: new Date(Date.now() - 1_000).toISOString(),
    });

    // B is admitted and fully resolved -- genuinely the latest scan now.
    const admitB = await admitSessionClaim(uid, "session-b", "scan-b", "fp-b");
    expect(admitB.outcome).toBe("ADMITTED");
    if (admitB.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    await finalizeSessionOutcome(uid, "session-b", authority(), {
      requestFingerprint: "fp-b",
      claimId: admitB.claimId,
      matchOutcome: matchOutcome({ modelId: "model-b" }),
    });
    expect(await todayUsage(uid)).toBe(1);

    // A late retry of A's own original request (same fingerprint) arrives
    // after A's lease expired AND after B has already become latest -- this
    // must be STALE, never a resurrection of A as latest, and never a
    // second quota charge.
    const retryA = await admitSessionClaim(uid, "session-a", "scan-a", "fp-a");
    expect(retryA.outcome).toBe("STALE");
    expect(await todayUsage(uid)).toBe(1);

    const latest = await readLatestSession(uid);
    expect(latest?.recognitionSessionId).toBe("session-b");
  });

  test("an expired claim reclaimed by a genuine retry fences out its own still-alive original owner -- that owner's later finalize is ABANDONED, never overwrites the reclaimer", async () => {
    const uid = randomUid();
    const admitA1 = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    expect(admitA1.outcome).toBe("ADMITTED");
    if (admitA1.outcome !== "ADMITTED") throw new Error("expected ADMITTED");

    // A1's lease lapses without it ever finalizing (simulated the same way
    // as the other expired-lease tests: seed the doc directly, past-expiry,
    // preserving A1's own claimId so its later finalize call below is using
    // a genuinely real, previously-issued generation token).
    const ref = admin.firestore().doc(userEquipmentIdentitySessionDocPath(uid, "session-1"));
    await ref.update({ leaseExpiresAt: new Date(Date.now() - 1_000).toISOString() });

    // A2 is a genuine retry of the SAME original request -- reclaims the
    // expired slot with a NEW claimId.
    const admitA2 = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    expect(admitA2.outcome).toBe("ADMITTED");
    if (admitA2.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    expect(admitA2.claimId).not.toBe(admitA1.claimId);

    // A1 was NOT actually dead -- it was merely slow, and only now (after
    // A2 already reclaimed its slot) gets around to calling finalize with
    // its own, now-stale claimId. This must NOT finalize A2's live claim.
    const finalizeA1 = await finalizeSessionOutcome(uid, "session-1", authority(), {
      requestFingerprint: "fp-1",
      claimId: admitA1.claimId,
      matchOutcome: matchOutcome({ modelId: "model-a1" }),
    });
    expect(finalizeA1.outcome).toBe("ABANDONED");

    // A2's own claim is untouched and still genuinely finalizable.
    const finalizeA2 = await finalizeSessionOutcome(uid, "session-1", authority(), {
      requestFingerprint: "fp-1",
      claimId: admitA2.claimId,
      matchOutcome: matchOutcome({ modelId: "model-a2" }),
    });
    expect(finalizeA2.outcome).toBe("RESOLVED");
    if (finalizeA2.outcome === "RESOLVED") {
      expect(finalizeA2.record.matchOutcome.modelId).toBe("model-a2");
    }
  });

  test("an expired claim under a DIFFERENT fingerprint -> STALE, never becomes a second owner of the same logical scan", async () => {
    const uid = randomUid();
    const ref = admin.firestore().doc(userEquipmentIdentitySessionDocPath(uid, "session-1"));
    await ref.set({
      schemaVersion: 1,
      status: "PENDING",
      scanId: "scan-1",
      requestFingerprint: "fp-original",
      claimId: "claim-dead",
      createdAt: new Date(Date.now() - 60_000).toISOString(),
      leaseExpiresAt: new Date(Date.now() - 1_000).toISOString(),
    });

    const result = await admitSessionClaim(uid, "session-1", "scan-1", "fp-different-evidence");
    expect(result.outcome).toBe("STALE");

    // Untouched -- no reclaim, no quota charge, the dead claim is still
    // exactly what was seeded.
    expect(await todayUsage(uid)).toBe(0);
    const session = await readSession(uid, "session-1");
    if (session?.status === "PENDING") {
      expect(session.claimId).toBe("claim-dead");
    } else {
      throw new Error("expected the seeded PENDING claim to be untouched");
    }
  });

  test("concurrent first-time admissions of the SAME (uid, scanId, fingerprint) converge -- exactly one ADMITTED, the rest WAIT, quota charged exactly once", async () => {
    const uid = randomUid();
    const results = await Promise.all(
      Array.from({ length: 5 }, () => admitSessionClaim(uid, "session-concurrent-1", "scan-1", "fp-1")),
    );
    const admitted = results.filter((r) => r.outcome === "ADMITTED");
    const waiting = results.filter((r) => r.outcome === "WAIT");
    expect(admitted.length).toBe(1);
    expect(waiting.length).toBe(4);
    expect(await todayUsage(uid)).toBe(1);
  });
});

describe("finalizeSessionOutcome -- real Firestore finalize semantics", () => {
  test("finalizing an admitted claim transitions it to RESOLVED", async () => {
    const uid = randomUid();
    const admitted = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    if (admitted.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    const result = await finalizeSessionOutcome(uid, "session-1", authority(), {
      requestFingerprint: "fp-1",
      claimId: admitted.claimId,
      matchOutcome: matchOutcome(),
    });
    expect(result.outcome).toBe("RESOLVED");

    const session = await readSession(uid, "session-1");
    expect(session?.status).toBe("RESOLVED");
    if (session?.status === "RESOLVED") {
      expect(session.matchOutcome).toEqual(matchOutcome());
    }
  });

  test("finalizing without ever having been admitted -> ABANDONED, writes nothing", async () => {
    const uid = randomUid();
    const result = await finalizeSessionOutcome(uid, "session-never-admitted", authority(), {
      requestFingerprint: "fp-1",
      claimId: "no-such-claim",
      matchOutcome: matchOutcome(),
    });
    expect(result.outcome).toBe("ABANDONED");
    expect(await readSession(uid, "session-never-admitted")).toBeNull();
  });

  test("finalizing twice for the same claim -- the SECOND attempt is ABANDONED, never overwrites the first RESOLVED record (the runtime immutability guarantee P1.G1's authority_tuple.ts DoD comment defers to this gate)", async () => {
    const uid = randomUid();
    const admitted = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    if (admitted.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    const first = await finalizeSessionOutcome(uid, "session-1", authority({ catalogVersion: "catalog-v1" }), {
      requestFingerprint: "fp-1",
      claimId: admitted.claimId,
      matchOutcome: matchOutcome(),
    });
    expect(first.outcome).toBe("RESOLVED");

    // A second finalize attempt for the SAME claim (same claimId too -- this
    // proves the STATUS-based guard rejects it even when the generation
    // token still matches), with a DIFFERENT authority/outcome -- as if a
    // duplicate finalize call somehow fired twice for the one logical
    // resolution.
    const second = await finalizeSessionOutcome(
      uid,
      "session-1",
      authority({ catalogVersion: "catalog-v2" }),
      { requestFingerprint: "fp-1", claimId: admitted.claimId, matchOutcome: matchOutcome({ modelId: "different-model" }) },
    );
    expect(second.outcome).toBe("ABANDONED");

    // A real, direct read -- not either function's own return value --
    // proves the FIRST resolution is what actually persisted, untouched.
    const directSnap = await admin.firestore().doc(userEquipmentIdentitySessionDocPath(uid, "session-1")).get();
    expect(directSnap.data()?.authority?.catalogVersion).toBe("catalog-v1");
    expect(directSnap.data()?.matchOutcome?.modelId).toBe(MODEL_ID);
  });

  // The CENTERPIECE proof for GPT-PM's round-3 finding: a slow-running scan
  // (A) admitted BEFORE a faster, later scan (B) must never win the
  // "latest" race just because it finishes last -- B's own admission
  // (which happens strictly after A's) already advanced the latest
  // pointer, so A's eventual finalize must discover it lost, regardless of
  // finish order.
  test("a scan admitted FIRST but finalized LAST loses to a scan admitted and finalized in between -- SUPERSEDED, never a real result", async () => {
    const uid = randomUid();
    // A starts first (e.g. a slow request).
    const admitA = await admitSessionClaim(uid, "session-a", "scan-a", "fp-a");
    expect(admitA.outcome).toBe("ADMITTED");
    if (admitA.outcome !== "ADMITTED") throw new Error("expected ADMITTED");

    // B starts later and finishes quickly -- genuinely later admission.
    const admitB = await admitSessionClaim(uid, "session-b", "scan-b", "fp-b");
    expect(admitB.outcome).toBe("ADMITTED");
    if (admitB.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    const finalizeB = await finalizeSessionOutcome(uid, "session-b", authority(), {
      requestFingerprint: "fp-b",
      claimId: admitB.claimId,
      matchOutcome: matchOutcome({ modelId: "model-b" }),
    });
    expect(finalizeB.outcome).toBe("RESOLVED");

    const latestAfterB = await readLatestSession(uid);
    expect(latestAfterB?.recognitionSessionId).toBe("session-b");

    // A finally finishes its own (independently computed) pipeline run --
    // it must NOT emit a real result now that B has already superseded it.
    const finalizeA = await finalizeSessionOutcome(uid, "session-a", authority(), {
      requestFingerprint: "fp-a",
      claimId: admitA.claimId,
      matchOutcome: matchOutcome({ modelId: "model-a" }),
    });
    expect(finalizeA.outcome).toBe("SUPERSEDED");

    // A retry of scan A now gets a FAST, correct STALE answer -- no lease
    // wait needed, because SUPERSEDED is terminal.
    const retryA = await admitSessionClaim(uid, "session-a", "scan-a", "fp-a");
    expect(retryA.outcome).toBe("STALE");

    // The latest pointer still correctly names B, untouched by A's own
    // (superseded) finalize attempt.
    const latestAfterA = await readLatestSession(uid);
    expect(latestAfterA?.recognitionSessionId).toBe("session-b");
  });

  test("readLatestSession returns null for a uid with no admitted session yet", async () => {
    const uid = randomUid();
    expect(await readLatestSession(uid)).toBeNull();
  });

  test("requestFingerprint and matchOutcome round-trip through a real read", async () => {
    const uid = randomUid();
    const admitted = await admitSessionClaim(uid, "session-1", "scan-1", "a-real-fingerprint");
    if (admitted.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    await finalizeSessionOutcome(uid, "session-1", authority(), {
      requestFingerprint: "a-real-fingerprint",
      claimId: admitted.claimId,
      matchOutcome: matchOutcome({ textSupportStatus: "EXPERIMENTAL" }),
    });

    const reread = await readSession(uid, "session-1");
    expect(reread?.status).toBe("RESOLVED");
    if (reread?.status === "RESOLVED") {
      expect(reread.requestFingerprint).toBe("a-real-fingerprint");
      expect(reread.matchOutcome).toEqual(matchOutcome({ textSupportStatus: "EXPERIMENTAL" }));
    }
  });

  test("pinning an authority tuple with a literal undefined optional field does not throw against real Firestore (regression: this exact shape previously crashed every MATCH with no identityParserVersion)", async () => {
    const uid = randomUid();
    const admitted = await admitSessionClaim(uid, "session-1", "scan-1", "fp-1");
    if (admitted.outcome !== "ADMITTED") throw new Error("expected ADMITTED");
    // Deliberately NOT using orchestrator.ts's own conditional-spread
    // discipline here -- this constructs the tuple the "naive" way a future
    // caller might, to prove the write path itself (not just one careful
    // producer) is safe against it.
    const a = { ...authority(), identityParserVersion: undefined } as RecognitionAuthorityTuple;

    await expect(
      finalizeSessionOutcome(uid, "session-1", a, {
        requestFingerprint: "fp-1",
        claimId: admitted.claimId,
        matchOutcome: matchOutcome(),
      }),
    ).resolves.not.toThrow();

    const reread = await readSession(uid, "session-1");
    if (reread?.status === "RESOLVED") {
      expect(reread.authority.catalogVersion).toBe(a.catalogVersion);
      expect(Object.prototype.hasOwnProperty.call(reread.authority, "identityParserVersion")).toBe(false);
    } else {
      throw new Error("expected a RESOLVED session");
    }
  });

  test("readSession returns null for a session that was never admitted", async () => {
    const uid = randomUid();
    expect(await readSession(uid, "never-created")).toBeNull();
  });
});
