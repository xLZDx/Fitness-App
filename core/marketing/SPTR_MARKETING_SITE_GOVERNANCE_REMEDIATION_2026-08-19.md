# SPTR Marketing Site — Governance Remediation (Gates A/B/C)

**Date:** 2026-08-19 · **Prior commit:** `dd12695` · **This change:** local commit, not yet made at
time of writing (see the site-build follow-up report for the final hash)
**Scope:** claim governance only. No product implementation (Level-1 memory, MRD-01…07) in this
change — those are out of scope pending their own plan; see the closing note.

---

## 1. What the independent review found

The post-implementation review of `dd12695` passed the prototype for internal use without a
rollback, but identified two governance defects and one documentation gap:

- **F1 (MAJOR):** the single `data-claim-class` axis conflated *is this true of the product* with
  *may this exact wording be published*. `exists` was implicitly treated as public-ready, which is
  not always correct — a technically true statement can still need a qualification, a coverage
  caveat, or simply belong to an internal build.
- **F2 (MEDIUM):** an unclassified claim silently disappeared from the hand-regenerated register
  instead of failing a check. Silence is not a failure signal a reviewer will ever see.
- **F3 (LOW now):** `noindex, nofollow` was standing in as the only stated privacy boundary, and
  that is not access control.

All three are addressed below.

---

## 2. F1 — two independent axes, re-adjudicated per claim

`data-claim-class` is retired. Every classified sentence in `public/index.html` now carries:

```
data-claim-id="…"                                    stable slug, unique
data-claim-state="exists|committed|hypothesis|never"  is it true of the product?
data-public-gate="allowed|qualify|blocked|internal-only"   may this wording be public?
data-claim-qualify="…"                                required whenever gate="qualify"
```

**Every one of the 22 claims on the page was re-adjudicated individually** rather than bulk-migrated
with `exists → allowed`. Four claims that were plain `exists` under the old system came out
`exists` + `qualify` under the new one:

| Claim | Why it needed qualification |
|---|---|
| `mechanic-exercise-library` | Injury filtering covers 1,527 of 1,887 exercises and is self-reported, not a medical screen — the page must say so before this can go public |
| `memory-suggested-weight` | A suggested next weight is derived from logged history, not personalised coaching — must not read as a recommendation the user should simply follow |
| `evidence-nameplate-prevalence` | See §4 — the original wording overclaimed how common printed nameplates are |
| `privacy-progress-photo-encryption` | The claim is verified against source architecture, not an independent security audit — wording must not imply the latter |

Two claim types keep the state/gate distinction explicit at the far end: `committed` and
`hypothesis` claims can only ever carry `internal-only` or `blocked` — never `allowed`, and never
`qualify` — which is enforced structurally (§3), not by convention.

**8 nodes gained claim classification they never had**, including two that were previously invisible
gaps in the old single-axis system: `s2Lede` ("no gym-side setup required") and `s4Lede` (the
nameplate-prevalence sentence) rendered on the page with zero claim metadata under `dd12695` — they
were marketing copy asserting a specific fact, unclassified, and the old system's "it just won't
appear in the register" behaviour meant nobody would have noticed.

Every other `data-i18n` node — headlines, eyebrows, CTA labels, framing sentences, illustration
example values, disclosure meta-text — now carries an explicit `data-nonclaim="reason"` instead of
silently having no metadata. 67 `data-i18n` nodes total: 22 classified claims, 45 explicit
non-claim exemptions, 0 unaccounted for.

---

## 3. F1 continued — one real correction the re-adjudication produced

Re-deriving both axes for `s4Lede` rather than trusting the old `exists` label caught a genuine
overclaim:

> **Before:** "Most machines have their own name printed on them."
> **After:** "Many machines have their own name printed on them. When SPTR **can** use those words…"

A prior round's own field measurement bounds the nameplate mechanic to roughly 28 of 69 registry
types — selectorised strength machines — and free weights and bodyweight equipment can never carry
one at all. "Most" is not supported by that bound; "many" is defensible and the sentence is now
marked `qualify` with the exact caveat attached (`core/marketing/claim_register.json`,
`evidence-nameplate-prevalence`). The Russian translation in `site.js` was corrected to match
(`На большинстве` → `На многих`, plus the same "can" qualifier).

This is exactly the kind of catch the two-axis system exists to produce, and it is why the review's
instruction not to auto-map `exists → allowed` mattered in practice, not just in principle.

---

## 4. F2 — the lint is fail-closed, and it proves it

`scripts/marketing/claim_lint.py` parses every `data-i18n` node in `public/index.html` and fails
unless each one carries either full claim metadata or an explicit `data-nonclaim`. It also fails on:

- an invalid `data-claim-state` or `data-public-gate` value;
- a `committed` or `hypothesis` claim marked `allowed` or `qualify`;
- `data-claim-state="never"` rendering at all — a `never` claim structurally cannot appear as
  marketing content, full stop;
- a `qualify` gate with no `data-claim-qualify` text;
- a duplicate `data-claim-id`;
- drift between the markup and `core/marketing/claim_register.json` — the register is now the
  single source of truth, and the human-readable `.md` register is *generated* from it rather than
  hand-maintained, so the two cannot silently disagree;
- a claim missing its Russian translation in `site.js`.

```
$ python scripts/marketing/claim_lint.py
CLAIM LINT: PASS -- 22 claims classified and reconciled with the register, 0 issues
```

**The self-test is the part that matters.** A validator that has never been shown to fail is not
known to work. `--self-test` applies six real mutations to the live file *in memory only* — strip a
claim ID, strip a state, feed an invalid enum, mark a `committed` claim `allowed`, duplicate an ID,
rename a claim out from under the register — and asserts the lint catches every one:

```
$ python scripts/marketing/claim_lint.py --self-test
self-test 'strip claim-id': caught (2 error(s)) -- OK
self-test 'strip claim-state': caught (2 error(s)) -- OK
self-test 'invalid enum': caught (2 error(s)) -- OK
self-test 'committed marked allowed': caught (2 error(s)) -- OK
self-test 'duplicate id': caught (3 error(s)) -- OK
self-test 'orphan register entry': caught (2 error(s)) -- OK

SELF-TEST: PASS -- the validator demonstrably fails on every tested mutation
```

Nothing on disk is touched by `--self-test` — the mutations are string substitutions held in memory,
run through the same `lint()` function the real check uses, then discarded.

### A defect the lint's own build caught before it shipped

Writing the parser surfaced a real regex bug: the attribute-matching pattern was `data-[a-z-]+`,
which does not match `data-i18n` — `i18n` contains digits, and the character class excluded them.
Every single claim node registered as "unclassified" on the first run (44 false failures) until the
class was widened to `data-[a-z0-9-]+`. Recorded here because it is the second time in this project
that a validator shipped with a defect in the validator itself — worth the reminder that the
self-test exists precisely to catch this class of problem, and does, since the six mutation cases
above only started passing once the regex was fixed.

---

## 5. F3 — access-control rule made explicit in source

`public/index.html` now carries a code comment directly above the `robots` meta tag stating plainly
that `noindex, nofollow` is not access control, and that any future remote deployment of this
prototype before the pre-public truth gate must sit behind real access control (authenticated
preview, VPN/internal network, or equivalent). This is a documentation-only change — **no
deployment occurred, and none is proposed by this remediation.**

---

## 6. A layout defect the remediation itself introduced, found and fixed before commit

Adding a `data-nonclaim` debug badge (`html[data-debug] [data-nonclaim]::after`) to every
non-claim node included the CTA buttons, which carry `data-nonclaim="cta-label"`. Those buttons are
`display: inline-flex; justify-content: center`, and the injected pseudo-element forced the flex box
to grow around it — overflowing the mobile nav bar by 13px in debug mode only. Caught by re-running
the full render QA matrix after the governance changes, not by inspection. Fixed by scoping every
debug badge selector to `:not(.btn)` — CTA buttons are self-evidently non-claims by their own
styling, and the annotation added no reviewer value there while breaking layout. Re-verified: 0px
overflow across all three concepts, both viewports, debug on and off.

---

## 7. What this remediation deliberately does not do

Per the review's own framing, product implementation (Level-1 equipment-type memory, the shared
uncertainty contract, MRD-01/02 workout–equipment and gym identity, MRD-03/04/05 physical-machine
identity and setup memory, MRD-07 contribution measurement) is explicitly **out of scope for this
change.** Those touch the live Flutter application's data models — Firestore schema, provider
wiring, and real user data — and constitute a scope expansion on an entirely different order than a
governance fix to a static marketing page. They are not attempted here; see the closing note in the
accompanying site-build report for why that work needs its own scoped plan rather than being folded
into this commit.

---

## 8. Independent review of this remediation, and what it found

Before committing, this change was itself reviewed by two independent agents in parallel — a
security review of the governance system and lint script, and an accessibility review of the new
debug-mode UI. Both found real, cited defects. Devil's-advocate review of a review pass is exactly
the discipline this whole project has tried to hold itself to, and it caught things a self-review
would not have.

### Security review — one BLOCKER, confirmed and fixed

**The lint's own node discovery only ever looked at tags carrying `data-i18n`.** Concretely: `<title>`
and `<meta name="description">` are live marketing copy — the meta description literally restates
the `hero-a-mechanic` and `hero-b-evidence` claims — and rendered completely unclassified with zero
lint errors, because they sit outside the localisation system entirely. This directly contradicted
the claim "meaningful marketing copy cannot render without classification."

Fixed at the root rather than special-cased: `TAG_RE` in `claim_lint.py` no longer requires
`data-i18n` at all — it matches any tag carrying `data-i18n`, `data-claim-id`, `data-claim-state`,
`data-public-gate`, or `data-nonclaim`. A second, belt-and-suspenders check
(`check_required_static_surfaces`) hardcodes that `<title>` and `<meta name="description">`
specifically must carry classification, so a future head-level marketing surface added without
*any* claim attribute at all is still caught by name, not just by the general scan. Both tags now
carry `data-nonclaim="seo-title"` / `data-nonclaim="seo-description"` in `public/index.html`, with a
code comment tying their wording to the two claims they restate.

**Minor finding, also fixed:** the register-drift check compared `state`/`gate`/`copy_key` but never
the qualification text itself — and three of the four `qualify`-gated claims had genuinely diverged
between the on-page tooltip and `claim_register.json` (confirmed by diffing them directly). All four
are now reconciled to one canonical wording, sourced from the JSON and copied verbatim into the
HTML attribute, with a new lint rule (`QUALIFY TEXT DRIFT`) that fails if they ever diverge again.

**Confirmed clean:** the privacy claims (hardware keystore encryption, backup exclusion, Gemini
upload disclosure) were independently cross-checked against `photo_key_store.dart`,
`aes_photo_cipher.dart`, the Android backup-rules XML, and `gemini_equipment_service.dart`, and match
source exactly — including that the code's own comment on the ceiling of the encryption claim ("not
end-to-end") is respected by the site's wording rather than oversold. The local-only event log and
the debug-mode qualify disclosure were confirmed to add no new leak: qualify text is already
plaintext in the HTML attribute regardless of debug mode: view-source discloses it either way.

### Accessibility review — one MAJOR, one same-class regression, both fixed

**The `:not(.btn)` fix for the first overflow bug (§6) was incomplete.** The same failure mode —
`white-space: nowrap` debug badge content forcing a flex item wider than its container — also
applied to `.mark-sub` (the "short for Spotter" line) inside `.mark`, a `display: flex` column that
is itself a child of the non-wrapping `.nav-in` row. Reproduced directly: 0px overflow at 320px and
above, but 2px at 300px and 22px at 280px, worst with the longer Russian brand string. Rather than
extend a growing `:not()` exclusion list, every debug badge rule (`data-claim-state`,
`data-public-gate`, `data-nonclaim`) had `white-space: nowrap` replaced with `overflow-wrap: anywhere`,
so badge text wraps instead of imposing a content-driven minimum width on any flex ancestor,
present or future. Re-swept at 280/300/320/360/390px in both languages: 0px overflow everywhere.

**The debug-only qualify tooltip used `el.title`**, which is unreachable by keyboard, touch, and much
assistive technology — defeating the purpose of a compliance-review affordance for exactly the
reviewers who'd need it most. Replaced with a real disclosure: a focusable `<button aria-expanded>`
inserted next to each `qualify`-gated claim that reveals the qualification text as visible, selectable
page content on click, not a hover-only tooltip.

**Minor, also fixed:** the debug panel's "concept" and "lang" button groups were plain
`<span>` + `<button>` rows with no programmatic association, so a screen-reader user tabbing through
heard "A button, B button…" with no group context. Converted to `<fieldset><legend>`, CSS-reset to
keep the identical flat layout.

**Confirmed clean by the same review:** panel focus order, `hidden` gating, `:focus-visible` outline,
and `aria-pressed` state logic were all already correct and needed no change.

### Regression coverage for both findings

Two of the security review's cases and both layout cases are now permanent self-test mutations
(`claim_lint.py --self-test`, 9 cases total, up from 6): stripping classification from `<title>` or
`<meta name="description">`, and a qualify-text edit that silently diverges from the register. The
layout fixes were re-verified with a live Playwright sweep rather than a lint rule, since they are a
rendering property the claim system cannot see.

---

## 9. Verification summary

- `python scripts/marketing/claim_lint.py` → PASS, 22/22 claims reconciled, 0 issues
- `python scripts/marketing/claim_lint.py --self-test` → PASS, 9/9 mutations caught (6 original +
  3 added in response to independent review: unclassified `<title>`, unclassified
  `<meta name="description">`, qualify-text register drift)
- Full render QA re-run (Chrome/Playwright, 3 concepts × 2 languages × 2 viewports, debug on and
  off): 0px horizontal overflow everywhere including a targeted sweep at 280–390px, 0 console
  errors, all pre-existing checks from the original QA report still hold
- Two independent reviews (security, accessibility) of this remediation itself: 1 BLOCKER + 1 MAJOR
  + 3 MINOR found, all fixed and re-verified; nothing deferred
- `git diff` confirms only `public/index.html`, `public/assets/sptr/site.css`,
  `public/assets/sptr/site.js`, plus the new `core/marketing/claim_register.json`,
  `scripts/marketing/claim_lint.py`, and this document, changed
