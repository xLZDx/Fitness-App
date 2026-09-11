/**
 * P2.G3 -- proves catalog_reader.ts's new logging actually distinguishes
 * "document does not exist yet" (honest, unlogged -- publication simply
 * hasn't happened) from "document exists but fails schema validation"
 * (real data corruption, now logged) against a real Firestore emulator,
 * not a mock (silent-failure-hunter finding, P2.G3 pre-commit review,
 * 2026-09-11).
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import type { CatalogActivePointer } from "../p1/contracts";
import { CATALOG_ACTIVE_POINTER_DOC_PATH, modelDocPath } from "../p1/firestore_paths";
import {
  fetchActiveCatalogPointer,
  fetchEquipmentModel,
  verifyActiveCatalogVersionStillCurrent,
} from "../p2/catalog_reader";

function seedPointer(catalogVersion: string): Promise<FirebaseFirestore.WriteResult> {
  const pointer: CatalogActivePointer = {
    schemaVersion: 1,
    activeCatalogVersion: catalogVersion,
    releaseStage: "SHADOW_INTERNAL",
    approvalSha256: "c".repeat(64),
    activatedAt: "2026-08-22T00:00:00Z",
  };
  return admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).set(pointer);
}

function randomCatalogVersion(): string {
  return `e2e-reader-catalog-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

afterAll(async () => {
  await admin.app().delete();
});

describe("catalog_reader.ts -- malformed vs. absent, against a real emulator", () => {
  test("fetchActiveCatalogPointer: an absent pointer doc logs nothing and returns null", async () => {
    await admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).delete();
    const logger = await import("firebase-functions/logger");
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);

    const result = await fetchActiveCatalogPointer();

    expect(result).toBeNull();
    expect(errorSpy).not.toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  test("fetchActiveCatalogPointer: a schema-invalid pointer doc logs equipment_catalog_active_pointer_schema_invalid and returns null", async () => {
    await admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).set({
      schemaVersion: 1,
      // activeCatalogVersion deliberately omitted -- required by the schema.
      releaseStage: "SHADOW_INTERNAL",
    });
    const logger = await import("firebase-functions/logger");
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);

    const result = await fetchActiveCatalogPointer();

    expect(result).toBeNull();
    expect(errorSpy).toHaveBeenCalledWith(
      "equipment_catalog_active_pointer_schema_invalid",
      expect.objectContaining({ path: CATALOG_ACTIVE_POINTER_DOC_PATH }),
    );
    errorSpy.mockRestore();
    await admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).delete();
  });

  test("fetchEquipmentModel: an absent model doc logs nothing and returns null", async () => {
    const catalogVersion = randomCatalogVersion();
    const logger = await import("firebase-functions/logger");
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);

    const result = await fetchEquipmentModel(catalogVersion, "no-such-model");

    expect(result).toBeNull();
    expect(errorSpy).not.toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  test("fetchEquipmentModel: a schema-invalid model doc logs equipment_model_schema_invalid and returns null", async () => {
    const catalogVersion = randomCatalogVersion();
    const modelId = "11111111-1111-4111-8111-111111111111";
    await admin.firestore().doc(modelDocPath(catalogVersion, modelId)).set({
      schemaVersion: 1,
      modelId,
      // canonicalName, modelCode, and every other required field
      // deliberately omitted -- an intentionally-corrupt document.
      catalogVersion,
    });
    const logger = await import("firebase-functions/logger");
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);

    const result = await fetchEquipmentModel(catalogVersion, modelId);

    expect(result).toBeNull();
    expect(errorSpy).toHaveBeenCalledWith(
      "equipment_model_schema_invalid",
      expect.objectContaining({ catalogVersion, modelId }),
    );
    errorSpy.mockRestore();
  });
});

// GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: the pre-emission
// eligibility check previously only re-read the MODEL doc at the
// already-pinned catalogVersion -- it never noticed the ACTIVE POINTER
// itself moving to a different catalogVersion in between. Proven here
// against a real emulator with a genuine pointer switch, not a mock.
describe("verifyActiveCatalogVersionStillCurrent -- real pointer-switch detection", () => {
  test("returns true while the active pointer still names this catalogVersion", async () => {
    const catalogVersion = randomCatalogVersion();
    await seedPointer(catalogVersion);
    await expect(verifyActiveCatalogVersionStillCurrent(catalogVersion)).resolves.toBe(true);
  });

  test("returns false once the active pointer has switched to a DIFFERENT catalogVersion", async () => {
    const originalVersion = randomCatalogVersion();
    await seedPointer(originalVersion);
    expect(await verifyActiveCatalogVersionStillCurrent(originalVersion)).toBe(true);

    const newVersion = randomCatalogVersion();
    await seedPointer(newVersion);

    expect(await verifyActiveCatalogVersionStillCurrent(originalVersion)).toBe(false);
    expect(await verifyActiveCatalogVersionStillCurrent(newVersion)).toBe(true);
  });

  test("returns false when no active pointer exists at all", async () => {
    await admin.firestore().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).delete();
    await expect(verifyActiveCatalogVersionStillCurrent("any-catalog-version")).resolves.toBe(false);
  });
});
