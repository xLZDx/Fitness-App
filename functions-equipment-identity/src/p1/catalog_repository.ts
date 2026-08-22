/**
 * P1.G1 §6.5/§6.6 — server-side write validation and catalog-level
 * uniqueness checks (SPTR Equipment Recognition v4.4).
 */
import { z } from "zod";
import {
  EquipmentModelSchema,
  type EquipmentBrand,
  type EquipmentModel,
  type ProductLine,
} from "./contracts";
import {
  loadGeneratedSnapshot,
  validateTypeReference,
  type FunctionalTypeSnapshot,
} from "./type_snapshot";

export class CatalogValidationError extends Error {
  constructor(message: string, public readonly cause?: unknown) {
    super(message);
    this.name = "CatalogValidationError";
  }
}

/**
 * Validates an EquipmentModel write candidate:
 *   1. EquipmentModelSchema (structural shape, incl. primary-in-supported
 *      and no-duplicate-supportedTypeIds, enforced in contracts.ts).
 *   2. The P0.G4 functional-type snapshot (primaryTypeId/supportedTypeIds
 *      actually exist -- see type_snapshot.ts).
 * Throws `CatalogValidationError` on any failure; never normalizes,
 * drops, or defaults an invalid reference. This is a pure function -- it
 * performs no I/O and calls no store. See `writeEquipmentModel` below for
 * the actual write path, which is what "the write path MUST call this
 * function" (§6.5) refers to in practice.
 */
export function validateEquipmentModelWrite(
  candidate: unknown,
  snapshot: FunctionalTypeSnapshot = loadGeneratedSnapshot(),
): EquipmentModel {
  let model: EquipmentModel;
  try {
    model = EquipmentModelSchema.parse(candidate);
  } catch (err) {
    if (err instanceof z.ZodError) {
      throw new CatalogValidationError(
        `EquipmentModel schema validation failed: ${err.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ")}`,
        err,
      );
    }
    throw err;
  }

  try {
    validateTypeReference(model.primaryTypeId, model.supportedTypeIds, snapshot);
  } catch (err) {
    throw new CatalogValidationError(
      `EquipmentModel ${model.modelId} references an invalid functional type: ${
        err instanceof Error ? err.message : String(err)
      }`,
      err,
    );
  }

  return model;
}

/** P1 additionally restricts every pilot record's support-status fields
 * (§5.11): P1-created records must never be textSupportStatus=VERIFIED,
 * and must always be visionSupportStatus=NONE. This is a P1-scoped
 * business rule, not a structural schema rule -- later phases (P2/P6) are
 * the ones that legitimately promote a model beyond these values, so the
 * restriction lives here, applied only to the P1 write path, not baked
 * into EquipmentModelSchema itself. */
export function validateP1PilotStatusRestrictions(model: EquipmentModel): void {
  if (model.textSupportStatus === "VERIFIED") {
    throw new CatalogValidationError(
      `EquipmentModel ${model.modelId}: textSupportStatus must not be VERIFIED for a P1-created record`,
    );
  }
  if (model.visionSupportStatus !== "NONE") {
    throw new CatalogValidationError(
      `EquipmentModel ${model.modelId}: visionSupportStatus must be NONE for a P1-created record, got ${model.visionSupportStatus}`,
    );
  }
}

export interface EquipmentModelStore {
  write(model: EquipmentModel): Promise<void>;
}

/**
 * The actual write path: validates, then writes. An invalid candidate
 * throws before `store.write` is ever called -- see
 * __tests__/p1_catalog_repository.test.ts's fake-store mutation proof.
 *
 * `options.enforceP1PilotRestrictions` defaults to false/unset: this gate
 * has no real Firestore write caller yet (P1.G5/G6 add one), so the flag
 * exists but is not unconditionally on. Whichever gate wires the real
 * write caller must pass `enforceP1PilotRestrictions: true` and is
 * responsible for a regression test proving it did (reviewer note, P1.G1
 * silent-failure review, 2026-08-22 -- not a defect in this gate, since
 * nothing here claims unconditional enforcement).
 */
export async function writeEquipmentModel(
  candidate: unknown,
  store: EquipmentModelStore,
  options: { snapshot?: FunctionalTypeSnapshot; enforceP1PilotRestrictions?: boolean } = {},
): Promise<EquipmentModel> {
  const model = validateEquipmentModelWrite(candidate, options.snapshot ?? loadGeneratedSnapshot());
  if (options.enforceP1PilotRestrictions) {
    validateP1PilotStatusRestrictions(model);
  }
  await store.write(model);
  return model;
}

// --- catalog-level uniqueness (§6.6) --------------------------------------

export type UniquenessViolationType =
  | "DUPLICATE_MODEL_ID"
  | "DUPLICATE_CANONICAL_SLUG"
  | "DUPLICATE_BRAND_ID"
  | "DUPLICATE_PRODUCT_LINE_ID"
  | "MODEL_REFERS_TO_ABSENT_BRAND"
  | "MODEL_REFERS_TO_ABSENT_PRODUCT_LINE"
  | "DUPLICATE_MODEL_CODE_SAME_BRAND_LINE";

export interface UniquenessViolation {
  type: UniquenessViolationType;
  detail: string;
}

export interface CatalogUniquenessInput {
  brands: EquipmentBrand[];
  productLines: ProductLine[];
  models: EquipmentModel[];
}

/**
 * Groups items by a composite key, encoding the key PARTS as a
 * `JSON.stringify`'d array -- never a delimiter-joined string. A joined
 * string like `` `${a} ${b}` `` is ambiguous whenever a part can itself
 * contain the delimiter (reviewer-found MAJOR, P1.G1 database review,
 * 2026-08-22: `catalogVersion`/`modelCode` are free text and can contain
 * spaces, so two structurally different tuples could concatenate to the
 * same string and be misreported as one false "duplicate"). JSON-encoding
 * an array preserves each element's boundary regardless of its content, so
 * this is collision-free for any string parts. The parts are kept
 * alongside each group (not re-derived by splitting the key with
 * `.split(" ")`) so building a detail message never has to guess where one
 * part ends and the next begins.
 */
function groupByParts<T>(
  items: T[],
  parts: (item: T) => string[],
): Map<string, { parts: string[]; items: T[] }> {
  const groups = new Map<string, { parts: string[]; items: T[] }>();
  for (const item of items) {
    const p = parts(item);
    const key = JSON.stringify(p);
    const existing = groups.get(key);
    if (existing) {
      existing.items.push(item);
    } else {
      groups.set(key, { parts: p, items: [item] });
    }
  }
  return groups;
}

/**
 * Catalog-level uniqueness/referential checks (§6.6). Never silently
 * renames or drops a collision -- every violation is returned, none is
 * auto-resolved. A duplicate `modelCode` within the same brand+line is
 * reported (not silently accepted) as `DUPLICATE_MODEL_CODE_SAME_BRAND_LINE`
 * -- whether that duplicate is a genuine conflict or two real distinct SKUs
 * sharing a printed code is P1.G5 reconciliation's call, not this
 * function's; this function only makes the collision visible.
 */
export function validateCatalogUniqueness(
  catalog: CatalogUniquenessInput,
): { valid: boolean; violations: UniquenessViolation[] } {
  const violations: UniquenessViolation[] = [];

  for (const { parts, items } of groupByParts(catalog.models, (m) => [m.modelId]).values()) {
    if (items.length > 1) {
      violations.push({
        type: "DUPLICATE_MODEL_ID",
        detail: `modelId ${parts[0]} appears ${items.length} times`,
      });
    }
  }

  for (const { parts, items } of groupByParts(catalog.models, (m) => [
    m.catalogVersion,
    m.canonicalSlug,
  ]).values()) {
    if (items.length > 1) {
      const [catalogVersion, slug] = parts;
      violations.push({
        type: "DUPLICATE_CANONICAL_SLUG",
        detail: `canonicalSlug ${slug} in catalogVersion ${catalogVersion} used by modelId(s) ${items
          .map((m) => m.modelId)
          .sort()
          .join(", ")}`,
      });
    }
  }

  for (const { parts, items } of groupByParts(catalog.brands, (b) => [
    b.catalogVersion,
    b.brandId,
  ]).values()) {
    if (items.length > 1) {
      const [catalogVersion, brandId] = parts;
      violations.push({
        type: "DUPLICATE_BRAND_ID",
        detail: `brandId ${brandId} appears ${items.length} times in catalogVersion ${catalogVersion}`,
      });
    }
  }

  for (const { parts, items } of groupByParts(catalog.productLines, (l) => [
    l.catalogVersion,
    l.productLineId,
  ]).values()) {
    if (items.length > 1) {
      const [catalogVersion, productLineId] = parts;
      violations.push({
        type: "DUPLICATE_PRODUCT_LINE_ID",
        detail: `productLineId ${productLineId} appears ${items.length} times in catalogVersion ${catalogVersion}`,
      });
    }
  }

  const knownBrandKeys = new Set(
    catalog.brands.map((b) => JSON.stringify([b.catalogVersion, b.brandId])),
  );
  const knownLineKeys = new Set(
    catalog.productLines.map((l) => JSON.stringify([l.catalogVersion, l.productLineId])),
  );
  for (const m of catalog.models) {
    if (!knownBrandKeys.has(JSON.stringify([m.catalogVersion, m.brandId]))) {
      violations.push({
        type: "MODEL_REFERS_TO_ABSENT_BRAND",
        detail: `modelId ${m.modelId} references brandId ${m.brandId} not present in catalogVersion ${m.catalogVersion}`,
      });
    }
    if (
      m.productLineId &&
      !knownLineKeys.has(JSON.stringify([m.catalogVersion, m.productLineId]))
    ) {
      violations.push({
        type: "MODEL_REFERS_TO_ABSENT_PRODUCT_LINE",
        detail: `modelId ${m.modelId} references productLineId ${m.productLineId} not present in catalogVersion ${m.catalogVersion}`,
      });
    }
  }

  for (const { parts, items } of groupByParts(catalog.models, (m) => [
    m.catalogVersion,
    m.brandId,
    m.productLineId ?? "",
    m.modelCode,
  ]).values()) {
    if (items.length > 1) {
      const [catalogVersion, brandId, productLineId, modelCode] = parts;
      violations.push({
        type: "DUPLICATE_MODEL_CODE_SAME_BRAND_LINE",
        detail: `modelCode ${modelCode} in brand ${brandId}${productLineId ? `/${productLineId}` : ""} (catalogVersion ${catalogVersion}) used by modelId(s) ${items
          .map((m) => m.modelId)
          .sort()
          .join(", ")}`,
      });
    }
  }

  return { valid: violations.length === 0, violations };
}
