/**
 * P2.G5-readiness step 2 -- real end-to-end proof, through the actual
 * exported wiring seam (`identity_handler.ts`'s
 * `resolveEquipmentIdentityAndRecordTelemetry`, the same function
 * `index.ts`'s `onCall` wrapper delegates to), that a real authenticated
 * call produces BOTH the identity response AND a matching Firestore
 * telemetry record (GPT-PM MAJOR, retrospective review of commit afca346,
 * 2026-09-15: no test previously exercised this seam at all -- deleting
 * the telemetry call from `index.ts`/`identity_handler.ts` would have left
 * every other suite green). Model/catalog seeding mirrors
 * `orchestrator.e2e.test.ts`.
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import type { CatalogActivePointer, EquipmentModel } from "../p1/contracts";
import { CATALOG_ACTIVE_POINTER_DOC_PATH, modelDocPath, userEquipmentIdentityTelemetryDocPath } from "../p1/firestore_paths";
import { materializeAndWrite, FirestoreTextKeyStore } from "../p2/text_key_index";
import { resolveEquipmentIdentityAndRecordTelemetry } from "../p2/identity_handler";
import { CURRENT_IDENTITY_CONTRACT_VERSION } from "../p2/contract";
import type { EquipmentIdentityTelemetryRecord } from "../p2/telemetry_contract";

const store = new FirestoreTextKeyStore();

function randomUid(): string {
  return `e2e-handler-uid-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function randomCatalogVersion(): string {
  return `e2e-handler-catalog-${Date.now()}-${Math.random().toString(36).slice(2)}`;
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

function baseRawRequest(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    scanId: `scan-${Date.now()}-${Math.random().toString(36).slice(2)}`,
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
  };
}

async function readTelemetry(uid: string, scanId: string): Promise<EquipmentIdentityTelemetryRecord | undefined> {
  const snap = await admin.firestore().doc(userEquipmentIdentityTelemetryDocPath(uid, scanId)).get();
  return snap.data() as EquipmentIdentityTelemetryRecord | undefined;
}

afterAll(async () => {
  await admin.app().delete();
});

describe("resolveEquipmentIdentityAndRecordTelemetry -- the real wiring seam, end to end", () => {
  test("a real authenticated MATCH is recorded as SERVER_TERMINAL telemetry under the same uid and the RESPONSE's own scanId", async () => {
    const catalogVersion = randomCatalogVersion();
    const model = makeModel(catalogVersion, { textSupportStatus: "VERIFIED" });
    await seedModel(model);
    await seedActiveCatalogPointer(catalogVersion);

    const uid = randomUid();
    const rawRequest = baseRawRequest();
    const response = await resolveEquipmentIdentityAndRecordTelemetry(uid, rawRequest);

    expect(response.decision).toBe("MATCH");

    const telemetry = await readTelemetry(uid, response.scanId);
    expect(telemetry?.state).toBe("SERVER_TERMINAL");
    expect(telemetry?.uid).toBe(uid);
    expect(telemetry?.scanId).toBe(response.scanId);
    expect(telemetry?.identityOutcome?.decision).toBe("MATCH");
    expect(telemetry?.identityOutcome?.model?.modelId).toBe(model.modelId);
  });

  test("a real UNAVAILABLE_CATALOG_VERSION failure is ALSO recorded as SERVER_TERMINAL telemetry -- every real response path is captured, not only MATCH", async () => {
    await clearActiveCatalogPointer();
    const uid = randomUid();
    const response = await resolveEquipmentIdentityAndRecordTelemetry(
      uid,
      baseRawRequest({ scanId: `scan-no-catalog-${Date.now()}` }),
    );
    expect(response.decision).toBe("UNAVAILABLE_CATALOG_VERSION");

    const telemetry = await readTelemetry(uid, response.scanId);
    expect(telemetry?.state).toBe("SERVER_TERMINAL");
    expect(telemetry?.identityOutcome?.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
  });

  test("a malformed request rejects before ever reaching Firestore -- no telemetry document is created", async () => {
    const uid = randomUid();
    const scanId = `scan-malformed-${Date.now()}`;
    await expect(
      resolveEquipmentIdentityAndRecordTelemetry(uid, { scanId, evidence: "not-an-object" }),
    ).rejects.toThrow();

    const telemetry = await readTelemetry(uid, scanId);
    expect(telemetry).toBeUndefined();
  });
});
