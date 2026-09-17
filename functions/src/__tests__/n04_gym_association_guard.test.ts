/**
 * N-04's own residual, made mechanical: `core/decisions/N-04.md` records the
 * operator's deferral (leave the gym-association code path dormant) as valid
 * PRECISELY because `gyms/` has no writer today, so `reportEquipment`'s lack
 * of any caller-to-gym association check has no live consequence yet.
 * `core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md`'s own text says that
 * trigger is inert unless something is keyed to it — "every webhook test
 * primes the gym document itself, so the branch is green today and stays
 * identically green the day a real writer ships."
 *
 * This is that something. It does not test today's behaviour (already
 * covered by `index.test.ts`'s `reportEquipment` suite) — it tests the
 * CONDITIONAL the deferral actually rests on:
 *
 *     gyms/ gains a real writer in production code  =>  reportEquipment's
 *     webhook dispatch must verify the caller is associated with that gym
 *
 * Exercised against three inputs, same shape as the N07/F025 dormant-trap
 * tests: the real source tree (today, vacuously true because there is no
 * writer), a synthetic tree with a writer and no association check (must
 * fail), and a synthetic tree with a writer AND an association check (must
 * pass). Only the first says anything about today; the other two are what
 * make this a guard rather than decoration -- a check that is vacuous
 * against every real input it has ever seen is not a check.
 */
import * as fs from "fs";
import * as path from "path";

/** Files this guard reads for real, so a rename doesn't silently blind it. */
const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
const FUNCTIONS_SRC = path.join(REPO_ROOT, "functions", "src");

function readAllSourceFiles(dir: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "__tests__" || entry.name === "node_modules") continue;
      Object.assign(out, readAllSourceFiles(full));
    } else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      out[full] = fs.readFileSync(full, "utf8");
    }
  }
  return out;
}

/** Strips `//` and `/* *\/` comments so prose mentioning the pattern (like
 * this file's own docstring, or index.ts's N-04 comments) is not mistaken
 * for the pattern actually appearing in executable code. Same fix the N07
 * Dart guard already needed once, applied here for the same reason. */
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/.*$/gm, "");
}

/**
 * Does any production source file WRITE to the `gyms/{id}` collection?
 * `.doc(\`gyms/...\`)` (or `.collection("gyms").doc(...)`) followed by
 * `.set(`, `.update(`, or `.create(` on that same reference. A `.get()`
 * (reportEquipment's own read of the gym's webhook URL) does not count --
 * only a WRITER activates the association-check requirement.
 */
function hasGymsWriterInProduction(sources: Record<string, string>): boolean {
  const writePattern =
    /\bgyms\/[^`'"]*[`'"]\s*\)\s*\.\s*(set|update|create)\s*\(/;
  const collectionWritePattern =
    /collection\s*\(\s*["'`]gyms["'`]\s*\)[^;]*\.\s*(set|update|create)\s*\(/;
  for (const src of Object.values(sources)) {
    const code = stripComments(src);
    if (writePattern.test(code) || collectionWritePattern.test(code)) {
      return true;
    }
  }
  return false;
}

/**
 * Does `reportEquipment`'s own source contain a caller-to-gym association
 * check before dispatching the webhook? Naming is necessarily a guess about
 * what a future implementation would call this -- same limitation the N07
 * guard's collection-name list already accepts, for the same reason: a
 * guard that requires guessing perfectly is still better than one that
 * checks nothing. Broadened here rather than pinned to one exact name.
 */
function reportEquipmentChecksAssociation(indexSource: string): boolean {
  const code = stripComments(indexSource);
  const reportEquipmentStart = code.indexOf("export const reportEquipment");
  if (reportEquipmentStart === -1) {
    // If the callable itself cannot be found, this guard cannot say
    // anything meaningful -- fail loudly rather than silently passing.
    throw new Error(
      "n04_gym_association_guard: could not locate `export const reportEquipment` " +
        "in functions/src/index.ts -- update this guard's anchor string.",
    );
  }
  const body = code.slice(reportEquipmentStart);
  return /(assert|verify|require|check)[A-Za-z]*Gym(Membership|Association|Access)\s*\(|isMemberOfGym\s*\(/.test(
    body,
  );
}

describe("N-04 gym-association guard (RESIDUAL[N-04-gym-association])", () => {
  it("today: gyms/ has no writer in production source, so the deferral is still valid", () => {
    const sources = readAllSourceFiles(FUNCTIONS_SRC);
    expect(Object.keys(sources).length).toBeGreaterThan(0);
    expect(hasGymsWriterInProduction(sources)).toBe(false);
  });

  it("today: reportEquipment has no association check either -- consistent with no writer existing", () => {
    const indexSource = fs.readFileSync(
      path.join(FUNCTIONS_SRC, "index.ts"),
      "utf8",
    );
    expect(reportEquipmentChecksAssociation(indexSource)).toBe(false);
  });

  it("synthetic: a gyms/ writer with NO association check must fail the guard", () => {
    const wiredSources = {
      "onboard_gym.ts":
        'db.doc(`gyms/${gymId}`).set({ maintenanceWebhookUrl: url });',
    };
    expect(hasGymsWriterInProduction(wiredSources)).toBe(true);

    const unguardedReportEquipment = `
      export const reportEquipment = onCall({}, async (request) => {
        const gymId = request.data.gymId;
        const gymSnap = await db.doc(\`gyms/\${gymId}\`).get();
        // no association check between request.auth.uid and gymId
      });
    `;
    expect(reportEquipmentChecksAssociation(unguardedReportEquipment)).toBe(false);
  });

  it("synthetic: a gyms/ writer WITH an association check passes the guard's own detector", () => {
    const guardedReportEquipment = `
      export const reportEquipment = onCall({}, async (request) => {
        const gymId = request.data.gymId;
        await assertGymMembership(request.auth.uid, gymId);
        const gymSnap = await db.doc(\`gyms/\${gymId}\`).get();
      });
    `;
    expect(reportEquipmentChecksAssociation(guardedReportEquipment)).toBe(true);
  });

  it("comments mentioning the pattern do not fool the detector (N07's own lesson, applied here)", () => {
    const commentOnly = {
      "readme_notes.ts":
        "// TODO: one day we might db.doc(`gyms/${id}`).set({...}) here",
    };
    expect(hasGymsWriterInProduction(commentOnly)).toBe(false);
  });
});
