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
 * NOT named `FIREBASE_WEB_API_KEY`, despite that being both this probe's
 * original Step 9A working name and the actual product this holds: Firebase's
 * own secret-name validation rejects `FIREBASE_`/`X_GOOGLE_`/`EXT_` as
 * reserved prefixes for a Cloud Functions secret -- discovered live when
 * `firebase functions:secrets:set FIREBASE_WEB_API_KEY` refused to create it.
 * `canary_probe.ts`'s `resolveFirebaseWebApiKey()` was updated in the same
 * change to read `process.env.CANARY_WEB_API_KEY` -- Cloud Functions v2
 * injects a bound secret into `process.env` under its own declared name at
 * runtime, so the name here and the name that function reads must match
 * exactly, which they do.
 */
const CANARY_WEB_API_KEY = defineSecret("CANARY_WEB_API_KEY");

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
 *
 * `concurrency: 1`, alongside `maxInstances: 1` — GPT-PM's review of the
 * first version (`b9d1e9a`) found `maxInstances: 1` alone does not make this
 * single-flight: it bounds the Cloud Run service to ONE instance, but that
 * one instance still defaults to `concurrency: 80` (v2 platform default,
 * confirmed in `firebase-functions/lib/v2/options.d.ts`), meaning up to 80
 * concurrent requests could still be routed into it. Two overlapping
 * invocations (a Scheduler retry, or a manual production proof run — Step
 * 4's own plan — landing while the schedule also fires) would both touch the
 * SAME fixed `_canary/{CANARY_UID}` document, racing each other's
 * write/read/delete/cleanup and producing a false failure. `concurrency: 1`
 * makes the one instance genuinely serialize requests instead.
 */
export const runProductionCanary = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "europe-west1",
    secrets: [CANARY_WEB_API_KEY],
    timeoutSeconds: 60,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
  },
  async () => {
    let result;
    try {
      result = await runCanaryProbe();
    } catch (e) {
      // `runCanaryProbe()` is documented to never throw -- every failure is
      // captured in its returned result. This branch exists only for a
      // genuinely unexpected rejection (a bug, or a synchronous throw before
      // that function's own try/catch is even entered). GPT-PM's review of
      // `b9d1e9a` found that without this catch, such a rejection would
      // reach the v2 onSchedule wrapper's own catch
      // (firebase-functions/lib/v2/providers/scheduler.js:71-73), which logs
      // ONLY `err.message` as a bare string and returns HTTP 500 -- it does
      // NOT emit `PLATFORM_UNHANDLED_ERROR` ("Unhandled error"); that literal
      // message is specific to the onCall wrapper (https.js), a different
      // code path this scheduled function never goes through. Confirmed by
      // reading both wrapper sources directly, not assumed. Without this
      // catch, an invocation that DOES run but rejects unexpectedly would
      // leave the canary-failure alert silently blind to it -- covered by a
      // direct regression test (__tests__/canary_schedule.test.ts). This is
      // distinct from, and does not cover, the Scheduler job never invoking
      // the function at all (disabled/deleted job, delivery failure) -- see
      // alert_definitions.ts's own comment on CANARY_PROBE_FAILURE_FILTER
      // for that stated, separate scope limit.
      logger.error(CANARY_PROBE_FAILED_EVENT, {
        stage: "SCHEDULE_HANDLER",
        failureClass: "UNEXPECTED",
        message: e instanceof Error ? e.message : String(e),
      });
      throw e; // still fail the Scheduler execution
    }
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
