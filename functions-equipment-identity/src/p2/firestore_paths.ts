/**
 * P2.G3 -- Firestore physical layout for the derived, server-maintained
 * text-lookup index. Deliberately kept OUT of P1.G1's own firestore_paths.ts:
 * that file is the frozen, already-reviewed P1 catalog schema layer, and
 * `equipment_model_text_keys` is a P2-owned derived collection with a
 * different identity scheme (hash-based, not `{catalogVersion}--{entityId}`)
 * -- adding it there would perturb an already-closed gate's file for no
 * shared benefit.
 *
 * Why a hash-based document id rather than P1's
 * `{catalogVersion}--{entityId}` composite scheme (GPT-PM round-3 MAJOR,
 * P2.G3 plan review, 2026-09-10): a `lookupKey` is derived from
 * `EquipmentModel.modelCode`/`skuAliases`/`aliases`, which P2.G2's parser
 * (mobile/lib/features/visual_equipment/data/identity_text_parser.dart:183)
 * deliberately preserves '/' and '-' inside as meaningful delimiters -- a
 * real code like "ABC/123" would create a different Firestore path segment
 * under a '/'-joined id, and a code containing '--' would collide with
 * P1's own reserved composite-id separator. `catalogVersion`, `lookupKey`,
 * `modelId` (and `keyKinds`) are therefore stored as plain indexed FIELDS,
 * never reconstructed by parsing the id, and the id itself is a
 * deterministic SHA-256 digest over exactly those three identity fields --
 * the same JSON.stringify([...]) array-encoding collision-safety pattern
 * catalog_repository.ts's `groupByParts` already uses for composite keys
 * containing free-text parts.
 */
import { createHash } from "crypto";

export const P2CollectionPaths = {
  /** `equipment_model_text_keys/{sha256(JSON.stringify([catalogVersion, lookupKey, modelId]))}`. */
  textKeys: "equipment_model_text_keys",
} as const;

/**
 * Deterministic, collision-safe document id for one
 * (catalogVersion, lookupKey, modelId) tuple. `keyKind`/`keyKinds` is
 * deliberately NOT part of the id -- identity is (catalogVersion,
 * lookupKey, modelId) alone (GPT-PM round-4 MAJOR: a model whose modelCode
 * and an alias both normalize to the same key must be ONE row, not one
 * row per source kind, or a naive row-count resolver misreports a unique
 * model as NONUNIQUE).
 */
export function textKeyDocId(catalogVersion: string, lookupKey: string, modelId: string): string {
  return createHash("sha256")
    .update(JSON.stringify([catalogVersion, lookupKey, modelId]))
    .digest("hex");
}

export function textKeyDocPath(catalogVersion: string, lookupKey: string, modelId: string): string {
  return `${P2CollectionPaths.textKeys}/${textKeyDocId(catalogVersion, lookupKey, modelId)}`;
}

/**
 * `users/{uid}/equipment_identity_latest_session/current` -- a P2-owned
 * per-user pointer to whichever `recognitionSessionId` was pinned most
 * recently, used to detect cross-scan supersession (GPT-PM MAJOR, P2.G3
 * pre-commit review round 2, 2026-09-11: a real "newer scan supersedes an
 * older one" mechanism was missing entirely -- round 1's remediation only
 * ever compared a retry against ITS OWN prior scanId, never against
 * whatever scan came after it). Deliberately a SEPARATE collection from
 * P1.G1's own `users/{uid}/equipment_identity_sessions` (frozen gate, see
 * this file's own header) rather than a reserved doc id inside it.
 */
export function userEquipmentIdentityLatestSessionDocPath(uid: string): string {
  if (!uid) throw new Error("userEquipmentIdentityLatestSessionDocPath: uid must be non-empty");
  return `users/${uid}/equipment_identity_latest_session/current`;
}
