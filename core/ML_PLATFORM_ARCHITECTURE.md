# SPTR — ML and continuous-retraining architecture

**Status: DESIGNED. Nothing in this document is implemented.**
Created 2026-08-17 (Track B of the forensic remediation programme).

This is one artefact rather than five, because the repository's convention is a small number of
long, evidence-carrying documents (`CODEMAP.md`, `PLATFORM_SCOPE.md`, `DECISION_LOG.md`) and five
cross-referencing files would have more index than content at this stage.

## Relationship to `core/plans/ML_STRATEGY_2026-08-11.md`

That document already exists and is not superseded. It answers **"are these three models good
enough, and which one is on the critical path?"** — with real measurements, a correct product
argument (§2's asymmetry table), and a correct refusal to put posture on the planner path.

This document answers a different question: **"what would have to exist for any of that to be
retrained, versioned, evaluated and promoted repeatedly rather than once?"** Registry, dataset
contracts, promotion gates, drift, rollback, and the module/process applicability sweep.

Where they overlap — the choice of first candidate — **the existing strategy wins**, because it is
backed by measurements this document did not repeat. §8 below defers to it rather than re-deciding.

One correction this workstream owes that document is recorded as **ML-F1** in §4.

---

## 0. The finding that shapes everything below

**SPTR has no product telemetry, and that is a deliberate decision recorded in a published privacy
policy.**

Measured, not assumed:

- `lib/core/diagnostics/debug_telemetry.dart` is the only event log in the codebase. Its own doc
  says why it is debug-only: *"This app holds health data, body-composition estimates and progress
  photographs. A 'log everything and upload it' switch belongs nowhere near a release build."*
  It is gated behind a `DEBUG_TELEMETRY` dart-define.
- The privacy policy (`app_en.arb: legalPrivacyBody`) states, as a promise to users: *"No
  advertising identifier is collected, and no third-party analytics or attribution SDK is built into
  the app."*
- There is no analytics dependency in `pubspec.yaml`.

Every ambition in this document past ML-0 depends on an event stream that does not exist. **ML-1 is
therefore not an engineering task — it is an operator decision with a privacy-policy consequence**,
and it is recorded here as a blocker rather than designed around.

What DOES exist, already collected for product reasons and already covered by the policy:

| Source | Collection | What it could support |
|---|---|---|
| Logged workouts | `workout_sessions`, `workout_logs` | sets, reps, weights, and `DifficultyRating` per exercise — a real, explicit outcome signal |
| Scheduled sessions | `scheduled_sessions` | planned-vs-performed, adherence |
| Scanner outcomes | `recognised_equipment` | model id, confidence, what it decided |
| Unrecognised machines | `machine_cards` | name, summary, `timesSeen`, the user's own photo |
| Generated exercises | `generated_exercises` | what the LLM produced, per machine and language |
| Programme enrolment | `programmes` | which template, which structure |

That is a narrow but genuine base. Two of these — `DifficultyRating` and `machine_cards.timesSeen`
— are **explicit** user signals rather than inferred ones, which matters enormously for label
quality (§5).

---

## 1. Module applicability matrix

39 feature modules exist under `mobile/lib/features/` (counted, not estimated). Assessed by what the
module actually does, not by what could theoretically be learned. The five classes below are a
**partition**: every module appears exactly once, and the counts sum to 39. That constraint is the
point — a matrix where a module can sit in two classes is a matrix nobody has to finish.

### ML_CORE — the module IS a model (3)

| Module | Model | Notes |
|---|---|---|
| `visual_equipment` | `equipment_v1.tflite` (MobileNetV2, 10-way) + Gemini vision | The only shipped trained model. Its **held-out** numbers are top-1 0.617 / top-3 0.835 (n=261), but those are a slice of the same web crawl it was trained on; measured against 30 real gym photos (B1) its three most confident answers were all wrong, up to 0.897. Ten classes serve a **69**-machine catalogue. |
| `form_check` | ML Kit Pose Detection + our rep counter | The pose model is a vendor's. The **rep counter is ours and has never been measured** — `ML_STRATEGY §1.2` shows the published accuracy figures were produced by a different algorithm (3D/bilateral/2-phase) than the one that ships (2D/one-side/4-phase). |
| `posture` | ML Kit Pose Detection + our metrics | Listed here rather than under "not justified" because it **is** an ML-derived system, and calling it otherwise would hide it. `ML_STRATEGY §3.4` decided it stays experimental and does not feed the planner — a single frame cannot be both profile and front-facing, so some reported metric is always read off the wrong projection. A deliberate stop, not a gap. |

### ML_AUGMENTED — deterministic authority, learned ranking inside it (5)

| Module | Where learning belongs |
|---|---|
| `personalisation` | `rankedForYouProvider`. Already the architecture ML wants: a ranker over an already-eligible list. |
| `programmes` | `ProgrammeBuildRequest.rank` — a **permutation** callback over candidates already filtered by role and safety. G-E's own doc calls it "the only door a learned signal comes through", and the type is what makes that true: a reordering cannot introduce an unsafe exercise. |
| `equipment` | Candidate ordering within a machine's exercise list. |
| `ai_coach` | An LLM surface already. The work is evaluation, not training — see §9. |
| `ai_planner` | **Contains no AI.** `plan_builder.dart` has zero references to `firebase_ai`, `generativeModel`, `http` or `Random` — it is a deterministic builder over the injury list, the weekly per-muscle set deficit and the deload verdict. Listed as `ML_AUGMENTED` because it is the natural place a learned dose signal would enter, and named here so nobody reads the directory name as an inventory entry. The user-visible title is "Today's plan" / "План на сегодня" — checked, because a module called `ai_planner` with no AI in it is exactly where an unsupported product claim would live, and in this case there isn't one. |

### RULE_BASED_WITH_ML_MONITORING — must stay deterministic; ML watches for drift (5)

| Module | Why it must not learn |
|---|---|
| `safety` | The eligibility layer is the product's authority. A learned safety verdict is not auditable, not explainable to a user, and not defensible to a clinician. ML may flag *anomalies* for review; it may never decide. |
| `catalog` | Canonical identity. §6. |
| `subscription`, `account_deletion`, `data_export` | Correctness is contractual and legal. There is nothing to learn, and a probabilistic answer to "was this account deleted" is not an answer. |

### ML_OPTIONAL — plausible later, no data today (10)

`body_comp`, `buddy`, `community`, `goal_photo`, `home` (suggestion ordering), `marketplace`,
`progress`, `recovery`, `social_feed`, `workouts` (progression).

### ML_NOT_JUSTIFIED — stated as a decision, not an omission (16)

`about`, `auth`, `celebrity_plans`, `cycle_aware`, `donor_wall`, `legal`, `licences`, `moments`,
`onboarding`, `profile`, `progress_photos`, `scanner` (the UI shell only — the model is in
`visual_equipment`), `sdk_export`, `settings`, `splash`, `voice`.

**A good `ML_NOT_JUSTIFIED` is worth more than a fake integration.** `cycle_aware` is the clearest
case: its phase notes are a published, citable model of a menstrual cycle, and replacing them with
a learned one would make a health claim nobody could audit.

**Partition check: ML_CORE 3 · ML_AUGMENTED 5 · RULE_BASED_WITH_ML_MONITORING 5 · ML_OPTIONAL 10 ·
ML_NOT_JUSTIFIED 16 = 39.** Matches the measured module count.

---

## 2. Business-process matrix

Processes, not modules. Assessed the same way.

| Process | Deterministic authority | ML opportunity | Feedback available today |
|---|---|---|---|
| Onboarding / profile setup | questionnaire | drop-off prediction | none (no telemetry) |
| Safety screening | `screen()` + eligibility | **none** — authority | n/a |
| Equipment scanning | catalogue lookup, then anchors | recognition | `recognised_equipment`, `machine_cards` |
| Exercise discovery | eligibility filter | ranking | none |
| AI Coach interaction | prompt + provider moderation | answer quality | none |
| Programme generation | `ProgrammeSpec` + validator | candidate ranking | `programmes` + completion |
| Workout execution | user input | — | `workout_sessions` |
| Progression | `progression.dart` rules | dose optimisation | **`DifficultyRating`** |
| Substitution | eligibility | ranking | none |
| Adherence / retention / churn | — | prediction | scheduled-vs-completed |
| Subscription conversion | Stripe | propensity | `subscription` |
| Content QA | manual | **review prioritisation** | `machine_cards.timesSeen` |
| Catalogue maintenance | manual | gap detection | `machine_cards` |
| Support, fraud, experimentation | — | — | none |

**Every row whose feedback column says "none" is blocked on the §0 decision.**

---

## 3. Lifecycle

```
product event → versioned event → schema validation → feature/signal
   → label/outcome → versioned dataset → training → offline eval
   → quality gate → SAFETY gate → challenger → shadow → promotion decision
   → champion → monitoring → drift/performance → retraining trigger → new challenger
```

**`TRAINED → PRODUCTION` is prohibited.** Promotion is always a separate, reversible decision.

**CI ≠ CD ≠ CT.** Code change → CI. Product release → CD. New data or drift → CT. CT never triggers
CD; it produces a *challenger*, and a challenger is not a deployment.

---

## 4. Registry and dataset contracts

Every production model version must resolve: `model_id`, `model_version`, `task`, `model_type`,
`training_code_commit`, `training_dataset_version`, `feature_schema_version`, `training_window`,
`hyperparameters`, `seed`, `evaluation_report`, `quality_metrics`, `safety_metrics`,
`artifact_hash`, `approval_status`, `deployment_status`, champion/challenger state,
`rollback_target`, `created_at`.

**No anonymous production models.** `equipment_v1.tflite` fails this: real measured metrics and a
training date in a README, but no registry entry, no artefact hash, no dataset version, and
`training_code_commit` is **unresolvable** — the pipeline lives at `D:\tools\equipment-model\`,
which is not a git repository (verified). The model in the APK cannot be traced to the code that
produced it.

### ML-F1 — the strategy document attributes v2's measurement to the shipped model

`MAJOR | FACT | documentation defect, no code change`

**Claim.** `core/plans/ML_STRATEGY_2026-08-11.md:36` describes "Equipment classifier v2 (29
classes)" as the "Bundled TFLite model behind ML Kit's labeler", and carries v2's real-world number
(top-3 5/18) in that row. v2 is not bundled and never was.

**Evidence.**
- `mobile/assets/models/` contains exactly two files: `README.md` and `equipment_v1.tflite`.
- `mobile/lib/core/assets/asset_bootstrap.dart:20`, `mlkit_visual_equipment_service.dart:19` and
  `mlkit_live_equipment_service.dart:31` all name `equipment_v1.tflite`.
- `mobile/assets/models/README.md`, v2 section: *"Not shipped. `equipment_v1.tflite` above is still
  what the app loads."*

**Failure scenario.** A reader plans from §1.1 and believes the app ships a 29-class model with a
trained `none` class. It ships a 10-class model that **cannot abstain at all** — which is precisely
B1's finding that "a confidence threshold does not repair this". The same conflation appears in
`ML_STRATEGY §3.2 E2(2)`, which proposes adding a "30th 'none of these' class" that v2 had already
trained four days before that document was written.

**Impact.** E2 looks partly done and is not started for the shipped artefact. A release decision
taken on §1.1 would be taken on the wrong model's capabilities.

**Required change.** Correct §1.1 to distinguish `SHIPPED` (v1, 10 classes, no abstention, B1
numbers) from `MEASURED_NOT_SHIPPED` (v2, abstention, 5/18). Do not restate the numbers — point at
the README.

**Acceptance test.** A `deployment_status` field per §4 that has to be filled in, so a document can
no longer describe an unshipped artefact as bundled without contradicting the register.

**This is the registry gap made concrete.** It is not a careless sentence — it is what happens when
two model versions exist, both are measured, and nothing in the repository records which one is
deployed. Every item in the field list above earns its place from a failure of this kind.

Every dataset must be reconstructable from source data, event schema, window, inclusion/exclusion
rules, labels + provenance, transforms, features, catalogue version, privacy filtering, quality
results, and a hash.

---

## 5. Label quality

Classify every signal. Do not call a click ground truth.

| Class | SPTR example |
|---|---|
| OBSERVATION | an exercise was displayed |
| IMPLICIT_FEEDBACK | the user opened it |
| PROXY_LABEL | the session was completed |
| EXPLICIT_FEEDBACK | **`DifficultyRating`** — the user was asked and answered |
| VERIFIED_LABEL | a scan the user corrected |
| DOMAIN_VALIDATED_LABEL | a clinician-reviewed exercise tag — **none exist** (D1, H3) |

Non-equivalences to hold: an impression is not a result; a click is not a successful exercise; a
programme start is not an effective programme; **a completed workout is not clinical safety**; a
liked AI answer is not a correct one.

**One dataset rule already exists and is correct.** `mobile/assets/models/README.md`: *"Do not train
on the operator's 30 photos. They are the only real-world sample in the project. Spending them on
training buys a slightly better model and destroys the ability to know whether it is better."*
`ML_STRATEGY §3.1` extends it — the 30 are already partly burned as a *selection* set, so M0 (a
second, independent, negatives-bearing set) blocks every number after it. That rule is the working
prototype of the dataset contract above: a named set, a stated purpose, and an explicit
prohibition. The gap is that it is enforced by a sentence in a README rather than by the pipeline.

Biases that apply here specifically: **exposure and popularity bias** (the For-You feed trains the
data that trains the For-You feed); **position bias**; **survivorship** (users who got hurt stop
logging); **delayed outcomes** (a bad prescription shows up weeks later); **missing-not-at-random**
(people skip `DifficultyRating` exactly when a session went badly).

---

## 6. Authority boundaries — non-negotiable

```
LEARNED PREDICTION  ≠  AUTHORITATIVE BUSINESS RULE
LEARNED PREDICTION  ≠  AUTHORITATIVE SAFETY RULE
MODEL OUTPUT        ≠  CANONICAL DATA IDENTITY
MODEL OUTPUT        ≠  TERMINAL USER MUTATION
PROVIDER MODERATION ≠  DOMAIN FITNESS SAFETY   (F026)
AI REVIEW           ≠  CLINICAL VALIDATION     (D1, H3)
```

The programme pipeline is the worked example, and G-E built it this way already:

```
ProgrammeSpec + authoritative constraints
        → candidate universe (eligibility-filtered)
        → ML ranking            ← the ONLY learned step, and a permutation
        → deterministic validation
        → canonical identity
        → current safety/eligibility at terminal action
        → programme
```

ML must never own: a safety override, canonical identity, force-fill, invented exercises, or a
bypass of `NO_SAFE_VIABLE_PROGRAMME`.

**F016 is an exception, not a precedent.** `MachineCard` output is safe because the TYPE cannot
carry an exercise id. That property does not generalise to any other AI surface, and each new one
must answer the F016 question for itself.

---

## 7. Drift, rollback, maturity

Monitor per model: **data drift** (feature distribution, device/camera/lighting mix, locale,
catalogue changes), **prediction drift** (confidence, class distribution, OOD/unknown rate),
**performance drift** where outcomes exist, and **safety drift** (rejection frequency, fallback
frequency, blocked-path attempts).

Triggers: scheduled, new-data volume, new verified labels, performance drop, data drift, concept
drift, catalogue change, taxonomy change, new equipment classes, model incident, safety incident,
product change, manual. **A trigger produces a challenger, never a promotion.**

Every production model needs a previous known-good version, a rollback procedure, a kill switch and
a defined degraded behaviour. Permitted fallbacks: previous model, deterministic baseline, rule
result, no recommendation, safe refusal, feature disabled. **Never invent content to avoid an empty
state** — that is `_fillDay` again, in a new costume.

Maturity: L0 static/manual · L1 telemetry · L2 reproducible datasets · L3 automated candidate
training · L4 champion/challenger + shadow + drift · L5 controlled continuous learning.

**Current, assessed per system rather than as a single number:**

| System | Level | Why |
|---|---|---|
| Equipment recognition | **L1-partial, not L0** | A real pipeline exists (`classes.py` → `fetch_roboflow.py` → `train_v2.py` → `eval_on_gym_photos.py`), with a held-out real-world set, a licence-filtered corpus, per-class holdout counts, and a documented leakage bug that the pipeline now *raises* on. That is more discipline than most L2 setups. It scores L1-partial anyway because the pipeline is **outside version control**, the datasets are unversioned, and there is no registry — so a training run is reproducible by the person who has that directory and by nobody else. |
| Rep counting | **L0** | Measured, but the thing measured is not the thing shipped (`ML_STRATEGY §1.2`). |
| Posture | **L0**, deliberately | `ML_STRATEGY §3.4`: off the path by decision, not by omission. |
| Gemini surfaces | **L0** | Vendor models, no evaluation harness. |
| Everything else | **L0** | No telemetry (§0). |

The equipment row is the one worth reading twice: **the hard part is already done and the cheap part
is missing.** Getting to L2 is version-controlling a directory and hashing a dataset, not building a
platform.

Safety-adjacent models should deliberately stop at human-gated L3/L4.

---

## 8. First CT candidate — already decided; this section does not re-open it

`ML_STRATEGY §2` and `§3.2` already selected **equipment recognition**, on better evidence than this
document gathered, and set the sequence `M0 → E1/E2 → E3 → E4` with M0 (an independent held-out set
with negatives) blocking everything after it. That stands.

Two things this workstream adds rather than replaces:

**1. The candidate comparison the existing strategy did not run**, because its scope was the three
existing ML features rather than the whole product:

| Candidate | Labels today | Risk | Verdict |
|---|---|---|---|
| Equipment recognition | `recognised_equipment`, `machine_cards`, user-correctable | low, non-clinical | **first, per `ML_STRATEGY`** |
| Content QA prioritisation | `machine_cards.timesSeen` | very low | **cheapest useful step, and not a model at all** |
| Recommendation ranking | none | medium — feedback loops (§5) | blocked on §0 |
| Progression | `DifficultyRating` | **clinical-adjacent** | not first, regardless of data |

Content QA prioritisation deserves the note: ranking missing catalogue content by how often users
actually met the machine uses data already collected, needs no telemetry decision, no model, no
promotion gate — and it feeds the corpus gap the README calls "the next gap that matters"
(`ab_crunch_machine`, 31 crops, the machine that reads `treadmill` at 0.940).

**2. The correction that the CT sequence must start further back than `M0`.** M0 is a *data*
prerequisite. There is a *platform* prerequisite before it that `ML_STRATEGY` did not have in scope:
ML-F1 shows the project cannot currently say which model is deployed. Running M0 against "the
model" is ambiguous until that is fixed — and fixing it is a registry entry, not a project.

**D3 is not reopened by this.** The existing decision stands until new evidence clears a promotion
gate. A platform's existence is not evidence about a model.

---

## 9. AI Coach

Evaluate continuously; do not fine-tune on thumbs. Dimensions: intent, retrieval/grounding, answer
relevance, hallucination rate, canonical grounding, domain safety, refusal quality, downstream
usefulness. Provider moderation (F026) is configured and closes none of these.

---

## 10. Privacy

Sensitivity classes: health answers and injury/safety answers (**special category**; currently
device-only by design and must stay so unless a separate decision says otherwise), camera images,
workout history, account, payment, support.

Rules: purpose limitation, minimum necessary, retention, access control, pseudonymisation,
**deletion propagation into datasets** (a deleted account must be removable from a training set, or
the dataset becomes a shadow copy of data the user erased), and lineage.

**Do not collect a sensitive signal because it improves a metric.** The §0 promise is the
constraint, and changing it is the operator's call.

---

## 11. Roadmap and definition of done

| Phase | Content | Blocked by |
|---|---|---|
| ML-0 | Inventory + applicability (**this document**) | — |
| ML-1 | Event contracts + telemetry | **§0 operator/privacy decision** |
| ML-2 | Dataset + label contracts | ML-1 |
| ML-3 | Reproducible training | ML-2 |
| ML-4 | Model registry — start by giving `equipment_v1` an entry and correcting ML-F1 | **nothing; do now** |
| ML-5 | Evaluation + promotion gates | ML-4 |
| ML-6 | First CT pipeline (equipment recognition) | ML-3, ML-5 |
| ML-7 | Champion/challenger + shadow | ML-6 |
| ML-8 | Drift-triggered retraining | ML-7 |
| ML-9 | Wider adoption | ML-8 |
| ML-10 | Operational governance | ML-9 |

Track separately and never collapse: DESIGNED · INSTRUMENTED · TRAINING_REPRODUCIBLE ·
EVALUATION_READY · CHALLENGER_READY · SHADOW_VALIDATED · PRODUCTION_READY ·
CONTINUOUS_RETRAINING_OPERATIONAL.

`CONTINUOUS_RETRAINING_OPERATIONAL` may be claimed only with evidence that approved data is
captured, labels exist, datasets are reproducible, candidate training runs, gates run, a candidate
**cannot** overwrite the champion directly, promotion is controlled, the deployed version is
observable, rollback works, and monitoring feeds the next decision.

**Current status: ML-0 DESIGNED. All others NOT STARTED** — with the honest qualification that
equipment recognition already has, outside version control, a substantial part of what ML-3 asks
for (§7).

**Next ML milestone: ML-4 for `equipment_v1` only.** It is the one step with no blocker, it makes
the single shipped model traceable, it corrects ML-F1, and it costs a registry entry rather than a
platform. Everything else waits on either §0 (an operator privacy decision) or M0 (a morning of
photography), and neither is an engineering task.

---

## 12. What this document does not authorise

No gate is opened here. No model is trained, no telemetry is added, no promotion is made, and D3,
D1 and H3 are untouched. Specifically not authorised: collecting any new user signal; treating any
statement in this document as evidence that a model works; and treating the existence of a
retraining design as progress toward clinical validation, which it is not and cannot be.
