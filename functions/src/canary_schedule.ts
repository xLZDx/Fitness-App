/**
 * MVP1.G3 Step 9B — the real Cloud Scheduler trigger for the Step 9A canary
 * probe (`canary_probe.ts`). That file was deliberately built with no
 * trigger attached to it ("Step 9B wires this into a Cloud Scheduler job and
 * an actual alert; this file does not create either" — `canary_probe.ts`'s
 * own module header). This file is that wiring, added only once GPT-PM's
 * Step 9B production-activation GO existed (`core/DECISION_LOG.md`,
 * 2026-08-27 correction entry).
 *
 * One `onSchedule` export, nothing else. GPT-PM's binding constraint on this
 * activation: "deploy only the exact Step 9B scheduled function — never an
 * unrestricted Functions deploy." The four AI Gateway callables
 * (`ai_coach_advice.ts` and siblings) are already exported from `index.ts`
 * but deliberately undeployed; a blanket `firebase deploy --only functions`
 * would deploy them too. The only correct deploy command for this change is
 * `firebase deploy --only functions:runProductionCanary`.
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { runCanaryProbe } from "./canary_probe";
import { CANARY_PROBE_FAILED_EVENT } from "./monitoring/log_signals";

/**
 * Same name `resolveFirebaseWebApiKey()` in `canary_probe.ts` already reads
 * via `process.env.FIREBASE_WEB_API_KEY` — Cloud Functions v2 injects a
 * bound secret into `process.env` under its own declared name at runtime, so
 * binding this param here is sufficient; `canary_probe.ts` itself needs no
 * change; it already reads the exact env var name this secret injects.
 */
const FIREBASE_WEB_API_KEY = defineSecret("FIREBASE_WEB_API_KEY");

/**
 * Every 30 minutes: frequent enough to catch a real Auth/Firestore Rules
 * regression well within a working day, infrequent enough that the
 * Scheduler invocation and the probe's own Firestore/Auth calls stay
 * negligible cost for this project's traffic. No product requirement
 * dictates a tighter cadence today; revisit against real incident-response
 * experience, not a guess, the same discipline `scaling.ts`'s profiles
 * document for their own numeric choices.
 *
 * `region` matches `scaling.ts`'s `REGION` constant (not exported from that
 * module, so restated literally here) — every other function in this
 * backend runs in `europe-west1`, and the canary's own Firestore/Auth calls
 * must originate from the same region the rest of the fleet does to mean
 * anything as a regression signal.
 */
export const runProductionCanary = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "europe-west1",
    secrets: [FIREBASE_WEB_API_KEY],
    timeoutSeconds: 60,
    memory: "256MiB",
    maxInstances: 1,
  },
  async () => {
    const result = await runCanaryProbe();
    if (!result.success) {
      // Thrown (not just logged) so this also surfaces as a genuine Cloud
      // Run/Functions execution failure, on top of the structured log line
      // below that the canary-failure alert policy actually keys on.
      logger.error(CANARY_PROBE_FAILED_EVENT, {
        stage: result.stage,
        failureClass: result.failureClass,
        cleanupSucceeded: result.cleanupSucceeded,
      });
      throw new Error(
        `canary probe failed at stage ${result.stage ?? "unknown"} ` +
          `(${result.failureClass ?? "UNKNOWN"})`,
      );
    }
    logger.info("canary_schedule: production canary probe succeeded", {
      latencyMs: result.latencyMs,
      cleanupSucceeded: result.cleanupSucceeded,
    });
  },
);
