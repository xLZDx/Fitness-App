/**
 * P2.G5-readiness step 2 -- the durable per-scan telemetry record schema.
 * Frozen design: `core/design/p2_g5_readiness/P2_G5_READINESS_SHADOW_TELEMETRY_LIFECYCLE_CONTRACT_2026-09-12.md`.
 *
 * One logical record per `{uid, scanId}` at
 * `users/{uid}/equipment_identity_telemetry/{scanId}` (path helper:
 * `../p1/firestore_paths.ts`'s `userEquipmentIdentityTelemetryDocPath`, already
 * reserved with a client deny-read/deny-write rule in `firestore.rules` since
 * before this gate -- this file adds the schema and writer, not a new
 * collection or a rules change).
 *
 * SCOPE NOTE, stated rather than silently assumed (design doc §7): this
 * step (server-side ingestion) writes ONLY the `SERVER_TERMINAL` state, from
 * the one place the server itself reaches a terminal identity decision
 * (`index.ts`, wrapping `resolveEquipmentIdentityFromText`). The other five
 * states (`NOT_ATTEMPTED`, `ENRICHMENT_DISABLED`, `LOCAL_FAILURE`,
 * `REQUEST_FAILURE`, `CONFLICT`) and the `genericOutcome`/`scanStartedAt`/
 * `scanEndedAt`/`localFailureReason`/`requestFailureReason` fields are
 * defined here for forward compatibility (so the schema does not need a
 * breaking migration when step 3 lands) but are NOT populated by this
 * step's own writer. Step 3 (mobile durable outbox) is what actually reports
 * them, through a delivery path that does not exist yet. Deliberately not
 * building that cross-source merge logic now: a server-only `SERVER_TERMINAL`
 * write and a mobile-only enrichment write of the SAME record are not
 * "conflicting" in the sense `payloadFingerprint` comparison means below --
 * they describe different aspects of the same scan -- and inventing that
 * merge rule before step 3's real request shape exists would be guessing.
 * `recordEquipmentIdentityTelemetry`'s own doc comment states this same
 * scope limit at the call site.
 */
import { z } from "zod";
import { EquipmentIdentityResponseSchema } from "./contract";

export const TELEMETRY_SCHEMA_VERSION = 1 as const;

/** Every real path a scan's telemetry can be in -- design doc §4. Only
 * `SERVER_TERMINAL` and `CONFLICT` are written by this step's own code;
 * the rest exist so step 3 does not require a schema migration to use them. */
export const TelemetryStateSchema = z.enum([
  "NOT_ATTEMPTED",
  "ENRICHMENT_DISABLED",
  "LOCAL_FAILURE",
  "REQUEST_FAILURE",
  "SERVER_TERMINAL",
  "CONFLICT",
]);
export type TelemetryState = z.infer<typeof TelemetryStateSchema>;

/** Direct mirror of `mobile/lib/features/visual_equipment/data/scan_outcome.dart`'s
 * `ScanOutcome` enum (design doc §4.1) -- not yet written by any server
 * code; reserved for step 3's mobile-originated enrichment write. */
export const GenericScanOutcomeSchema = z.enum([
  "confident",
  "alternatives",
  "unknown",
  "noEquipment",
  "timeout",
  "failed",
]);
export type GenericScanOutcome = z.infer<typeof GenericScanOutcomeSchema>;

/** PROVISIONAL (design doc §4.2/§7): the plan's own step-1 wording, not yet
 * independently verified against `equipment_identity_providers.dart`'s real
 * branches. Step 3 must confirm or correct this set before it ships a real
 * `LOCAL_FAILURE` write using it. */
export const LocalFailureReasonSchema = z.enum([
  "missingImagePath",
  "missingStructuredRecognizer",
  "ocrException",
  "parserException",
]);
export type LocalFailureReason = z.infer<typeof LocalFailureReasonSchema>;

/** PROVISIONAL (design doc §7): not yet verified against
 * `cloud_equipment_identity_service.dart`'s real failure surface. Step 3
 * must confirm or correct this set before it ships a real `REQUEST_FAILURE`
 * write using it. */
export const RequestFailureReasonSchema = z.enum([
  "networkUnreachable",
  "timeout",
  "unknownClientError",
]);
export type RequestFailureReason = z.infer<typeof RequestFailureReasonSchema>;

/** Internal audit trail entries -- never read by the §5 metric formulas,
 * kept only so a human/debug read of a record can see what it used to be. */
const PriorStateEntrySchema = z.object({ state: TelemetryStateSchema, recordedAt: z.string().min(1) });
const ConflictingWriteEntrySchema = z.object({
  payloadFingerprint: z.string().min(1),
  recordedAt: z.string().min(1),
  // The conflicting write's own record shape, opaque here (it failed
  // exactly BECAUSE it did not match what full validation would expect for
  // a fresh write against an already-terminal doc) -- stored as `unknown`,
  // never re-validated against this same schema.
  attempted: z.unknown(),
});

export const EquipmentIdentityTelemetryRecordSchema = z
  .object({
    schemaVersion: z.literal(TELEMETRY_SCHEMA_VERSION),
    /** SERVER-AUTHORITATIVE ONLY. Never accepted from client input -- set
     * exclusively from the authenticated callable's own `request.auth.uid`,
     * exactly as `index.ts:70` already does for the identity response
     * itself. Also the record's own Firestore path segment; stored again
     * here so a `collectionGroup('equipment_identity_telemetry')` read (the
     * step-5 report script's natural query shape) does not have to parse a
     * document path to recover it. */
    uid: z.string().min(1),
    /** Also the record's own docId (design doc §3). */
    scanId: z.string().min(1),
    state: TelemetryStateSchema,
    /** Present iff `state === "SERVER_TERMINAL"`. The FULL server response
     * (design doc §4.3: "storing the full record ... is what lets a later,
     * differently-shaped report be computed from the same telemetry
     * without a second data-collection pass"), reusing
     * `EquipmentIdentityResponseSchema` verbatim rather than a hand-rolled
     * subset, so this can never drift from what the callable actually
     * returns to the client for the exact same request. */
    identityOutcome: EquipmentIdentityResponseSchema.optional(),
    /** Present iff `state === "NOT_ATTEMPTED"` or `"SERVER_TERMINAL"` (the
     * generic pipeline runs regardless of whether identity was attempted) --
     * not yet written by any server code, see this file's header. */
    genericOutcome: GenericScanOutcomeSchema.optional(),
    /** Present iff `state === "LOCAL_FAILURE"`. */
    localFailureReason: LocalFailureReasonSchema.optional(),
    /** Present iff `state === "REQUEST_FAILURE"`. */
    requestFailureReason: RequestFailureReasonSchema.optional(),
    /** Mobile-side wall-clock scan boundaries for latency (design doc
     * §5.4) -- deliberately NOT server round-trip timing. Not yet written
     * by any server code. */
    scanStartedAt: z.string().optional(),
    scanEndedAt: z.string().optional(),
    /** The idempotency key for §6's merge rule -- sha256 over this write's
     * own outcome-affecting fields, mirroring `orchestrator.ts`'s own
     * `computeRequestFingerprint` pattern. */
    payloadFingerprint: z.string().min(1),
    createdAt: z.string().min(1),
    updatedAt: z.string().min(1),
    priorStates: z.array(PriorStateEntrySchema).optional(),
    conflictingWrites: z.array(ConflictingWriteEntrySchema).optional(),
  })
  .strict();
export type EquipmentIdentityTelemetryRecord = z.infer<typeof EquipmentIdentityTelemetryRecordSchema>;
