/**
 * MVP1.G3 Step 10A — TEMPORARY, proof-only. NOT part of the permanent
 * surface; delete this file and its `index.ts` export once the proof below
 * is captured.
 *
 * WHY THIS EXISTS
 *
 * GPT-PM's round-4 live-activation review (`core/DECISION_LOG.md`,
 * 2026-08-27): the existing negative proof
 * (`core/evidence/step10a_negative_proof_2026-08-27.json`) is a manually
 * written `gcloud logging write` entry — it proves the alert filter/routing
 * matches, but not that the DEPLOYED `runEnforcementStateCheck` code, under
 * a genuine live failure, actually produces this log line and returns
 * non-OK before the platform deadline. GPT-PM's own suggested mechanism,
 * explicitly preferred over revoking shared IAM: "a temporary proof-only
 * invocation/deployment using the same probe with a deliberately invalid
 * project/API target."
 *
 * This function calls the exact same `runEnforcementStateProbe()` the real
 * scheduled check calls — same code, same logging, same fail-closed
 * contract — pointed at a project id that cannot possibly resolve to a real
 * GCP project, so every section's live API call genuinely fails (403/404
 * from Google's own APIs, not a fabricated response) and the probe's
 * existing DEGRADED/FAILED path runs for real.
 *
 * WHY invoker: "private"
 *
 * This is a temporary HTTPS endpoint whose only job is to run once under
 * this session's own authenticated invocation and then be deleted —
 * `invoker: "private"` (Cloud Run IAM, Gen2 default surface) means only a
 * caller already holding `cloudfunctions.functions.invoke` on this project
 * (this session's own `gcloud` identity) can reach it; it is never public.
 *
 * WHY THE INVALID PROJECT ID IS A CONSTANT, NOT AN INPUT
 *
 * No request body/query parameter is read at all — the target is fixed at
 * deploy time so this endpoint cannot be repurposed into a generic
 * project-scoped probe of anything the caller chooses.
 */
import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { runEnforcementStateProbe } from "./enforcement_state";
import { ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT } from "./monitoring/log_signals";

// Deliberately unresolvable — not a real, not a deleted, not a permission-
// restricted project this service account could ever legitimately reach.
const PROOF_ONLY_INVALID_PROJECT = "fa-d1-proof-only-invalid-project-id";

export const runEnforcementStateCheckProofOnly = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 60,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
    invoker: "private",
  },
  async (_req, res) => {
    const result = await runEnforcementStateProbe({ project: PROOF_ONLY_INVALID_PROJECT });
    if (result.status !== "OK") {
      const unavailableSections = Object.entries(result.sections)
        .filter(([, s]) => s.status === "UNAVAILABLE")
        .map(([name]) => name);
      // Same event name and shape the real scheduled check logs on failure —
      // this is the exact log line the negative-proof alert filter matches,
      // now genuinely produced by a real failure instead of hand-written.
      logger.error(ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT, {
        overallStatus: result.status,
        unavailableSections,
        sections: result.sections,
        proofOnly: true,
      });
      res.status(500).json({ status: result.status, unavailableSections });
      return;
    }
    // Should be unreachable against an invalid project — every section
    // should fail. Logged plainly (not as the failure event) if it somehow
    // doesn't, so the proof attempt itself is never silently misreported.
    logger.warn("enforcement_state_proof_only: probe unexpectedly reported OK", {
      generatedAt: result.generatedAt,
    });
    res.status(200).json({ status: result.status });
  },
);
