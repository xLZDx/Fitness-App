# 37 - Final verdict

## Overall: NOT_RELEASE_READY

Two BLOCKERs and one CRITICAL are structural, reachable by an ordinary user, and touch health
safety. Separately, the sections that would decide whether the product is *good* - do the clips match
their descriptions, is the technique text coaching-sound, does recognition work in a real gym - are
UNAVAILABLE to a static audit, so even with the blockers fixed the honest ceiling is
CONDITIONALLY_READY pending human and device work.

## By area

| Area | Status | Why |
|---|---|---|
| Architecture | PASS_WITH_FINDINGS | 316 lib files, clear feature boundaries, one eligibility layer. Only 5 of 196 providers `autoDispose` |
| UI / navigation | PASS | 32 routes, zero duplicates, no dead route found |
| Exercise catalog | PASS_WITH_FINDINGS | 1,887 rows, zero duplicate ids, full EN/RU parity, `summary == steps[0]` holds in both languages, zero broken equipment references |
| Exercise media | INSUFFICIENT_EVIDENCE | Paths and posters verified; whether a clip depicts its exercise is unverifiable without human review |
| Fitness content | INSUFFICIENT_EVIDENCE | 1,484 of 1,887 rows have no `purpose`; the 403 that do were written by an assistant, not a trainer |
| Equipment | PASS_WITH_FINDINGS | 69 machines, 4 with no exercise |
| Scanner | PASS_WITH_FINDINGS | Pipeline reads sound; device behaviour UNAVAILABLE |
| ML | PASS_WITH_FINDINGS | Model genuinely trained with documented metrics and a caught data leak; covers 10 of 69 machines |
| Form Check | INSUFFICIENT_EVIDENCE | 540 of 1,887 rows have a pose target; biomechanical validity needs a clinician |
| Personalisation | FAIL | 14 of 37 collected fields reach no engine; `difficulty` is 1,877/1,887 `beginner`, so level ranking is inert |
| Programmes | **FAIL** | The questionnaire-built programme is an alphabetical filler and skips the whole-person safety gate |
| AI Coach | PASS_WITH_FINDINGS | No health data reaches any model - the best decision in the product. No safety settings on any Gemini call; no medical-advice constraint in the prompt |
| Health safety | **FAIL** | Exercise-level filter fails open on 360 rows; no pregnancy path; chest-pain refusal carries no urgency |
| Female health | PASS | The dangerous version was already removed by this project. Feature is dead code |
| Recovery | PASS_WITH_FINDINGS | Does not read the sleep and stress it collects |
| Workout player | INSUFFICIENT_EVIDENCE | Lifecycle needs a device |
| Progress | NOT_CHECKED | |
| Firebase | PASS | |
| Firestore security | PASS_WITH_FINDINGS | Ownership enforced by uid; `usage` and `receipts` client-writable through the wildcard |
| Privacy | PASS_WITH_FINDINGS | AES-256-GCM photos, Keystore keys, no health data to any LLM. 12 sensitive fields stored unencrypted and read by nothing |
| Payments | PASS_WITH_FINDINGS | Server-authoritative; 5 price IDs still uncreated |
| CI | PASS_WITH_FINDINGS | Rules and deletion e2e genuinely gate. Analyzer cannot fail; working branch gets no push CI |
| Tests | PASS_WITH_FINDINGS | 2,643 + 165 green; no empty, skipped or tautological test found |
| Accessibility | INSUFFICIENT_EVIDENCE | |
| Performance | INSUFFICIENT_EVIDENCE | |
| Documentation | PASS_WITH_FINDINGS | 930 claim candidates; the model row in the scope is contradicted by the artefact |
| Reproducibility | PASS | Every number in this audit was produced by a command that can be re-run |

## The sentence that matters

The eligibility layer is the best-engineered part of this product and it fails in one direction: a
person is screened carefully, and an exercise carrying no tags is served to everyone. 360 rows -
19.1% of the catalogue - cannot be withheld from anyone, while the interface says the list was
screened. Everything else in this verdict is smaller than that.
