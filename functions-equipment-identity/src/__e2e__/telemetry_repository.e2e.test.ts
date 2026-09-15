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
import { recordServerTerminalTelemetry } from "../p2/telemetry_repository";
import { CURRENT_IDENTITY_CONTRACT_VERSION } from "../p2/contract";
import type { EquipmentIdentityResponse } from "../p2/contract";
import type { EquipmentIdentityTelemetryRecord } from "../p2/telemetry_contract";

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
});
