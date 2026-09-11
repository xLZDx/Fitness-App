/**
 * P2.G3 -- the full callable pipeline (`resolveEquipmentIdentityFromText`)
 * against a real Firestore emulator: contract validation -> admission
 * (session ownership/latest-scan ordering/quota, all atomic) -> the real
 * `equipment_catalog_active/current` pointer -> the real
 * `equipment_model_text_keys` lookup -> the real `evaluateExactResolutionPolicy`
 * -> the real pre-emission revocation re-read -> the real finalize.
 * `orchestrator.test.ts` already proves the orchestrator's OWN
 * branching/mapping logic against mocked collaborators; this file proves
 * those real collaborators actually agree with each other end to end,
 * which a mock can only assert, never prove.
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import type { CatalogActivePointer, EquipmentModel } from "../p1/contracts";
import { CATALOG_ACTIVE_POINTER_DOC_PATH, modelDocPath, userEquipmentIdentitySessionDocPath } from "../p1/firestore_paths";
import { materializeAndWrite, FirestoreTextKeyStore } from "../p2/text_key_index";
import { resolveEquipmentIdentityFromText } from "../p2/orchestrator";
import { CURRENT_IDENTITY_CONTRACT_VERSION } from "../p2/contract";
import * as catalogReader from "../p2/catalog_reader";
import * as sessionRepository from "../p2/session_repository";

const store = new FirestoreTextKeyStore();

function randomUid(): string {
  return `e2e-orch-uid-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function randomCatalogVersion(): string {
  return `e2e-orch-catalog-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function makeProvenance(): EquipmentModel["provenance"][number] {
  return {
    sourceId: "technogym_interior_design",
    sourceUrl: "https://www.technogym.com/product/selection-leg-press",
    retrievedAt: "2026-08-22T00:00:00Z",
    fixtureSha256: "a".repeat(64),
    adapterId: "technogym-adapter",
    adapterVersion: "1.0.0",
    fields: ["canonicalName", "modelCode"],
  };
}

function makeModel(catalogVersion: string, overrides: Partial<EquipmentModel> = {}): EquipmentModel {
  return {
    schemaVersion: 1,
    modelId: "11111111-1111-4111-8111-111111111111",
    canonicalSlug: "technogym-selection-leg-press",
    brandId: "technogym",
    productLineId: "technogym-selection",
    canonicalName: "Selection Leg Press",
    modelCode: "8TRX",
    skuAliases: [],
    primaryTypeId: "some-type",
    supportedTypeIds: ["some-type"],
    aliases: [],
    catalogStatus: "ACTIVE",
    textSupportStatus: "VERIFIED",
    visionSupportStatus: "NONE",
    sourceConfidence: "OFFICIAL",
    catalogVersion,
    provenance: [makeProvenance()],
    ...overrides,
  } as EquipmentModel;
}

async function seedModel(model: EquipmentModel): Promise<void> {
  await admin.firestore().doc(modelDocPath(model.catalogVersion, model.modelId)).set(model);
  await materializeAndWrite(model, store);
}

async function seedActiveCatalogPointer(catalogVersion: string): Promise<void> {
  const pointer: CatalogActivePointer = {
    schemaVersion: 1,
    activeCatalogVersion: catalogVersion,
    releaseStage: "SHADOW_INTERNAL",
    approvalSha256: "b".repeat(64),
    activatedAt: "2026-08-22T00:00:00Z",
  };
  await admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).set(pointer);
}

async function clearActiveCatalogPointer(): Promise<void> {
  await admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).delete();
}

function baseRequest(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    scanId: `scan-${Date.now()}`,
    identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
    clientCapabilities: [],
    evidence: {
      brandCandidates: ["technogym"],
      productLineCandidates: [],
      modelCodeCandidates: ["8TRX"],
      typeHints: [],
      conflicts: [],
    },
    ocrVersion: "ocr-1.0.0",
    ...overrides,
  } as never;
}

afterAll(async () => {
  await admin.app().delete();
});

describe("resolveEquipmentIdentityFromText -- real end-to-end pipeline", () => {
  test("a VERIFIED model resolves to a real MATCH, and the session is really pinned in Firestore", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const response = await resolveEquipmentIdentityFromText({ uid, request: baseRequest() });

    expect(response.decision).toBe("MATCH");
    expect(response.identityLevel).toBe("EXACT_MODEL");
    expect(response.verifierInvoked).toBe(false);
    expect(response.model).toEqual({
      modelId: model.modelId,
      catalogVersion,
      textSupportStatus: "VERIFIED",
    });
    expect(response.authority.catalogVersion).toBe(catalogVersion);

    const sessionSnap = await admin
      .firestore()
      .doc(userEquipmentIdentitySessionDocPath(uid, response.recognitionSessionId))
      .get();
    expect(sessionSnap.exists).toBe(true);
    expect(sessionSnap.data()?.scanId).toBeDefined();
    expect(sessionSnap.data()?.authority.catalogVersion).toBe(catalogVersion);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11 (correcting
  // round 1's own matchAuthority side-channel remediation): a shadow-only
  // (EXPERIMENTAL) exact resolution is gathered as non-authoritative shadow
  // evidence -- it is still pinned in Firestore -- but the RESPONSE is
  // NOT_SUPPORTED with a shadowCandidate, never a MATCH (v4.4 binds
  // MATCH/EXACT_MODEL to VERIFIED text support only).
  test("an EXPERIMENTAL model resolves to NOT_SUPPORTED + shadowCandidate (not a MATCH) while the platform is not READY_FOR_PRODUCTION (real app_check_readiness artifact is BLOCKED_EXTERNAL_PLATFORM_MIGRATION), and is still pinned as shadow evidence", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "EXPERIMENTAL" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const response = await resolveEquipmentIdentityFromText({ uid, request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
    expect(response.model).toBeUndefined();
    expect(response.shadowCandidate).toEqual({
      modelId: model.modelId,
      catalogVersion,
      textSupportStatus: "EXPERIMENTAL",
    });

    // Still really pinned in Firestore as shadow evidence, not discarded.
    const sessionSnap = await admin
      .firestore()
      .doc(userEquipmentIdentitySessionDocPath(uid, response.recognitionSessionId))
      .get();
    expect(sessionSnap.exists).toBe(true);
    expect(sessionSnap.data()?.matchOutcome).toEqual({
      modelId: model.modelId,
      catalogVersion,
      textSupportStatus: "EXPERIMENTAL",
    });
  });

  test("a model with textSupportStatus NONE never emits an exact claim", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "NONE" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const response = await resolveEquipmentIdentityFromText({ uid: randomUid(), request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
    expect(response.model).toBeUndefined();
  });

  test("no active catalog pointer -> UNAVAILABLE_CATALOG_VERSION, an honest reflection of nothing published yet", async () => {
    await clearActiveCatalogPointer();
    const response = await resolveEquipmentIdentityFromText({ uid: randomUid(), request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(response.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
  });

  test("an unresolvable candidate against the pinned catalog -> NOT_SUPPORTED, no false match", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const response = await resolveEquipmentIdentityFromText({
      uid: randomUid(),
      request: baseRequest({
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["NOSUCHCODE"],
          typeHints: [],
          conflicts: [],
        },
      }),
    });
    expect(response.decision).toBe("NOT_SUPPORTED");
  });

  test("two candidates resolving to different real models -> real ABSTAIN/EVIDENCE_CONFLICT, drawn from real catalog data", async () => {
    const catalogVersion = randomCatalogVersion();
    const modelA = makeModel(catalogVersion, {
      modelId: "11111111-1111-4111-8111-111111111111",
      modelCode: "8TRX",
      textSupportStatus: "VERIFIED",
    });
    const modelB = makeModel(catalogVersion, {
      modelId: "22222222-2222-4222-8222-222222222222",
      modelCode: "9XYZ",
      textSupportStatus: "VERIFIED",
    });
    await seedModel(modelA);
    await seedModel(modelB);
    await seedActiveCatalogPointer(catalogVersion);

    const response = await resolveEquipmentIdentityFromText({
      uid: randomUid(),
      request: baseRequest({
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["8TRX", "9XYZ"],
          typeHints: [],
          conflicts: [],
        },
      }),
    });
    expect(response.decision).toBe("ABSTAIN");
    expect(response.abstainReason).toBe("EVIDENCE_CONFLICT");
  });

  test("revocation after pinning: a model demoted to DISCONTINUED after a first successful match blocks a later emission for the same code", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED", catalogStatus: "ACTIVE" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const first = await resolveEquipmentIdentityFromText({ uid: randomUid(), request: baseRequest() });
    expect(first.decision).toBe("MATCH");

    // Demote the SAME model doc directly, as a real catalog revocation
    // would -- the derived text-key index is untouched (this simulates a
    // status change on an already-materialized model, the exact scenario
    // v4.4 §6.6's authoritative-pre-emission-read bound exists for).
    await admin
      .firestore()
      .doc(modelDocPath(catalogVersion, model.modelId))
      .set({ ...model, catalogStatus: "DISCONTINUED" });

    const second = await resolveEquipmentIdentityFromText({ uid: randomUid(), request: baseRequest() });
    expect(second.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(second.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
  });

  test("quota is really charged against the caller's own users/{uid}/usage/{day} document", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    await resolveEquipmentIdentityFromText({ uid, request: baseRequest() });

    const today = new Date().toISOString().slice(0, 10);
    const usageSnap = await admin.firestore().doc(`users/${uid}/usage/${today}`).get();
    expect(usageSnap.data()?.identityTextLookup).toBe(1);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: this test previously
  // locked in the buggy behavior it's named after -- every retry of the
  // SAME (uid, scanId) minted a fresh session and paid quota again, with
  // no idempotency of any kind. recognitionSessionId is now deterministic
  // per (uid, scanId); a genuine retry of the identical request replays
  // the already-pinned outcome instead of creating a second session.
  test("a repeated call under the same (uid, scanId) with IDENTICAL evidence reuses the SAME session and does not double-charge quota", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const request = baseRequest();
    const r1 = await resolveEquipmentIdentityFromText({ uid, request });
    const r2 = await resolveEquipmentIdentityFromText({ uid, request });

    expect(r1.recognitionSessionId).toBe(r2.recognitionSessionId);
    expect(r2.decision).toBe("MATCH");
    expect(r2.model).toEqual(r1.model);

    const today = new Date().toISOString().slice(0, 10);
    const usageSnap = await admin.firestore().doc(`users/${uid}/usage/${today}`).get();
    expect(usageSnap.data()?.identityTextLookup).toBe(1);
  });

  test("a repeated call under the same (uid, scanId) with DIFFERENT evidence -> real CANCELLED_STALE, no second quota charge", async () => {
    const catalogVersion = randomCatalogVersion();
    const modelA = makeModel(catalogVersion, {
      modelId: "11111111-1111-4111-8111-111111111111",
      modelCode: "8TRX",
      textSupportStatus: "VERIFIED",
    });
    const modelB = makeModel(catalogVersion, {
      modelId: "22222222-2222-4222-8222-222222222222",
      modelCode: "9XYZ",
      textSupportStatus: "VERIFIED",
    });
    await seedModel(modelA);
    await seedModel(modelB);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const scanId = `scan-${Date.now()}`;
    const first = await resolveEquipmentIdentityFromText({
      uid,
      request: baseRequest({
        scanId,
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["8TRX"],
          typeHints: [],
          conflicts: [],
        },
      }),
    });
    expect(first.decision).toBe("MATCH");

    const second = await resolveEquipmentIdentityFromText({
      uid,
      request: baseRequest({
        scanId,
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["9XYZ"],
          typeHints: [],
          conflicts: [],
        },
      }),
    });
    expect(second.decision).toBe("CANCELLED_STALE");
    expect(second.recognitionSessionId).toBe(first.recognitionSessionId);

    const today = new Date().toISOString().slice(0, 10);
    const usageSnap = await admin.firestore().doc(`users/${uid}/usage/${today}`).get();
    expect(usageSnap.data()?.identityTextLookup).toBe(1);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: a deterministic
  // pointer-switch scenario, against a real emulator, proving the
  // pre-emission check now catches the active pointer moving to a
  // DIFFERENT catalogVersion strictly BETWEEN this request's own earlier
  // pointer read (step 3) and its later pre-emission re-check (step 8) --
  // not just a model doc being revoked within the SAME catalogVersion
  // (the "revocation after pinning" test above only ever covers that).
  // `jest.spyOn` wraps the REAL `fetchActiveCatalogPointer` (calls
  // through to it, does not fake its result) and uses the one guaranteed
  // synchronization point available -- "after step 3's real read has
  // resolved, before step 8 runs" -- to switch the pointer in real
  // Firestore right then, deterministically, with no timing race.
  test("the active pointer moving to a DIFFERENT catalogVersion strictly between the initial read and the pre-emission re-check blocks emission", async () => {
    const originalVersion = randomCatalogVersion();
    const model = makeModel(originalVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(originalVersion);

    const newVersion = randomCatalogVersion();

    const realFetch = catalogReader.fetchActiveCatalogPointer;
    const spy = jest
      .spyOn(catalogReader, "fetchActiveCatalogPointer")
      .mockImplementationOnce(async () => {
        // The real read below genuinely observes `originalVersion` (seeded
        // above, untouched so far) -- only AFTER it resolves does this
        // switch the real pointer away from it, so the request's own
        // later pre-emission re-check sees a genuinely different value.
        const result = await realFetch();
        await seedActiveCatalogPointer(newVersion);
        return result;
      });

    const response = await resolveEquipmentIdentityFromText({ uid: randomUid(), request: baseRequest() });

    expect(response.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(response.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
    expect(response.authority.catalogVersion).toBe(originalVersion);

    spy.mockRestore();
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11: round 1's
  // idempotency check only ever compared a retry against its OWN prior
  // scanId -- a genuinely NEWER scan (different scanId) for the same uid
  // was never checked for. Real cross-scan supersession, against a real
  // Firestore emulator: scan A resolves and pins, scan B (a later scan for
  // the SAME uid) resolves and pins, and a retry of scan A's own original
  // request is now stale -- the user has moved on to a different scan.
  test("a retry of an OLDER scan is CANCELLED_STALE once a genuinely NEWER scan for the same uid has been pinned", async () => {
    const catalogVersion = randomCatalogVersion();
    const modelA = makeModel(catalogVersion, {
      modelId: "11111111-1111-4111-8111-111111111111",
      modelCode: "8TRX",
      textSupportStatus: "VERIFIED",
    });
    const modelB = makeModel(catalogVersion, {
      modelId: "22222222-2222-4222-8222-222222222222",
      modelCode: "9XYZ",
      textSupportStatus: "VERIFIED",
    });
    await seedModel(modelA);
    await seedModel(modelB);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const requestA = baseRequest({
      scanId: `scan-a-${Date.now()}`,
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: ["8TRX"],
        typeHints: [],
        conflicts: [],
      },
    });
    const requestB = baseRequest({
      scanId: `scan-b-${Date.now()}`,
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: ["9XYZ"],
        typeHints: [],
        conflicts: [],
      },
    });

    const firstA = await resolveEquipmentIdentityFromText({ uid, request: requestA });
    expect(firstA.decision).toBe("MATCH");
    const firstB = await resolveEquipmentIdentityFromText({ uid, request: requestB });
    expect(firstB.decision).toBe("MATCH");

    // A genuine retry of A's own IDENTICAL original request -- same
    // fingerprint, so this is the replay path, not the conflicting-evidence
    // path -- but B has since superseded it as this uid's latest scan.
    const retryA = await resolveEquipmentIdentityFromText({ uid, request: requestA });
    expect(retryA.decision).toBe("CANCELLED_STALE");
    expect(retryA.recognitionSessionId).toBe(firstA.recognitionSessionId);

    // B itself is still perfectly replayable -- it IS the latest.
    const retryB = await resolveEquipmentIdentityFromText({ uid, request: requestB });
    expect(retryB.decision).toBe("MATCH");
    expect(retryB.model).toEqual(firstB.model);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11: the
  // idempotent-replay short-circuit must live-verify the pinned outcome is
  // STILL eligible before replaying it, exactly like a fresh MATCH's own
  // pre-emission check -- never hand back a cached MATCH for a model that
  // has since been revoked.
  test("a retry of an already-pinned MATCH fails closed instead of replaying it once the underlying model has since been revoked", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED", catalogStatus: "ACTIVE" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const request = baseRequest();
    const first = await resolveEquipmentIdentityFromText({ uid, request });
    expect(first.decision).toBe("MATCH");

    // Revoke the SAME model doc directly, as a real catalog revocation
    // would, strictly AFTER it was already pinned as a MATCH.
    await admin
      .firestore()
      .doc(modelDocPath(catalogVersion, model.modelId))
      .set({ ...model, catalogStatus: "DISCONTINUED" });

    // An identical retry (same scanId, same evidence -> same fingerprint)
    // takes the replay path -- it must not hand back the now-stale MATCH.
    const retry = await resolveEquipmentIdentityFromText({ uid, request });
    expect(retry.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(retry.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
    expect(retry.model).toBeUndefined();

    // No second quota charge for the failed-closed retry -- the
    // idempotency check still short-circuited BEFORE quota, it just
    // refused to replay a now-stale outcome.
    const today = new Date().toISOString().slice(0, 10);
    const usageSnap = await admin.firestore().doc(`users/${uid}/usage/${today}`).get();
    expect(usageSnap.data()?.identityTextLookup).toBe(1);
  });

  test("the identity-lookup daily quota is really enforced end-to-end -> UNAVAILABLE_RATE_LIMIT/RATE_LIMITED, no session created", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const today = new Date().toISOString().slice(0, 10);
    await admin.firestore().doc(`users/${uid}/usage/${today}`).set({ identityTextLookup: 60 });

    const response = await resolveEquipmentIdentityFromText({ uid, request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_RATE_LIMIT");
    expect(response.failureCode).toBe("RATE_LIMITED");

    const sessionSnap = await admin
      .firestore()
      .doc(userEquipmentIdentitySessionDocPath(uid, response.recognitionSessionId))
      .get();
    expect(sessionSnap.exists).toBe(false);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review round 3, 2026-09-11 -- the
  // CENTERPIECE proof, end to end through the real callable, of the exact
  // failure scenario round 2's own remediation still allowed: "A стартовал
  // -> работает медленно; B стартовал позже -> быстро завершился -> pin B,
  // latest=B; A затем завершает работу -> ... A возвращает результат вместо
  // CANCELLED_STALE." `jest.spyOn` wraps the REAL `admitSessionClaim` (to
  // know, deterministically, the exact moment A's own admission has
  // genuinely committed in real Firestore) and the REAL
  // `finalizeSessionOutcome` (to hold A at its own finalize step, AFTER its
  // admission already committed, until B has fully admitted AND finalized)
  // -- the same real-collaborator-wrapping technique already established
  // by the pointer-switch test above, never a fake/simulated interleaving.
  test("a scan admitted first but held at finalize until a later scan is admitted and fully resolved -> the first scan's own finalize is superseded, never emits a stale MATCH", async () => {
    const catalogVersion = randomCatalogVersion();
    const modelA = makeModel(catalogVersion, {
      modelId: "11111111-1111-4111-8111-111111111111",
      modelCode: "8TRX",
      textSupportStatus: "VERIFIED",
    });
    const modelB = makeModel(catalogVersion, {
      modelId: "22222222-2222-4222-8222-222222222222",
      modelCode: "9XYZ",
      textSupportStatus: "VERIFIED",
    });
    await seedModel(modelA);
    await seedModel(modelB);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const scanIdA = `scan-a-${Date.now()}`;
    const scanIdB = `scan-b-${Date.now()}`;
    const requestA = baseRequest({
      scanId: scanIdA,
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: ["8TRX"],
        typeHints: [],
        conflicts: [],
      },
    });
    const requestB = baseRequest({
      scanId: scanIdB,
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: ["9XYZ"],
        typeHints: [],
        conflicts: [],
      },
    });

    const realAdmit = sessionRepository.admitSessionClaim;
    let aAdmitted: () => void = () => undefined;
    const aAdmittedPromise = new Promise<void>((resolve) => {
      aAdmitted = resolve;
    });
    const admitSpy = jest
      .spyOn(sessionRepository, "admitSessionClaim")
      .mockImplementationOnce(async (...args) => {
        const result = await realAdmit(...args);
        aAdmitted();
        return result;
      });

    const realFinalize = sessionRepository.finalizeSessionOutcome;
    let releaseAFinalize: () => void = () => undefined;
    const aFinalizeGate = new Promise<void>((resolve) => {
      releaseAFinalize = resolve;
    });
    const finalizeSpy = jest
      .spyOn(sessionRepository, "finalizeSessionOutcome")
      .mockImplementationOnce(async (...args) => {
        await aFinalizeGate;
        return realFinalize(...args);
      });

    const promiseA = resolveEquipmentIdentityFromText({ uid, request: requestA });
    // Deterministic synchronization point: A's own admission has genuinely
    // committed in real Firestore (this uid's latest pointer now names A)
    // BEFORE B's own request is even started below -- not a timing guess.
    await aAdmittedPromise;
    const latestAfterAAdmitted = await sessionRepository.readLatestSession(uid);
    expect(latestAfterAAdmitted?.scanId).toBe(scanIdA);

    const responseB = await resolveEquipmentIdentityFromText({ uid, request: requestB });
    expect(responseB.decision).toBe("MATCH");
    const latestAfterBResolved = await sessionRepository.readLatestSession(uid);
    expect(latestAfterBResolved?.scanId).toBe(scanIdB);

    releaseAFinalize();
    const responseA = await promiseA;
    expect(responseA.decision).toBe("CANCELLED_STALE");

    admitSpy.mockRestore();
    finalizeSpy.mockRestore();
  });
});
