/**
 * P2.G5-readiness steps 2 + 3a -- the idempotent-merge writer for
 * `users/{uid}/equipment_identity_telemetry/{scanId}` (design doc §6).
 * `recordServerTerminalTelemetry` is the server's own terminal-decision
 * writer (step 2, unchanged in shape); `recordMobileTelemetryFragment` is
 * the NEW mobile-originated writer (step 3a) backing the
 * `equipmentIdentityRecordTelemetry` callable -- see that function's own
 * doc comment for rules 1/2/3/5's mobile-side implementation.
 */
import { createHash } from "crypto";
import * as logger from "firebase-functions/logger";
import type { EquipmentIdentityResponse } from "./contract";
import {
  TELEMETRY_SCHEMA_VERSION,
  EquipmentIdentityTelemetryRecordSchema,
  type EquipmentIdentityTelemetryRecord,
  type TelemetryState,
  type EquipmentIdentityTelemetryReportRequest,
  type LocalFailureReason,
  type RequestFailureReason,
} from "./telemetry_contract";
import { userEquipmentIdentityTelemetryDocPath } from "../p1/firestore_paths";
import { db } from "./firestore_admin";
import { stripUndefinedFields } from "./session_repository";

/** Deterministic sha256 over a mobile report's own canonicalized fields --
 * the idempotency key for rules 2/3/5a below, same construction as
 * `computeServerTerminalFingerprint`. */
function computeMobileFragmentFingerprint(report: EquipmentIdentityTelemetryReportRequest): string {
  return createHash("sha256").update(JSON.stringify(canonicalize(report))).digest("hex");
}

/** A `ScanTimingReportSchema` fragment carries no `state` at all -- see
 * `telemetry_contract.ts`'s own header for why that is the ONE shape of the
 * 3-member discriminated union that is structurally state-less. */
function isStateDefiningReport(
  report: EquipmentIdentityTelemetryReportRequest,
): report is Extract<EquipmentIdentityTelemetryReportRequest, { state: "LOCAL_FAILURE" | "REQUEST_FAILURE" }> {
  return "state" in report;
}

/** The {reason} half of an existing mobile-authoritative record's own
 * current state, for carrying into `clientObservedFailures`/`priorStates`
 * when that record is about to be replaced (design doc §6 rule 3). Callers
 * only invoke this after `isMobileNonTerminalState(existing.state)`, so
 * `existing.state` is always `LOCAL_FAILURE` or `REQUEST_FAILURE` here. */
function extractMobileReason(existing: EquipmentIdentityTelemetryRecord): LocalFailureReason | RequestFailureReason {
  return existing.state === "LOCAL_FAILURE"
    ? (existing.localFailureReason as LocalFailureReason)
    : (existing.requestFailureReason as RequestFailureReason);
}

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
 * being a conflict (design doc §6 rule 3, verbatim: "still LOCAL_FAILURE/
 * REQUEST_FAILURE") -- a genuine progression from "we couldn't tell yet" to
 * "now we can", e.g. a scan that locally failed once and succeeded on a
 * same-`scanId` retry. Deliberately NOT `NOT_ATTEMPTED`/`ENRICHMENT_DISABLED`
 * (GPT-PM MAJOR, retrospective review of commit afca346, 2026-09-15): the
 * frozen contract never names those two, and silently allowing them here
 * would turn a logically contradictory pair -- e.g. "enrichment explicitly
 * disabled" followed by a SERVER_TERMINAL for the same logical scan -- into
 * an ordinary overwrite instead of a visible CONFLICT. Not yet reachable in
 * practice (nothing writes ANY of the four states today -- step 3's job),
 * listed explicitly so this function's own logic is correct the day they
 * start arriving instead of needing a second look then. */
const NON_TERMINAL_STATES: ReadonlySet<TelemetryState> = new Set(["LOCAL_FAILURE", "REQUEST_FAILURE"]);

/** Type-guard wrapper around `NON_TERMINAL_STATES.has` -- `Set#has` alone
 * does not narrow TypeScript's type of its argument, which both call sites
 * below need (to assign `existing.state` into a `clientObservedFailures`
 * entry, whose own `state` field is `LOCAL_FAILURE | REQUEST_FAILURE`, not
 * the full 6-value `TelemetryState`). */
function isMobileNonTerminalState(state: TelemetryState): state is "LOCAL_FAILURE" | "REQUEST_FAILURE" {
  return NON_TERMINAL_STATES.has(state);
}

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
      // Revised for step 3a (design doc §6 rule 3, round 3): the REPLACED
      // fragment's full {state, reason, recordedAt} -- not just its state
      // name -- also goes into `clientObservedFailures`, symmetric with
      // rule 5a's reverse arrival order (SERVER_TERMINAL first, a mobile
      // fragment arriving late).
      if (isMobileNonTerminalState(existing.state)) {
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
          clientObservedFailures: [
            ...(existing.clientObservedFailures ?? []),
            {
              state: existing.state,
              reason: extractMobileReason(existing),
              recordedAt: nowIso,
              payloadFingerprint: existing.payloadFingerprint,
            },
          ],
        };
        EquipmentIdentityTelemetryRecordSchema.parse(updated);
        tx.set(ref, updated);
        return;
      }

      // Rule 4: either already terminal (SERVER_TERMINAL or CONFLICT), or in
      // a state the narrowed Rule 3 set above no longer treats as a
      // legitimate transition -- with a DIFFERING fingerprint. Never
      // overwrite, surface as CONFLICT instead. Two genuinely different
      // SERVER_TERMINAL outcomes for the same scanId should not happen given
      // `session_repository.ts`'s own per-(uid, scanId) immutability
      // guarantee -- this branch exists so a future bug in that guarantee,
      // or in this writer's own call site, fails loudly (a CONFLICT record
      // excluded from every §5 metric except `incomplete_evidence_count`)
      // rather than silently picking a winner.
      //
      // GPT-PM MAJOR (retrospective review of commit afca346, 2026-09-15):
      // a REPEATED delivery of the SAME conflicting payload must also be a
      // no-op past the first time -- §6 promises "safe to replay any number
      // of times" for ANY payload this writer has already durably recorded,
      // not only the winning one. Checking only `existing.payloadFingerprint`
      // (which never changes once a conflict is recorded) let every retry of
      // an already-known conflict append a fresh `conflictingWrites` entry
      // forever. Check the full known-fingerprint set first.
      const alreadyKnownConflict = (existing.conflictingWrites ?? []).some(
        (c) => c.payloadFingerprint === payloadFingerprint,
      );
      if (alreadyKnownConflict) {
        tx.update(ref, { updatedAt: nowIso });
        return;
      }

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

/**
 * Records a mobile-originated telemetry fragment (design doc §6, step 3a) --
 * the counterpart to `recordServerTerminalTelemetry` above, backing the
 * `equipmentIdentityRecordTelemetry` callable. `report` is already
 * contract-valid (`EquipmentIdentityTelemetryReportRequestSchema` parsed it
 * at the call site) so it can only ever be one of the 3 mobile-authoritative
 * shapes -- never `SERVER_TERMINAL`/`CONFLICT` (design doc §6's "authority
 * split", enforced at the contract boundary, not by convention here).
 *
 * `uid` must come from `request.auth.uid` at the call site, exactly like
 * `recordServerTerminalTelemetry`. Failures are logged and swallowed, never
 * thrown, for the identical reason that function documents: a telemetry
 * write failing must never turn a real callable response into a 500.
 *
 * Rules implemented (design doc §6, all renumbered from that section):
 * 1. No record exists -- create fresh FROM a state-defining fragment. A
 *    timing-only fragment with no existing record has nothing to create a
 *    record WITH (no state to assign) -- structurally near-impossible given
 *    `identity_handler.ts` always awaits the server's own SERVER_TERMINAL
 *    write before a client can ever see the success reply that triggers a
 *    timing-only send, but handled explicitly (dropped, logged) rather than
 *    inventing a state outside this step's scope.
 * 2. Incoming fingerprint matches the record's own current fingerprint --
 *    no-op. Never matches while `existing` is server-authoritative (its
 *    fingerprint lives in `computeServerTerminalFingerprint`'s own hash
 *    namespace, never producible by a mobile report), which is exactly why
 *    that case correctly falls through to rule 5 instead.
 * 3. Existing is mobile-authoritative non-terminal, fingerprint differs --
 *    legitimate transition/overwrite. The replaced fragment's full
 *    `{state, reason, recordedAt}` joins `clientObservedFailures`;  its bare
 *    `{state, recordedAt}` joins `priorStates` too, mirroring
 *    `recordServerTerminalTelemetry`'s own rule 3.
 * 4. (Structurally unreachable from this function -- see the authority-split
 *    note above; rule 4 only ever fires from `recordServerTerminalTelemetry`.)
 * 5. Existing is already terminal -- never a conflict. 5a: a state-defining
 *    fragment joins `clientObservedFailures` only (idempotent per stored
 *    `payloadFingerprint`), touching nothing else. 5b: a timing-only
 *    fragment fills `scanStartedAt`/`scanEndedAt` only if not already set,
 *    first-write-wins per field.
 */
export async function recordMobileTelemetryFragment(
  uid: string,
  report: EquipmentIdentityTelemetryReportRequest,
): Promise<void> {
  const scanId = report.scanId;
  try {
    const ref = db().doc(userEquipmentIdentityTelemetryDocPath(uid, scanId));
    const payloadFingerprint = computeMobileFragmentFingerprint(report);

    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const nowIso = new Date().toISOString();

      if (!snap.exists) {
        // Rule 1.
        if (!isStateDefiningReport(report)) {
          logger.warn("equipment_identity_telemetry_timing_fragment_orphaned", { uid, scanId });
          return;
        }
        const fresh: EquipmentIdentityTelemetryRecord = stripUndefinedFields({
          schemaVersion: TELEMETRY_SCHEMA_VERSION,
          uid,
          scanId,
          state: report.state,
          localFailureReason: report.state === "LOCAL_FAILURE" ? report.reason : undefined,
          requestFailureReason: report.state === "REQUEST_FAILURE" ? report.reason : undefined,
          scanStartedAt: report.scanStartedAt,
          scanEndedAt: report.scanEndedAt,
          payloadFingerprint,
          createdAt: nowIso,
          updatedAt: nowIso,
        } as EquipmentIdentityTelemetryRecord);
        EquipmentIdentityTelemetryRecordSchema.parse(fresh);
        tx.set(ref, fresh);
        return;
      }

      const existing = snap.data() as EquipmentIdentityTelemetryRecord;

      // Rule 2.
      if (existing.payloadFingerprint === payloadFingerprint) {
        tx.update(ref, { updatedAt: nowIso });
        return;
      }

      if (isMobileNonTerminalState(existing.state)) {
        // Rule 3.
        // GPT-PM MAJOR (round 1, implementation review of commit 39dcfd8):
        // once a fragment has been superseded and archived into
        // `clientObservedFailures`, a DELAYED duplicate delivery of that
        // exact same (now-archived) fragment no longer matches the
        // record's own top-level `payloadFingerprint` (rule 2's check), so
        // without this guard it would fall through here and be treated as
        // a brand-new legitimate transition -- rolling the current state
        // BACK to the stale one and re-archiving the real current state on
        // top of it. Reports are independent fire-and-forget sends with no
        // delivery-order guarantee (this provider's own doc comment), so a
        // delayed duplicate of an already-superseded send is a real
        // scenario, not a hypothetical one. Same idempotency posture as
        // rule 5a's own `alreadyKnown` check just below, and the same
        // class of repeat-delivery gap `recordServerTerminalTelemetry`'s
        // own rule 4 already had to close for conflicting writes.
        const alreadyArchived = (existing.clientObservedFailures ?? []).some(
          (f) => f.payloadFingerprint === payloadFingerprint,
        );
        if (alreadyArchived) {
          tx.update(ref, { updatedAt: nowIso });
          return;
        }

        const replacedEntry = {
          state: existing.state,
          reason: extractMobileReason(existing),
          recordedAt: nowIso,
          payloadFingerprint: existing.payloadFingerprint,
        };
        const priorStates = [...(existing.priorStates ?? []), { state: existing.state, recordedAt: nowIso }];
        const clientObservedFailures = [...(existing.clientObservedFailures ?? []), replacedEntry];

        if (isStateDefiningReport(report)) {
          const updated: EquipmentIdentityTelemetryRecord = stripUndefinedFields({
            schemaVersion: TELEMETRY_SCHEMA_VERSION,
            uid,
            scanId,
            state: report.state,
            localFailureReason: report.state === "LOCAL_FAILURE" ? report.reason : undefined,
            requestFailureReason: report.state === "REQUEST_FAILURE" ? report.reason : undefined,
            // First-write-wins, same as rule 5b -- a differing fingerprint
            // here comes from `state`/`reason` changing, not necessarily a
            // fresh scanStartedAt (a retry reuses the SAME scanId, design
            // doc §5.4).
            scanStartedAt: existing.scanStartedAt ?? report.scanStartedAt,
            scanEndedAt: report.scanEndedAt,
            payloadFingerprint,
            createdAt: existing.createdAt,
            updatedAt: nowIso,
            priorStates,
            clientObservedFailures,
          } as EquipmentIdentityTelemetryRecord);
          EquipmentIdentityTelemetryRecordSchema.parse(updated);
          tx.set(ref, updated);
          return;
        }

        // A timing-only fragment while still mobile-authoritative
        // non-terminal -- structurally near-unreachable today (see this
        // function's own header), kept explicit rather than assumed
        // impossible. Enriches metadata only, first-write-wins.
        if (existing.scanStartedAt !== undefined && existing.scanEndedAt !== undefined) {
          tx.update(ref, { updatedAt: nowIso });
          return;
        }
        tx.update(
          ref,
          stripUndefinedFields({
            updatedAt: nowIso,
            scanStartedAt: existing.scanStartedAt ?? report.scanStartedAt,
            scanEndedAt: existing.scanEndedAt ?? report.scanEndedAt,
          }),
        );
        return;
      }

      // Rule 5: existing is already terminal (SERVER_TERMINAL/CONFLICT).
      // Never a conflict for a mobile-authoritative fragment -- rule 4 is
      // structurally unreachable from this function (see header comment).
      if (isStateDefiningReport(report)) {
        // Rule 5a. GPT-PM MAJOR (round 1, implementation review of commit
        // 39dcfd8): the design doc's own rule 5 preamble -- "enrich only
        // the metadata fields the server-side write could never have
        // supplied -- scanStartedAt/scanEndedAt, filled in only if not
        // already set" -- applies to BOTH mobile-fragment shapes that reach
        // this rule, not only the timing-only one (5b). The first cut of
        // this function only filled them in 5b, silently discarding a real
        // failure fragment's own timestamps even though the client
        // supplied them. First-write-wins here too, same as 5b.
        const timingFill: Partial<Pick<EquipmentIdentityTelemetryRecord, "scanStartedAt" | "scanEndedAt">> = {};
        if (existing.scanStartedAt === undefined) timingFill.scanStartedAt = report.scanStartedAt;
        if (existing.scanEndedAt === undefined) timingFill.scanEndedAt = report.scanEndedAt;

        // Idempotent per stored fingerprint, same mechanism as
        // `conflictingWrites`' own repeat-delivery check above.
        const alreadyKnown = (existing.clientObservedFailures ?? []).some(
          (f) => f.payloadFingerprint === payloadFingerprint,
        );
        if (alreadyKnown) {
          tx.update(ref, { updatedAt: nowIso, ...timingFill });
          return;
        }
        tx.update(ref, {
          updatedAt: nowIso,
          ...timingFill,
          clientObservedFailures: [
            ...(existing.clientObservedFailures ?? []),
            { state: report.state, reason: report.reason, recordedAt: nowIso, payloadFingerprint },
          ],
        });
        return;
      }

      // Rule 5b: timing-only enrichment, first-write-wins per field.
      if (existing.scanStartedAt !== undefined && existing.scanEndedAt !== undefined) {
        tx.update(ref, { updatedAt: nowIso });
        return;
      }
      tx.update(
        ref,
        stripUndefinedFields({
          updatedAt: nowIso,
          scanStartedAt: existing.scanStartedAt ?? report.scanStartedAt,
          scanEndedAt: existing.scanEndedAt ?? report.scanEndedAt,
        }),
      );
    });
  } catch (e) {
    logger.error("equipment_identity_telemetry_mobile_write_failed", {
      uid,
      scanId,
      err: e instanceof Error ? (e.stack ?? e.message) : String(e),
    });
  }
}
