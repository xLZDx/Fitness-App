/**
 * P1.G1 — canonical equipment-identity ontology contracts (SPTR Equipment
 * Recognition v4.4). See core/design/sptr_equipment_recognition_v4_1/
 * SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md,
 * P1.G1 section, and core/equipment_identity/p1/P1_G1_SCHEMA.md.
 *
 * These schemas are additive to the existing functional ontology
 * (mobile/assets/data/equipment.json, Layer A) — nothing here replaces
 * ExerciseItem.equipmentId or the generic scanner's existing behavior.
 * `primaryTypeId`/`supportedTypeIds` reference that same functional
 * ontology by id; see type_snapshot.ts for how a reference is validated
 * against P0.G4's frozen snapshot.
 */
import { z } from "zod";

// --- shared primitives ------------------------------------------------

/** A lowercase hex SHA-256 digest.
 *
 * The end assertion is `(?![\s\S])` rather than `$` so this agrees with the
 * Python side character for character. JavaScript's `$` already refuses a
 * trailing newline, but Python's `$` accepts one — and both
 * `scripts/equipment_identity/rights.py` and the Draft-07 schema (validated
 * with Python's own `re`) previously used `$`, so `"a".repeat(64) + "\n"` was
 * legal to two layers and illegal to this one. Not a permission bypass; a
 * digest like that fails the byte comparison anyway. It simply made the
 * claim "all three layers enforce the same shape" untrue. */
export const Sha256HexSchema = z
  .string()
  .regex(/^[0-9a-f]{64}(?![\s\S])/, "must be a lowercase 64-character hex SHA-256 digest");

export const IsoTimestampSchema = z.string().datetime({ offset: true });

export const UuidV4Schema = z.string().uuid();

/** Stable slug: lowercase, digits, hyphen/underscore, must start alnum.
 * Forbids a `--` substring -- reviewer-found gap (P1.G1 database review,
 * 2026-08-22): `{catalogVersion}--{entityId}` (firestore_paths.ts) is a
 * plain string join, and this schema's own regex otherwise legally admits
 * e.g. `"ab--cd"`. A slug containing `--` could make a future
 * `documentId()` prefix-range read (the exact query shape the versioned
 * docId scheme exists to support) pull entities from the wrong
 * catalogVersion into the same read. No real data exists yet, so this is
 * cheap to close now and expensive once it does. */
export const SlugSchema = z
  .string()
  .regex(/^[a-z0-9][a-z0-9_-]*$/, "must be a stable lowercase slug")
  .refine((v) => !v.includes("--"), {
    message: "must not contain '--' -- reserved as the {catalogVersion}--{entityId} Firestore docId separator",
  });

/** Same Firestore-docId-safety concern as SlugSchema's `--` ban, for the
 * catalogVersion string itself (which is not slug-shaped -- its exact
 * format is P1.G6's to define -- but still must never contain `/` or
 * `--`, since it is always the LEFT half of a `{catalogVersion}--
 * {entityId}` composite docId). */
export const CatalogVersionSchema = z
  .string()
  .min(1)
  .max(200)
  .refine((v) => !v.includes("/"), "catalogVersion must not contain '/'")
  .refine((v) => !v.includes("--"), {
    message: "catalogVersion must not contain '--' -- reserved as the {catalogVersion}--{entityId} Firestore docId separator",
  });

/** A free-form entity id (mappingId/setupSpecId/assetId/jobId) that will be
 * interpolated into a raw Firestore docId (versionedDocId in
 * firestore_paths.ts is plain string concatenation, no escaping) -- unlike
 * brandId/productLineId/canonicalSlug/modelId, these are not required to
 * be slug-shaped (adapters may source them from arbitrary external
 * identifiers), but they still must be safe to use as a Firestore docId
 * segment. Reviewer-found gap (P1.G1 database review, 2026-08-22): these
 * fields previously had zero format validation. */
export const EntityIdSchema = z
  .string()
  .min(1)
  .max(300)
  .refine((v) => !v.includes("/"), "must not contain '/'")
  .refine((v) => v !== "." && v !== "..", "must not be '.' or '..'")
  .refine((v) => !/^__.*__$/.test(v), "must not match the reserved __...__ pattern")
  .refine((v) => !v.includes("--"), {
    message: "must not contain '--' -- reserved as the {catalogVersion}--{entityId} Firestore docId separator",
  });

// --- provenance ---------------------------------------------------------

/** P1.G2 (§5.9): how `sourceUrl`'s content was actually obtained.
 * DIRECT_FETCH = the page itself was retrieved and read. SEARCH_INDEX_SNIPPET
 * = only located via a search-engine index (e.g. a domain that blocks
 * direct retrieval outright) -- still legitimate discovery-based provenance
 * under §5.9 as long as `sourceUrl` points at the verified official domain,
 * but honestly distinguished from a page an adapter actually fetched.
 * Optional so P1.G1-era provenance refs (predating this distinction) stay
 * valid without a migration. */
export const RetrievalMethodSchema = z.enum(["DIRECT_FETCH", "SEARCH_INDEX_SNIPPET"]);
export type RetrievalMethod = z.infer<typeof RetrievalMethodSchema>;

export const ProvenanceRefSchema = z.object({
  sourceId: SlugSchema,
  sourceUrl: z.string().url(),
  retrievedAt: IsoTimestampSchema,
  // Only present when an actual network response was captured -- never a
  // hash of something that was never fetched. See §6.1: "No provenance ref
  // may claim a hash that was not actually computed."
  sourceContentSha256: Sha256HexSchema.optional(),
  fixtureSha256: Sha256HexSchema,
  adapterId: z.string().min(1),
  adapterVersion: z.string().min(1),
  sourceLocator: z.string().min(1).optional(),
  retrievalMethod: RetrievalMethodSchema.optional(),
  fields: z.array(z.string().min(1)).nonempty(),
});
export type ProvenanceRef = z.infer<typeof ProvenanceRefSchema>;

// --- rights (mirrors core/equipment_identity/p0/rights_decision.schema.json,
// so a Firestore-projected EquipmentSource record and the Python-owned
// source_registry.json record stay structurally identical) -----------------

export const LegalReviewStateSchema = z.enum(["UNREVIEWED", "REVIEWED", "BLOCKED"]);

/** One grammar for every scope identifier, shared VERBATIM with
 * `scripts/equipment_identity/rights.py` (`IDENTIFIER_PATTERN`) and
 * `rights_decision.schema.json` (`#/definitions/scopeIdentifier`).
 *
 * The two odd choices in it are what make that sharing real rather than
 * cosmetic — identical characters are not identical meaning:
 *
 * - The alphabet is enumerated ASCII, never `\w` or `\S`, because Python and
 *   JavaScript disagree about which code points are whitespace. Measured in
 *   both engines: Python's `\S` rejects U+0085 and accepts U+FEFF; ours does
 *   exactly the reverse.
 * - The end assertion is `(?![\s\S])` rather than `$`, because Python's `$`
 *   also matches just before a trailing newline while ours does not — and the
 *   Python `jsonschema` package compiles `pattern` with Python's own `re`. A
 *   `$` here would therefore leave Python and the JSON Schema agreeing with
 *   each other while this mirror silently disagreed, which is precisely the
 *   drift this file exists to prevent. `[\s\S]` is a set unioned with its own
 *   complement, so it means "any character" in both engines whatever either
 *   calls whitespace.
 *
 * Exported as the pattern TEXT so the contract tests can feed the identical
 * string to all three runtimes instead of comparing source files by eye. */
export const SCOPE_IDENTIFIER_PATTERN =
  "^[A-Za-z0-9](?:[A-Za-z0-9._:-]*[A-Za-z0-9])?(?![\\s\\S])";

export const ScopeIdentifierSchema = z.string().regex(new RegExp(SCOPE_IDENTIFIER_PATTERN));

/** The lexical shape of a recorded `termsSnapshotPath`, shared verbatim with
 * `rights.py` (`SNAPSHOT_PATH_PATTERN`) and the Draft-07 schema — so all three
 * agree on the VALUE and not merely on whether the field is present. A
 * previous version used `z.string().min(1)` here, `{"type": "string"}` in the
 * schema and a `.strip()` check in Python, which meant `" "` was accepted by
 * two layers and refused by the third.
 *
 * The component alphabet is what closes an NTFS alternate data stream:
 * `terms.txt:legal-review` is not absolute, has no drive and no `..`, sits
 * inside the declared directory and resolves to a regular file — and yet
 * addresses a separate stream whose bytes Git never stored. Measured on the
 * Windows checkout: such a record validated and its hash matched. Colons are
 * refused on every platform, because a path that names one file on Linux and
 * a hidden stream on Windows is not the portable repository reference this
 * field claims to be.
 *
 * It deliberately does NOT reject `..`; `rights.py` bans that separately, so
 * that guard stays independently mutation-provable rather than subsumed. */
export const SNAPSHOT_PATH_PATTERN = "^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*(?![\\s\\S])";

/** The population a grant covers. `WHOLE_SOURCE` means every subject in the
 * declared namespace — a deliberate act of trust in upstream provenance,
 * since the registry holds no population oracle and cannot know that a key
 * does NOT belong to a source. `SUBSET` enumerates the covered keys. The
 * namespace is carried by both kinds, because two upstream catalogues can
 * each number an item `123` and only the namespace tells them apart. */
export const RightsScopeSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("WHOLE_SOURCE"),
    keyNamespace: ScopeIdentifierSchema,
  }).strict(),
  z.object({
    kind: z.literal("SUBSET"),
    keyNamespace: ScopeIdentifierSchema,
    // A SUBSET covering nothing is an ambiguity, not a grant.
    keys: z.array(ScopeIdentifierSchema).nonempty(),
  }).strict(),
]);
export type RightsScope = z.infer<typeof RightsScopeSchema>;

export const RightsDecisionSchema = z.object({
  legalReviewState: LegalReviewStateSchema,
  commercialAllowed: z.boolean(),
  displayAllowed: z.boolean(),
  recognitionProcessingAllowed: z.boolean(),
  trainingAllowed: z.boolean(),
  derivativeAllowed: z.boolean(),
  redistributionAllowed: z.boolean(),
  attributionRequired: z.boolean(),
  shareAlike: z.boolean(),
  noAiRestriction: z.boolean(),
  termsCaptured: z.boolean(),
  termsSnapshotPath: z.string().regex(new RegExp(SNAPSHOT_PATH_PATTERN)).optional(),
  termsSnapshotSha256: Sha256HexSchema.optional(),
  rightsScope: RightsScopeSchema.optional(),
  licenseIdOrTermsVersion: z.string().optional(),
  reviewedAt: IsoTimestampSchema.optional(),
  recheckAt: IsoTimestampSchema.optional(),
  decisionBasis: z.string().optional(),
}).strict().superRefine((rights, ctx) => {
  // The evidence/scope matrix, identical to the `allOf` blocks in
  // rights_decision.schema.json and to validate_rights() in rights.py:
  //
  //   UNREVIEWED + termsCaptured=false  snapshot forbidden, scope forbidden
  //   UNREVIEWED + termsCaptured=true   snapshot required,  scope forbidden
  //   REVIEWED                          snapshot required,  scope required
  //   BLOCKED                           snapshot required,  scope forbidden
  //
  // Capture-before-review (the second row) is deliberate: terms text can
  // honestly exist before anyone has reviewed it. What the matrix requires is
  // that a capture be re-checkable, not that it wait for a review.
  //
  // Only presence/absence is checked here. Whether the recorded sha256 is
  // actually the hash of the file at termsSnapshotPath is a question about
  // bytes on disk, which neither this mirror nor a JSON Schema can answer;
  // rights.py opens the file and compares.
  const state = rights.legalReviewState;

  if (rights.termsCaptured) {
    if (rights.termsSnapshotPath === undefined || rights.termsSnapshotSha256 === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "termsCaptured=true requires both termsSnapshotPath and termsSnapshotSha256 — " +
          "a captured snapshot nobody can re-read is a boolean somebody set, not evidence",
      });
    }
  } else if (rights.termsSnapshotPath !== undefined || rights.termsSnapshotSha256 !== undefined) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "termsSnapshotPath/termsSnapshotSha256 is set but termsCaptured=false",
    });
  }

  if (state === "REVIEWED") {
    if (rights.rightsScope === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "legalReviewState=REVIEWED requires rightsScope — a grant with no stated " +
          "population reads as covering the whole source, which the review behind it " +
          "may never have claimed",
      });
    }
  } else if (rights.rightsScope !== undefined) {
    // BLOCKED grants nothing, so a scope there could only mean a PARTIAL
    // block, which this contract cannot express and must not appear to.
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: `legalReviewState=${state} must not carry rightsScope`,
    });
  }

  if ((state === "REVIEWED" || state === "BLOCKED") && rights.termsCaptured !== true) {
    // BLOCKED is a human legal conclusion, not an absence: a source whose
    // terms could not be reached at all is UNREVIEWED, which is already
    // fail-closed and is already the honest word for "nobody could look".
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: `legalReviewState=${state} requires termsCaptured=true`,
    });
  }
});
export type RightsDecision = z.infer<typeof RightsDecisionSchema>;

export const SourceClassSchema = z.enum([
  "OFFICIAL_MANUFACTURER",
  "OFFICIAL_BIM",
  "WGER",
  "EXERCISEDB",
  "API_NINJAS",
  "DISTRIBUTOR",
  "REFURBISHED_USED",
  "MARKETPLACE_3D",
  "SEARCH_DISCOVERY",
  "OTHER",
]);

export const SourcePrioritySchema = z.enum([
  "P0",
  "P1",
  "P2",
  "ENRICHMENT",
  "STAGING",
  "DISCOVERY_ONLY",
]);

/** `equipment_sources/{sourceId}` — server/admin only. Provenance record,
 * never itself a grant of usage rights; see RightsDecision's own field. */
export const EquipmentSourceSchema = z.object({
  sourceId: SlugSchema,
  providerName: z.string().min(1),
  sourceClass: SourceClassSchema,
  priority: SourcePrioritySchema,
  canonicalUrl: z.string().url(),
  retrievedAt: IsoTimestampSchema,
  termsUrl: z.string().url().nullable(),
  rights: RightsDecisionSchema,
}).strict();
export type EquipmentSource = z.infer<typeof EquipmentSourceSchema>;

// --- brand / product line ------------------------------------------------

/** `equipment_brands/{catalogVersion}--{brandId}`. */
export const EquipmentBrandSchema = z.object({
  schemaVersion: z.literal(1),
  brandId: SlugSchema,
  displayName: z.string().min(1),
  catalogVersion: CatalogVersionSchema,
  provenance: z.array(ProvenanceRefSchema).nonempty(),
}).strict();
export type EquipmentBrand = z.infer<typeof EquipmentBrandSchema>;

/** `equipment_product_lines/{catalogVersion}--{productLineId}`.
 * productLineId convention: `<brandId>-<stable-line-slug>` (§5.5). */
export const ProductLineSchema = z.object({
  schemaVersion: z.literal(1),
  productLineId: SlugSchema,
  brandId: SlugSchema,
  displayName: z.string().min(1),
  catalogVersion: CatalogVersionSchema,
  provenance: z.array(ProvenanceRefSchema).nonempty(),
}).strict();
export type ProductLine = z.infer<typeof ProductLineSchema>;

// --- lifecycle / support status enums ------------------------------------

export const CatalogStatusSchema = z.enum(["ACTIVE", "DISCONTINUED", "LEGACY", "RETIRED"]);
export const CatalogStatusCandidateSchema = z.enum([
  "ACTIVE",
  "DISCONTINUED",
  "LEGACY",
  "RETIRED",
  "UNKNOWN",
]);
export const TextSupportStatusSchema = z.enum(["NONE", "EXPERIMENTAL", "VERIFIED"]);
export const VisionSupportStatusSchema = z.enum([
  "NONE",
  "EXPERIMENTAL",
  "SHADOW",
  "SUPPORTED",
  "VERIFIED",
]);
export const SourceConfidenceSchema = z.enum([
  "OFFICIAL",
  "SECONDARY",
  "USER_VERIFIED",
  "INFERRED",
]);

// --- staged candidate (adapters emit this, never EquipmentModel) --------

/** Adapters/reconciliation staging output. NEVER carries an authoritative
 * `primaryTypeId` — see §5.8: "Adapters NEVER assign authoritative
 * primaryTypeId." `typeHints` are non-binding suggestions only. */
export const StagedEquipmentModelCandidateSchema = z.object({
  schemaVersion: z.literal(1),
  candidateId: z.string().min(1),
  brandId: SlugSchema,
  productLineCandidate: SlugSchema.optional(),
  canonicalNameCandidate: z.string().min(1),
  modelCode: z.string().min(1).optional(),
  skuAliases: z.array(z.string().min(1)),
  aliases: z.array(z.string().min(1)),
  catalogStatusCandidate: CatalogStatusCandidateSchema,
  sourceConfidence: SourceConfidenceSchema,
  provenance: z.array(ProvenanceRefSchema).nonempty(),
  typeHints: z.array(z.string().min(1)),
  sourceStableKey: z.string().min(1),
}).strict();
export type StagedEquipmentModelCandidate = z.infer<
  typeof StagedEquipmentModelCandidateSchema
>;

// --- EquipmentModel (canonical, published) -------------------------------

/** `equipment_models/{catalogVersion}--{modelId}`. `modelId` is a UUID v4
 * assigned once when a candidate is accepted into the canonical catalog
 * (§5.5) and never re-derived from modelCode/SKU/URL/slug.
 *
 * `productLineId`/`generation` are `.optional()` only, deliberately NOT
 * also `.nullable()` (reviewer-found gap, P1.G1 type-design review,
 * 2026-08-22): the only code reading these fields (catalog_repository.ts)
 * already treats `null` and `undefined` identically, so admitting both
 * wire representations bought nothing and instead let two otherwise-equal
 * models serialize to different JSON depending on which representation an
 * adapter happened to write -- a real problem once catalog-version content
 * hashing (P1.G6) needs identical input to hash identically. */
export const EquipmentModelSchema = z
  .object({
    schemaVersion: z.literal(1),
    modelId: UuidV4Schema,
    canonicalSlug: SlugSchema,
    brandId: SlugSchema,
    productLineId: SlugSchema.optional(),
    canonicalName: z.string().min(1),
    modelCode: z.string().min(1),
    skuAliases: z.array(z.string().min(1)),
    primaryTypeId: z.string().min(1),
    supportedTypeIds: z.array(z.string().min(1)).nonempty(),
    generation: z.string().min(1).optional(),
    aliases: z.array(z.string().min(1)),
    catalogStatus: CatalogStatusSchema,
    textSupportStatus: TextSupportStatusSchema,
    visionSupportStatus: VisionSupportStatusSchema,
    sourceConfidence: SourceConfidenceSchema,
    catalogVersion: CatalogVersionSchema,
    provenance: z.array(ProvenanceRefSchema).nonempty(),
  })
  .strict()
  .superRefine((model, ctx) => {
    if (!model.supportedTypeIds.includes(model.primaryTypeId)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `primaryTypeId ${JSON.stringify(model.primaryTypeId)} must be present in supportedTypeIds`,
        path: ["primaryTypeId"],
      });
    }
    const seen = new Set<string>();
    const dupes = new Set<string>();
    for (const t of model.supportedTypeIds) {
      if (seen.has(t)) dupes.add(t);
      seen.add(t);
    }
    if (dupes.size > 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `supportedTypeIds contains duplicate id(s): ${[...dupes].sort().join(", ")}`,
        path: ["supportedTypeIds"],
      });
    }
  });
export type EquipmentModel = z.infer<typeof EquipmentModelSchema>;

// --- external mapping / setup spec / asset -------------------------------

export const ExternalSystemSchema = z.enum(["WGER"]);

/** `equipment_external_mappings/{catalogVersion}--{mappingId}`. An exact
 * model may be linked to an external reference id (e.g. a wger exercise
 * equipment tag) for enrichment only — see §10.9: wger may inform mapping
 * candidates, never settle an exact-model conflict. */
export const ExternalMappingSchema = z.object({
  schemaVersion: z.literal(1),
  mappingId: EntityIdSchema,
  modelId: UuidV4Schema,
  externalSystem: ExternalSystemSchema,
  externalId: z.string().min(1),
  mappingConfidence: z.enum(["MATCHED", "ALIAS_CANDIDATE", "VARIATION_CANDIDATE"]),
  catalogVersion: CatalogVersionSchema,
  provenance: z.array(ProvenanceRefSchema).nonempty(),
}).strict();
export type ExternalMapping = z.infer<typeof ExternalMappingSchema>;

/** `equipment_model_setup_specs/{catalogVersion}--{setupSpecId}`. Physical
 * per-model setup guidance (seat height, pulley ratio, handle position...).
 * P1 only defines the shape; P1.G5 populates one only where staging
 * evidence is actually verified enough to exist (§5.4) — never guessed. */
export const EquipmentModelSetupSpecSchema = z.object({
  schemaVersion: z.literal(1),
  setupSpecId: EntityIdSchema,
  modelId: UuidV4Schema,
  catalogVersion: CatalogVersionSchema,
  adjustments: z.array(
    z.object({
      parameter: z.string().min(1),
      guidance: z.string().min(1),
      unit: z.string().min(1).optional(),
    }),
  ),
  provenance: z.array(ProvenanceRefSchema).nonempty(),
}).strict();
export type EquipmentModelSetupSpec = z.infer<typeof EquipmentModelSetupSpecSchema>;

export const AssetTypeSchema = z.enum(["IMAGE", "DOCUMENT"]);

/** `equipment_assets/{catalogVersion}--{assetId}` — server/admin only. P1
 * defines the shape; P3.G1 owns actual rights-approved acquisition (§5.6 /
 * §11 of the P1 implementation prompt) — no P1 process may set any
 * eligibility-relevant field to true merely because an asset is
 * referenced here. */
export const EquipmentAssetSchema = z.object({
  schemaVersion: z.literal(1),
  assetId: EntityIdSchema,
  modelId: UuidV4Schema.optional(),
  sourceId: SlugSchema,
  assetType: AssetTypeSchema,
  catalogVersion: CatalogVersionSchema,
  provenance: z.array(ProvenanceRefSchema).nonempty(),
}).strict();
export type EquipmentAsset = z.infer<typeof EquipmentAssetSchema>;

// --- RecognitionAuthorityTuple (immutable) --------------------------------

/** Immutable at the schema/rules layer per P1.G1 T4 (AC-M04-corrected: the
 * *runtime* session-mutation test is P2.G3's, once a session runtime
 * exists to test against — see assertAuthorityTupleUnchanged in
 * authority_tuple.ts and the Firestore rules carve-out that makes the
 * whole `equipment_identity_sessions` collection server-only, so there is
 * no client mutation surface for this tuple at all). */
export const RecognitionAuthorityTupleSchema = z
  .object({
    catalogVersion: CatalogVersionSchema,
    ocrVersion: z.string().min(1),
    identityParserVersion: z.string().min(1).optional(),
    textPolicyVersion: z.string().min(1),
    fusionPolicyVersion: z.string().min(1),
    identityPolicyVersion: z.string().min(1),
    embeddingModelVersion: z.string().min(1).optional(),
    embeddingIndexVersion: z.string().min(1).optional(),
    exemplarSetVersion: z.string().min(1).optional(),
    verifierModelVersion: z.string().min(1).optional(),
  })
  .strict();
export type RecognitionAuthorityTuple = Readonly<
  z.infer<typeof RecognitionAuthorityTupleSchema>
>;

// --- catalog version / active pointer / publish job / approval -----------

export const CatalogVersionRecordSchema = z.object({
  schemaVersion: z.literal(1),
  catalogVersion: CatalogVersionSchema,
  contentSha256: Sha256HexSchema,
  componentHashes: z.object({
    p0TypeSnapshotSha256: Sha256HexSchema,
    sourceCaptureManifestSha256: Sha256HexSchema,
    reconciliationReportSha256: Sha256HexSchema,
    diffSha256: Sha256HexSchema,
    approvalSha256: Sha256HexSchema,
  }).strict(),
}).strict();
export type CatalogVersionRecord = z.infer<typeof CatalogVersionRecordSchema>;

export const ReleaseStageSchema = z.enum(["SHADOW_INTERNAL", "PRODUCTION"]);

/** `equipment_catalog_active/current`. */
export const CatalogActivePointerSchema = z.object({
  schemaVersion: z.literal(1),
  activeCatalogVersion: CatalogVersionSchema,
  previousCatalogVersion: CatalogVersionSchema.optional(),
  releaseStage: ReleaseStageSchema,
  approvalSha256: Sha256HexSchema,
  activatedAt: IsoTimestampSchema,
}).strict();
export type CatalogActivePointer = z.infer<typeof CatalogActivePointerSchema>;

export const PublishJobStatusSchema = z.enum([
  "STAGING",
  "NORMALIZE",
  "VALIDATE",
  "DIFF",
  "REVIEW_APPROVAL",
  "BUILD_IMMUTABLE_VERSION",
  "ACTIVATE_POINTER",
  "COMPLETE",
  "FAILED",
]);

/** `equipment_catalog_publish_jobs/{jobId}` — server/admin only. */
export const CatalogPublishJobSchema = z.object({
  schemaVersion: z.literal(1),
  jobId: EntityIdSchema,
  status: PublishJobStatusSchema,
  catalogVersion: CatalogVersionSchema.optional(),
  createdAt: IsoTimestampSchema,
  updatedAt: IsoTimestampSchema,
  error: z.string().optional(),
}).strict();
export type CatalogPublishJob = z.infer<typeof CatalogPublishJobSchema>;

export const ApprovalDecisionSchema = z.enum(["APPROVED", "REJECTED"]);

/** Hash-bound to an exact diff + candidate content — see P1.G6 §11.6. Never
 * self-issued by the pipeline itself. */
export const PublishApprovalSchema = z.object({
  schemaVersion: z.literal(1),
  approvalId: z.string().min(1),
  candidateContentSha256: Sha256HexSchema,
  diffSha256: Sha256HexSchema,
  decision: ApprovalDecisionSchema,
  reviewers: z.array(z.string().min(1)).nonempty(),
  reviewedAt: IsoTimestampSchema,
  notes: z.string().optional(),
}).strict();
export type PublishApproval = z.infer<typeof PublishApprovalSchema>;
