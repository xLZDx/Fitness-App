# 34 - Reviewers and how their findings were handled

| Reviewer | Persona source | Scope | Outcome |
|---|---|---|---|
| Orchestrator | - | Inventory, datasets, claim ledger, routes, providers, CI, l10n, personalisation | 12 findings; **corrected itself twice** (see `31_CONTRADICTIONS.md`) |
| Security / privacy | native `security-reviewer` | Firestore rules, Cloud Functions auth, deletion, secrets, photos, logs, LLM exposure | 4 findings; listed 7 open items honestly rather than claiming clean |
| Clinical safety gate | `.claude/agents/clinical-safety-gate.md` | Injury filtering, health inputs, refusal path, cycle, pregnancy, medical boundary | 2 BLOCKER, 1 CRITICAL, 6 HIGH |
| Recommendation adversary | `.claude/agents/recommendation-adversary.md` | AI coach, generation safety, ranking, programme pipeline | 2 BLOCKER, 1 CRITICAL, 4 HIGH |
| Medical-boundary copy | sub-sweep of the clinical review | Every `.arb` key and hardcoded Dart string | 12 ranked findings |
| Test forensics | native `functional-test-reviewer` | False-green hunt across 264 test files | **Partial** - refused to report unread domains |

## Independent corroboration

The clinical reviewer and the recommendation adversary were given non-overlapping briefs and never
saw each other's output. Both independently found the spec-less programme path bypassing the
whole-person gate (`programme_providers.dart:199-206`). That is the strongest single signal in this
audit.

## Where a reviewer was overruled or corrected

- The test reviewer was given three "confirmed" false-green examples that had in fact been fixed
  earlier the same day. It refused to re-report them. The brief was wrong; the refusal was right.
- The security reviewer's first pass labelled its own gaps NOT_CHECKED rather than clean. Accepted
  as-is and the gaps were reassigned.
- Every BLOCKER and CRITICAL below was re-opened by the orchestrator and confirmed against source
  before entering the verdict. None was taken on an agent's word.

## Not run

QA-adversary as a separate final pass (§62), and a second independent reviewer per
BLOCKER/CRITICAL as §3 requires. The orchestrator's own source confirmation stands in for the
latter, and that substitution is recorded here rather than hidden.
