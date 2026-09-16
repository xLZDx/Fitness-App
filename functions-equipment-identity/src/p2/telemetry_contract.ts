/**
 * P2.G5-readiness steps 2 + 3a -- the durable per-scan telemetry record
 * schema, and the mobile-submittable report-request contract. Frozen design:
 * `core/design/p2_g5_readiness/P2_G5_READINESS_SHADOW_TELEMETRY_LIFECYCLE_CONTRACT_2026-09-12.md`
 * (4 revisions, GPT-PM APPROVE round 5).
 *
 * One logical record per `{uid, scanId}` at
 * `users/{uid}/equipment_identity_telemetry/{scanId}` (path helper:
 * `../p1/firestore_paths.ts`'s `userEquipmentIdentityTelemetryDocPath`, already
 * reserved with a client deny-read/deny-write rule in `firestore.rules` since
 * before this gate -- this file adds the schema and writer, not a new
 * collection or a rules change).
 *
 * SCOPE, current as of step 3a (design doc §4.2b/§7): the server's own
 * terminal-decision write (`index.ts`'s `equipmentIdentityResolveFromText`)
 * writes ONLY `SERVER_TERMINAL`. The NEW `equipmentIdentityRecordTelemetry`
 * callable (this step) is what a mobile client uses to report
 * `LOCAL_FAILURE`/`REQUEST_FAILURE`/timing, through
 * `EquipmentIdentityTelemetryReportRequestSchema` below -- see
 * `telemetry_repository.ts`'s §6 merge-rule implementation for how a
 * mobile-authoritative fragment and a server-authoritative terminal write
 * reconcile. `NOT_ATTEMPTED`, `ENRICHMENT_DISABLED` (schema-reserved but
 * deliberately never sent over the network -- design doc §4.2b) and
 * `genericOutcome` remain unpopulated; that is step 3b's scope, not this
 * one's, and is disclosed rather than silently omitted.
 */
import { z } from "zod";
import { EquipmentIdentityResponseSchema } from "./contract";
import { isFirestoreDocIdSegment } from "../p1/firestore_paths";

export const TELEMETRY_SCHEMA_VERSION = 1 as const;

/** Every real path a scan's telemetry can be in -- design doc §4.
 * `SERVER_TERMINAL`/`CONFLICT` (server-authoritative) and
 * `LOCAL_FAILURE`/`REQUEST_FAILURE` (mobile-authoritative, via
 * `EquipmentIdentityTelemetryReportRequestSchema` below) are all written as
 * of step 3a. `NOT_ATTEMPTED`/`ENRICHMENT_DISABLED` remain schema-reserved,
 * never written -- step 3b's scope (design doc §4.2b/§7). */
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

/** Confirmed against `equipment_identity_providers.dart`'s real OCR/parser
 * exception branches (design doc §4.2, step 3a recon) -- all four occur
 * strictly BEFORE any network call, which is what separates this enum from
 * `RequestFailureReasonSchema` below. */
export const LocalFailureReasonSchema = z.enum([
  "missingImagePath",
  "missingStructuredRecognizer",
  "ocrException",
  "parserException",
]);
export type LocalFailureReason = z.infer<typeof LocalFailureReasonSchema>;

/** Confirmed against `cloud_equipment_identity_service.dart`'s real throw
 * surface (design doc §4.2a, step 3a recon): `networkUnreachable` /
 * `timeout` / `appCheckOrAuth` / `rateLimited` / `backendError` /
 * `unknownClientError` bucket a `FirebaseFunctionsException` thrown by the
 * `httpsCallable(...).call(...)` await; `malformedReply` is the ONE
 * post-reply case -- a `FormatException` from `EquipmentIdentity.fromJson`
 * after the callable already returned successfully. Safe specifically
 * because of §6 rule 5's enrichment-not-conflict behavior: the server has
 * already committed `SERVER_TERMINAL` by the time this fires, so this
 * fragment only ever lands as a `clientObservedFailures` entry, never as a
 * competing state-defining write. */
export const RequestFailureReasonSchema = z.enum([
  "networkUnreachable",
  "timeout",
  "appCheckOrAuth",
  "rateLimited",
  "backendError",
  "unknownClientError",
  "malformedReply",
]);
export type RequestFailureReason = z.infer<typeof RequestFailureReasonSchema>;

/** The two mobile-authoritative non-terminal states -- the only states a
 * `clientObservedFailures` entry or a mobile report request can ever carry
 * (design doc §6 rules 3/5a). */
const MobileAuthoritativeStateSchema = z.enum(["LOCAL_FAILURE", "REQUEST_FAILURE"]);

/** RFC3339 UTC instant -- zod's default `.datetime()` requires the literal
 * `Z` suffix, matching design doc §5.4's mandate (Dart's own
 * `toIso8601String()` omits `Z` for a non-UTC value, so this rejects a
 * caller that forgot `.toUtc()` rather than silently accepting local time). */
const utcIsoDateTime = () => z.string().datetime({ message: "must be an RFC3339 UTC timestamp (Z suffix)" });

/** design doc §5.4: the ONLY ordering rule is `scanEndedAt >= scanStartedAt`
 * -- no upper bound (a previously proposed 15-minute latency ceiling was
 * removed in round 4 of this gate's design review: `scanId` is reused
 * across a retry with no time boundary of its own, so a long-running
 * legitimate retry must not be rejected). Compared via `Date#getTime()`,
 * not lexical string order, since `.datetime()` allows variable fractional
 * precision and two equal-precision strings are not guaranteed. */
function assertScanTimingOrder(
  data: { scanStartedAt: string; scanEndedAt: string },
  ctx: z.RefinementCtx,
): void {
  if (new Date(data.scanEndedAt).getTime() < new Date(data.scanStartedAt).getTime()) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "scanEndedAt must not be before scanStartedAt",
      path: ["scanEndedAt"],
    });
  }
}

const scanIdField = () =>
  z
    .string()
    .min(1)
    .refine(isFirestoreDocIdSegment, { message: "scanId must be a valid Firestore document-ID segment" });

/**
 * The mobile-submittable request contract for the NEW
 * `equipmentIdentityRecordTelemetry` callable (design doc §7/plan step 3):
 * exactly 3 shapes. `SERVER_TERMINAL`/`CONFLICT`/`ENRICHMENT_DISABLED` are
 * all rejected outright at this boundary -- a mobile client has no
 * authority to assert any of them (§6 rules 3/4/5).
 */
export const LocalFailureReportSchema = z
  .object({
    scanId: scanIdField(),
    state: z.literal("LOCAL_FAILURE"),
    reason: LocalFailureReasonSchema,
    scanStartedAt: utcIsoDateTime(),
    scanEndedAt: utcIsoDateTime(),
  })
  .strict()
  .superRefine(assertScanTimingOrder);

export const RequestFailureReportSchema = z
  .object({
    scanId: scanIdField(),
    state: z.literal("REQUEST_FAILURE"),
    reason: RequestFailureReasonSchema,
    scanStartedAt: utcIsoDateTime(),
    scanEndedAt: utcIsoDateTime(),
  })
  .strict()
  .superRefine(assertScanTimingOrder);

/** The success-path fragment (design doc §6 rule 5b): timing only, no
 * `state` at all -- sent from the provider's OWN success path, since the
 * server already committed `SERVER_TERMINAL` before the client can act on a
 * successful reply. */
export const ScanTimingReportSchema = z
  .object({
    scanId: scanIdField(),
    scanStartedAt: utcIsoDateTime(),
    scanEndedAt: utcIsoDateTime(),
  })
  .strict()
  .superRefine(assertScanTimingOrder);

export const EquipmentIdentityTelemetryReportRequestSchema = z.union([
  LocalFailureReportSchema,
  RequestFailureReportSchema,
  ScanTimingReportSchema,
]);
export type EquipmentIdentityTelemetryReportRequest = z.infer<
  typeof EquipmentIdentityTelemetryReportRequestSchema
>;

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

/** design doc §3/§6 rules 3 and 5a: audit-only trail of every
 * mobile-authoritative failure fragment this record has ever received,
 * REGARDLESS of whether it also became (or was superseded as) the record's
 * own `state`. Excluded from every §5 metric formula except the new §5.3
 * third term -- see that section for why a `SERVER_TERMINAL` record with a
 * non-empty `clientObservedFailures` still counts as incomplete evidence. */
const ClientObservedFailureEntrySchema = z.object({
  state: MobileAuthoritativeStateSchema,
  reason: z.union([LocalFailureReasonSchema, RequestFailureReasonSchema]),
  recordedAt: z.string().min(1),
  /** Not part of design doc §3's own abbreviated shape note, added the same
   * way `ConflictingWriteEntrySchema` already carries it: §6 rule 5a
   * requires "a repeat of the SAME clientObservedFailures entry (identical
   * fingerprint) is a no-op" -- {state, reason} alone cannot tell a genuine
   * retry of one occurrence apart from two independent occurrences sharing
   * a reason, so the fingerprint that already makes rule 2/4 idempotent is
   * stored per-entry here too, mirroring `conflictingWrites`. */
  payloadFingerprint: z.string().min(1),
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
    clientObservedFailures: z.array(ClientObservedFailureEntrySchema).optional(),
  })
  .strict();
export type EquipmentIdentityTelemetryRecord = z.infer<typeof EquipmentIdentityTelemetryRecordSchema>;
