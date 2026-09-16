/**
 * P2.G5-readiness step 2 -- real Firestore proof of `telemetry_repository.ts`'s
 * idempotent-merge writer (design doc §6). Against a real emulator, not a
 * mock: the property being proven is a transaction's actual read-then-write
 * behavior under the 4 merge rules, which only a real transaction can
 * demonstrate (mirrors `session_repository.e2e.test.ts`'s own rationale).
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import { userEquipmentIdentityTelemetryDocPath } from "../p1/firestore_paths";
import { recordServerTerminalTelemetry, recordMobileTelemetryFragment } from "../p2/telemetry_repository";
import { CURRENT_IDENTITY_CONTRACT_VERSION } from "../p2/contract";
import type { EquipmentIdentityResponse } from "../p2/contract";
import type {
  EquipmentIdentityTelemetryRecord,
  EquipmentIdentityTelemetryReportRequest,
} from "../p2/telemetry_contract";

function randomUid(): string {
  return `e2e-telemetry-uid-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

const MODEL_ID = "11111111-1111-4111-8111-111111111111";
const CATALOG_VERSION = "catalog-v1";

function matchResponse(
  overrides: Partial<{ scanId: string; modelId: string; recognitionSessionId: string }> = {},
): EquipmentIdentityResponse {
  return {
    scanId: overrides.scanId ?? "scan-1",
    recognitionSessionId: overrides.recognitionSessionId ?? "session-1",
    identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
    authority: {
      catalogVersion: CATALOG_VERSION,
      ocrVersion: "ocr-1.0.0",
      textPolicyVersion: "p2g3-text-exact-v1",
      fusionPolicyVersion: "none",
      identityPolicyVersion: "p2g3-text-exact-v1",
    },
    evidenceLane: "TEXT_ONLY",
    decision: "MATCH",
    identityLevel: "EXACT_MODEL",
    model: {
      modelId: overrides.modelId ?? MODEL_ID,
      catalogVersion: CATALOG_VERSION,
      textSupportStatus: "VERIFIED",
    },
    verifierInvoked: false,
  };
}

async function readRaw(uid: string, scanId: string): Promise<EquipmentIdentityTelemetryRecord | undefined> {
  const snap = await admin.firestore().doc(userEquipmentIdentityTelemetryDocPath(uid, scanId)).get();
  return snap.data() as EquipmentIdentityTelemetryRecord | undefined;
}

afterAll(async () => {
  await admin.app().delete();
});

describe("recordServerTerminalTelemetry -- real Firestore merge semantics (design doc §6)", () => {
  test("rule 1: no existing record -- creates a fresh SERVER_TERMINAL record", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.uid).toBe(uid);
    expect(record?.scanId).toBe("scan-1");
    expect(record?.identityOutcome?.model?.modelId).toBe(MODEL_ID);
    expect(record?.createdAt).toBe(record?.updatedAt);
    expect(record?.priorStates).toBeUndefined();
  });

  test("rule 2: an identical replay is a no-op except updatedAt -- safe to call any number of times", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());
    const first = await readRaw(uid, "scan-1");

    await new Promise((resolve) => setTimeout(resolve, 5));
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());
    const second = await readRaw(uid, "scan-1");

    expect(second?.payloadFingerprint).toBe(first?.payloadFingerprint);
    expect(second?.createdAt).toBe(first?.createdAt);
    expect(second?.identityOutcome).toEqual(first?.identityOutcome);
    expect(second?.priorStates).toBeUndefined();
  });

  test("rule 3: a legitimate transition from a non-terminal state -- promotes to SERVER_TERMINAL and records the prior state", async () => {
    const uid = randomUid();
    const ref = admin.firestore().doc(userEquipmentIdentityTelemetryDocPath(uid, "scan-1"));
    const seededCreatedAt = new Date(Date.now() - 60_000).toISOString();
    await ref.set({
      schemaVersion: 1,
      uid,
      scanId: "scan-1",
      state: "LOCAL_FAILURE",
      localFailureReason: "ocrException",
      payloadFingerprint: "local-failure-fp",
      createdAt: seededCreatedAt,
      updatedAt: seededCreatedAt,
    });

    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.createdAt).toBe(seededCreatedAt);
    expect(record?.priorStates).toEqual([{ state: "LOCAL_FAILURE", recordedAt: record?.updatedAt }]);
    expect(record?.identityOutcome?.model?.modelId).toBe(MODEL_ID);
  });

  test("rule 4: an already-terminal record with a DIFFERING fingerprint -- never overwritten, surfaced as CONFLICT instead", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ modelId: MODEL_ID }));
    const before = await readRaw(uid, "scan-1");

    // A genuinely different SERVER_TERMINAL outcome for the SAME scanId --
    // should not happen given session_repository.ts's own immutability
    // guarantee, but this proves the writer fails loudly rather than
    // silently picking a winner if it ever does.
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ modelId: "22222222-2222-4222-8222-222222222222" }));

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("CONFLICT");
    // The original winning outcome is untouched.
    expect(record?.identityOutcome?.model?.modelId).toBe(MODEL_ID);
    expect(record?.payloadFingerprint).toBe(before?.payloadFingerprint);
    expect(record?.conflictingWrites).toHaveLength(1);
    expect(record?.conflictingWrites?.[0]?.payloadFingerprint).not.toBe(before?.payloadFingerprint);
  });

  test("a second CONFLICT for the same scanId appends rather than replaces the conflictingWrites trail", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ modelId: MODEL_ID }));
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ modelId: "22222222-2222-4222-8222-222222222222" }));
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ modelId: "33333333-3333-4333-8333-333333333333" }));

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("CONFLICT");
    expect(record?.conflictingWrites).toHaveLength(2);
  });

  // GPT-PM MAJOR (retrospective review of commit afca346, 2026-09-15): §6
  // promises a retried delivery is safe to replay "any number of times" --
  // that has to hold for an already-known CONFLICTING payload too, not only
  // the winning one. A repeated delivery of the SAME conflicting outcome
  // must not keep growing `conflictingWrites`.
  test("a REPEAT of an already-known conflicting payload is idempotent -- the conflictingWrites trail does not keep growing (A -> B -> B -> B stays length 1, contrasted with A -> B -> C's own length 2 above)", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ modelId: MODEL_ID }));
    const b = matchResponse({ modelId: "22222222-2222-4222-8222-222222222222" });
    await recordServerTerminalTelemetry(uid, "scan-1", b);
    const afterFirstB = await readRaw(uid, "scan-1");
    expect(afterFirstB?.conflictingWrites).toHaveLength(1);

    await recordServerTerminalTelemetry(uid, "scan-1", b);
    await recordServerTerminalTelemetry(uid, "scan-1", b);

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("CONFLICT");
    expect(record?.conflictingWrites).toHaveLength(1);
  });

  // GPT-PM MAJOR (retrospective review of commit afca346, 2026-09-15): the
  // frozen §6 rule 3 names ONLY LOCAL_FAILURE/REQUEST_FAILURE as legitimate
  // non-terminal-to-SERVER_TERMINAL transitions. NOT_ATTEMPTED and
  // ENRICHMENT_DISABLED must NOT silently overwrite -- a SERVER_TERMINAL
  // arriving for either of those existing states is a logically
  // contradictory pair and must surface as CONFLICT instead, exactly like
  // any other already-settled state would.
  test.each(["NOT_ATTEMPTED", "ENRICHMENT_DISABLED"] as const)(
    "rule 3 boundary: an existing %s state is NOT a legitimate transition target -- a differing SERVER_TERMINAL surfaces as CONFLICT, never a silent overwrite",
    async (existingState) => {
      const uid = randomUid();
      const ref = admin.firestore().doc(userEquipmentIdentityTelemetryDocPath(uid, "scan-1"));
      await ref.set({
        schemaVersion: 1,
        uid,
        scanId: "scan-1",
        state: existingState,
        payloadFingerprint: `${existingState}-fp`,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

      const record = await readRaw(uid, "scan-1");
      expect(record?.state).toBe("CONFLICT");
      expect(record?.conflictingWrites).toHaveLength(1);
    },
  );

  // GPT-PM MAJOR (retrospective review of commit afca346, 2026-09-15): the
  // public request contract allows any non-empty scanId up to 128 chars,
  // including `/`, which would otherwise nest an unintended subcollection
  // or write to an unexpected path. The path helper now rejects it before
  // any write is attempted; the writer's own top-level try/catch (see its
  // doc comment) swallows the resulting error rather than letting it
  // become a 500 -- so the correct, safe outcome is simply NO telemetry
  // document at all, not a misplaced one.
  test("a scanId containing '/' never silently misplaces or nests a telemetry write -- no document is created at all", async () => {
    const uid = randomUid();
    const unsafeScanId = "scan/../other";

    await expect(recordServerTerminalTelemetry(uid, unsafeScanId, matchResponse())).resolves.not.toThrow();

    const escapedDoc = await admin.firestore().collection(`users/${uid}/equipment_identity_telemetry`).get();
    expect(escapedDoc.empty).toBe(true);
  });

  // GPT-PM MAJOR (retrospective review of commit 0563335, round 2,
  // 2026-09-15): the FIRST fix for the '/' finding above reused
  // `assertFirestoreSafeIdPart`, which also rejects any `--` because that
  // separator is reserved for the UNRELATED `{catalogVersion}--{entityId}`
  // composite scheme -- a real regression, not a pre-existing gap: a
  // perfectly valid, Firestore-safe, contract-valid scanId containing `--`
  // was silently losing its telemetry record. `assertFirestoreDocIdSegment`
  // (the corrected helper) must accept it.
  test("a Firestore-safe scanId containing '--' is NOT rejected -- it is not part of the unrelated {catalogVersion}--{entityId} composite scheme", async () => {
    const uid = randomUid();
    const scanId = "scan--123";

    await recordServerTerminalTelemetry(uid, scanId, matchResponse({ scanId }));

    const record = await readRaw(uid, scanId);
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.scanId).toBe(scanId);
  });

  test("different scanIds for the same uid never interact", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse({ scanId: "scan-1", modelId: MODEL_ID }));
    await recordServerTerminalTelemetry(uid, "scan-2", matchResponse({ scanId: "scan-2", modelId: "22222222-2222-4222-8222-222222222222" }));

    const record1 = await readRaw(uid, "scan-1");
    const record2 = await readRaw(uid, "scan-2");
    expect(record1?.state).toBe("SERVER_TERMINAL");
    expect(record2?.state).toBe("SERVER_TERMINAL");
    expect(record1?.identityOutcome?.model?.modelId).toBe(MODEL_ID);
    expect(record2?.identityOutcome?.model?.modelId).toBe("22222222-2222-4222-8222-222222222222");
  });

  test("never throws even when passed a response whose optional fields are literal undefined (regression: session_repository.ts hit this exact shape)", async () => {
    const uid = randomUid();
    const response = { ...matchResponse(), abstainReason: undefined, failureCode: undefined } as EquipmentIdentityResponse;

    await expect(recordServerTerminalTelemetry(uid, "scan-1", response)).resolves.not.toThrow();

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(Object.prototype.hasOwnProperty.call(record?.identityOutcome ?? {}, "abstainReason")).toBe(false);
  });

  // Step 3a: rule 3's REPLACED fragment must also populate
  // clientObservedFailures, symmetric with rule 5a's reverse arrival order.
  test("rule 3 also appends the replaced fragment's full detail to clientObservedFailures, not just priorStates", async () => {
    const uid = randomUid();
    const ref = admin.firestore().doc(userEquipmentIdentityTelemetryDocPath(uid, "scan-1"));
    const seededCreatedAt = new Date(Date.now() - 60_000).toISOString();
    await ref.set({
      schemaVersion: 1,
      uid,
      scanId: "scan-1",
      state: "REQUEST_FAILURE",
      requestFailureReason: "timeout",
      payloadFingerprint: "request-failure-fp",
      createdAt: seededCreatedAt,
      updatedAt: seededCreatedAt,
    });

    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.clientObservedFailures).toEqual([
      { state: "REQUEST_FAILURE", reason: "timeout", recordedAt: record?.updatedAt, payloadFingerprint: "request-failure-fp" },
    ]);
  });
});

function localFailure(overrides: Partial<EquipmentIdentityTelemetryReportRequest> = {}): EquipmentIdentityTelemetryReportRequest {
  return {
    scanId: "scan-1",
    state: "LOCAL_FAILURE",
    reason: "ocrException",
    scanStartedAt: "2026-09-16T10:00:00.000Z",
    scanEndedAt: "2026-09-16T10:00:01.000Z",
    ...overrides,
  } as EquipmentIdentityTelemetryReportRequest;
}

function requestFailure(overrides: Partial<EquipmentIdentityTelemetryReportRequest> = {}): EquipmentIdentityTelemetryReportRequest {
  return {
    scanId: "scan-1",
    state: "REQUEST_FAILURE",
    reason: "timeout",
    scanStartedAt: "2026-09-16T10:00:00.000Z",
    scanEndedAt: "2026-09-16T10:00:01.000Z",
    ...overrides,
  } as EquipmentIdentityTelemetryReportRequest;
}

function timingOnly(overrides: Partial<EquipmentIdentityTelemetryReportRequest> = {}): EquipmentIdentityTelemetryReportRequest {
  return {
    scanId: "scan-1",
    scanStartedAt: "2026-09-16T10:00:00.000Z",
    scanEndedAt: "2026-09-16T10:00:01.000Z",
    ...overrides,
  } as EquipmentIdentityTelemetryReportRequest;
}

describe("recordMobileTelemetryFragment -- real Firestore merge semantics (design doc §6, step 3a)", () => {
  test("rule 1: no existing record -- creates a fresh LOCAL_FAILURE record from a state-defining fragment", async () => {
    const uid = randomUid();
    await recordMobileTelemetryFragment(uid, localFailure());

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("LOCAL_FAILURE");
    expect(record?.localFailureReason).toBe("ocrException");
    expect(record?.scanStartedAt).toBe("2026-09-16T10:00:00.000Z");
    expect(record?.scanEndedAt).toBe("2026-09-16T10:00:01.000Z");
    expect(record?.createdAt).toBe(record?.updatedAt);
  });

  test("rule 1: a timing-only fragment with no existing record creates nothing (dropped, logged) -- there is no state to create a record with", async () => {
    const uid = randomUid();
    await expect(recordMobileTelemetryFragment(uid, timingOnly())).resolves.not.toThrow();

    const record = await readRaw(uid, "scan-1");
    expect(record).toBeUndefined();
  });

  test("rule 2: an identical replay is a no-op except updatedAt", async () => {
    const uid = randomUid();
    await recordMobileTelemetryFragment(uid, localFailure());
    const first = await readRaw(uid, "scan-1");

    await new Promise((resolve) => setTimeout(resolve, 5));
    await recordMobileTelemetryFragment(uid, localFailure());
    const second = await readRaw(uid, "scan-1");

    expect(second?.payloadFingerprint).toBe(first?.payloadFingerprint);
    expect(second?.createdAt).toBe(first?.createdAt);
    expect(second?.clientObservedFailures).toBeUndefined();
  });

  test("rule 3: a mobile retry landing in a DIFFERENT mobile state overwrites and records both priorStates and clientObservedFailures", async () => {
    const uid = randomUid();
    await recordMobileTelemetryFragment(uid, localFailure());

    await recordMobileTelemetryFragment(uid, requestFailure({ reason: "backendError" }));

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("REQUEST_FAILURE");
    expect(record?.requestFailureReason).toBe("backendError");
    expect(record?.priorStates).toEqual([{ state: "LOCAL_FAILURE", recordedAt: record?.updatedAt }]);
    expect(record?.clientObservedFailures).toEqual([
      { state: "LOCAL_FAILURE", reason: "ocrException", recordedAt: record?.updatedAt, payloadFingerprint: expect.any(String) },
    ]);
  });

  test("rule 3: a retry landing in the SAME state with a DIFFERENT reason is also a legitimate transition (A -> B -> C)", async () => {
    const uid = randomUid();
    await recordMobileTelemetryFragment(uid, requestFailure({ reason: "timeout" }));
    await recordMobileTelemetryFragment(uid, requestFailure({ reason: "backendError" }));

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("REQUEST_FAILURE");
    expect(record?.requestFailureReason).toBe("backendError");
    expect(record?.clientObservedFailures).toHaveLength(1);
    expect(record?.clientObservedFailures?.[0]).toMatchObject({ state: "REQUEST_FAILURE", reason: "timeout" });
  });

  test("rule 5a: a mobile failure fragment arriving AFTER SERVER_TERMINAL never overwrites state -- it only joins clientObservedFailures", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());
    const before = await readRaw(uid, "scan-1");

    await recordMobileTelemetryFragment(uid, requestFailure({ reason: "malformedReply" }));

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.identityOutcome?.model?.modelId).toBe(MODEL_ID);
    expect(record?.payloadFingerprint).toBe(before?.payloadFingerprint);
    expect(record?.clientObservedFailures).toEqual([
      { state: "REQUEST_FAILURE", reason: "malformedReply", recordedAt: record?.updatedAt, payloadFingerprint: expect.any(String) },
    ]);
  });

  test("rule 5a is idempotent -- a repeat of the SAME mobile fragment does not keep growing clientObservedFailures", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

    const fragment = requestFailure({ reason: "malformedReply" });
    await recordMobileTelemetryFragment(uid, fragment);
    await recordMobileTelemetryFragment(uid, fragment);
    await recordMobileTelemetryFragment(uid, fragment);

    const record = await readRaw(uid, "scan-1");
    expect(record?.clientObservedFailures).toHaveLength(1);
  });

  test("rule 5a: two DIFFERENT mobile failure fragments against the same terminal record both survive, distinctly", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

    await recordMobileTelemetryFragment(uid, requestFailure({ reason: "timeout" }));
    await recordMobileTelemetryFragment(uid, requestFailure({ reason: "malformedReply" }));

    const record = await readRaw(uid, "scan-1");
    expect(record?.clientObservedFailures).toHaveLength(2);
    expect(record?.clientObservedFailures?.map((f) => f.reason).sort()).toEqual(["malformedReply", "timeout"]);
  });

  test("rule 5b: the success-path timing-only fragment fills scanStartedAt/scanEndedAt on an already-terminal record", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());
    const before = await readRaw(uid, "scan-1");
    expect(before?.scanStartedAt).toBeUndefined();

    await recordMobileTelemetryFragment(uid, timingOnly());

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.scanStartedAt).toBe("2026-09-16T10:00:00.000Z");
    expect(record?.scanEndedAt).toBe("2026-09-16T10:00:01.000Z");
    expect(record?.identityOutcome?.model?.modelId).toBe(MODEL_ID);
  });

  test("rule 5b is first-write-wins -- a second timing-only fragment with DIFFERENT timestamps does not overwrite the first", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());
    await recordMobileTelemetryFragment(uid, timingOnly());

    await recordMobileTelemetryFragment(
      uid,
      timingOnly({ scanStartedAt: "2026-09-16T11:00:00.000Z", scanEndedAt: "2026-09-16T11:00:02.000Z" }),
    );

    const record = await readRaw(uid, "scan-1");
    expect(record?.scanStartedAt).toBe("2026-09-16T10:00:00.000Z");
    expect(record?.scanEndedAt).toBe("2026-09-16T10:00:01.000Z");
  });

  test("rule 4/5 authority split: a mobile-authoritative fragment against an already-terminal record never produces CONFLICT", async () => {
    const uid = randomUid();
    await recordServerTerminalTelemetry(uid, "scan-1", matchResponse());

    await recordMobileTelemetryFragment(uid, localFailure());
    await recordMobileTelemetryFragment(uid, timingOnly());

    const record = await readRaw(uid, "scan-1");
    expect(record?.state).toBe("SERVER_TERMINAL");
    expect(record?.conflictingWrites ?? []).toHaveLength(0);
  });

  test("different scanIds for the same uid never interact", async () => {
    const uid = randomUid();
    await recordMobileTelemetryFragment(uid, localFailure({ scanId: "scan-1" }));
    await recordMobileTelemetryFragment(uid, requestFailure({ scanId: "scan-2", reason: "timeout" }));

    const record1 = await readRaw(uid, "scan-1");
    const record2 = await readRaw(uid, "scan-2");
    expect(record1?.state).toBe("LOCAL_FAILURE");
    expect(record2?.state).toBe("REQUEST_FAILURE");
  });
});
