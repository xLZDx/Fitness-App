/**
 * P1.G1 §5.5/§5.6 — canonical id helpers (SPTR Equipment Recognition v4.4).
 *
 * modelId is a random UUID v4, assigned ONCE when a candidate is accepted
 * into the canonical catalog and persisted in
 * core/equipment_identity/p1/reconciliation/model_id_registry.json (P1.G5
 * owns that registry; this module only generates/validates the id shape).
 * It is never derived from modelCode/SKU/URL/canonicalSlug -- a later
 * rename must not change it.
 */
import { randomUUID, createHash } from "crypto";

export function generateModelId(): string {
  return randomUUID();
}

const UUID_V4_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isValidModelId(value: string): boolean {
  return UUID_V4_RE.test(value);
}

/** candidateId MAY be deterministic (§5.5) -- it is staging identity, never
 * the canonical primary key, so a stable derivation is fine and useful
 * (reruns of an adapter against the same source produce the same
 * candidateId, which is what lets G5's reconciliation dedupe reruns).
 *
 * The `\n` delimiter between `sourceId` and `sourceStableKey` is only
 * collision-free if neither input can itself contain `\n` -- true today
 * because every real caller's `sourceId` round-trips through `SlugSchema`
 * (which disallows it), but that was caller discipline, not something this
 * function itself enforced (reviewer-found gap, P1.G1 type-design review,
 * 2026-08-22). Rejecting `\n` here locally closes the gap regardless of
 * what a future caller passes. */
export function deriveCandidateId(sourceId: string, sourceStableKey: string): string {
  if (!sourceId) throw new Error("deriveCandidateId: sourceId must be non-empty");
  if (!sourceStableKey) {
    throw new Error("deriveCandidateId: sourceStableKey must be non-empty");
  }
  if (sourceId.includes("\n")) {
    throw new Error("deriveCandidateId: sourceId must not contain a newline");
  }
  if (sourceStableKey.includes("\n")) {
    throw new Error("deriveCandidateId: sourceStableKey must not contain a newline");
  }
  return createHash("sha256").update(`${sourceId}\n${sourceStableKey}`).digest("hex");
}

const SLUG_INVALID_CHARS_RE = /[^a-z0-9]+/g;
// eslint-disable-next-line no-control-regex -- U+0300-U+036F combining
// diacritical marks left behind by NFKD normalization (e.g. "é" -> "e" +
// U+0301); written as an explicit \uXXXX escape rather than a literal
// character so the source stays plain ASCII.
const COMBINING_DIACRITIC_RE = /[̀-ͯ]/g;

function slugifyPart(part: string): string {
  return part
    .trim()
    .toLowerCase()
    .normalize("NFKD")
    .replace(COMBINING_DIACRITIC_RE, "")
    .replace(SLUG_INVALID_CHARS_RE, "-")
    .replace(/^-+|-+$/g, "");
}

/** productLineId convention: `<brandId>-<stable-line-slug>` (§5.5). */
export function buildProductLineId(brandId: string, lineSlug: string): string {
  const brand = slugifyPart(brandId);
  const line = slugifyPart(lineSlug);
  if (!brand) throw new Error("buildProductLineId: brandId slugifies to empty");
  if (!line) throw new Error("buildProductLineId: lineSlug slugifies to empty");
  return `${brand}-${line}`;
}

/** canonicalSlug is a human-readable, unique secondary field generated from
 * brand + official line (where applicable) + exact model code/name. A
 * collision is a VISIBLE CONFLICT (§5.6) -- this function never silently
 * suffixes `-2`/`-3`; uniqueness enforcement is validateCatalogUniqueness's
 * job (catalog_repository.ts), not this builder's. */
export function buildCanonicalSlug(parts: {
  brandId: string;
  productLine?: string | null;
  modelCodeOrName: string;
}): string {
  const segments = [
    slugifyPart(parts.brandId),
    parts.productLine ? slugifyPart(parts.productLine) : "",
    slugifyPart(parts.modelCodeOrName),
  ].filter((s) => s.length > 0);
  if (segments.length === 0) {
    throw new Error("buildCanonicalSlug: all parts slugify to empty");
  }
  return segments.join("-");
}
