# MVP1.G4 Step 1 — Vertex AI model revalidation

Per GPT-PM's binding exit criteria for MVP1.G4, criterion 1: "Revalidate the configured
Vertex model and region against current supported models. If `gemini-3-flash-preview`
must be replaced, treat the model change as a reviewed behavioral change, not a string
substitution. Prove one bounded direct backend smoke test before deployment."

## Why not trust the docs alone

`functions/src/ai_gateway.ts`'s own comment (written 2026-08-26, during G1) says
`gemini-3-flash-preview` "is a DEPRECATED model on Vertex AI (Google's own docs point
migrators at `gemini-3.5-flash`)." Before either keeping or changing that, checked
current web documentation first -- and it was **internally contradictory**:

- `ai.google.dev/gemini-api/docs/deprecations` (Gemini Developer API, not Vertex):
  reported `gemini-3-flash-preview` shutdown date **2025-12-17**, replacement
  `gemini-3.6-flash`.
- `docs.cloud.google.com/vertex-ai/generative-ai/docs/release-notes` (Vertex AI, the
  actual backend this codebase uses -- `ai_gateway.ts` sets `vertexai: true`): reported
  `gemini-3-flash-preview` as **announced in public preview on 2025-12-17** (the SAME
  date the other page called a shutdown), "no mention of retirement," and named
  `gemini-2.5-flash` as the current stable recommendation -- itself later contradicted by
  search results showing Gemini 2.5 Flash's own retirement date (2026-10-16).
- Search results separately surfaced `gemini-3.7-flash` (newest, no shutdown date
  announced) and `gemini-3.1-flash-lite`/`gemini-3.1-flash-image` as more recent entries
  neither doc page mentioned.

Given a same-day date used as both an "announcement" and a "shutdown" across two official
Google pages, and models appearing in one source but not another, none of this was
treated as reliable enough for a production decision on its own (CLAUDE.md §3 --
evidence over inference; a citation is not proof by itself).

## Live proof: called the real Vertex AI endpoint for this real project

Not simulated -- `gcloud auth print-access-token` (operator's own credentialed account,
already used throughout this session) + a direct REST call to
`https://aiplatform.googleapis.com/v1/projects/fitness-app-korostelev/locations/global/publishers/google/models/{MODEL}:generateContent`,
the exact project/location `ai_gateway.ts` itself uses (`LOCATION = "global"` by default).
Tested 5 candidates with a minimal prompt ("Reply with exactly one word: OK",
`maxOutputTokens: 16`, no `thinkingConfig` override):

| Model | Result |
|---|---|
| `gemini-3-flash-preview` (current) | **200 OK**, real text returned (`"OK"`) |
| `gemini-3.5-flash` | 200 OK, `finishReason: MAX_TOKENS` (no visible text within the 16-token cap) |
| `gemini-3.6-flash` | 200 OK, `finishReason: MAX_TOKENS` (same) |
| `gemini-3.7-flash` | 200 OK, some text returned (`":"`) then `MAX_TOKENS` |
| `gemini-2.5-flash` | 200 OK, `finishReason: MAX_TOKENS` (same) |

**Finding: `gemini-3-flash-preview` is NOT dead.** It answered a real live call against
the real production project today, contradicting the "deprecated"/shutdown framing taken
at face value. All 4 candidate replacements are also live and callable.

**Caveat on the "no visible text" results, stated honestly rather than overclaimed:** the
16-token cap was chosen to make this smoke test cheap, not to characterize real product
behavior. Every non-preview model spent its entire tiny budget on `thoughtsTokenCount`
(default "thinking" reasoning tokens) before emitting any visible answer text --
`gemini-3-flash-preview` did not, at least not enough to prevent an "OK" from coming
through. This is a REAL, observed difference in default token consumption across model
generations, but this specific test cannot say whether it holds at each real callable's
actual `maxOutputTokens` (512 for `aiCoachAdvice`; smaller structured-JSON budgets for the
other three) or whether the three callables that already set
`thinkingConfig: { thinkingBudget: 0 }` (`aiEquipmentRecognition`, `aiMachineDescription`,
`aiExerciseGeneration`) would see the same default-thinking behavior at all once that
override is applied. A same-shaped test at each callable's real parameters would be
needed before treating this as a confirmed regression risk, not just a smoke-test
artifact of an artificially small token budget.

## The actual decision this step needs

`gemini-3-flash-preview` still works, but it is Google's own preview tier, explicitly
flagged in this repo's source as something to migrate off of. G4's own stated scope
(GPT-PM's words) is to "safely activate and prove the four server-side AI capabilities,"
narrowly -- not to redesign which model the product uses. A full model migration is
itself the kind of "reviewed behavioral change" GPT-PM's own criterion calls out, and
would need its own re-verification of `disableThinking`/`temperature`/token-budget
behavior across all 4 callables -- real scope, not a one-line swap.

Two honest paths, not a unilateral call:

**A. Keep `gemini-3-flash-preview` for G4.** It is live-proven functional today. Ship G4
narrowly as scoped, and record the preview-tier risk as an explicit, disclosed, accepted
limitation with its own tracked follow-up (a preview model can be pulled with less notice
than a GA model) rather than silently deferring it with no owner.

**B. Migrate the model as part of G4's own Step 1**, most likely to `gemini-3.6-flash`
(the officially documented replacement for the retired/deprecated preview tier per
Google's own deprecations page) or `gemini-3.7-flash` (newest stable, no shutdown date
announced). This expands G4's scope to include re-verifying real behavior (thinking-token
consumption, output shape, latency) across all 4 callables at their real parameters
before deployment -- the "reviewed behavioral change" GPT-PM's criterion anticipates, done
properly rather than as a string substitution.

Recommendation, mine, not yet acted on: (A) -- the model is proven live-functional right
now, and G4's own scope was explicitly kept narrow by GPT-PM ("do not merge unrelated
post-G3 cleanup into G4"); a full model migration with real per-callable behavioral
re-verification is comparable in size to a second sub-gate, not a corner of Step 1. But
this is a real trade-off with a real residual risk (preview-tier stability), not a purely
technical call -- asking GPT-PM to decide rather than picking silently.

## GPT-PM ruling (round 1): MAJOR — B′, migrate within Step 1

GPT-PM rejected (A). Full reply in `core/DECISION_LOG.md`. Summary of the binding ruling:

- **Path A is not approved.** Criterion 1 of G4 is specifically to revalidate the model
  for production; a preview-tier model with a GA replacement already named by Google is
  not a settled production target, live-functional or not.
- **Adopt B′**: migrate within G4 Step 1, but test before editing production source --
  run an exact-call-shape comparison against the 4 real callable configs (system prompt
  structure, image payload, JSON schema contract, real `maxOutputTokens`, equivalent
  thinking control), not a 16-token smoke test. `gemini-3.6-flash` is the default
  candidate (Google's named replacement, supports `thinking_level: MINIMAL`, closest to
  today's `thinkingBudget: 0`); `gemini-3.7-flash` is a challenger only, not a mandatory
  target, since it lacks a MINIMAL/zero thinking level.
- **MINOR (accepted):** this document's "documentation is internally self-contradictory"
  framing overstated the case -- corrected below.
- No CEO escalation needed for this call; it is a technical production-readiness
  decision GPT-PM is scoped to make.

**Correction to the earlier documentation-contradiction claim:** the current official
Google deprecations table lists `gemini-3-flash-preview`'s shutdown date as "No shutdown
date announced," not 2025-12-17 -- 2025-12-17 is the *release* date, misread earlier as a
shutdown date. The table does explicitly name `gemini-3.6-flash` as the recommended
replacement. So: Vertex/global availability is live-proven (unchanged finding); the model
remains Preview with no announced shutdown (corrected); Google nevertheless recommends
migrating to the GA replacement (unchanged conclusion). The REST evidence stays valid --
it proves availability, which documentation alone does not.

## Real-shaped comparison test (per GPT-PM's required B′ verification)

Ran all 4 callables' exact real configs (`disableThinking`, `temperature`,
`maxOutputTokens`, `jsonResponse`, and for the two vision callables a real image payload)
against `gemini-3-flash-preview` (current), `gemini-3.6-flash` (candidate),
`gemini-3.7-flash` (challenger) -- live REST, same project/location as production.
Script: `D:\Temp\claude\d--Repo\61e7dfec-d8b3-4a63-a048-387194650f47\scratchpad\model_comparison_test.mjs`.

| Callable | Model | finishReason | Valid JSON | thoughtsTokenCount | candidateTokens | latencyMs |
|---|---|---|---|---|---|---|
| aiEquipmentRecognition (image, disableThinking, temp 0, json, cap 256) | preview | STOP | yes | null | 21 | 4710 |
| | 3.6-flash | STOP | yes | **null** | 26 | 3035 |
| | 3.7-flash | STOP | yes | **38** | 32 | 1492 |
| aiMachineDescription (image, disableThinking, temp 0, json, cap 384) | preview | STOP | yes | null | 66 | 5726 |
| | 3.6-flash | STOP | yes | **null** | 35 | 1752 |
| | 3.7-flash | STOP | yes | **100** | 35 | 4401 |
| aiExerciseGeneration (text, disableThinking, temp 0.4, json, cap 1024) | preview | STOP | yes | null | 495 | 4239 |
| | 3.6-flash | STOP | yes | null | 745 | 4081 |
| | 3.7-flash | STOP | yes | null | 740 | 6117 |
| aiCoachAdvice (text, no thinking override, prose, cap 512) | preview | MAX_TOKENS | n/a | 487 | 21 | 9887 |
| | 3.6-flash | MAX_TOKENS | n/a | 492 | 16 | 10861 |
| | 3.7-flash | MAX_TOKENS | n/a | 488 | 20 | 6807 |

**Finding 1 — `gemini-3.6-flash` matches `gemini-3-flash-preview`'s thinking-suppression
behavior exactly.** On every one of the 3 callables that set
`thinkingConfig: { thinkingBudget: 0 }`, both preview and 3.6 report
`thoughtsTokenCount: null` (fully suppressed). This is the decisive evidence for choosing
3.6 as the migration target.

**Finding 2 — `gemini-3.7-flash` does NOT fully honor `thinkingBudget: 0` on image
input.** It leaked 38 and 100 thinking tokens on the two vision callables despite the
same override (though not on the text-only `aiExerciseGeneration`, where it stayed at
null). This is a real, measured behavioral difference, not a config bug in the test, and
it independently confirms GPT-PM's reasoning for preferring 3.6: migrating to 3.7 would
have silently changed latency/cost on the two vision callables. **Decision: 3.7-flash is
rejected as the target; 3.6-flash is adopted.**

**Finding 3 -- all 3 models return valid, parseable JSON on every JSON-mode callable**,
with `finishReason: STOP` (not truncated). No JSON-mode regression from migrating to 3.6.

**Finding 4 -- `aiCoachAdvice` truncates on ALL 3 models, including the current
production model.** With no `disableThinking` override (matching the mobile source this
gateway ports unchanged), all 3 models spend ~487-492 of the 512-token budget on
thinking and hit `MAX_TOKENS` before finishing the answer. This is **not a migration
regression** -- it reproduces identically on `gemini-3-flash-preview`, today's production
model. It is a pre-existing product-quality gap this test surfaced as a side effect:
`aiCoachAdvice` answers are likely already getting cut off in production, independent of
which model is configured. Logged as a new finding for the backlog, out of scope for
this model-choice decision -- see `core/DECISION_LOG.md`.

## Decision

**Migrated `AI_MODEL` in `functions/src/ai_gateway.ts` from `gemini-3-flash-preview` to
`gemini-3.6-flash`.** `ai_gateway.test.ts`'s 24 tests pass unchanged (the suite asserts
against the exported `AI_MODEL` constant, not a hardcoded literal). Not yet deployed --
deployment is a later G4 criterion (targeted-only deployment with source↔live
provenance), gated on its own review round.
