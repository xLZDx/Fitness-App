# 25 - AI Coach and AI recommendation safety

Reviewed by a recommendation adversary working from `.claude/agents/recommendation-adversary.md`;
load-bearing claims re-confirmed against source by the orchestrator.

## What the AI Coach actually is

| | |
|---|---|
| Provider | Firebase AI Logic / Google AI (`firebase_ai` 3.3.0); key stays server-side |
| Model | `gemini-3-flash-preview` at all three call sites |
| System prompt | **none** - a single user turn built by `buildCoachPrompt` (`ai_coach_context.dart:97-137`) |
| Context sent | source enum, catalogue subject id, display name, language code - **and nothing else** |
| Health context | **deliberately none**, recorded at `ai_coach_context.dart:22-34` |
| Output | free text; no `GenerationConfig` on the coach call |
| Timeout | **none** on the coach call; 25 s on the generator, 20 s on the describer |
| Fallback | none - failure renders an error card with retry |

**There is no free-text input.** The sheet renders one generated question about one catalogue
subject (`ai_coach_sheet.dart:35-51`). So the adversarial prompts the mandate asks about - injury,
medical, medication, pregnancy, eating disorder, chest pain, minors - **cannot be asked through this
surface at all.**

The honest statement for the audit: **no guardrail exists; the risk is bounded by the absence of an
input, not by a control.** No `SafetySetting` / `HarmCategory` / `HarmBlockThreshold` is set on any
of the three Gemini calls - grep over `mobile/lib` returns zero hits, so all three run on provider
defaults. There is no age gate on this path. The protection evaporates the day a text field is added.

## CRITICAL - the AI can invent an exercise, and it reaches the user unvalidated

`machine_describer.dart:105-123` asks the model for `"uses": ["<one short exercise done on it>"]`.
`parseDescription` (`:165-177`) validates only: is a string, non-empty, at most 120 characters,
deduped, capped at five. **Confirmed by direct read - there is no check against the catalogue, no
injury screen, no equipment check.** It is wired live at `main.dart:473` and rendered at
`machine_card_view.dart:93-101` under "What you can do on it".

The prompt's own comment explains why no vocabulary constraint was applied - for an unrecognised
machine "there is no page by definition". Understandable, and it leaves free-text model output being
presented as exercise guidance to a user whose injuries this path never consults.

## Personalisation - real, but thinner than the word implies

The complete input set of the For-You ranking is: weekly per-muscle set deficit
(`volume_ledger.dart:151-193`) and a +0.05 novelty bump for anything not logged in seven days
(`for_you_ranker.dart:38`). Goal, age, sex, session length and history beyond seven days do not
influence order at all; injuries, equipment and screening act only as an upstream filter.

Home's "recommended because" strings are **honest** - each reason is assigned inside the same branch
that adds the score (`suggestion_builder.dart:147-196`), so the sentence is not post hoc. The file
even records that a stronger claim was deliberately removed.

`sortByTierFit` (`exercise_filter.dart:188-210`) reorders by difficulty distance and never removes.
With 1,877 of 1,887 rows `beginner`, every row ties at distance 0 and the comparator returns 0 for
all of them: **an O(n log n) sort that changes nothing.** It also has no index tie-break, and the
repo states elsewhere that Dart's `List.sort` is not stable - so the For-You list can reshuffle
between runs and cannot be reproduced from a bug report.

## Nine dangling ids in the celebrity plans

`celebrity_plan_repository.dart:26-43` seeds nine exercise ids. **Confirmed against the shipped
asset: 0 of 9 exist.** Every real id is `ea_*`-prefixed. Currently unreachable - no widget reads
`dailyWorkouts` - but one of the plans is titled "Low-Back-Friendly", which is a safety claim over
exercises that do not exist.
