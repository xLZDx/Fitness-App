/**
 * P1.G2 — official P0 brand adapter contracts (SPTR Equipment Recognition
 * v4.4). See core/equipment_identity/p1/P1_G2_OFFICIAL_P0_ADAPTERS.md.
 *
 * A "source capture fixture" is the raw, honestly-labeled evidence an
 * adapter consumes -- never a live network call at build/test time (P1 has
 * no production Cloud Function export at all -- see P0.G5/P0.G6). Every
 * fixture under core/equipment_identity/p1/source_captures/ was populated
 * from real official-manufacturer data gathered during this gate; nothing
 * here is fabricated to fill a quota.
 *
 * `retrievalMethod` exists to keep two honestly-different evidence classes
 * structurally distinct, per §5.9's discovery allowance: a page an adapter's
 * author actually fetched and read (DIRECT_FETCH) versus one only located
 * via a search-engine index because the domain blocked direct retrieval
 * (SEARCH_INDEX_SNIPPET, e.g. technogym.com returning HTTP 403 on every
 * path tried). Both are legitimate provenance under §5.9 as long as
 * `sourceUrl` still points at the verified official domain and no content
 * hash is ever claimed for bytes that were never actually fetched -- see
 * ProvenanceRefSchema's own `sourceContentSha256` comment in ../contracts.ts.
 */
import { z } from "zod";
import { SlugSchema, IsoTimestampSchema, RetrievalMethodSchema } from "../contracts";

export { RetrievalMethodSchema };

/** One raw, un-reconciled product record as captured from an official
 * source. `modelCodeRaw` is required (not optional): a record with no real
 * manufacturer model code carries no exact-model identity at all, and §5.7
 * requires every pilot model to have "a stable exact manufacturer
 * identifier" -- refusing a codeless record here, structurally, is cheaper
 * than filtering one out later in G5. */
export const RawCaptureRecordSchema = z
  .object({
    brandNameRaw: z.string().min(1),
    productNameRaw: z.string().min(1),
    modelCodeRaw: z.string().min(1),
    productLineRaw: z.string().min(1).optional(),
    lifecycleStatusRaw: z.string().min(1).optional(),
    // Non-binding hints only -- never authoritative (§5.8). May be empty
    // when no confident real-ontology id applies; a wrong guess is worse
    // than no hint.
    typeHintsRaw: z.array(z.string().min(1)),
    specsRaw: z.record(z.string(), z.string()).optional(),
    sourceUrl: z.string().url(),
    retrievalMethod: RetrievalMethodSchema,
  })
  .strict();
export type RawCaptureRecord = z.infer<typeof RawCaptureRecordSchema>;

/** `core/equipment_identity/p1/source_captures/{sourceId}.json`. One
 * fixture per registered `OFFICIAL_MANUFACTURER` source. `capturedAt` uses
 * the same strict ISO-8601-with-offset schema as `retrievedAt` downstream
 * (reviewer-found gap, P1.G2 review, 2026-08-22): it used to be a bare
 * `z.string().min(1)`, so a malformed value (e.g. a date with no time/
 * offset) passed fixture load and only failed deep inside
 * `mapRecordToCandidate` -- the error should point at the fixture that
 * actually has the bad value, not somewhere downstream of it. */
export const SourceCaptureFixtureSchema = z
  .object({
    schemaVersion: z.literal(1),
    sourceId: SlugSchema,
    capturedAt: IsoTimestampSchema,
    records: z.array(RawCaptureRecordSchema).nonempty(),
  })
  .strict();
export type SourceCaptureFixture = z.infer<typeof SourceCaptureFixtureSchema>;
