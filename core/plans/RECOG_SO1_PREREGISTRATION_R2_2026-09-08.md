# RECOG-SO1 pre-registration, REVISION 2 — 2026-09-08

Revision 1 of this experiment ran on 2026-09-08 and **failed as an instrument**. It is archived,
unscored, and it is an input to nothing. Its own pre-registration
(`RECOG_SO1_PREREGISTRATION_2026-09-07.md`) and its own seal are untouched by this document, so run
#1 remains judgeable by the protocol it actually ran under. That is deliberate: a revision that
edits the artefacts of the run it is replacing destroys the only record of what the earlier run was
measured against.

**This revision changes the instrument. It does not change what is being measured.** The
hypothesis, the thresholds, the prompt, the vocabulary, the ground truth and the 52 source
photographs are identical to revision 1 and are bound by digest in the appendix at the end.

---

## 0. Status: DRAFTED AND UNSEALED

**This protocol is not sealed, and it authorises nothing.** The seal block in §12 is empty; the
runner refuses on an empty seal rather than reporting that it verified nothing successfully. Four
conditions gate any transmission, and **all four are currently unmet**. None of them is a note:
each is enforced by the runner, which refuses and exits non-zero.

| # | Condition | State on 2026-09-08 | Enforced by | Exit |
| --- | --- | --- | --- | --- |
| 1 | 24 hours of quiet since the last Qwen request of any class | **2.1 h elapsed** | `isolation_ok()` | 7 |
| 2 | A stress-probe receipt: both arm shapes, successful, `cleared: true`, bound to config + prompt + vocabulary | **absent** | `stress_probe_receipt_ok()` | 8 |
| 3 | A non-empty seal, written only after condition 2 | **empty** | `load_seal()` / `verify_seal()` | 2 |
| 4 | Renewed operator consent binding **all four** partitions and attesting organisation exclusivity | **absent** | `evaluate_consent_r2()` | 3 |

The probes cannot run today for two independent reasons, either of which suffices: the
organisation's daily budget on 2026-09-08 stood at 199,789 of 200,000 tokens, and condition 1 is
unmet — run #1 made 260 transmissions this morning.

An earlier draft of this document carried a **filled** seal while the probes were still outstanding,
and justified it by distinguishing "sealing the artefact list" from "clearing transmission".
GPT-PM's closure review rejected that: the approved plan's branch said *drafted but not sealed*, and
inventing a second sense of "sealed" to satisfy the first half of it was a claim wider than the
check behind it. The digests are preserved in §12 as an explicitly **provisional appendix that no
program reads**, and the seal itself stays empty until the probes succeed.

---

---

## 1. What revision 1 measured, and why it produced nothing

104 observations were attempted. 46 were answered, 58 were refused, and every failure was HTTP 429.
Neither of the two limits behind those refusals was the limit the run had been paced against.

| Limit | What it is | Refusals | Guarded in revision 1? |
| --- | --- | --- | --- |
| ITPM 7,000 | input tokens per minute | 0 | yes — this is what the 20 s pacing was built for |
| **TPD 200,000** | tokens per **day**, enforced per **organisation** | 48 | no |
| **OTPM 1,000** | output tokens, a **per-request** ceiling | 10 | no |

Measured from the run's own usage blocks: mean prompt 2,153 tokens, maximum 2,198 — not the 1,813
the pacing arithmetic assumed. A clean 104-observation pass with zero retries therefore costs
**2,153 × 104 = 223,962 input tokens against a 200,000 daily ceiling.** The experiment does not fit
in one day on this tier at all. 260 requests were made to obtain 104 observations, and nothing in
the program knew that.

OTPM is a per-request ceiling rather than a rate: Groq estimates a request's output cost
pessimistically from `max_completion_tokens` and refuses outright when the estimate exceeds 1,000.
Revision 1 sent 4,096 and was refused for that reason alone ten times, twice while the daily budget
was still intact. **No amount of pacing can avoid a per-request ceiling.** Actual completions were
22–41 tokens.

---

## 2. The hypothesis, unchanged and bound by hash

RECOG-C1 established that the recogniser's own self-report carries no abstention signal: across 104
observations it never answered `unknown`, and neither confidence, nor the lead over the second
candidate, nor the number of alternatives separated frames that have a single right answer from
frames that do not.

SO1 asks whether a **second, independent model** supplies from outside what the first cannot supply
about itself: do the two models disagree more often on frames where no single machine is the
subject than on frames where one is?

- `D` — the two models do not name the same equipment
- `D_multiple` — D over frames whose frozen ground truth is `multiple`
- `D_canonical` — D over frames whose frozen ground truth is `canonical_single`
- `Δ` — `D_multiple − D_canonical`, in percentage points

**PASS requires all five:** `D_multiple ≥ 60%`; `D_canonical ≤ 20%`; `Δ ≥ 40 pp`; the direction
holds in both arms; source-clustered permutation `p < 0.05`.

**FAIL on any one:** `D_multiple < 50%`; `D_canonical > 25%`; `Δ < 25 pp`; Qwen canonical top-1
`< 80%` or more than 10 pp worse than Gemini; the direction reverses in either arm.

**The conservative unresolved rule:** an unresolved observation counts AGAINST the signal — as
agreement in `multiple`, as disagreement in `canonical_single`. Both push Δ down. A run that fails
to get answers is not rewarded with a result.

**Inference clusters by source photograph.** 104 observations are 52 scenes seen twice, not 104
independent samples, and the frozen ground truth confirms kind is a property of the photograph: all
52 sources carry the same kind in both arms.

None of the above is re-implemented in revision 2. `recog_so1_score_r2.py` **imports** the
arithmetic and the thresholds from revision 1's sealed scorer, so "the hypothesis did not move" is
a property of the code rather than a claim about it.

---

## 3. Run validity precedes every statistic

Revision 1's scorer had the right thresholds in the wrong order: it computed the disagreement rates,
Δ, the clustered permutation p and the competence figures, and only THEN reached the power floor
that was supposed to stop an underpowered dataset from producing a verdict. And that floor counted
manifest **rows**: `unique_sources()` reported 26 sources per arm and kind for a run in which 58 of
104 observations carried no reply at all.

Two outcomes are added, and they are not verdicts:

| Outcome | Meaning |
| --- | --- |
| `INVALID_INSTRUMENT` | A provider, configuration or quota failure makes the measurement structurally invalid. **No hypothesis statistic is produced at all** — not computed-and-withheld, not reported-with-caveats. There is nothing to caveat. |
| `INCONCLUSIVE` | Execution was valid; there were simply too few valid answers, or the numbers met neither the PASS bar nor any FAIL condition. |

`run_validity()` is the first statement in both `verdict()` and `report()`, and both return from
inside it. This is proven by instrumentation rather than by reading rendered text: the suite
replaces `rate`, `delta_pp`, `permutation_p` and `competence` with spies that raise, on the module
where they actually execute, and requires an invalid fixture to complete with **zero** calls to all
four — paired with a control requiring a valid fixture to reach all four, so the zero-call assertion
is known to be capable of failing.

**The coverage floor counts answers.** At least **20 unique source photographs per ground-truth
kind** must carry a valid parsed answer in **both** arms. A 429, a timeout, a 5xx or an unparseable
reply does not become coverage because a manifest row exists for it. `answered_sources()` sits
beside `unique_sources()` so a report prints both and the difference is visible: on run #1's shape
that difference is 26 rows against 6 answers.

---

## 4. The frozen decision table

Read as data from the sealed configuration. Attempt counts are **transport attempts** — calls that
spend tokens and write a ledger entry — never sleeps.

| Class | Outcome | Transport attempts | Stops the run |
| --- | --- | --- | --- |
| `http_400` / `401` / `403` / `404` | INVALID_INSTRUMENT | 1 | yes |
| `otpm_request_too_large` | INVALID_INSTRUMENT | 1 | yes |
| `tpd_exhausted` | INVALID_INSTRUMENT | 1 | yes |
| `unrecognised_429` | INVALID_INSTRUMENT | 1 | **yes — fails closed** |
| `rolling_window_429` | unresolved | 2 | no |
| `transport_failure` (5xx, connection, timeout) | unresolved | 3 | no |
| `parse_failure` | unresolved | 1 | no |
| `finish_reason_length` | unresolved | 1 | no — and never retried |
| `ledger_budget_exceeded` | INVALID_INSTRUMENT | 0 | yes |
| `availability_failed` | INVALID_INSTRUMENT | 0 | yes |
| fewer than 20 answered pairs in either kind | INCONCLUSIVE | — | — |

**The trap this table is built around.** The daily refusal and the ordinary rolling-window refusal
open with *identical words*:

```
Rate limit reached for model `qwen/qwen3.8-27b` ... on tokens per day (TPD): Limit 200000, Used 199789, Requested 2495.
Rate limit reached for model `qwen/qwen3.8-27b` ... on tokens per minute (TPM): Limit 7000, Used 6671, Requested 2096.
```

A classifier keyed on that prefix would read a spent **day** as a spent **minute** and retry into
it. So classification reads the parenthesised limit code — `(TPD)`, `(RPD)`, `(OTPM)`, `(TPM)`,
`(RPM)` — and anything else stops the run. Both bodies above are verbatim, and both are test
fixtures.

**And the code alone is not enough either, which is a second trap inside the first.** `(OTPM)`
names two different failures. With *Request too large* it is the permanent per-request output
ceiling and the run stops; with *Rate limit reached* it is an ordinary rolling window and the
frozen table says retry twice. The first implementation of this revision mapped the `(OTPM)` code
unconditionally to the permanent class — contradicting this document's own sealed configuration,
which had said to read the form all along. GPT-PM's closure review caught it. A transient OTPM
refusal would have invalidated an entire partition. Classification now reads code **and** form,
and an `(OTPM)` body in wording nobody has seen fails closed.

**A network error that is raised rather than returned reaches the same table.** Revision 1's
transport converts only `HTTPError`; a read timeout or a reset connection propagates straight out
of it, so the frozen `transport_failure → exactly 3 attempts` row was unreachable with the real
transport and a timeout would have crashed the process *after* its ledger entry was written —
spent budget with no matching result record. `post_with_transport_failures()` converts
`URLError`, `TimeoutError`, `ConnectionError` and `OSError` into the frozen class. Also GPT-PM's,
also on this revision's first implementation.

---

## 5. One wait authority

Revision 1 had two: the ordinary pacing sleep, and `pace_after_failure()`, which took
`max(pacing, Retry-After)` on the failure path only. Adding a TPM guard beside them would have left
three signals with no defined composition — the same defect one branch over. **`pace_after_failure`
does not exist in revision 2.** One function computes the interval before every transport call, of
every class, and the runner sleeps once for the result:

```
wait = 20                                              # the frozen pacing, always the floor
if the latest VALID x-ratelimit-remaining-tokens < 3600:
    wait = max(wait, x-ratelimit-reset-tokens + 2)     # the provider's own TPM reset, plus margin
    if that reset is absent or malformed:
        wait = max(wait, 60)                           # conservative fallback for a low window
if this attempt follows a retryable 429 with a VALID Retry-After:
    wait = max(wait, Retry-After)
# a malformed or absent Retry-After contributes NOTHING
sleep ONCE for wait
```

**Maximum, never addition.** Each term states the earliest moment the next request may go out, so
the binding one is the latest. Adding them would honour none of the three and would stretch a
44-request partition past every wall-clock estimate here.

The nine frozen values, each asserted in the suite as the **total** interval before the next
transport call, with an injected clock and no real sleeping:

| remaining | reset | Retry-After | total wait |
| --- | --- | --- | --- |
| low | 12 s | — | **20 s** |
| low | 30 s | — | **32 s** |
| low | malformed | — | **60 s** |
| healthy | 30 s | — | **20 s** |
| header absent | — | — | **20 s** |
| low | 12 s | 45 | **45 s** |
| low | 30 s | 10 | **32 s** |
| low | malformed | 75 | **75 s** |
| healthy | — | absent | **20 s** |

`next_request_tpm_bound` is **3,600** — the same measured quantity as the empirical per-request
charge bound in §6, used for both purposes on purpose. Two separately invented numbers could
disagree about what one request costs; one cannot.

**The sleep consumes no attempt.** Only the transport call does. A request that waits 45 seconds and
then succeeds has made one attempt and written one ledger entry.

**`x-ratelimit-remaining-tokens` and `x-ratelimit-reset-tokens` are Groq's tokens-per-MINUTE window
figures.** They are not an ITPM or OTPM remaining budget, and above all they say nothing about the
day. Groq writes these durations as `7.66s`, `2m59.56s`, `16m26.688s`; the parser handles that
format, and an unparseable value takes the conservative branch rather than zero.

---

## 6. The ledger, and the day counted locally

Every transmission to the model, of every class — stress probe, availability check, corpus
observation, **and every retry attempt separately** — is written to
`core/plans/recog_so1_raw/RECOG_SO1_QWEN_REQUEST_LEDGER.jsonl` **before** it is sent, carrying
model, UTC timestamp, request class and partition.

Before, not after, and the ordering is the design: a request that is sent and then fails to be
recorded is spent budget the next run cannot see. Recording first can over-count if the process dies
between the write and the send, and over-counting is the safe direction.

A ledger that is **missing, unreadable or malformed** raises and nothing is transmitted. A missing
file is refused rather than read as "nothing spent yet", because an absent ledger is
indistinguishable from a deleted one and the deleted one is the case that matters.

**The daily ceiling is accounted here and nowhere else.** The provider exposes no
remaining-per-day figure at all, and the minute-window headers describe the minute.

```
tokens per day, measured               200,000     (verbatim: "Limit 200000, Used 199789, Requested 2495")
daily experiment budget                160,000     = 80% of measured
empirical charge bound per request       3,600     = 3,408 observed maximum + 5.6% margin
requests per partition                      44     = floor(160000 / 3600)
                                                   = 1 availability + 26 corpus + at most 17 retries
```

The 3,600 is **empirical with a margin, not a proven ceiling**: a request the provider charges more
than 3,600 for would break this arithmetic, and nothing here can rule that out. Stated as what it
is.

The availability call **counts**. Either it does, or the arithmetic is 45 rather than 44. The suite
proves this by mutation: excluding it lets a partition make 45 transmissions.

**The ledger is seeded with run #1's own transmissions, or the isolation rule would be vacuous on
its first day.** Run #1 made **260** transmissions — the sum of the `attempts` field across all 104
archived records, which is also the figure the failure report gives. They are recorded as 260
entries of class `corpus` with `partition: null`, so they constrain the isolation clock without
being attributed to any revision 2 partition.

The archive carries no per-request timestamp, so all 260 are dated `2026-09-08T07:26:46Z`, the
commit time of the archive itself. That instant is necessarily **later** than the last real request,
which makes the isolation wait longer rather than shorter — the safe direction, and stated here
rather than left as an unexplained constant. Reading `attempts` from the archive is transmission
bookkeeping; the 46 answers in that file remain unread and unscored.

Measured on 2026-09-08 immediately after seeding: `isolation ok: False — only 2.1h since the last
Qwen request; the isolation rule requires 24h`, and both the corpus path and the probe path refuse
accordingly. **Partition 1 cannot start today**, and that is a refusal the program performs rather
than a sentence this document asserts.

---

## 7. Isolation, and the exclusivity that is attested rather than verified

- **Partition 1** may not start until **24 hours** after the ledger's last Qwen request of **any
  class, stress probes included**. A probe run while sealing this document spends the same
  organisation's tokens as a corpus observation does, so it advances the same clock the partition
  gate reads. The suite proves this with a one-hour-old probe, which makes partition 1 refuse and
  reach the image reader **zero** times — and with its mirror, a 25-hour-old probe, which proceeds.
- **Each later partition** may not start until 24 hours after the previous partition's last ledger
  entry.

**Organisation exclusivity is an operator ATTESTATION, not a machine check.** The daily limit is
enforced per organisation and the provider exposes nothing that could confirm no other traffic is
using `qwen/qwen3.8-27b` under the same organisation. It is named here so nobody later mistakes it
for something the runner verified. It is part of what the renewed consent record must carry.

**The availability check is an availability check, and it GATES the corpus.** It runs through
the same bounded attempt engine as every other request — a rolling-window refusal gets its 2
attempts, a transport failure its 3 — and **only a success permits corpus transmission**.
Exhausted attempts are `availability_failed`, which is INVALID_INSTRUMENT: not a verdict, and
not permission to proceed. The first implementation gave it a single-shot path of its own and,
on a transient 429, recorded `degraded` and transmitted the corpus anyway — so the one question
the check exists to answer went unanswered while the photographs were spent regardless.
GPT-PM's closure review, MAJOR. The suite now asserts that a failed availability check reaches
the corpus image reader **zero** times.

One synthetic request at the head of a
partition, asking only whether the model is answering at all. It is not a capability measurement,
not a quality measurement, and it transmits no corpus photograph.

---

## 8. Four partitions, generated

Within each ground-truth kind, sources are ordered by ascending hex of
`sha256(source_photo_id)` and dealt round-robin with a per-kind offset:

```
partition = (index + offset) mod 4        offset 0 for canonical_single
                                          offset 2 for multiple
```

The offsets differ because 26 sources dealt four ways gives 7, 7, 6, 6 — not 6.5 each. With both
kinds at offset 0 the partitions would hold 14, 14, 12, 12 sources rather than 13 apiece.

**Generated counts, printed by `recog_so1_build_partitions.py` and asserted in the suite:**

| Partition | canonical_single | multiple | sources | observations |
| --- | --- | --- | --- | --- |
| 1 | 7 | 6 | 13 | 26 |
| 2 | 7 | 6 | 13 | 26 |
| 3 | 6 | 7 | 13 | 26 |
| 4 | 6 | 7 | 13 | 26 |
| **total** | **26** | **26** | **52** | **104** |

Both arms of a source always travel together. Ordering by the hash of the source id rather than by
manifest position makes the allocation a property of the corpus, not of the file: regenerating from
a **row-shuffled** input manifest produces byte-identical output, which the suite asserts.

**Blindness is preserved by emitting four separate files.** Partition membership is derived from the
ground truth, so it is never a column in the runner's input. Each partition manifest carries exactly
revision 1's closed schema — `observation_id`, `source_photo_id`, `arm`, `image_path`,
`expected_sha256` — and not one field more. The partition is named by which file the runner is
pointed at.

---

## 9. The request

Identical to revision 1 except where stated. Model `qwen/qwen3.8-27b`, `temperature` 0, `top_p` 1,
`seed` 20260907, `reasoning_effort` "none", strict `json_schema` structured output.

**`machine` becomes an enum derived from the sealed vocabulary** — the 71 canonical names plus the
sentinel `unknown` — `alternatives` gains `maxItems: 2`, and every `confidence` gains
`minimum: 0` / `maximum: 1`. The enum is **derived at build time**, never typed into the
configuration, because a hand-copied list could drift from the vocabulary the prompt is built from
and nothing would notice. The suite asserts the serialized body's enum equals exactly
`canonical_machines + [unknown_sentinel]`, and that dropping one name from the vocabulary changes
the request body.

**The honest consequence, recorded rather than buried:** this closes the off-list answer class by
construction on the Qwen side. Under revision 1's scorer an off-list name was a *disagreement*,
which pushes Δ toward PASS, so removing that class is conservative rather than favourable. The
asymmetry objection to this change was measured rather than argued: **Gemini's own off-list rate
across all 104 revision-1 observations is 0 of 104**, so there is no real asymmetry to create.

**`max_completion_tokens` is 256.** Two separate claims stand behind it, and each is proven by
the instrument that can actually prove it. The first implementation of this revision conflated
them: it called a solid-colour frame a *stress probe* and let the reply that produced — which is
the **shortest** possible answer, `unknown` with no alternatives — stand as evidence about the
**longest** one. GPT-PM's closure review rejected that, and it was right: no image can force a
worst-case answer, because the model chooses its own.

**Claim 1 — serialization headroom — is proven OFFLINE, and it is a hard gate.** Because
`machine` is now an enum, the longest answer this schema permits is fully determined: the three
longest canonical names in the sealed vocabulary, `alternatives` at its `maxItems` of 2, fixed
keys and punctuation. `worst_case_answer_bytes()` builds exactly that answer and measures it:
**243 bytes**. A UTF-8 byte is worth at least one token to any tokeniser, so 243 bytes bounds the
reply at 243 tokens, under 256. `serialization_headroom_ok()` refuses the run if that stops being
true — add a long enough name to the vocabulary and it fires, which the suite demonstrates.

The residual is stated rather than argued away: the bound assumes a confidence literal of at most
19 bytes, and JSON numbers have no length limit. A longer one lands on `finish_reason "length"`,
pre-registered as **unresolved, never retried** — at temperature 0 with a fixed seed a retry
returns the same truncation, and retrying until a reply becomes scoreable is sampling for a usable
result. Unresolved counts against the signal, so the residual fails conservatively.

**Claim 2 — that the provider ACCEPTS this request shape at this cap — needs a probe**, and
cannot be settled offline: Groq's output-cost estimator is undocumented and the only datum is that
4,096 produced `Requested 1072` against a limit of 1,000. Synthetic probes in **both** arm shapes
go through the ledger, and a receipt clears the cap only if it records both shapes, a successful
outcome for each, `cleared: true`, no probe finishing on `length`, and bindings to the
configuration, the prompt **and** the vocabulary. Binding the configuration alone would let a
probe obtained under a different prompt clear a request shape it never tested. See §0 — that
receipt does not exist, which is why the seal is empty.

---

## 10. What travels, and what does not

The request carries the frozen prompt, the frozen machine list and one image. It carries no Gemini
answer, no confidence, no ground-truth kind, no arm identity, no partition and no scorer-derived
field. This is asserted against the **serialized request body** with a capturing transport, not
inferred from which files the source happens to import.

**No corpus photograph is transmitted by anything in this revision** until renewed consent exists.
The stress probes and the availability check use synthetic solid-colour frames of the two real arm
dimensions and contain no person.

**Consent, and it needs its own contract.** The record committed before run #1 authorised that
manifest **once**, and run #1 consumed it. A second transmission of the same 52 photographs
requires a **new operator reaffirmation**. That is the operator's alone; no reviewer approval
substitutes for it.

Revision 1's consent evaluator cannot express that reaffirmation, and this is structural rather
than cosmetic — GPT-PM's closure review, MAJOR. Its schema is **closed**: it refuses any property
it does not know, so the organisation-exclusivity attestation §7 requires could not be recorded in
a record it would accept. And it carries a single `manifest_sha256`, which under four partition
files would bind one partition and force the consent record to be **rewritten between partition
days** — making "the operator consented" a thing this program edits on its own behalf.

`evaluate_consent_r2()` therefore defines a revision 2 contract. **One immutable record binds the
whole rerun**: this pre-registration by digest, **all four** partition manifests by digest, the
provider retention state, the verbatim operator statement, and
`organisation_exclusivity_attested: true`. A missing or false attestation refuses. A record
binding only some partitions refuses. A record in revision 1's shape refuses. Every one of those
refusals happens before any transport exists and before any image byte is read, and each has its
own test alongside a positive control.

---

## 11. Verification

Everything below runs offline. `py -3 scripts/dev/recog_so1_r2.tests.py` — **162 checks, no network
call, no real sleep**, cover the pre-aggregation-gate R2 runner alone. Every mutation is reverted
and the revert is itself asserted.

**Stale-count note, added after GPT-PM's Rosetta closure review flagged this section as
unreconciled with the aggregation-contract gate's own additions -- and deliberately carrying no
second number here after that same fix was itself found stale one round later (a specific count
written here drifted out of sync with the growing suite twice in a row, which is exactly the
failure mode a second copy of a moving number always produces):** the 162 below describe the
pre-aggregation-gate R2 runner alone and are unchanged. Sections (y) onward, added by the separate
aggregation-contract gate -- Contracts 1-5, B and D, plus every defect that gate's own mandatory
`review.js`/closure review found and had fixed -- are NOT counted here. The file's current whole
total lives in `core/DECISION_LOG.md`, the single place it is updated as the suite grows, not
retyped into this document a second time. This section stays deliberately scoped to the runner
alone rather than rewritten to describe both gates at once, for the same reason: the aggregation
contract already has its own artefact-digest entry in the provisional appendix below and its own
closure evidence in the decision log.

- the nine wait values, exactly, as totals
- exactly one sleep per transport call, structurally — not two fragments summing to the same number
- each wait term load-bearing by its own mutation: the 3,600 bound, the 60-second fallback, and
  Retry-After
- `1 + 26 + 17 = 44`, the 45th refused before transport, and the mutation that excludes the
  availability call producing 45
- a partition whose every request fails still stops at exactly 44
- a missing, malformed, or unknown-class ledger transmits nothing
- validity before arithmetic, by raising spies, with a control that proves the assertion can fail
- the coverage floor firing at 19 and not over-firing at 20, plus the mutation that makes 19 wrongly
  PASS
- the daily guard and the minute guard proven separate in both directions
- the decision table on the verbatim bodies run #1 received, including the identical-prefix trap
- the enum derived from the vocabulary, and the mutation that drops a name
- the four partitions generated, balanced, disjoint, and byte-identical under a row-shuffled input
- `(OTPM)` split by form, with the mutation that collapses it back to the code alone
- a raised `URLError`/timeout reaching the frozen 3-attempt row, and succeeding on a later attempt
- a failed availability check reaching the corpus image reader zero times, and its mirror
- the offline serialization bound, and the vocabulary mutation that makes it refuse
- every way a stress-probe receipt can fail to be proof — missing or wrong dimensions, a
  duplicated arm, an extra probe, a failed probe, `cleared: false`, a wrong prompt or
  vocabulary binding — each with a positive control, plus a round-trip showing the receipt the
  runner writes satisfies the runner's own validator, and a decoy-prompt mutation proving the
  receipt binds what was actually sent rather than a path constant
- a filled seal that omits the clearance receipt being refused
- the revision 2 consent contract: four partitions bound, exclusivity attested, and eight refusals
- revision 1's own seal still verifying

`py -3 scripts/dev/recog_so1.tests.py` — revision 1's suite, **61 checks**, still green and
untouched.

---

## 12. The seal is EMPTY, and that is the current state

<!-- SEAL -->
```json
{}
```

**This protocol is not sealed.** The block above is empty on purpose, and the runner refuses on an
empty seal rather than reporting that it verified nothing successfully.

An earlier draft of this document carried a filled seal while item 10 -- the stress probes -- was
still outstanding, and drew a distinction between "sealing the artefact list" and "clearing
transmission" to justify it. GPT-PM's closure review rejected that as going beyond the branch the
approved plan allowed, which said plainly: if the probes cannot run, the revision is **drafted but
not sealed**. It was the same defect this session keeps producing -- a claim wider than the check
behind it -- so the seal is empty until the check exists.

**What has to happen before this document may be sealed**, in order:

1. 24 hours of quiet since the ledger's last Qwen request of any class.
2. `--stress-probe` succeeds in **both** arm shapes, writing a receipt that binds the
   configuration, the prompt AND the vocabulary, and records `cleared: true`, exactly one probe
   per arm, each carrying its real frame dimensions, and no probe finishing on `length`.
3. Only then are the digests computed and written into the block above — **and the receipt itself
   is one of them.** `RECOG_SO1_STRESS_PROBE_RECEIPT_R2.json` is sealed alongside everything else,
   so the evidence the clearance rested on cannot be swapped afterwards without verification
   failing. `seal_binds_receipt()` refuses a non-empty seal that omits it, so this is a check
   rather than a step someone has to remember.

GPT-PM's round-2 MAJOR found both halves of this: the validator was comparing only the SET of
`arm_shape` labels, so three records labelled A, A, B would have satisfied it and a receipt with no
`dimensions` field at all passed — the positive fixture in the suite was itself structurally such a
receipt. A label is not evidence that the declared 1640×1082 and 1868×4000 frames were ever probed.
And the receipt sat outside the seal, so after sealing it could be replaced and `verify_seal()`
would notice nothing.

### Provisional digests — NOT a seal, and not read by any program

Recorded on 2026-09-08 so the artefact list is reviewable now. Nothing verifies against these; they
exist to show WHICH files the protocol consists of, and they will be recomputed at sealing time.
The eighteenth entry is the stress-probe receipt, which does not exist yet: it is what sealing
waits on, and it is sealed together with everything it clears.

Revision 1's `recog_so1_run.py` and `recog_so1_score.py` appear here because revision 2 **imports**
them -- the seal check, the consent machinery it extends, the closed manifest schema, the single
image-reading function, the reply parser and the entire hypothesis arithmetic are theirs. A file
that revision 2's behaviour depends on belongs in revision 2's seal, or editing it would change
this experiment silently.

```json
{
  "core/plans/RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv": "367af387ea68a2af340c97a935524738a0bb5fba71c83a2adfc4ad5feedee076",
  "core/plans/RECOG_SO1_PARTITION_1_R2_2026-09-08.csv": "bb687891b25d19cf0c19e6a6ebbf0f69dc7596d107dd49bf9c7aab59c7f0eae1",
  "core/plans/RECOG_SO1_PARTITION_2_R2_2026-09-08.csv": "e1a89bbcab4ebd96c051e966ef962a7137298d7060f37c0f59130cfb849be305",
  "core/plans/RECOG_SO1_PARTITION_3_R2_2026-09-08.csv": "02b497c6a527f53ef9e248161ef98db9464764aa532c15c34b17255354a27ffa",
  "core/plans/RECOG_SO1_PARTITION_4_R2_2026-09-08.csv": "de63e2e672f4fe0cb842e53084ffa9f856a3e5192f5d91e0be8eeb0afcc9d904",
  "core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv": "2e631f5c80011ef350ff483c4fd47bbefd9fc46f1faa7ca2c72d7954664921c3",
  "core/plans/RECOG_SO1_CONSENT.schema.json": "22dade06f4628c1f56d45c614607891b184394fc1d7fc852a5832b2e643e6cd6",
  "scripts/dev/recog_so1_prompt.txt": "d83b9b66c0c540617cb5c61d78181aa2917cd9c902ae745e8cd6d171ceb9f3af",
  "scripts/dev/recog_so1_vocab.json": "58d1886f38f72f096a62a504c6560b90e175f28f45df0466cc92b7a7e491973a",
  "scripts/dev/recog_so1_config_r2.json": "9bd27f548c0cd08de36aafe0f64a1bfbf1f9f0a4a5e0a84322410f14f69e3694",
  "scripts/dev/recog_so1_ledger.py": "c1c81208c4ebf631068ac196d0eb25d12c4157447a73a5e882e1d0e30148125e",
  "scripts/dev/recog_so1_build_partitions.py": "214c55bbda80e096c09477b446c7548fa64c7d553dde707fe950e621b44fe4d9",
  "scripts/dev/recog_so1_run.py": "0c4b14e6b28029ed7cbfd84ae346156890219abd5fe5fbbbe016ba63d7733e79",
  "scripts/dev/recog_so1_score.py": "24edecd877cbb196d0acf946eed95fa3f9eb5ca68bd46742d864ed92a0cf7c9f",
  "scripts/dev/recog_so1_run_r2.py": "de06224839a04b3e0c2b931f6f1ea0f433180405916db3d00133ab2aaaf89118",
  "scripts/dev/recog_so1_score_r2.py": "dda27e92250da56b873a82cc0c6d2b8d0a114657b0fb3fbd49b3523c1243b74c",
  "scripts/dev/recog_so1_r2.tests.py": "61e14d754d0bde09843b73a7df8f81be5eb1385dbc3b03b03c9d266d61e98949",
  "scripts/dev/recog_so1_aggregate_r2.py": "43c00fd78af796d9d3c72ac6ae4fa0dbf4116387785c53d7ac664448078d48eb",
  "core/plans/RECOG_SO1_STRESS_PROBE_RECEIPT_R2.json": "<computed at sealing time; this file does not exist yet and is what sealing waits on>"
}
```

Artefact 19, `scripts/dev/recog_so1_aggregate_r2.py`, is the aggregation-contract boundary between the
runner's four per-partition outputs and the scorer's one evidence bundle
(`recog_so1_score_r2.py`'s `main()` now runs entirely behind its `validate_bundle()`). Recorded here,
documentation only, exactly like every other entry above: nothing verifies against this table, and
this digest will be recomputed at sealing time along with the other eighteen.


**The raw photographs are deliberately not sealed here and are not in this repository.** They live
outside it and are identified by the digests in the observation manifest. The contact sheets in
`core/plans/recog_c1_sheets/` contain identifiable people, including two children whose faces are
legible: they must not be published, attached to an external review, or made public without the
operator's explicit say-so, and faces must be blurred first if they ever need to travel.
