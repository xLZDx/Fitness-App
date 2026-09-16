/**
 * P2-ACCESS-1 -- semantic, operation-specific verification of EVERY
 * `clientAccess` cell declared in scripts/ci/data_lifecycle_policy.json,
 * run against the real Firestore emulator.
 *
 * check_data_access_policy.js (run separately, outside jest) proves the
 * policy file is INTERNALLY consistent with firestore.rules' own text --
 * it never opens a Firestore connection. This file is the other half: it
 * proves each declared `access` value is what the rules ACTUALLY grant at
 * runtime, and -- the part a static text check cannot do at all -- that
 * every CONDITIONAL cell's `conditionalRefs` test genuinely exercises the
 * declared operation with a real payload, not just a same-collection test
 * that happens to exist.
 *
 * THIS SUITE RE-VERIFIES EVERY DECLARED PATH+OPERATION CELL ON EVERY CI
 * RUN. There is no incremental/changed-only mode here, and there must
 * never be one -- GPT-PM's round-1 MAJOR-3 finding (round-3 DoD item):
 * a partial-coverage optimization is exactly the kind of silent drift this
 * whole gate exists to prevent one axis further up the stack. A future
 * change to this file that adds a "skip unchanged collections" shortcut
 * is a regression against this gate's own Definition of Done, not an
 * optimization.
 *
 * Two parts:
 *   1. Seven hand-written, single-operation tests -- one per CONDITIONAL
 *      cell (_canary's four verbs, debug_sessions' create, profile's
 *      create/update). Searched firestore_rules.test.ts first per this
 *      gate's own plan ("only write a new emulator test if no existing
 *      one already proves the specific operation") -- none of the
 *      existing tests isolate a SINGLE operation with both a clean
 *      assertSucceeds and an adversarial assertFails in one block (the
 *      existing canary test bundles read+create+delete together; the
 *      existing profile re-attack tests are assertFails-only). Writing
 *      fresh, single-operation pairs here keeps this gate's own
 *      operation-specific proof mechanically checkable by
 *      check_data_access_policy.js's `findTestBody`/SDK-call-regex
 *      matcher, rather than relying on fragile text-archaeology against
 *      tests that were written for a different, narrative purpose.
 *   2. A generic, DATA-DRIVEN sweep, generated directly from the policy
 *      JSON, covering every NONE/OWNER/AUTHENTICATED/PUBLIC cell (every
 *      CONDITIONAL cell is covered by part 1 instead, deliberately
 *      excluded from the generic sweep -- a generic payload cannot
 *      exercise a field-conditioned rule meaningfully).
 *
 * Own project id ("demo-fitness-access-policy"), separate from
 * firestore_rules.test.ts's "demo-fitness-rules" and e2e's
 * "demo-fitness-e2e" -- `initializeTestEnvironment` supports multiple
 * independent projects against the same emulator instance, and sharing a
 * project would mean one suite's seeded fixtures leaking into the other's
 * assertions.
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { resolve } from "path";
import { doc, getDoc, setDoc, deleteDoc, updateDoc } from "firebase/firestore";

type AccessValue = "NONE" | "OWNER" | "AUTHENTICATED" | "PUBLIC" | "CONDITIONAL";
interface ClientAccessEntry {
  path: string;
  access: Record<"read" | "create" | "update" | "delete", AccessValue>;
  conditionalRefs?: Record<string, { testFile: string; testName: string; operation: string }>;
}
interface Policy {
  collections: Record<string, { clientAccess?: ClientAccessEntry[] }>;
}

let env: RulesTestEnvironment;

const ALICE = "alice";
const BOB = "bob";
const CANARY_UID = "canary-probe-uid";

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-fitness-access-policy",
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const asBob = () => env.authenticatedContext(BOB).firestore();
const asCanary = () => env.authenticatedContext(CANARY_UID, { canary: true }).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

async function seedAsAdmin(fsPath: string, data: Record<string, unknown>): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), fsPath), data);
  });
}

// ---------------------------------------------------------------------------
// Part 1: dedicated, single-operation CONDITIONAL cell proofs.
// ---------------------------------------------------------------------------
describe("CONDITIONAL cells", () => {
  describe("_canary", () => {
    test("CONDITIONAL cell _canary/read: the canary identity can read its own document", async () => {
      await seedAsAdmin(`_canary/${CANARY_UID}`, { probe: true });
      await assertSucceeds(getDoc(doc(asCanary(), `_canary/${CANARY_UID}`)));
      await assertFails(getDoc(doc(asAlice(), `_canary/${CANARY_UID}`)));
    });

    test("CONDITIONAL cell _canary/create: the canary identity can create its own document", async () => {
      await assertSucceeds(setDoc(doc(asCanary(), `_canary/${CANARY_UID}`), { probe: true }));
      await assertFails(setDoc(doc(asAlice(), `_canary/${ALICE}`), { probe: true }));
    });

    test("CONDITIONAL cell _canary/update: the canary identity can update its own document", async () => {
      await seedAsAdmin(`_canary/${CANARY_UID}`, { probe: true });
      await assertSucceeds(updateDoc(doc(asCanary(), `_canary/${CANARY_UID}`), { probe: false }));
      await seedAsAdmin(`_canary/other-canary`, { probe: true });
      // Cross-identity: a real canary token, wrong document -- the clause
      // that proves uid-equality is genuinely enforced, not merely the claim.
      await assertFails(updateDoc(doc(asCanary(), `_canary/other-canary`), { probe: false }));
    });

    test("CONDITIONAL cell _canary/delete: the canary identity can delete its own document", async () => {
      await seedAsAdmin(`_canary/${CANARY_UID}`, { probe: true });
      await assertSucceeds(deleteDoc(doc(asCanary(), `_canary/${CANARY_UID}`)));
      await seedAsAdmin(`_canary/${ALICE}`, { probe: true });
      await assertFails(deleteDoc(doc(asAlice(), `_canary/${ALICE}`)));
    });
  });

  describe("debug_sessions", () => {
    test("CONDITIONAL cell debug_sessions/create: a correctly-shaped, self-stamped session is accepted", async () => {
      await assertSucceeds(
        setDoc(doc(asAlice(), "debug_sessions/s1"), {
          identity: { sha: "abc" },
          droppedCount: 0,
          events: [{ m: "hi" }],
          uid: ALICE,
        }),
      );
      // Same shape, wrong uid stamp -- the field-ownership clause this cell
      // exists to prove, not a generic "malformed document" failure.
      await assertFails(
        setDoc(doc(asAlice(), "debug_sessions/s2"), {
          identity: { sha: "abc" },
          droppedCount: 0,
          events: [{ m: "hi" }],
          uid: BOB,
        }),
      );
    });
  });

  describe("profile", () => {
    const strippedHealth = () => ({
      conditions: [],
      allergies: [],
      medications: [],
      injuries: [],
      physicalLimitations: [],
      recentSurgeries: [],
      bloodPressure: null,
      otherConcerns: null,
      screening: {},
      flags: { restrictions: [], bloodPressure: null, surgery: null, clinicianAdvice: null },
    });

    test("CONDITIONAL cell profile/create: a stripped health block is accepted, a real one is refused", async () => {
      await assertSucceeds(
        setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { health: strippedHealth() }),
      );
      await assertFails(
        setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: { ...strippedHealth(), conditions: ["type 2 diabetes"] },
        }),
      );
      // Lifestyle bypass (item 6, was MINOR): profile's real write condition
      // (firestore.rules:188-197) is health-strip AND lifestyle.smoking is
      // null AND lifestyle.alcohol is null -- three conjoined clauses. The
      // two cases above only ever vary `health`, so a regression in either
      // lifestyle-null clause specifically (with the health-strip left
      // intact) would pass this cell's proof by coincidence, not because
      // it was actually exercised. These assert failure with health
      // correctly stripped but a non-null lifestyle value present.
      await assertFails(
        setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: strippedHealth(),
          lifestyle: { smoking: "sometimes" },
        }),
      );
      await assertFails(
        setDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: strippedHealth(),
          lifestyle: { alcohol: "sometimes" },
        }),
      );
    });

    test("CONDITIONAL cell profile/update: a stripped-health patch is accepted, a real one is refused", async () => {
      await seedAsAdmin(`users/${ALICE}/profile/main`, { goal: "strength" });
      await assertSucceeds(
        updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { health: strippedHealth() }),
      );
      await assertFails(
        updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: { ...strippedHealth(), conditions: ["type 2 diabetes"] },
        }),
      );
      // Lifestyle bypass (item 6) -- same rationale as profile/create above,
      // exercised on update too since the write condition is shared by
      // create/update alike (one `allow write` statement).
      await assertFails(
        updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: strippedHealth(),
          lifestyle: { smoking: "sometimes" },
        }),
      );
      await assertFails(
        updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), {
          health: strippedHealth(),
          lifestyle: { alcohol: "sometimes" },
        }),
      );
    });
  });
});

// ---------------------------------------------------------------------------
// Part 2: generic, data-driven sweep over every non-CONDITIONAL cell.
// ---------------------------------------------------------------------------
const policy: Policy = JSON.parse(
  readFileSync(resolve(__dirname, "../../../scripts/ci/data_lifecycle_policy.json"), "utf8"),
);

/** `/users/{uid}/workout_logs/{docId}` -> `users/alice/workout_logs/fixtureDoc`. */
function concretePath(templatePath: string, ownerUid: string): string {
  return templatePath
    .replace(/^\//, "")
    .replace(/\{uid\}/g, ownerUid)
    .replace(/\{[^}]+\}/g, "fixtureDoc");
}

const OPS = ["read", "create", "update", "delete"] as const;

describe("generic policy sweep (every declared NONE/OWNER/AUTHENTICATED/PUBLIC cell)", () => {
  for (const [collName, entry] of Object.entries(policy.collections)) {
    for (const ca of entry.clientAccess ?? []) {
      const isUserSub = /^\/users\/\{uid\}\//.test(ca.path);
      const ownerPath = concretePath(ca.path, ALICE);

      for (const op of OPS) {
        const declared = ca.access[op];
        if (declared === "CONDITIONAL") continue; // covered by Part 1 above.

        const label = `${collName} ${ca.path} / ${op} = ${declared}`;

        // A distinct, guaranteed-nonexistent document id for a negative
        // CREATE assertion (item 7, was MAJOR -- Row 24 gate remediation
        // round 2): Firestore's rules engine decides create-vs-update by
        // whether the document ALREADY EXISTS (`resource == null`), never
        // by which client SDK method was called. The positive assertion in
        // the OWNER/AUTHENTICATED branches below creates `ownerPath` for
        // real; reusing that same path for the immediately-following
        // negative principal's `setDoc` would therefore have Firestore
        // evaluate it as an UPDATE, not a create -- the negative case would
        // silently stop proving anything about `create` access the moment
        // create/update ever diverged for a collection. `negPath` is never
        // seeded, so it stays genuinely nonexistent for the negative call.
        const negPath = ownerPath.replace(/fixtureDoc$/, "fixtureDocNeg");

        test(label, async () => {
          const seedIfNeeded = async () => {
            if (op === "update" || op === "delete") {
              await seedAsAdmin(ownerPath, { probe: true });
            }
          };
          // Typed as `Promise<unknown>` explicitly: the four branches return
          // different concrete promise types (`getDoc` -> DocumentSnapshot,
          // the rest -> void), and assertSucceeds/assertFails's overloads
          // cannot unify a union of those on their own -- inference picked
          // the first overload and rejected every other branch. `path`
          // defaults to `ownerPath` -- callers that need a DIFFERENT,
          // guaranteed-nonexistent document (the create-negative case) pass
          // `negPath` explicitly.
          const call = (db: ReturnType<typeof asAlice>, path: string = ownerPath): Promise<unknown> => {
            const ref = doc(db, path);
            switch (op) {
              case "read":
                return getDoc(ref);
              case "create":
                return setDoc(ref, { probe: true });
              case "update":
                return updateDoc(ref, { probe: false });
              case "delete":
                return deleteDoc(ref);
            }
          };

          /** Proves `negPath` is genuinely nonexistent right before a
           * create-negative assertion uses it -- a guard against a future
           * regression silently reintroducing the reused-fixture bug this
           * item fixes (e.g. someone "simplifying" `negPath` back to
           * `ownerPath`): if the fixture were reused, this would find an
           * existing document and fail LOUDLY here, rather than the
           * negative assertion silently exercising update semantics again
           * with no test failure to show for it. */
          const assertNegPathIsFreshForCreate = async (path: string): Promise<void> => {
            await env.withSecurityRulesDisabled(async (ctx) => {
              const snap = await getDoc(doc(ctx.firestore(), path));
              if (snap.exists()) {
                throw new Error(
                  `${label}: negative-create fixture path "${path}" already exists -- this would make the ` +
                  "negative assertion exercise Firestore's update semantics, not create, since Firestore " +
                  "decides create-vs-update by whether the document already exists, never by which SDK " +
                  "method was called.",
                );
              }
            });
          };

          switch (declared) {
            case "OWNER": {
              // Owner succeeds; a different signed-in user on the SAME
              // path fails. Only meaningful for a user-scoped path --
              // every real OWNER declaration in this policy is one, but
              // this guards against a future top-level OWNER mistakenly
              // added with nothing to compare identity against.
              if (!isUserSub) {
                throw new Error(
                  `${label}: declared OWNER on a non-/users/{uid}/ path -- this generic sweep has no ` +
                  "second identity to test ownership against; declare a per-path fixture manually.",
                );
              }
              await seedIfNeeded();
              await assertSucceeds(call(asAlice()));
              if (op === "create") {
                // See `negPath`'s own doc comment above -- Bob's negative
                // create must target a document that genuinely does not
                // exist yet, not the one Alice's positive call just created.
                await assertNegPathIsFreshForCreate(negPath);
                await assertFails(call(asBob(), negPath));
              } else {
                // The positive call may have consumed the fixture (delete)
                // or left it stable (update, read) -- re-seed before the
                // negative check so it starts from a known, stable state
                // regardless of which op ran.
                await seedAsAdmin(ownerPath, { probe: true });
                await assertFails(call(asBob()));
              }
              break;
            }
            case "AUTHENTICATED": {
              await seedIfNeeded();
              await assertSucceeds(call(asAlice()));
              if (op === "create") {
                // Same reused-fixture hazard as OWNER/create above -- the
                // signed-out negative call must target a fresh document.
                await assertNegPathIsFreshForCreate(negPath);
                await assertFails(call(signedOut(), negPath));
              } else {
                await assertFails(call(signedOut()));
              }
              break;
            }
            case "PUBLIC": {
              await seedIfNeeded();
              await assertSucceeds(call(signedOut()));
              break;
            }
            case "NONE": {
              await seedIfNeeded();
              await assertFails(call(asAlice()));
              if (op === "read") await assertFails(call(signedOut()));
              break;
            }
            default:
              throw new Error(`${label}: unrecognised access value ${declared as string}`);
          }
        });
      }
    }
  }
});
