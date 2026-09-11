/**
 * P2.G3 -- small read helpers against P1.G1's already-defined catalog
 * collections (equipment_catalog_active, equipment_models). No writer for
 * either exists in this repo yet (P1.G6 real publication runtime is out of
 * scope for this gate); these reads therefore honestly return `null` today
 * in a real deployment, which the orchestrator turns into
 * `UNAVAILABLE_CATALOG_VERSION` -- an accurate reflection of "nothing has
 * been published yet," never a faked success.
 *
 * Every function here returns `null` for BOTH "the document doesn't exist"
 * and "the document exists but fails schema validation" -- callers
 * genuinely cannot and should not distinguish the two (both mean "there is
 * no usable catalog state to act on"). But a caller not distinguishing them
 * must not mean NOBODY does: a malformed-but-present document is a real
 * data-integrity bug a corrupted-nothing-published state is not, so each
 * function logs the parse failure here, at the one place that actually
 * still holds the raw snapshot and the zod issue list (silent-failure-hunter
 * finding, P2.G3 pre-commit review, 2026-09-11 -- the orchestrator's own
 * generic UNAVAILABLE_CATALOG_VERSION/NOT_SUPPORTED responses were
 * previously indistinguishable from this in every log, so a real corrupt
 * document could persist indefinitely with zero operational signal).
 */
import * as logger from "firebase-functions/logger";
import {
  CatalogActivePointerSchema,
  EquipmentModelSchema,
  type CatalogActivePointer,
  type EquipmentModel,
} from "../p1/contracts";
import { CATALOG_ACTIVE_POINTER_DOC_PATH, modelDocPath } from "../p1/firestore_paths";
import { db } from "./firestore_admin";
import type { CatalogModelFields, TextSupportStatus } from "./exact_resolution_policy";

export async function fetchActiveCatalogPointer(): Promise<CatalogActivePointer | null> {
  const snap = await db().doc(CATALOG_ACTIVE_POINTER_DOC_PATH).get();
  if (!snap.exists) return null;
  const parsed = CatalogActivePointerSchema.safeParse(snap.data());
  if (!parsed.success) {
    logger.error("equipment_catalog_active_pointer_schema_invalid", {
      path: CATALOG_ACTIVE_POINTER_DOC_PATH,
      issues: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    });
    return null;
  }
  return parsed.data;
}

export async function fetchEquipmentModel(
  catalogVersion: string,
  modelId: string,
): Promise<EquipmentModel | null> {
  const path = modelDocPath(catalogVersion, modelId);
  const snap = await db().doc(path).get();
  if (!snap.exists) return null;
  const parsed = EquipmentModelSchema.safeParse(snap.data());
  if (!parsed.success) {
    logger.error("equipment_model_schema_invalid", {
      path,
      catalogVersion,
      modelId,
      issues: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    });
    return null;
  }
  return parsed.data;
}

export async function fetchModelFields(
  catalogVersion: string,
  modelId: string,
): Promise<CatalogModelFields | null> {
  const model = await fetchEquipmentModel(catalogVersion, modelId);
  if (!model) return null;
  return {
    modelId: model.modelId,
    catalogVersion: model.catalogVersion,
    textSupportStatus: model.textSupportStatus,
    primaryTypeId: model.primaryTypeId,
    supportedTypeIds: model.supportedTypeIds,
  };
}

const TEXT_SUPPORT_RANK: Record<TextSupportStatus, number> = {
  NONE: 0,
  EXPERIMENTAL: 1,
  VERIFIED: 2,
};

export type RevocationCheckOutcome = { eligible: true } | { eligible: false; reason: string };

/**
 * v4.1 §6.2's revocation-correctness bound, option (a): "Authoritative
 * read before emission. Every EXACT_MODEL emission performs a live,
 * authoritative read of the model's current support/revocation status
 * immediately before responding" (v4.4 §6.6, binding rule for v4.3, still
 * in force -- option (b), bounded staleness, was explicitly ruled out by
 * GPT-PM for this gate as unprovable without live deployment evidence).
 */
export async function checkModelStillEligibleForExact(
  catalogVersion: string,
  modelId: string,
  requiredTextSupportStatus: "EXPERIMENTAL" | "VERIFIED",
): Promise<RevocationCheckOutcome> {
  const model = await fetchEquipmentModel(catalogVersion, modelId);
  if (!model) {
    return { eligible: false, reason: "model no longer present in the pinned catalog version" };
  }
  if (model.catalogStatus !== "ACTIVE") {
    return { eligible: false, reason: `model catalogStatus is ${model.catalogStatus}, no longer ACTIVE` };
  }
  if (TEXT_SUPPORT_RANK[model.textSupportStatus] < TEXT_SUPPORT_RANK[requiredTextSupportStatus]) {
    return {
      eligible: false,
      reason: `model textSupportStatus was downgraded to ${model.textSupportStatus}`,
    };
  }
  return { eligible: true };
}

/**
 * The other half of v4.4 §6.6's authoritative-pre-emission-read bound:
 * `checkModelStillEligibleForExact` above only re-reads the MODEL doc at
 * the catalogVersion the candidate was ALREADY pinned to earlier in the
 * request -- it can prove the model itself was not revoked, but it can
 * never notice the active pointer moving to a DIFFERENT catalogVersion in
 * between (e.g. a new catalog published and promoted mid-request). That
 * gap meant an EXACT_MODEL emission could authoritatively vouch for a
 * catalogVersion Firestore's own active pointer had already stopped
 * pointing at (GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11). Called
 * as a SEPARATE re-read here, deliberately, rather than folded into
 * `checkModelStillEligibleForExact` -- the two checks answer different
 * questions ("is this model still good" vs "is this catalogVersion still
 * the one in force") and keeping them apart keeps each one's own name
 * accurate.
 */
export async function verifyActiveCatalogVersionStillCurrent(catalogVersion: string): Promise<boolean> {
  const pointer = await fetchActiveCatalogPointer();
  return pointer !== null && pointer.activeCatalogVersion === catalogVersion;
}
