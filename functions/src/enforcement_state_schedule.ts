/**
 * MVP1.G3 Step 10A — the Cloud Scheduler trigger for `enforcement_state.ts`.
 * Same one-export-nothing-else shape as `canary_schedule.ts`, wiring an
 * already-built, deliberately trigger-less check into a real Scheduler job.
 * The correct deploy command is `firebase deploy --only
 * functions:runEnforcementStateCheck` — never an unrestricted deploy, same
 * constraint Step 9B's own GO carried (the four AI Gateway callables must
 * stay undeployed).
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { runEnforcementStateProbe } from "./enforcement_state";
import { ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT } from "./monitoring/log_signals";

/**
 * Every 6 hours: this checks slow-moving configuration state (deployed
 * functions, rules, App Check, Auth config), not a fast-moving user-facing
 * path the way the 30-minute canary is — a regression here (someone
 * disabling App Check enforcement, a rules release reverting) is real but
 * does not need 30-minute detection to be useful, and a coarser cadence
 * keeps this check's own API-call volume negligible. `region` matches every
 * other function in this backend (`europe-west1`).
 *
 * `concurrency: 1` + `maxInstances: 1`, same reasoning as the canary: two
 * overlapping runs would just double the read traffic for no benefit (this
 * check has no shared mutable state to race, unlike the canary's fixed
 * Firestore document, but there is no reason to allow concurrent runs
 * either).
 */
export const runEnforcementStateCheck = onSchedule(
  {
    schedule: "every 6 hours",
    region: "europe-west1",
    timeoutSeconds: 60,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
  },
  async () => {
    let result;
    try {
      result = await runEnforcementStateProbe();
    } catch (e) {
      // `runEnforcementStateProbe()` is documented to never throw -- every
      // failure is captured in its returned result (status FAILED/DEGRADED).
      // This branch exists only for a genuinely unexpected rejection, same
      // backstop `canary_schedule.ts` carries for the same documented reason
      // (`onSchedule`'s own wrapper never logs "Unhandled error" -- that
      // literal is `onCall`-specific, confirmed by reading both wrapper
      // sources directly, not assumed).
      logger.error(ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT, {
        stage: "SCHEDULE_HANDLER",
        failureClass: "UNEXPECTED",
        message: e instanceof Error ? e.message : String(e),
      });
      throw e;
    }
    if (result.status !== "OK") {
      // Thrown (not just logged) so this also surfaces as a genuine Cloud
      // Run/Functions execution failure, on top of the structured log line
      // the alert policy actually keys on -- same pattern as the canary.
      const unavailableSections = Object.entries(result.sections)
        .filter(([, s]) => s.status === "UNAVAILABLE")
        .map(([name]) => name);
      logger.error(ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT, {
        overallStatus: result.status,
        unavailableSections,
        sections: result.sections,
      });
      throw new Error(
        `enforcement state check ${result.status}: ${unavailableSections.join(", ")}`,
      );
    }
    // `result.sections` is safe to log in full: every section's `data` was
    // individually constructed to be safe (Identity Toolkit's own strict
    // allowlist in particular never carries the raw response through -- see
    // `enforcement_state.ts`'s module header). GPT-PM's remediation-round
    // finding: logging only counts here proved the read succeeded but threw
    // away the one thing a human/alert would actually need to act on --
    // which release, which functions, which App Check services are (not)
    // enforced.
    logger.info("enforcement_state_schedule: check succeeded", {
      generatedAt: result.generatedAt,
      sections: result.sections,
    });
  },
);
