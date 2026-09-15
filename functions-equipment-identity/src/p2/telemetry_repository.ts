/**
 * P2.G5-readiness step 2 -- the idempotent-merge writer for
 * `users/{uid}/equipment_identity_telemetry/{scanId}` (design doc §6).
 * See `telemetry_contract.ts`'s own header for this step's scope limit:
 * this file writes ONLY the `SERVER_TERMINAL` state, from the server's own
 * terminal identity decision. It does not (yet) implement the cross-source
 * merge with a future mobile-originated enrichment write -- see that same
 * header comment for why that is deliberately deferred to step 3.
 */
import { createHash } from "crypto";
import * as logger from "firebase-functions/logger";
import type { EquipmentIdentityResponse } from "./contract";
import {
  TELEMETRY_SCHEMA_VERSION,
  EquipmentIdentityTelemetryRecordSchema,
  type EquipmentIdentityTelemetryRecord,
  type TelemetryState,
} from "./telemetry_contract";
import { userEquipmentIdentityTelemetryDocPath } from "../p1/firestore_paths";
import { db } from "./firestore_admin";
import { stripUndefinedFields } from "./session_repository";

/** Deterministic recursive key-sort so two semantically identical objects
 * built via different code paths (e.g. a conditional spread that includes a
 * key in one branch and omits it in another) still hash identically --
 * `orchestrator.ts`'s own `computeRequestFingerprint` skips this because it
 * always builds its literal object in one fixed shape; this writer's input
 * (`EquipmentIdentityResponse`) is built across MANY different branches in
 * `orchestrator.ts`, so relying on incidental key order would be fragile. */
function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value as Record<string, unknown>)
        .sort()
        .map((key) => [key, canonicalize((value as Record<string, unknown>)[key])]),
    );
  }
  return value;
}

function computeServerTerminalFingerprint(identityOutcome: EquipmentIdentityResponse): string {
  return createHash("sha256")
    .update(JSON.stringify(canonicalize({ state: "SERVER_TERMINAL" as TelemetryState, identityOutcome })))
    .digest("hex");
}

/** States a `SERVER_TERMINAL` write may legitimately supersede without it
 * being a conflict (design doc §6 rule 3) -- a genuine progression from "we
 * couldn't tell yet" to "now we can", e.g. a scan that locally failed once
 * and succeeded on a same-`scanId` retry. Not yet reachable in practice
 * (nothing writes these states today -- step 3's job), listed explicitly so
 * this function's own logic is correct the day they start arriving instead
 * of needing a second look then. */
const NON_TERMINAL_STATES: ReadonlySet<TelemetryState> = new Set([
  "NOT_ATTEMPTED",
  "ENRICHMENT_DISABLED",
  "LOCAL_FAILURE",
  "REQUEST_FAILURE",
]);

/**
 * Records the server's own terminal identity decision for `{uid, scanId}`,
 * idempotently. Called from exactly one place (`index.ts`, after
 * `resolveEquipmentIdentityFromText` returns) so every real response path
 * -- the 4 genuine identity outcomes AND the 8 infrastructure/lifecycle
 * outcomes (design doc §4.3.1/§4.3.2) -- is recorded, never silently
 * dropped; the §5 metric formulas decide separately which of those are
 * `eligible` versus `incomplete_evidence`, over this same complete data.
 *
 * `uid` must come from `request.auth.uid` at the call site -- never
 * client-supplied -- exactly like the identity response itself
 * (`index.ts:70`).
 *
 * Failures here are logged and swallowed, never thrown: a telemetry write
 * failing must not turn a real identity response the user is waiting on
 * into a 500 (design doc's own UX-fail-open-but-evidence-visible
 * distinction, step 1's silent-failure-hunter review item). The dropped
 * write itself is not silently lost from the metric picture either -- a
 * scan whose telemetry never arrives simply has no record at all, and
 * step 5's report counts distinct scanIds it CAN observe; making that
 * count-of-what-is-missing itself visible needs cross-referencing against
 * `equipment_identity_sessions` (which every admitted scan already writes,
 * successfully or not) and is a report-side concern for step 5, not this
 * writer's.
 */
export async function recordServerTerminalTelemetry(
  uid: string,
  scanId: string,
  identityOutcome: EquipmentIdentityResponse,
): Promise<void> {
  try {
    const ref = db().doc(userEquipmentIdentityTelemetryDocPath(uid, scanId));
    const cleanOutcome = stripUndefinedFields(identityOutcome);
    const payloadFingerprint = computeServerTerminalFingerprint(cleanOutcome);

    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const nowIso = new Date().toISOString();

      if (!snap.exists) {
        const fresh: EquipmentIdentityTelemetryRecord = {
          schemaVersion: TELEMETRY_SCHEMA_VERSION,
          uid,
          scanId,
          state: "SERVER_TERMINAL",
          identityOutcome: cleanOutcome,
          payloadFingerprint,
          createdAt: nowIso,
          updatedAt: nowIso,
        };
        EquipmentIdentityTelemetryRecordSchema.parse(fresh);
        tx.set(ref, fresh);
        return;
      }

      const existing = snap.data() as EquipmentIdentityTelemetryRecord;

      // Rule 2: identical replay is a no-op except for `updatedAt` -- makes
      // a retried delivery of this exact call safe to repeat any number of
      // times (this writer is not itself retried today, but the rule is
      // the same one step 3's outbox will depend on).
      if (existing.payloadFingerprint === payloadFingerprint) {
        tx.update(ref, { updatedAt: nowIso });
        return;
      }

      // Rule 3: a legitimate transition from a non-terminal state.
      if (NON_TERMINAL_STATES.has(existing.state)) {
        const updated: EquipmentIdentityTelemetryRecord = {
          schemaVersion: TELEMETRY_SCHEMA_VERSION,
          uid,
          scanId,
          state: "SERVER_TERMINAL",
          identityOutcome: cleanOutcome,
          payloadFingerprint,
          createdAt: existing.createdAt,
          updatedAt: nowIso,
          priorStates: [...(existing.priorStates ?? []), { state: existing.state, recordedAt: nowIso }],
        };
        EquipmentIdentityTelemetryRecordSchema.parse(updated);
        tx.set(ref, updated);
        return;
      }

      // Rule 4: already terminal (SERVER_TERMINAL or CONFLICT) with a
      // DIFFERING fingerprint -- never overwrite, surface as CONFLICT
      // instead. Two genuinely different SERVER_TERMINAL outcomes for the
      // same scanId should not happen given `session_repository.ts`'s own
      // per-(uid, scanId) immutability guarantee -- this branch exists so a
      // future bug in that guarantee, or in this writer's own call site,
      // fails loudly (a CONFLICT record excluded from every §5 metric
      // except `incomplete_evidence_count`) rather than silently picking a
      // winner.
      logger.warn("equipment_identity_telemetry_conflict", {
        uid,
        scanId,
        existingState: existing.state,
        existingFingerprint: existing.payloadFingerprint,
        incomingFingerprint: payloadFingerprint,
      });
      const conflicted: EquipmentIdentityTelemetryRecord = {
        ...existing,
        state: "CONFLICT",
        updatedAt: nowIso,
        conflictingWrites: [
          ...(existing.conflictingWrites ?? []),
          { payloadFingerprint, recordedAt: nowIso, attempted: cleanOutcome },
        ],
      };
      EquipmentIdentityTelemetryRecordSchema.parse(conflicted);
      tx.set(ref, conflicted);
    });
  } catch (e) {
    logger.error("equipment_identity_telemetry_write_failed", {
      uid,
      scanId,
      err: e instanceof Error ? (e.stack ?? e.message) : String(e),
    });
  }
}
