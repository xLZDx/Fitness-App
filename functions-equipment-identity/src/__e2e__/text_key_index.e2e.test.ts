/**
 * P2.G3 T1 -- the derived `equipment_model_text_keys` index against a real
 * Firestore emulator. `text_key_index.test.ts` already covers the pure
 * normalizer/materializer logic; what a unit test cannot prove is that the
 * real write path (`FirestoreTextKeyStore`) and the real query path
 * (`resolveModelCodeLookup`) actually agree with each other -- that is a
 * fact about Firestore, not about this repo, and every fixture here flows
 * through the real materializer -> real write -> real query, never a
 * hand-written row planted directly in the collection.
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import type { EquipmentModel } from "../p1/contracts";
import {
  materializeAndWrite,
  resolveModelCodeLookup,
  FirestoreTextKeyStore,
} from "../p2/text_key_index";
import { P2CollectionPaths } from "../p2/firestore_paths";

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

function makeModel(overrides: Partial<EquipmentModel> = {}): EquipmentModel {
  return {
    schemaVersion: 1,
    modelId: "11111111-1111-4111-8111-111111111111",
    canonicalSlug: "technogym-selection-leg-press",
    brandId: "technogym",
    productLineId: "technogym-selection",
    canonicalName: "Selection Leg Press",
    modelCode: "SEL-LEGPRESS-500",
    skuAliases: [],
    primaryTypeId: "some-type",
    supportedTypeIds: ["some-type"],
    aliases: [],
    catalogStatus: "ACTIVE",
    textSupportStatus: "EXPERIMENTAL",
    visionSupportStatus: "NONE",
    sourceConfidence: "OFFICIAL",
    catalogVersion: `e2e-catalog-${Date.now()}`,
    provenance: [makeProvenance()],
    ...overrides,
  } as EquipmentModel;
}

const store = new FirestoreTextKeyStore();

async function clearCollection(): Promise<void> {
  const snap = await admin.firestore().collection(P2CollectionPaths.textKeys).get();
  const batch = admin.firestore().batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  if (snap.docs.length > 0) await batch.commit();
}

beforeEach(async () => {
  await clearCollection();
});

afterAll(async () => {
  await admin.app().delete();
});

describe("materializeAndWrite -> resolveModelCodeLookup, end to end against a real emulator", () => {
  test("a stored raw '8TRx' resolves from a differently-cased OCR query '8TRX'", async () => {
    const model = makeModel({ modelCode: "8TRx" });
    await materializeAndWrite(model, store);

    const result = await resolveModelCodeLookup("8TRX", model.catalogVersion);
    expect(result).toEqual({
      outcome: "UNIQUE",
      modelId: model.modelId,
      keyKinds: ["MODEL_CODE"],
    });
  });

  test("an alias resolves through the same normalizer as the model code", async () => {
    const model = makeModel({ modelCode: "SEL-LEGPRESS-500", aliases: ["SelLegPress500Alt"] });
    await materializeAndWrite(model, store);

    const result = await resolveModelCodeLookup("SELLEGPRESS500ALT", model.catalogVersion);
    expect(result).toEqual({
      outcome: "UNIQUE",
      modelId: model.modelId,
      keyKinds: ["ALIAS"],
    });
  });

  test("modelCode and alias colliding on one model resolves UNIQUE with both keyKinds", async () => {
    const model = makeModel({ modelCode: "8TRx", aliases: ["8trx"] });
    await materializeAndWrite(model, store);

    const result = await resolveModelCodeLookup("8TRX", model.catalogVersion);
    expect(result).toEqual({
      outcome: "UNIQUE",
      modelId: model.modelId,
      keyKinds: ["ALIAS", "MODEL_CODE"],
    });
  });

  test("the same normalized key from two different modelIds resolves NONUNIQUE", async () => {
    const catalogVersion = `e2e-catalog-nonunique-${Date.now()}`;
    const modelA = makeModel({
      modelId: "11111111-1111-4111-8111-111111111111",
      modelCode: "8TRX",
      catalogVersion,
    });
    const modelB = makeModel({
      modelId: "22222222-2222-4222-8222-222222222222",
      modelCode: "8trx",
      catalogVersion,
    });
    await materializeAndWrite(modelA, store);
    await materializeAndWrite(modelB, store);

    const result = await resolveModelCodeLookup("8TRX", catalogVersion);
    expect(result.outcome).toBe("NONUNIQUE");
    if (result.outcome === "NONUNIQUE") {
      expect(result.modelIds.sort()).toEqual([modelA.modelId, modelB.modelId].sort());
    }
  });

  test("an unknown code resolves NO_MATCH", async () => {
    const model = makeModel({ modelCode: "8TRX" });
    await materializeAndWrite(model, store);

    const result = await resolveModelCodeLookup("NOSUCHCODE", model.catalogVersion);
    expect(result).toEqual({ outcome: "NO_MATCH" });
  });

  test("a slash-containing code round-trips correctly through Firestore", async () => {
    const model = makeModel({ modelCode: "ABC/123", aliases: [] });
    await materializeAndWrite(model, store);

    const result = await resolveModelCodeLookup("abc/123", model.catalogVersion);
    expect(result).toEqual({ outcome: "UNIQUE", modelId: model.modelId, keyKinds: ["MODEL_CODE"] });
  });

  test("resolution is scoped to catalogVersion -- the same code in a different version does not match", async () => {
    const model = makeModel({ modelCode: "8TRX", catalogVersion: "catalog-scope-a" });
    await materializeAndWrite(model, store);

    const result = await resolveModelCodeLookup("8TRX", "catalog-scope-b");
    expect(result).toEqual({ outcome: "NO_MATCH" });
  });

  test("lookup is rights-independent -- resolves regardless of the model's provenance/sourceConfidence", async () => {
    const model = makeModel({ modelCode: "8TRX", sourceConfidence: "INFERRED" });
    await materializeAndWrite(model, store);

    // The derived collection carries no rights/provenance field at all
    // (only catalogVersion/lookupKey/modelId/keyKinds), so a caller with no
    // knowledge of the model's rights state can still resolve it.
    const result = await resolveModelCodeLookup("8TRX", model.catalogVersion);
    expect(result.outcome).toBe("UNIQUE");
  });
});
