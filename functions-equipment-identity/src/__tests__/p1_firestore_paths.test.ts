import {
  versionedDocId,
  CollectionPaths,
  brandDocPath,
  productLineDocPath,
  modelDocPath,
  setupSpecDocPath,
  externalMappingDocPath,
  sourceDocPath,
  assetDocPath,
  publishJobDocPath,
  catalogVersionDocPath,
  CATALOG_ACTIVE_POINTER_DOC_PATH,
  userRecognisedModelDocPath,
  userEquipmentIdentitySessionDocPath,
  userEquipmentIdentityTelemetryDocPath,
} from "../p1/firestore_paths";

// Reviewer-found gap (P1.G1 database review, 2026-08-22): this module
// implements the entire versioned-docId scheme every P1.G1 collection
// depends on, and had zero unit tests in the original diff.

describe("versionedDocId", () => {
  test("joins catalogVersion and entityId with '--'", () => {
    expect(versionedDocId("catalog-v1-abc", "brand-technogym")).toBe(
      "catalog-v1-abc--brand-technogym",
    );
  });

  test("rejects an empty catalogVersion", () => {
    expect(() => versionedDocId("", "id")).toThrow(/catalogVersion must be non-empty/);
  });

  test("rejects an empty entityId", () => {
    expect(() => versionedDocId("catalog-v1-abc", "")).toThrow(/entityId must be non-empty/);
  });

  test("rejects a catalogVersion containing '/'", () => {
    expect(() => versionedDocId("catalog/v1", "id")).toThrow(/catalogVersion must not contain '\//);
  });

  test("rejects an entityId containing '/'", () => {
    expect(() => versionedDocId("catalog-v1-abc", "a/b")).toThrow(/entityId must not contain '\//);
  });

  test("rejects a catalogVersion containing '--' (would make the composite ambiguous)", () => {
    expect(() => versionedDocId("catalog--v1", "id")).toThrow(/catalogVersion must not contain '--'/);
  });

  test("rejects an entityId containing '--'", () => {
    expect(() => versionedDocId("catalog-v1-abc", "a--b")).toThrow(/entityId must not contain '--'/);
  });

  test("regression proof: without the '--' guard, two distinct (catalogVersion, entityId) pairs could produce the same docId", () => {
    // ("v1--extra", "id") and ("v1", "extra--id") would both naively join
    // to "v1--extra--id" -- exactly the ambiguity the guard closes. Both
    // are now rejected outright.
    expect(() => versionedDocId("v1--extra", "id")).toThrow();
    expect(() => versionedDocId("v1", "extra--id")).toThrow();
  });
});

describe("collection path builders", () => {
  test("brandDocPath", () => {
    expect(brandDocPath("catalog-v1-abc", "technogym")).toBe(
      `${CollectionPaths.brands}/catalog-v1-abc--technogym`,
    );
  });

  test("productLineDocPath", () => {
    expect(productLineDocPath("catalog-v1-abc", "technogym-selection")).toBe(
      `${CollectionPaths.productLines}/catalog-v1-abc--technogym-selection`,
    );
  });

  test("modelDocPath", () => {
    const modelId = "11111111-1111-4111-8111-111111111111";
    expect(modelDocPath("catalog-v1-abc", modelId)).toBe(
      `${CollectionPaths.models}/catalog-v1-abc--${modelId}`,
    );
  });

  test("setupSpecDocPath", () => {
    expect(setupSpecDocPath("catalog-v1-abc", "setup-1")).toBe(
      `${CollectionPaths.setupSpecs}/catalog-v1-abc--setup-1`,
    );
  });

  test("externalMappingDocPath", () => {
    expect(externalMappingDocPath("catalog-v1-abc", "mapping-1")).toBe(
      `${CollectionPaths.externalMappings}/catalog-v1-abc--mapping-1`,
    );
  });

  test("assetDocPath", () => {
    expect(assetDocPath("catalog-v1-abc", "asset-1")).toBe(
      `${CollectionPaths.assets}/catalog-v1-abc--asset-1`,
    );
  });

  test("sourceDocPath (not versioned -- single segment)", () => {
    expect(sourceDocPath("technogym_interior_design")).toBe(
      `${CollectionPaths.sources}/technogym_interior_design`,
    );
  });

  test("sourceDocPath rejects an empty sourceId", () => {
    expect(() => sourceDocPath("")).toThrow(/sourceId must be non-empty/);
  });

  test("sourceDocPath rejects a sourceId containing '/'", () => {
    expect(() => sourceDocPath("a/b")).toThrow(/sourceId must not contain '\//);
  });

  test("publishJobDocPath", () => {
    expect(publishJobDocPath("job-1")).toBe(`${CollectionPaths.publishJobs}/job-1`);
  });

  test("publishJobDocPath rejects an empty jobId", () => {
    expect(() => publishJobDocPath("")).toThrow(/jobId must be non-empty/);
  });

  test("catalogVersionDocPath", () => {
    expect(catalogVersionDocPath("catalog-v1-abc")).toBe(
      `${CollectionPaths.catalogVersions}/catalog-v1-abc`,
    );
  });

  test("catalogVersionDocPath rejects a catalogVersion containing '--'", () => {
    expect(() => catalogVersionDocPath("catalog--v1")).toThrow(/must not contain '--'/);
  });

  test("CATALOG_ACTIVE_POINTER_DOC_PATH is the singleton 'current' doc", () => {
    expect(CATALOG_ACTIVE_POINTER_DOC_PATH).toBe(`${CollectionPaths.catalogActive}/current`);
  });
});

describe("per-user path builders", () => {
  test("userRecognisedModelDocPath", () => {
    expect(userRecognisedModelDocPath("alice", "m1")).toBe("users/alice/recognised_models/m1");
  });

  test("userRecognisedModelDocPath rejects an empty uid", () => {
    expect(() => userRecognisedModelDocPath("", "m1")).toThrow(/uid must be non-empty/);
  });

  test("userEquipmentIdentitySessionDocPath", () => {
    expect(userEquipmentIdentitySessionDocPath("alice", "s1")).toBe(
      "users/alice/equipment_identity_sessions/s1",
    );
  });

  test("userEquipmentIdentityTelemetryDocPath", () => {
    expect(userEquipmentIdentityTelemetryDocPath("alice", "t1")).toBe(
      "users/alice/equipment_identity_telemetry/t1",
    );
  });
});
