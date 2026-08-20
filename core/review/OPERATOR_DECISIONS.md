# Everything waiting on you

**Eight decisions remain open; one (P1) has been answered.** None of the nine was engineering's to
decide, and none could be closed from inside this repository without a named artefact from you.
Each row below is answerable in one sentence without opening another document; the research is
finished and cited, not summarised again here.

> **This file is not a decision record.** Recording a decision means a file at
> `core/decisions/<id>.md`, written by you. `core/decisions/gym-webhook-disclosure.md` is the first
> one, recorded 2026-08-21 from a live exchange with you while porting Gate F (see P1 below) — a
> decision record authored by engineering on its own say-so, with no such exchange behind it, would
> be exactly the forgery the ledger exists to catch, which is why every other row here still has
> none.

---

## The short version

| ID | Question | Recommended | Reversible? |
|---|---|---|---|
| **N05-A** | Accept the documented extraction risk for this release? | **Yes, accept** | Total |
| **N05-B** | Configure a platform budget alert? | **Yes, do it** | Total |
| **N05-C** | Enforce App Check? | **Not yet** — sequence it after the first Play upload | Total |
| **N04** | Who is the customer for an equipment report? | **The user**, for now | High |
| **P1** | Is a gym's webhook a disclosed processor? | **ANSWERED 2026-08-21: keep it, disclose it (P1-A)** | -- |
| **S1** | Where does the pipeline source live? | **Separate clean repo, evidence tree frozen** | High |
| **S2** | May the corpora leave this machine? | **No** | One-way if yes |
| **S3** | Does the scanner programme continue? | **Pause, preserve** | Total |
| **RF** | The exposed Roboflow key | **Revoke without replacement** | Total |

---

## N05 — anonymous access to the video library

Three independent actions, not one plan. They address different threats and can be taken in any
order. Full analysis: [core/review/N05_DISPOSITION.md](core/review/N05_DISPOSITION.md), §7 and §8.

### N05-A · Accept the residual extraction risk

**Recommended: accept.** Full extraction of the licensed library costs an attacker **$0.077–$0.31**
in serving, against a library this repository records as acquired for **$329**. That is roughly a
thousandfold arbitrage — and at a user base of 5–10 App Distribution testers it is still the right
trade, because every option that would reduce it is either undeployable today (N05-C) or costs more
than it buys (identity requirement, refused).

*Risk if you do nothing:* identical. Doing nothing **is** this option; the only difference is
whether it was chosen.
*What changes after yes:* nothing in the product. The row stops asking.

> **AUTHORIZE N05-A:** *"Accept the documented residual extraction risk for the current release.
> Revisit when the app ships through Google Play."*

### N05-B · Platform budget alert

**Recommended: configure it.** Free, no code, no user impact, fully reversible. Whether one already
exists is genuinely unknown — nothing in this repository reads a billing budget, so the first action
is to go and look.

**What it does not do:** it cannot detect the extraction that N05-A accepts. An alert set high enough
to survive normal operation will never fire on a $0.31 event. It is insurance against the *other*
scenario — a Sybil-amplified redemption day priced around $44,000 — and the two must not be read as
one control.

> **AUTHORIZE N05-B:** *"Configure a GCP budget alert at $X/day for the project. Notification only,
> no automatic action."*

### N05-C · App Check enforcement

**Recommended: not yet, and it is a sequence rather than a date.** Enforcing today locks out the
entire current population — App Distribution testers attest as strangers by design — and locks out
no attacker, because there are none yet. The real precondition is stricter than "at Play launch":
the Play App Signing SHA-256 **does not exist until the first bundle upload creates it**, so the
instruction cannot be executed on launch day.

The order is: first bundle upload → register the Play App Signing SHA-256 with App Check →
accumulate real installs → read the attested share → then decide. **Nothing in this repository will
remind you**; the only automated tripwire on N-05 watches a sentence in the privacy policy, and
shipping to Play changes no source file. This is a calendar item owned by a person.

> **AUTHORIZE N05-C (later):** *"After the first Play bundle upload and once real attestation
> telemetry has been observed, set `APP_CHECK_ENFORCED_VIDEO=true` and redeploy."*

---

## N04 — who is the customer for an equipment report?

Full analysis: [core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md](core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md).

The question was framed as "should a report require a verified gym association". Measuring it showed
that is the wrong question, because there is nothing to associate with: `gyms/` has **no writer
anywhere in the repository**, the onboarding tooling `firestore.rules` refers to does not exist, and
the only caller never supplies a `gymId`. The real question is one level up.

**Recommended: the user is the customer, for now.** The code is built for the gym, behaves as though
the customer is the user, and the UI claims the first. Choosing "the user" makes the behaviour and
the claim agree at the lowest cost and forecloses nothing: if gym onboarding ever ships, the
association question returns properly, with something real to associate to.

**Requiring membership is refused** on its own merits: it would mean building an onboarding domain,
a membership model, a verification signal, and a migration — before the feature has one real
customer — and it would put a handshake in front of the `unsafe` report (frayed cable, cracked
plate, missing safety pin), which is the report the whole feature exists for.

*What changes if accepted:* the report copy stops promising forwarding, and P-1 resolves to "remove
the dispatch".
*What stays if rejected:* today's behaviour, plus an open question that nothing will re-raise —
`gyms/` becoming non-empty is a console write, and no test, CI check or guard is keyed to it.

> **AUTHORIZE N04:** *"The user is the customer for an equipment report. Reports stay inside SPTR;
> gym routing is not a product commitment."*

---

## P1 — is a gym's webhook a disclosed processor? — ANSWERED: P1-A

**AUTHORIZED P1-A, 2026-08-21** (`core/decisions/gym-webhook-disclosure.md`), surfaced live while
porting Gate F (`gym identity`, MRD-02) onto `master`: Gate F is the first client code to ever
supply a real, non-`"unknown"` `gymId` on a report, which is what turns the dispatch below from
unreachable to reachable, and a Codex review of that port raised this exact question again before
it landed. The operator chose keep-and-disclose over remove. `scripts/legal/legal_text.py` (the
single canonical source for both `.arb` locales and `public/privacy.html`/`terms.html`, per
`scripts/legal/build_legal.py`) now names the gym as a conditional third *recipient* of report
contents specifically -- not a "processor" in the GDPR Article 28 sense, because it receives the
report to fix its own equipment for its own purpose, not on this app's instructions -- and states
plainly that this app does not control what a named gym does with what it receives. Full
purposes-and-means reasoning: `core/decisions/gym-webhook-disclosure.md`.
`core/CURRENT_STATE.md`'s `gym-webhook-disclosure` row is `CLOSED`, with an invariant
(`gym_webhook_disclosure_stays_honest`, `scripts/review/state_ledger.py`) that reopens it if the
disclosure regresses on any of six checked texts (`legal_text.py` and `public/privacy.html`, each in
both locales, plus the generated `legalPrivacyBody` key in both `.arb` files), if the webhook
dispatch in `functions/src/index.ts` is removed, or if the decision record disappears.

Surfaced while measuring N-04, and genuinely new. The analysis below is preserved as the record of
what was actually weighed, not rewritten after the fact.

The published privacy body says: **"Two processors are involved, and no others: Google … and
Stripe."** `reportEquipment` looks up `gyms/{gymId}.maintenanceWebhookUrl` and POSTs report contents
to it — a third recipient.

**What leaves SPTR today**, measured field by field after this pass removed the reporter's uid:

| Field | Class |
|---|---|
| `equipmentId`, `gymId`, `fault`, `reportedAt` | technical metadata |
| `reportId` | pseudonymous identifier, resolvable only by the operator |
| `note` | **user-authored free text** — can contain anything the reporter typed |
| ~~`Reporter: <uid>`~~ | **removed this pass**; the copy promised a pull model and the code was a push |

**Recommended: remove the dispatch (Option B).** It is harmless today only because no gym document
exists, and it stops being harmless the moment one does, with no code change in between. Under the
recommended N04 answer there is no recipient to disclose. Removing it is total, reversible, and
deletes the question rather than documenting it.

**Option A — keep it — is legitimate**, but then the privacy copy must name gym-selected endpoints as
recipients of report contents *before* any gym is onboarded, and the free-text note must be
described accurately.

*Security note, independent of the product choice:* the endpoint had no validation of any kind. This
pass added an `https:`-only check and `redirect: "manual"`, because report contents including
user free text should not travel in cleartext regardless of who the customer is, and a scheme check
that redirects can undo is decorative. That is engineering's and is done.

> ~~AUTHORIZE P1-B: "Remove the gym webhook dispatch. Reports stay inside SPTR."~~
> **AUTHORIZED P1-A, 2026-08-21:** *"Keep gym dispatch and amend the privacy copy to name
> gym-selected endpoints as recipients of report contents, including the free-text note, before
> onboarding any gym."* See `core/decisions/gym-webhook-disclosure.md` for the full record.

---

## S1 / S2 / S3 — the recovered scanner pipeline

Three independent decisions. Full analysis:
[core/ml/SCANNER_PROVENANCE.md](core/ml/SCANNER_PROVENANCE.md).

### S1 · Where the pipeline source lives

**Recommended: an immutable recovered-evidence tree, a separate clean training repository, and
corpora addressed by content.** The decisive reason is measured, not aesthetic: the pipeline root
has already destroyed provenance once by being written in place — a 37-class run landed on top of a
29-class one and produced the only contradiction in the record. The evidence tree and the workspace
cannot be the same directory.

The first commit anchors on **digests published earlier, elsewhere**, not on ancestry — commit dates
are forgeable, digests are not.

*Activates:* the CI-asymmetric pin assertion, which must be fixed in the same change.
*Risk if you do nothing:* the source is 80 KB with one physical copy, and a local repository is not
a backup.

> **AUTHORIZE S1:** *"Copy the pipeline source into a new clean repository at &lt;path&gt;, first commit
> anchored to the 2026-08-18 digests. Leave D:/tools/equipment-model in place as read-only
> evidence."*

### S2 · May the corpora leave this machine?

**Recommended: no.** `dataset/` — the corpus behind the model this app **currently ships** — was
assembled by image search with no per-image source record, and the origin URLs were discarded at
download time. Its rightsholders are not identifiable from anything on disk. That is not a licence
question awaiting research; it is one that cannot be answered by inspection.

*If you say yes anyway:* a CC BY 4.0 attribution manifest, a crop-to-source mapping and a
"changes made" record must exist first, and reconstructing them requires re-querying an API whose
projects can be withdrawn by their owners.
*One-way:* deletion does not recall clones, forks or caches.

> **AUTHORIZE S2:** *"Image corpora stay on this machine. Nothing is uploaded to any hosted remote.
> I accept that they have one physical copy."*

### S3 · Does the scanner programme continue?

**Recommended: pause and preserve.** Both models are useless on real gym photos — historical top-3
0/18, reproduced 1/18. Pausing costs nothing and the preservation obligation stands either way,
because v1 ships today and `dataset/` is the only evidence of what it was trained on if a rights
claim arrives.

> **AUTHORIZE S3:** *"Pause the scanner programme. Preserve the evidence; build no training
> platform."*

---

## RF — the exposed Roboflow key

**No key literal is committed to this repository — not at HEAD and not anywhere in history**,
verified with `git log --all -S`. What exists is a 2026-08-07 planning note recording that the key
was pasted into a *conversation*, recommending a reissue, with no record of one happening. This is a
credential-console action, not a repository clean-up.

**Recommended: revoke without replacement.** Measured: nothing shipped uses Roboflow. The only
consumers are `discover_roboflow.py` and `fetch_roboflow.py` in the pipeline directory outside this
repository, and under the recommended S3 answer they will not run again.

**Do not paste the new key anywhere.** Not into chat, not into a document, not into a commit
message, not into this repository. If a replacement is ever needed it belongs in the pipeline
machine's environment and nowhere else.

*Afterwards, record only:* the reissue date and your confirmation. The credential identifier only if
it is not itself secret.

> **AUTHORIZE RF:** *"Revoke the Roboflow API key. No replacement — nothing in the product uses it."*

---

## What is not on this list, and why

* **D1, H3, CT-1** need a named clinician's signature or real human QA labels. No local artefact may
  stand in, and none has appeared. `HUMAN_REVIEW_LABELS = 0 of 15 files scanned`.
* **Scanner metadata is answered.** This list previously said it needed "a Linux host that can
  reach PyPI", on the strength of a `pip install` that failed *inside a container* —
  a property of the container's certificate bundle, generalised into a claim about the host. The
  host reaches PyPI perfectly well. Downloading the manylinux wheels there and installing them
  offline in the container needs no TLS bypass at all, and the genuine library then computes
  `1.0.0` — **matching the value the pipeline's stub stamped**. Labels intact, normalisation
  intact. Recipe: `scripts/ml/metadata_validation_recipe.md`. Result:
  `core/ml/METADATA_VALIDATION.json`. Nothing is asked of you here.
* **N-07 and F025** are dormant *observations*, not pending questions. Nothing is being asked.
