/**
 * P2.G3 T1 (SPTR Equipment Recognition v4.4) -- canonical, case-normalized
 * exact model-code/SKU/alias lookup against the authoritative catalog.
 *
 * Why a derived collection rather than querying `equipment_models`
 * directly (GPT-PM round-2/3 review of the P2.G3 plan, 2026-09-10):
 * `EquipmentModel.modelCode`/`skuAliases`/`aliases` (contracts.ts:404-409)
 * are arbitrary non-empty strings with NO canonical-case invariant, and
 * `equipment_external_mappings` (contracts.ts:450-459) carries no
 * model-code/alias field at all. P2.G2's mobile parser already uppercases
 * detected candidates (identity_text_parser.dart:284), so a live
 * "normalize the query, compare against raw stored bytes" approach would
 * miss a stored "8TRx" on an OCR "8TRX" query. This module instead
 * materializes ONE normalized key per (catalogVersion, lookupKey, modelId)
 * at write time (see `materializeEquipmentModelTextKeys`) into
 * `equipment_model_text_keys`, and resolves purely against that derived,
 * pre-normalized index -- never against `equipment_models`' raw bytes, and
 * never treating `equipment_external_mappings` as an alias table.
 *
 * Who calls the write path today (GPT-PM round-3 MAJOR): P1.G6's real
 * catalog-publication pipeline does not exist yet in this repo. This
 * module is therefore the ONLY writer of `equipment_model_text_keys` --
 * every test below drives a real EquipmentModel fixture through
 * `materializeEquipmentModelTextKeys` -> `FirestoreTextKeyStore.writeMany`
 * -> `resolveModelCodeLookup`, end to end, never a test that hand-writes
 * rows directly into the derived collection. A future P1.G6 publisher is
 * REQUIRED to call `materializeEquipmentModelTextKeys` (and write its
 * output through the same store shape) on every publish, not reimplement
 * a second canonicalizer.
 *
 * HARD CALLER CONTRACT, load-bearing and NOT enforced by this module
 * (ontology reviewer finding, P2.G3 pre-commit review, 2026-09-11):
 * `writeMany`/`materializeAndWrite` are purely ADDITIVE -- they only ever
 * `batch.set()` the records the CURRENT call computes; there is no
 * read-before-write and no delete of a previously-materialized row for the
 * same modelId. This is safe ONLY under the assumption the rest of P1.G1
 * already implies (`CatalogPublishJobSchema`'s `BUILD_IMMUTABLE_VERSION`
 * status, contracts.ts): a `catalogVersion`, once built, is NEVER
 * re-materialized with different model content. A future P1.G6 publisher
 * MUST call this primitive exactly once per model per catalogVersion, and
 * MUST cut a brand-new catalogVersion for any model-code/alias correction
 * -- never re-publish an existing version with changed content. Violating
 * this leaves a stale, orphaned derived row (e.g. an old "OLD123" key)
 * silently resolving UNIQUE forever, with no error and no log anywhere,
 * because nothing in this file can detect a rewrite it was never told
 * about. Reconciling/deleting stale rows is explicitly OUT OF SCOPE for
 * this gate (P1.G6's real publication runtime does not exist yet -- see
 * this file's own note above) and is P1.G6's own obligation to design for,
 * not something this primitive can safely guess at without knowing the
 * publisher's actual batch/diff shape.
 */
import type { EquipmentModel } from "../p1/contracts";
import { db } from "./firestore_admin";
import { P2CollectionPaths, textKeyDocId } from "./firestore_paths";

export type LookupKeyKind = "MODEL_CODE" | "SKU_ALIAS" | "ALIAS";

export interface DerivedTextKeyRecord {
  catalogVersion: string;
  lookupKey: string;
  modelId: string;
  /** Every source field on the model that normalized to this same key. */
  keyKinds: LookupKeyKind[];
}

/**
 * Matches P2.G2's own uppercase convention exactly: trim, strip only
 * LEADING/TRAILING non-alphanumeric characters (identity_text_parser.dart's
 * `stripPunctuation`, `^[^A-Za-z0-9]+|[^A-Za-z0-9]+$`), then uppercase.
 * Internal delimiters ('/', '-') are deliberately preserved -- they are
 * meaningful, not noise, per the same file's own `hasDelimiter` check.
 *
 * Returns "" for a degenerate all-punctuation input; callers treat an
 * empty normalized key as "no real key here", never as a valid match
 * target (an empty lookupKey would otherwise match every other empty
 * source across the whole catalog, a silent false-positive class).
 */
export function normalizeModelCodeLookupKey(raw: string): string {
  return raw
    .trim()
    .replace(/^[^A-Za-z0-9]+|[^A-Za-z0-9]+$/g, "")
    .toUpperCase();
}

/**
 * Deterministic, pure builder. Groups every source field that normalizes
 * to the same key into ONE record (GPT-PM round-4 MAJOR fix) -- a model
 * whose modelCode and an alias both normalize to "8TRX" produces exactly
 * one DerivedTextKeyRecord with keyKinds: ["ALIAS", "MODEL_CODE"], never
 * two. Output is sorted by lookupKey for a deterministic return order
 * regardless of the model's own array ordering.
 */
export function materializeEquipmentModelTextKeys(model: EquipmentModel): DerivedTextKeyRecord[] {
  const kindsByKey = new Map<string, Set<LookupKeyKind>>();

  const addSource = (raw: string, kind: LookupKeyKind): void => {
    const key = normalizeModelCodeLookupKey(raw);
    if (key.length === 0) return;
    if (!kindsByKey.has(key)) kindsByKey.set(key, new Set());
    kindsByKey.get(key)!.add(kind);
  };

  addSource(model.modelCode, "MODEL_CODE");
  for (const sku of model.skuAliases) addSource(sku, "SKU_ALIAS");
  for (const alias of model.aliases) addSource(alias, "ALIAS");

  const records: DerivedTextKeyRecord[] = [];
  for (const [lookupKey, kinds] of kindsByKey) {
    records.push({
      catalogVersion: model.catalogVersion,
      lookupKey,
      modelId: model.modelId,
      keyKinds: [...kinds].sort(),
    });
  }
  return records.sort((a, b) => a.lookupKey.localeCompare(b.lookupKey));
}

export interface TextKeyStore {
  writeMany(records: DerivedTextKeyRecord[]): Promise<void>;
}

/** The real, Firestore-backed writer. */
export class FirestoreTextKeyStore implements TextKeyStore {
  async writeMany(records: DerivedTextKeyRecord[]): Promise<void> {
    if (records.length === 0) return;
    const batch = db().batch();
    for (const record of records) {
      const id = textKeyDocId(record.catalogVersion, record.lookupKey, record.modelId);
      const ref = db().collection(P2CollectionPaths.textKeys).doc(id);
      batch.set(ref, record);
    }
    await batch.commit();
  }
}

/**
 * The single entry point a publisher (this gate's own tests today, a
 * future P1.G6 publisher tomorrow) is required to call -- materializes
 * then writes, so the two steps can never drift apart.
 */
export async function materializeAndWrite(
  model: EquipmentModel,
  store: TextKeyStore,
): Promise<DerivedTextKeyRecord[]> {
  const records = materializeEquipmentModelTextKeys(model);
  await store.writeMany(records);
  return records;
}

export type ModelCodeLookupResult =
  | { outcome: "UNIQUE"; modelId: string; keyKinds: LookupKeyKind[] }
  | { outcome: "NONUNIQUE"; modelIds: string[] }
  | { outcome: "NO_MATCH" };

/**
 * Query-side resolver. Decides UNIQUE/NONUNIQUE/NO_MATCH from the count of
 * DISTINCT modelIds in the result set -- never raw document/row count
 * (GPT-PM round-4 MAJOR: a single model can legitimately own more than one
 * derived row only if the materializer's own dedup were bypassed; this is
 * a defensive second layer independent of that dedup, not a replacement
 * for it). Rights-independent by construction: this collection carries no
 * rights/legal-review-state field at all, only catalogVersion/lookupKey/
 * modelId/keyKinds, so there is nothing here for a rights check to gate.
 */
export async function resolveModelCodeLookup(
  rawQuery: string,
  catalogVersion: string,
): Promise<ModelCodeLookupResult> {
  const lookupKey = normalizeModelCodeLookupKey(rawQuery);
  if (lookupKey.length === 0) return { outcome: "NO_MATCH" };

  const snap = await db()
    .collection(P2CollectionPaths.textKeys)
    .where("catalogVersion", "==", catalogVersion)
    .where("lookupKey", "==", lookupKey)
    .get();

  const keyKindsByModelId = new Map<string, LookupKeyKind[]>();
  for (const doc of snap.docs) {
    const data = doc.data() as DerivedTextKeyRecord;
    keyKindsByModelId.set(data.modelId, data.keyKinds);
  }

  const distinctModelIds = [...keyKindsByModelId.keys()].sort();
  if (distinctModelIds.length === 0) return { outcome: "NO_MATCH" };
  if (distinctModelIds.length === 1) {
    const modelId = distinctModelIds[0];
    return { outcome: "UNIQUE", modelId, keyKinds: keyKindsByModelId.get(modelId)! };
  }
  return { outcome: "NONUNIQUE", modelIds: distinctModelIds };
}
