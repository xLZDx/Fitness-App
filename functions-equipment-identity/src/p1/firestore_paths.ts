/**
 * P1.G1 §5.15 — Firestore physical layout (SPTR Equipment Recognition
 * v4.4). Versioned entity docs use a `{catalogVersion}--{entityId}`
 * composite docId so immutable old versions coexist without ever being
 * overwritten; the business primary key remains the entity's own id
 * (modelId, brandId, ...), the version prefix exists only so Firestore's
 * flat docId namespace can hold every version at once. See
 * firestore.rules for the matching security-rule collection names -- this
 * module is the single place both the reader/writer code and the rules
 * comments should trace back to if a collection name ever changes.
 */

/** Runtime backstop, independent of zod schema validation: this module's
 * functions can be called directly with a raw string that never passed
 * through contracts.ts's schemas (e.g. an ad-hoc reader call), so the
 * `{catalogVersion}--{entityId}` scheme's own safety invariants -- no `/`
 * (would nest an unintended subcollection), no bare `--` inside either
 * half (would make the composite ambiguous to any future prefix-range
 * read) -- are enforced here too, not only in CatalogVersionSchema/
 * SlugSchema/EntityIdSchema (reviewer-found gap, P1.G1 database review,
 * 2026-08-22). */
function assertFirestoreSafeIdPart(label: string, value: string): void {
  if (value.includes("/")) {
    throw new Error(`versionedDocId: ${label} must not contain '/', got ${JSON.stringify(value)}`);
  }
  if (value.includes("--")) {
    throw new Error(
      `versionedDocId: ${label} must not contain '--' (reserved as the {catalogVersion}--{entityId} separator), got ${JSON.stringify(value)}`,
    );
  }
}

/** Firestore's own actual documented doc-ID constraints for a STANDALONE
 * segment -- unlike `assertFirestoreSafeIdPart` above, this never applies
 * the `{catalogVersion}--{entityId}` composite scheme's `--`-separator
 * rule, which has no meaning for an id that is not part of that scheme.
 * Exported so a public request schema (e.g. `EquipmentIdentityRequestSchema
 * .scanId`) can enforce the SAME rule at the contract boundary, not only at
 * the persistence boundary (GPT-PM MAJOR, retrospective review of commit
 * afca346, round 3, 2026-09-15: a path-helper-only backstop still lets a
 * contract-valid, `/`-containing scanId through the orchestrator to a real
 * identity response -- the telemetry write is then the only thing that
 * silently fails, which is exactly the "invisible denominator loss" the
 * original finding named; the contract boundary has to reject it before
 * any work happens, not just fail to persist it afterward). */
export function isFirestoreDocIdSegment(value: string): boolean {
  if (value.includes("/")) return false;
  if (value === "." || value === "..") return false;
  if (/^__.*__$/.test(value)) return false;
  return true;
}

/** Runtime backstop, independent of Zod, for the persistence boundary --
 * see `isFirestoreDocIdSegment`'s own doc comment for what this checks and
 * why a public schema enforces the identical rule separately.
 *
 * GPT-PM MAJOR (retrospective review of commit 0563335, round 2, 2026-09-15):
 * `userEquipmentIdentityTelemetryDocPath` originally reused
 * `assertFirestoreSafeIdPart` for this, which meant a perfectly valid,
 * Firestore-safe, contract-valid scanId like `scan--123` was wrongly
 * rejected -- a direct regression from that fix, not a pre-existing gap. */
function assertFirestoreDocIdSegment(label: string, value: string): void {
  if (!isFirestoreDocIdSegment(value)) {
    throw new Error(`${label} is not a valid Firestore document-ID segment, got ${JSON.stringify(value)}`);
  }
}

export function versionedDocId(catalogVersion: string, entityId: string): string {
  if (!catalogVersion) throw new Error("versionedDocId: catalogVersion must be non-empty");
  if (!entityId) throw new Error("versionedDocId: entityId must be non-empty");
  assertFirestoreSafeIdPart("catalogVersion", catalogVersion);
  assertFirestoreSafeIdPart("entityId", entityId);
  return `${catalogVersion}--${entityId}`;
}

export const CollectionPaths = {
  brands: "equipment_brands",
  productLines: "equipment_product_lines",
  models: "equipment_models",
  setupSpecs: "equipment_model_setup_specs",
  externalMappings: "equipment_external_mappings",
  sources: "equipment_sources",
  assets: "equipment_assets",
  publishJobs: "equipment_catalog_publish_jobs",
  catalogVersions: "equipment_catalog_versions",
  catalogActive: "equipment_catalog_active",
} as const;

export function brandDocPath(catalogVersion: string, brandId: string): string {
  return `${CollectionPaths.brands}/${versionedDocId(catalogVersion, brandId)}`;
}

export function productLineDocPath(catalogVersion: string, productLineId: string): string {
  return `${CollectionPaths.productLines}/${versionedDocId(catalogVersion, productLineId)}`;
}

export function modelDocPath(catalogVersion: string, modelId: string): string {
  return `${CollectionPaths.models}/${versionedDocId(catalogVersion, modelId)}`;
}

export function setupSpecDocPath(catalogVersion: string, setupSpecId: string): string {
  return `${CollectionPaths.setupSpecs}/${versionedDocId(catalogVersion, setupSpecId)}`;
}

export function externalMappingDocPath(catalogVersion: string, mappingId: string): string {
  return `${CollectionPaths.externalMappings}/${versionedDocId(catalogVersion, mappingId)}`;
}

export function sourceDocPath(sourceId: string): string {
  if (!sourceId) throw new Error("sourceDocPath: sourceId must be non-empty");
  assertFirestoreSafeIdPart("sourceId", sourceId);
  return `${CollectionPaths.sources}/${sourceId}`;
}

export function assetDocPath(catalogVersion: string, assetId: string): string {
  return `${CollectionPaths.assets}/${versionedDocId(catalogVersion, assetId)}`;
}

export function publishJobDocPath(jobId: string): string {
  if (!jobId) throw new Error("publishJobDocPath: jobId must be non-empty");
  assertFirestoreSafeIdPart("jobId", jobId);
  return `${CollectionPaths.publishJobs}/${jobId}`;
}

export function catalogVersionDocPath(catalogVersion: string): string {
  if (!catalogVersion) throw new Error("catalogVersionDocPath: catalogVersion must be non-empty");
  assertFirestoreSafeIdPart("catalogVersion", catalogVersion);
  return `${CollectionPaths.catalogVersions}/${catalogVersion}`;
}

export const CATALOG_ACTIVE_POINTER_DOC_PATH = `${CollectionPaths.catalogActive}/current`;

export function userRecognisedModelDocPath(uid: string, modelDocId: string): string {
  if (!uid) throw new Error("userRecognisedModelDocPath: uid must be non-empty");
  if (!modelDocId) throw new Error("userRecognisedModelDocPath: modelDocId must be non-empty");
  return `users/${uid}/recognised_models/${modelDocId}`;
}

export function userEquipmentIdentitySessionDocPath(uid: string, sessionId: string): string {
  if (!uid) throw new Error("userEquipmentIdentitySessionDocPath: uid must be non-empty");
  if (!sessionId) {
    throw new Error("userEquipmentIdentitySessionDocPath: sessionId must be non-empty");
  }
  return `users/${uid}/equipment_identity_sessions/${sessionId}`;
}

export function userEquipmentIdentityTelemetryDocPath(uid: string, docId: string): string {
  if (!uid) throw new Error("userEquipmentIdentityTelemetryDocPath: uid must be non-empty");
  if (!docId) throw new Error("userEquipmentIdentityTelemetryDocPath: docId must be non-empty");
  // GPT-PM MAJOR (retrospective review of commit afca346, 2026-09-15): docId
  // here is a mobile-minted scanId that reaches this function through the
  // public request contract (`EquipmentIdentityRequestSchema.scanId`, any
  // non-empty string up to 128 chars -- no character restriction). Runtime
  // backstop, independent of Zod: a `/` would silently nest an unintended
  // subcollection or land the write at an unexpected path instead of
  // `equipment_identity_telemetry/{scanId}` -- the caller
  // (`recordServerTerminalTelemetry`) already catches and logs any thrown
  // error rather than letting it become a 500, so this fails loudly into
  // that existing path instead of silently misplacing or dropping the write.
  // Uses `assertFirestoreDocIdSegment`, NOT `assertFirestoreSafeIdPart` --
  // a scanId is a standalone id, not part of the `{catalogVersion}--
  // {entityId}` composite scheme, so the `--`-separator rule does not apply
  // to it (round-2 finding: reusing the composite-scheme validator here
  // wrongly rejected a valid scanId like `scan--123`).
  assertFirestoreDocIdSegment("docId", docId);
  return `users/${uid}/equipment_identity_telemetry/${docId}`;
}
