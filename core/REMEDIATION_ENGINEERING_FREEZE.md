# Engineering remediation — FROZEN

```text
ENGINEERING_REMEDIATION = FROZEN
```

**Frozen 2026-08-17**, after an independent adversarial review that was told to disprove the
completed state rather than confirm it. It found six defects worth reopening for. All six are fixed
and mutation-proven; the freeze is dated after the fixes, not after the review.

| | |
|---|---|
| Baseline HEAD (state entering this review) | `4cdc35d` |
| Reviewed HEAD | `4cdc35d` |
| Test-evidence HEAD | `8857e6e` |
| Suites at the freeze | mobile **2828** · functions **185** · Firestore rules **64** · 0 failures |
| Delivery state | `LOCAL_ONLY` — 43 commits ahead of origin, nothing pushed |

---

## What the freeze means

Previously reconciled forensic findings are **not automatically reopened** during ordinary feature
or ML development. A defect found from here on is a NEW finding or a regression against this
baseline, and is tracked as such.

It does not mean the code is defect-free. It means the audit is closed as an audit, because
continuing to re-examine the same surface indefinitely stopped producing new information — and this
review is the evidence for that claim rather than an assertion of it: it went looking for eight
specific bypass classes and found the defects listed below, none of which the previous eleven
reconciliation passes had surfaced.

---

## What the review found

Six reopened. Every fix carries a test that fails against the previous behaviour — that is the bar,
and it was met in every case by running the test before the fix and watching it go red.

| id | severity | what |
|---|---|---|
| **N-01** | BLOCKER | The F014 block was discarded on the next profile read. `HealthFlags.operator ==` omitted `professionalGuidance`, so a reported need compared equal to no answer at all; `HealthHistory.isEmpty` asked through that equality, and the merge drops a local health block that reads as empty. After a restart and a clean PAR-Q, `allowsAnyTraining` came back **true**. |
| **N-02** | MAJOR | The Firestore health rule inspected eight fields of a ten-field map. The PAR-Q+ answers and the normalised flags — the most structured health data the model holds — were the part the server-side backstop did not look at. |
| **N-03** | MAJOR | `bookCoachSession` was exempted by F011 as "bounded by what deletion removes". It writes: a Stripe customer holding the deleted uid, a subscription document re-created after the erasure sweep, and a charged card. |
| **N-04** | MAJOR | `reportEquipment`: no quota, a client-chosen document id written with `set()`, an unbounded note, and that note relayed verbatim into a third party's channel. |
| **N-05** | MAJOR (mitigated) | Per-uid quotas on the metered video endpoints did not bind, because an anonymous uid is free to mint. |
| **N-06** | MAJOR | `exportAccountData` fanned out into sixteen reads over client-writable collections with no ceiling. |
| **N-09..N-13** | MAJOR/MINOR | Five guards that reported success against the regression they exist to catch. |

### The pattern the review actually exposed

Two, and they are worth carrying forward because they will recur:

**A field reaches the model and the serialiser and not the guard.** N-01 and N-02 are the same
defect in different languages. F014's field was added to `toJson`/`copyWith` and not `fromJson`
(caught pre-commit), then to `fromJson` and not `operator ==` (N-01), and the `health` map grew two
fields the Firestore rule never learned about (N-02). Nothing in Dart or in the rules language checks
"did you list the field again", and every instance passed the analyzer, the suite and review.

**A guard that matches a substring of prose is evidence about the substring, not about the thing.**
Five guards could not fail. Deleting the entire Firestore rules job left its test green, because the
word "rules" appears five times in comments. Deleting the whole-suite CI step left its test green,
because `flutter test` also matches the integration job. `contains('SHIPPED')` was satisfied by
`NOT SHIPPED`. Two of the five sat in a file where a comment-stripping helper already existed and was
declared below the groups that needed it.

Neither pattern was found by reading. Both were found by breaking the thing and watching the test
stay green.

---

## What was checked and found sound

Not everything reopened, and the negative results are part of the evidence.

- **F016 / the AI trust boundary.** Every `MachineCard` consumer enumerated: all render-only or
  card-store-only. No LLM or model output can mint, mutate or prescribe a canonical exercise
  identity. Model-derived writes reach two per-user subcollections and never the catalogue.
- **Model governance.** The bundled artefact's sha256 and byte count were recomputed and match the
  registry exactly; the committed blob matches the worktree (git treats it as binary, so no EOL
  rewrite). The code's load path is the registry's bundled path. No code loads v2 and no document
  claims it ships. `training_code_commit: UNKNOWN` is intact and nothing invented a value.
- **Entitlements and receipts.** Server-only, double-closed in the rules, denial-tested per verb.
  There is no store-receipt path at all; entitlement flows only from a signature-verified Stripe
  webhook whose uid is stamped server-side. No replay, no cross-account binding.
- **F014 wording.** The EN and RU strings carry none of the forbidden vocabulary. Reasons are a typed
  enum rendered through an exhaustive switch, so an unhandled case fails to compile. Both ARBs carry
  1,197 keys with identical names and order.
- **CI triggers.** Both workflows run on push to every branch and on all pull requests, and both
  carry a live nightly schedule — the previously-fixed commented-`schedule:` defect is genuinely
  fixed and is mutation-proven.
- **Three-state semantics.** One decision site in `lib/`, using the safe `== reported`. No
  `!= reported` anywhere in the repository, and no null-coalescing default on the field.

---

## Residual — recorded, not fixed

None of these is release-blocking, and none is a safety or privacy defect. They are listed so the
freeze is not read as "nothing is left".

| | |
|---|---|
| `startCoachOnboarding` | Any signed-in caller can mint a Stripe Connect account. No money can move (`coach_listings` is not client-writable, and a listing without a price is refused), so the impact is junk connected accounts. |
| `coach_listings` rules | Denied to clients by having no rule block at all — by omission rather than by decision. `bookCoachSession` trusts two fields from it. |
| Donor wall | The document id is the uid, and the collection is world-readable, so "Anonymous donor" is anonymous only in its label. |
| `MachineCard.name` | Unbounded; a hallucinated multi-KB name overruns the Firestore document-id limit, the write throws, and the error is swallowed — the card renders and is silently never persisted. Same class as N-04. |
| `MachineCard.recognisedAs` / `confidence` | Documented as the card's evidence and never populated in production. Either wire them or delete them and the claim. |
| Subscription exception strings | Hardcoded English in a data layer, reached through interpolation, which is the localisation guard's blind spot. Not safety copy. |
| Localisation guard blind spots | Cannot see `Text.rich`, `SelectableText`, `Tooltip(message:)`, `Semantics(label:)`, any literal containing `$`, triple-quoted strings, or a literal assigned upstream and passed in as a variable. |
| F010 provider cleanup | Unchanged: `DEFERRED_TO_DEDICATED_CLEANUP_GATE`, 14 of 193 unread, `SAFE_TO_DELETE` deliberately empty. |

## Operator decisions outstanding

Neither is a code defect, and neither may be settled by assumption.

1. **Enforce App Check on the metered video endpoints?** This is the only control that closes N-05.
   `APP_CHECK_ENFORCED` defaults to off. The alternative — refusing anonymous callers outright — was
   deliberately not taken, because anonymous sign-in is a first-class login button and removing video
   from it is a product decision.
2. **Must filing an equipment report require an association with that gym?** The report's free text
   reaches that gym's maintenance channel. Requiring an association means modelling gym membership,
   which this repository does not do.

---

## What the freeze does NOT touch

```text
D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED   unchanged
H3 = HOLD                                    unchanged
D3 = CLOSED                                  unchanged
PRODUCTION_IMAGE_COLLECTION = DISABLED       unchanged
CT != CD                                     unchanged
```

An engineering freeze is a statement about engineering. No green suite, no registry, no content
scan and no amount of remediation is evidence about clinical safety, and nothing here moves an
external authority. `core/review/CLINICAL_VALIDATION_HANDOFF.md` remains a request for validation,
not validation.

## Release status, in the four dimensions that must stay separate

```text
ENGINEERING_STATUS        = remediation complete; independently reviewed; FROZEN
CLINICAL_AUTHORITY_STATUS = D1 external validation required · H3 hold
PRODUCT_RELEASE_VERDICT   = evidence-based; not inferable from push state
DELIVERY_STATE            = LOCAL_ONLY
```

43 commits ahead of origin with nothing pushed is an operational fact about delivery. It is not a
product-quality finding and must not be read as one.
