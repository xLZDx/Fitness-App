# RECOG-SO1 — pre-registration

**Status: frozen 2026-09-07, before any Qwen output existed.** Every threshold, definition and
scoring rule below was fixed before the first real image could be sent, and every artefact the
experiment depends on carries a digest in the seal at the end of this document. A criterion chosen
after seeing the data is not a criterion; this file exists so that nothing in SO1 can still be
chosen.

Authorising plan: `fitness_app-2026-09-07T16-22-42-159Z-2801e8`, hash
`f6d7183bed7bec69a873c271fb0cd203e8339f80ac5727a1aa00d5576a73774d`, GPT-PM `VERDICT: APPROVE`,
0 BLOCKER / 0 MAJOR.

---

## 1. The question

RECOG-C1 established a negative result: the recogniser's own self-report carries **no** abstention
signal. Across 104 observations it answered `unknown` exactly zero times, and neither the stated
confidence, nor the lead over the second candidate, nor the number of alternatives offered, nor the
framing separated frames that have a single right answer from frames that do not. Whatever makes a
recogniser stay silent has to come from outside the model's opinion of itself.

**SO1 asks whether a second, independent model supplies it.** Concretely: do two different models
disagree with each other more often on frames where no single machine is the subject than on frames
where one is?

SO1 is **a pre-registered hypothesis test, not the beginning of an ensemble implementation**
(GPT-PM's framing, adopted verbatim). Nothing in production changes on the strength of it. A PASS
earns the right to design an abstention mechanism in a later gate; it does not authorise one.

## 2. The dataset, frozen

The 52 RECOG-C1 source photographs, each in two arms — A the full frame, B the scanner's crop —
giving 104 observations. The set is fixed by
`core/plans/RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv`, whose every row carries the expected
sha256 of the image bytes. The runner re-hashes each image immediately before its own request and
refuses on any mismatch: recording the digest of what was already sent is forensics, not a
frozen-dataset rule.

Ground truth is the frozen `RECOG_C1_GROUND_TRUTH_2026-09-05.csv` and is **not modified, extended or
re-adjudicated** by SO1.

**Clustering.** 104 observations are 52 scenes seen twice, not 104 independent samples. All
inference clusters by source photograph. The frozen ground truth licenses a single label per source:
all 52 carry the same `gt_kind` in both arms.

| | unique source photographs |
| --- | --- |
| `canonical_single`, arm A | 26 |
| `canonical_single`, arm B | 26 |
| `multiple`, arm A | 26 |
| `multiple`, arm B | 26 |

## 3. Consent and privacy, decided before the run

The corpus is the operator's own photographs of their own gym. A per-photograph survey
(`core/plans/RECOG_SO1_PEOPLE_SURVEY_2026-09-07.csv`) records that **21 of 52 contain real people**,
**22 contain printed human figures** that are not people — wall murals, banners, and photographs of
models on the machines' own instruction placards — **10 contain both**, and in **5 a face is fully
legible**: a trainer and two children.

**Privacy-selection policy, fixed here rather than after the numbers are visible.** Selection is
**source-level**: a photograph enters the `people_free_only` subset only if **both** of its arms are
people-free. This keeps the paired design intact; observation-level filtering could admit a full
frame containing a person whose crop excludes them, changing the arm populations.

**The operator's decision, verbatim:** *"весь корпус (52 фото, максимальная статистическая сила)"* —
the whole corpus, 52 photographs, maximum statistical power. Recorded 2026-09-07.

**Provider retention state at the time of consent**, recorded from the operator's own Groq console
because it is not readable from the API — there is no data-controls endpoint and `/models` carries
no retention field:

- **Global ZDR: Enabled** — *"input and output data will not be logged, and features that require
  data storage will be disabled for members of your organization"*.
- Inference APIs ZDR: own toggle off, overridden by Global ZDR. The same page records that Groq may
  otherwise store inputs and outputs for up to 30 days for reliability and compliance.
- Batch storage: **Off**. Fine-tuning & LoRA storage: **Off**.

**The runner enforces this rather than trusting anyone's restraint.** `RECOG_SO1_CONSENT.json` must
satisfy `RECOG_SO1_CONSENT.schema.json`: `decision` is a closed enum
`whole_corpus | people_free_only | deny`; a `deny`, an unrecognised value, a missing field, an
unparseable file, an absent file, an undefined property, or a binding to the wrong manifest or the
wrong pre-registration each REFUSE — evaluated **before any image byte is read and before the HTTP
client is constructed**.

**Both halves of that claim are proven, and the second one had to be added.** GPT-PM's closure review
pointed out that zero transport constructions and no output file do NOT establish that no image was
opened: a runner could read the file, then refuse, and satisfy both assertions. Every image read now
goes through the single function `read_image_bytes`, and the suite replaces it with one that raises
on any call. A `deny` record, an absent record and an unrecognised decision each finish with an
image-read count of **zero**, a transport count of **zero**, and no output file. A positive control
accompanies it — an authorised run must reach the reader exactly twice on the two-observation fixture
— because a counter that never counts proves nothing.

## 4. What the second model is asked

**The frozen SO1 prompt is production's own prompt, byte for byte** — extracted from
`functions/src/ai_equipment_recognition.ts`'s `buildPrompt()`, not rewritten. A differently-worded
question would confound every disagreement with the wording, and the experiment would be comparing
two prompts rather than two models.

The request carries the frozen prompt, the frozen canonical machine list, and **one image**. It
carries no Gemini answer, no confidence, no ground-truth kind, no arm identity and no scorer-derived
field. This is not claimed from the absence of those files in the runner's source — that would prove
only that those particular files were not opened. The runner's input schema is **closed** (exactly
`observation_id`, `source_photo_id`, `arm`, `image_path`, `expected_sha256`; any other column
refuses), and the test suite inspects the **serialized request body** through a capturing transport.

## 5. Configuration, pinned

`scripts/dev/recog_so1_config.json`, sealed below. Model `qwen/qwen3.8-27b`; `temperature` 0;
`top_p` 1; `seed` 20260907; `max_completion_tokens` 4096; `response_format` a **strict
`json_schema`**; `extra_body` `{"reasoning_effort": "none"}`.

**The response format is strict structured output, and the objection to it was mine and was wrong.**
An earlier revision of this document used `{"type": "json_object"}` and justified it from the model
metadata, which on 2026-09-07 returned `supported_features` `['tools','json_mode','reasoning']` — no
structured outputs. GPT-PM read Groq's documentation as saying otherwise. Rather than choose between
two secondary readings, the primary source was probed with **synthetic images only**: that metadata
list is incomplete, and `json_schema` with `strict: true` returns HTTP 200. The probe used the
**exact** schema this experiment freezes — nested `alternatives` array of objects, every property
required, `additionalProperties: false` at both levels — together with the real frozen prompt read
from `recog_so1_prompt.txt`, because testing a simplified two-field stand-in and shipping the real
one is a claim broader than its check. Result: HTTP 200,
`{"alternatives": [], "confidence": 0.0, "machine": "unknown"}`, 1686 prompt / 21 completion tokens.

**One honest consequence, recorded rather than left implicit.** Strict mode requires `alternatives`
to be *present* in every reply, where production's own contract allows it absent. That is an
envelope difference, not a measurement one: an empty array is the natural encoding of "no
alternatives", the scorer never reads the field, and `machine` is an unconstrained string, so the
schema cannot steer *which* equipment is named. What it removes is the parse-failure class, which
would otherwise be scored `unresolved` and pushed against the signal. Strictly speaking a change of
decoding constraint *can* move a result — constrained decoding alters generation probabilities — and
that is precisely why it is permissible here and would not be later: **no real observation exists
yet.** After the first corpus reply exists, this field is frozen like every other.

**Configuration-class statuses ABORT the whole run.** 400, 401, 403 and 404 record the current
observation with its failure class, make no further request, and exit reporting a *stopped* run. The
request shape is frozen and identical for all 104 observations, so such a status is a property of
the request, never of the photograph in front of it; continuing would burn the entire corpus against
a request the provider already rejected and produce 104 unresolved observations that look like data.
This was a defect found in this document's own already-closed gate: the text said a 4xx stops the
run and the runner recorded it and carried on. Under strict mode there is also no best-effort
schema-mismatch 400 to confuse with a configuration 400, so the rule is a plain status check with no
provider-specific error-text classifier. 429, 5xx and transport errors are **not** in this class.

**Pacing is derived from a measured limit, not from a response header.** The enforced ceiling is
**input** tokens per minute and it is **7000**, read from the body of a real 429:
`Limit 7000, Used 6671, Requested 2096`. The `x-ratelimit-limit-tokens` header says 8000; an earlier
revision recorded that number and paced at 14 s, which at the measured worst case of 1813 prompt
tokens is 7778 input tokens/min — over the real limit, and the run would have spent itself in
continuous 429s. Frozen at **20 s between requests**: 3.0 req/min = 5439 input tokens/min, inside
7000 with headroom. 104 observations ≈ 35 minutes. The retired 8000 is kept in the config beside its
replacement rather than deleted, so nothing hides that the pacing was once wrong.

**Pacing applies to every observation that actually sent a request, including a failed one.** A
request refused with 429 still spent its input tokens; the bucket does not care that the reply was a
refusal. The first revision of this change paced only the successful path, so an observation whose
three attempts were exhausted on 429s went straight to the next photograph after the 5 s + 10 s
retry backoff alone — 15 s, under the frozen interval, at exactly the moment the provider had said
the bucket was empty, and one 429 could then cascade into a run of them. That would manufacture
unresolved observations, which this document's own conservative rule counts AGAINST the signal, for
transport reasons rather than recognition ones. Where the response carries a `Retry-After` longer
than 20 s, the provider's number wins. An observation whose image is missing or fails its digest
check sends nothing and is not paced; the abort path is not paced either, because the run ends there.

**`reasoning_effort` is FROZEN at `none`, not pending.** An earlier revision of this document marked
it UNVERIFIED and deferred it to a synthetic preflight. GPT-PM's closure review rejected that, and
correctly: a value still to be chosen after a preflight is a **methodological degree of freedom left
open after pre-registration** — had the preflight rejected it, someone would have been picking a
replacement once the experiment was supposedly frozen. No probe is needed to settle it, because
Groq's API documentation specifies `reasoning_effort` for `qwen/qwen3.8-27b` with the values
`none | default | low | medium | high` and documents `none` as instruct / non-thinking mode.

`none` is GPT-PM's ruling and its reasoning is adopted here: it is the closest methodological
analogue to the production Gemini recognition path, which runs with thinking disabled, and it keeps
reasoning-token behaviour out of what is meant to be a visual-classification second opinion.

**If the provider later stops accepting this frozen configuration, SO1 STOPS** and requires a new
pre-registration revision. A 4xx is a hard experiment failure — never permission to edit the config
in place and carry on, which is precisely the freedom this document exists to remove.

**Retry policy.** At most 3 attempts. Retried: 429, 5xx, connection errors, read timeouts — they say
nothing about the model's opinion, and they never abort the run. **Never retried:** 4xx configuration
errors, which stop the run outright as described above, and any well-formed
HTTP 200 whose body will not parse. At temperature 0 with a fixed seed a retry returns the same
answer anyway, and retrying until a reply becomes scoreable is sampling for a usable result — the
exact tuning this document forbids. On exhaustion the observation is recorded `unresolved` with its
failure class; it is never dropped and no value is substituted.

## 6. Definitions

Comparison is on **resolved equipment identity**, never on raw strings. The frozen vocabulary maps
`plyo box` and `aerobic step` to the same `plyo_box`, and `parallettes` and `push-up blocks` to the
same `parallettes`; scoring the strings would manufacture two disagreement classes that are
agreements. Raw strings are still reported for audit. Canonicalisation is frozen before any output
exists and is **derived** from production's `CANONICAL_MACHINES` and alias registry by
`recog_so1_build_vocab.py`, a port of `EquipmentAliasIndex.normalise` and `resolve` passes 1–2,
cross-checked at test time against the shipped TypeScript port.

| symbol | definition |
| --- | --- |
| `D` | the two models do not name the same equipment on an observation |
| `D_multiple` | `D` over observations whose frozen ground truth is `multiple` |
| `D_canonical` | `D` over observations whose frozen ground truth is `canonical_single` |
| `Δ` | `D_multiple − D_canonical`, in percentage points |

**`unknown` is an abstention and is scored as one.** If exactly one model answers `unknown`, that is
a disagreement; if both do, it is agreement.

**An invalid reply is never an abstention, and an unresolved observation counts AGAINST the signal.**
In the `multiple` stratum an unresolved observation is scored as agreement (lowering `D_multiple`);
in the `canonical_single` stratum as disagreement (raising `D_canonical`). Both push `Δ` down. A run
that fails to obtain answers must not be rewarded with a result.

## 7. The bars — GPT-PM's, adopted wholesale

**Power floor, checked first and able to override everything below it.** Fewer than **20 unique
source photographs** in either ground-truth kind of either evaluated arm ⇒ **INCONCLUSIVE**, however
good the point estimates look. The whole corpus gives 26 and 26 and clears it; the `people_free_only`
subset would have given 16 and 15 and could not have produced a verdict at all.

**PASS requires all five:**

1. `D_multiple ≥ 60%`
2. `D_canonical ≤ 20%`
3. `Δ ≥ 40 pp`
4. the direction holds separately in **both** arms
5. source-photo-clustered permutation test, one-sided `p < 0.05`

**FAIL if any one of:**

1. `D_multiple < 50%`
2. `D_canonical > 25%`
3. `Δ < 25 pp`
4. Qwen canonical top-1 accuracy `< 80%`, or more than **10 pp** worse than Gemini's on the same set
5. the direction reverses in either arm

**Anything else is INCONCLUSIVE**, which is a real outcome — and it is **not permission to tune on
these same 52 photographs**. A threshold chosen after seeing them is not a threshold.

## 8. Reporting surface

`D`, `D_multiple`, `D_canonical`, `Δ`; the clustered permutation `p` over 20 000 permutations seeded
at 20260907; per-arm slices; Qwen and Gemini canonical top-1 accuracy against frozen ground truth;
`unknown` rates for both models; every disagreement pair with both raw strings and resolved ids;
parse failures, retries and transport errors counted separately; and unique source counts per kind
per arm.

## 9. Evidence that the guards are load-bearing

`scripts/dev/recog_so1.tests.py`, 51 checks, **no network call anywhere**. It shows the scorer
reaching PASS, FAIL and INCONCLUSIVE on synthetic data with known answers, plus FAIL on a single-arm
reversal and on an incompetent second model; it shows twelve distinct consent refusals; it shows a
one-byte image change and a mutated prompt, vocabulary or configuration each refusing with no
request sent. Three guards are shown **failing under mutation and passing on the real code**:

- removing the power floor turns the underpowered fixture into a PASS;
- weakening the clustering to per-observation collapses the permutation `p`;
- counting an unresolved observation as disagreement turns a run that mostly did not work into a
  significant result in the hypothesised direction.

It closes with `test_the_test`: a `verdict()` stubbed to always return PASS, and a consent gate
stubbed to always authorise, must each be rejected by every expectation written against them.

---

## Sealed artefacts

Digests taken 2026-09-07, before any real Qwen output existed. The runner re-hashes every entry at
start-up and refuses to send anything if one has changed.

<!-- SEAL -->
```json
{
  "core/plans/RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv": "367af387ea68a2af340c97a935524738a0bb5fba71c83a2adfc4ad5feedee076",
  "core/plans/RECOG_SO1_PEOPLE_SURVEY_2026-09-07.csv": "a3c944ef280a81765dcae8d3975ca9d9122f99605cdf5f7920da4920a758b560",
  "core/plans/RECOG_SO1_CONSENT.schema.json": "22dade06f4628c1f56d45c614607891b184394fc1d7fc852a5832b2e643e6cd6",
  "scripts/dev/recog_so1_prompt.txt": "d83b9b66c0c540617cb5c61d78181aa2917cd9c902ae745e8cd6d171ceb9f3af",
  "scripts/dev/recog_so1_vocab.json": "58d1886f38f72f096a62a504c6560b90e175f28f45df0466cc92b7a7e491973a",
  "scripts/dev/recog_so1_config.json": "60fe272d5e7db7c9c32323f7f3bf6dc4b1662eff5d7322c2f6221a85110487c6",
  "scripts/dev/recog_so1_build_vocab.py": "da2bb7998ce51be9d9a397b0de98c2962f33f3c6f9394d0324181f68ddf4ca1b",
  "scripts/dev/recog_so1_build_prompt.py": "bb319229a476946ed4ceecbc609d093a8268fdc3104735ddd7d9dca8ea45d96e",
  "scripts/dev/recog_so1_build_manifest.py": "8a8f81ce93f89cf147d507d5bcf6cc3e9ad2a4a1c02e6595ff868d87dda272d6",
  "scripts/dev/recog_so1_run.py": "0c4b14e6b28029ed7cbfd84ae346156890219abd5fe5fbbbe016ba63d7733e79",
  "scripts/dev/recog_so1_score.py": "24edecd877cbb196d0acf946eed95fa3f9eb5ca68bd46742d864ed92a0cf7c9f",
  "scripts/dev/recog_so1.tests.py": "6f01d97fbba5b3a62df24f633a6c6a16cbbd1dd0db70ecbd38df9d40d074bad5"
}
```

**The raw photographs are deliberately not sealed here and are not in this repository.** They live
outside it and are identified by the digests in the observation manifest. The contact sheets in
`core/plans/recog_c1_sheets/` show what was measured and must not be published, attached to an
external review, or made public without the operator's explicit say-so; blur faces first if they
ever need to travel.
