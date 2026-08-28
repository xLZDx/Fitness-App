# MVP1.G4 Step 1 — Vertex AI model revalidation

Per GPT-PM's binding exit criteria for MVP1.G4, criterion 1: "Revalidate the configured
Vertex model and region against current supported models. If `gemini-3-flash-preview`
must be replaced, treat the model change as a reviewed behavioral change, not a string
substitution. Prove one bounded direct backend smoke test before deployment."

## Why not trust either the old source comment or the docs alone

`functions/src/ai_gateway.ts`'s own comment (written 2026-08-26, during G1) said
`gemini-3-flash-preview` "is a DEPRECATED model on Vertex AI." That framing overstated
the case -- corrected here after GPT-PM's round-2 review caught this document itself
repeating the same overstatement (see "GPT-PM ruling (round 2)" below for the full
finding).

**Corrected reading of Google's current lifecycle table** (`ai.google.dev`'s deprecations
page, the authoritative source): `gemini-3-flash-preview`'s **release date** is
2025-12-17; its **shutdown date is "No shutdown date announced."** There is no
self-contradiction in the current table -- the earlier draft of this document misread the
release date as a shutdown date, compared it against a second, differently-scoped page,
and called the mismatch a "contradiction" when it was a misreading. What the table DOES
say, correctly: Google names `gemini-3.6-flash` as the recommended replacement for
`gemini-3-flash-preview`. That -- a named GA replacement for a Preview-tier model, not an
imminent shutdown -- is the real, verifiable reason to migrate, and it is confirmed
independently by the live REST evidence below (the model still answers real calls today;
nothing here was ever about the model being dead).

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

## Model source change (round 1 close-out)

**Migrated `AI_MODEL` in `functions/src/ai_gateway.ts` from `gemini-3-flash-preview` to
`gemini-3.6-flash`.** `ai_gateway.test.ts`'s 24 tests pass unchanged (the suite asserts
against the exported `AI_MODEL` constant, not a hardcoded literal). Not yet deployed --
deployment is a later G4 criterion (targeted-only deployment with source↔live
provenance), gated on its own review round. Commit `d12d8ac`.

## GPT-PM ruling (round 2): MAJOR — model choice confirmed, verification incomplete

Sent commit `d12d8ac` (the migration + the comparison table above) for the verification
round GPT-PM's own round-1 ruling required. Full reply in `core/DECISION_LOG.md`. Summary:

- **`gemini-3.6-flash` remains the approved migration target; no reason to revert
  `d12d8ac`.** The thinking-suppression evidence (Finding 1/2 above) was accepted as
  persuasive on its own terms.
- **MAJOR (the real gap):** the round-1 comparison table proved the model's output was
  syntactically valid JSON, not that it satisfies the actual contract the production
  clients enforce AFTER parsing. `aiEquipmentRecognition`, `aiMachineDescription` and
  `aiExerciseGeneration` all forward the model's raw JSON text unchanged; validation
  happens client-side (`GeminiVisualEquipmentService.parseResponse`,
  `GeminiMachineDescriber.parseDescription`, `AiExerciseGenerator.parseResponse` in the
  Flutter source). A syntactically valid `{}` can still be silently discarded by all
  three. Required: validate each 3.6 response through the real contract (or an
  exact-equivalent port), record "usable recognition" / "valid MachineCard" / "N usable
  ExerciseItems," not just "JSON.parse succeeded."
- **MINOR:** the original "documentation is internally self-contradictory" paragraph was
  left standing in this document even after a later paragraph admitted it was a
  misreading -- two incompatible factual versions in the same durable record. Required:
  rewrite the section itself, not append a correction below it.
- Verdict: `gemini-3.6-flash` stays `AI_MODEL`; Step 1 is **not yet closed**.

**Independent verification found the MAJOR was worse than stated.** Checking GPT-PM's
claim against the real Dart parsers (per CLAUDE.md §3/§13 -- verify before acting)
surfaced that the round-1 test's JSON schemas for the two vision callables were not just
unvalidated against the client contract, they were **built from a guess, not read from
source**: the test asked the model for `{"machineName", "confidence", "category"}` and
`{"name", "summary", "exercises"}`, while the REAL prompts in
`functions/src/ai_equipment_recognition.ts`/`ai_machine_description.ts` ask for
`{"machine", "confidence", "alternatives"}` and
`{"isGymEquipment", "name", "summary", "uses"}` -- verbatim, copied from source this time.
The round-1 test also used a blank/noise placeholder JPEG, which only ever exercised the
NEGATIVE path (empty/unknown result) -- never proved a positive, usable recognition.

## Round-2 remediation: verbatim prompts, real image, real contract validation

Rebuilt the comparison
(`D:\Temp\claude\d--Repo\61e7dfec-d8b3-4a63-a048-387194650f47\scratchpad\model_comparison_test2.mjs`)
with three fixes: (1) all 4 prompts copied verbatim from `functions/src/ai_*.ts`'s
`buildPrompt()` source, including the real `CANONICAL_MACHINES` (71 items) and
`MUSCLE_VOCAB` lists; (2) a real illustration,
`mobile/assets/posters/girl/leg_press.jpg` (leg press is in `CANONICAL_MACHINES`), in
place of the blank placeholder, so a positive recognition path is actually exercised; (3)
each JSON-mode response run through a faithful JS port of the real Dart contract
(`validateEquipmentRecognition`/`validateMachineDescription`/`validateExerciseGeneration`
in the script) instead of `JSON.parse` alone.

| Callable | Model | Contract result | thoughtsTokenCount |
|---|---|---|---|
| aiEquipmentRecognition | preview | usable: true — "smith machine" (0.95), resolved against CANONICAL_MACHINES | null |
| | 3.6-flash | usable: true — "smith machine" (0.99) | **null** |
| | 3.7-flash | usable: true — "smith machine" (0.98) | **47** |
| aiMachineDescription | preview | usable: true — name/summary present, 5 usable `uses` lines | null |
| | 3.6-flash | usable: true — name/summary present, 5 usable `uses` lines | **null** |
| | 3.7-flash | usable: true — name/summary present, 5 usable `uses` lines | **62** |
| aiExerciseGeneration | preview | usable: true — 4/4 items pass (title + steps present) | null |
| | 3.6-flash | usable: true — 4/4 items pass | null |
| | 3.7-flash | usable: true — 4/4 items pass | null |

**All three models produced a client-contract-usable result on every JSON-mode callable,
on the SAME real image, not just parseable JSON.** All three independently identified the
`leg_press.jpg` illustration as "smith machine" (a real, model-driven recognition
question about that illustration's fidelity, not a migration artifact -- preview, 3.6 and
3.7 agree with each other, so this is not model-choice-dependent). The thinking-leak
pattern from the round-1 test reproduces exactly: 3.6 matches preview's
`thoughtsTokenCount: null` on both vision callables; 3.7 leaks non-zero thinking tokens on
both (47, 62) despite the identical `thinkingBudget: 0` override. This is now the second,
independent confirmation of Finding 2 above, on a real image and the real schema this
time. `aiExerciseGeneration` (text-only) stays at `null` for all 3 models, matching the
round-1 result -- the leak is specific to 3.7 handling image input with thinking disabled.

## Decision (updated)

**`AI_MODEL = "gemini-3.6-flash"` stands, confirmed by contract-level evidence, not just
JSON-syntax evidence.** Sending this remediation (the corrected documentation section
above + this round-2 test) back to GPT-PM for the close-out round it asked for. Deployment
remains gated on its own later G4 criterion.
