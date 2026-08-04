# Resume prompt — Fitness App audit remediation, paste this as the first message in a new session

You are continuing work on `D:\test 2\Fitness App` (Flutter + Firebase fitness
app) exclusively. Per the operator's One-Session-One-Project rule, do not
read, edit, or run anything belonging to another project this session.

## Where things stand

Git: `HEAD = 9d9a049`, pushed, tree clean (three pre-existing untracked dirs
— `data/preflight/`, `data/staging/library/`, `data/staging/video_library.json`
— are not yours, leave them alone).

The operator supplied a full external audit of the app. You (a prior session)
verified its claims against the working tree, wrote a remediation plan, ran
it through a 5-agent T3 design/architecture review round (`architect`,
`code-architect`, `a11y-architect`, `flutter-reviewer`, `planner`), and
produced a consensus plan — not the pre-review draft.

**Read the plan before doing anything else:**
`core/PLAN_AUDIT_REMEDIATION_2026-08-04.md`

Read-only skim of what's in there: 13 gates (I0, S0a, S0b, S2, S1a, S3a,
S3b×N, S1b, C0, W0, L0a-d, R0), a full dependency graph, a Part-0 fact-check
of the audit itself (headline correction: catalog safety-tag coverage is
**0 of 1887 exercises, not the audit's claimed 6%** — the legacy catalog
carrying the only 144 tagged exercises was deleted the day before, in
`0c4bf24`), and a full review audit trail with every BLOCKER cited to
`file:line`.

## Gate progress (updated 2026-08-05)

Every gate below is committed AND pushed. Working tree clean at `9d9a049`.

| Gate | Commit | What landed |
|---|---|---|
| I0 | `77d7c99` | merge-by-id write path; `safetyCoverage()`; coverage floor test |
| docs | `bc7a669` | plan + resume committed; corrected I0's false "audit exit 0" claim |
| docs | `bc55851` | N0-N4 load-readiness gates appended to the plan |
| N0 | `491267e` | scaling ceilings on all 12 functions; Stripe lazy-loaded |
| N1 | `1f9874b` | clip signature memoised + in-flight dedup |
| N2 | `8382e6d` | windowed the two cold-start listeners; count() + streak high-water mark |
| N3 | `685f2ac` | 4 unbound price secrets; webhook event ordering; ensureCustomer race |
| N4 | `af3384e` | donor_wall rule, fetch timeout, token refresh, scan write, router stream |
| S0a | `f9b8943` | removed 8 always-false injury-screening claims; honesty banner |
| S2 | `23553c4` | catalog boundary made real; deep link screened; cold-start race closed |
| docs | `fb2a1d8` | retro plan blocks for the first ten commits |
| S1a | `cc07ece` | InjuryRegion enum, /injuries edit screen, one serializer |
| S3a | `cf83e3b` | vocabulary projection + per-region ratchet |
| fix | `6376c79` | vendor paths were mis-pathed, not missing -- builder runs again |
| S3b-1 | `5a55d7f` | knee tagged; three-state disclosure |
| S3b-2 | `d484797` | shoulder + lower_back tagged |
| S3b-3 | `8b5a0ba` | hip, ankle, wrist, elbow, neck; AI exercises excluded for injured users |
| S1b | `64493ee` | backfill NOT run -- S1a's shape removed the need; nudge instead |
| C0 | `9d9a049` | tier override guarded at the read site |

**Safety chain is complete.** Catalog coverage: 1,435 of 1,887 rows tagged
across all 8 regions. All eight injuries at once hides 76%, leaving 452.

## What remains, in order

1. **W0** — logging loop. Capture sheet + idempotency in ONE commit (a
   double-tap after weight capture ships double-counts in `suggestNextWeight`).
2. **L0a** — Terms/Privacy routes. Independent, no dependency.
3. **M0** — label or hide the mocks (progress photos, marketplace, community).
   Shares files with S0b.
4. **L0c** — data export. **L0d** — guest to Google migration.
5. **L0b** — account deletion. **Destructive: needs its own second GO.**
   Must reach Auth, subscription doc, workout logs, scheduled sessions, AND
   cancel the Stripe subscription; needs `firestore.rules` changes.
6. **R0** — release hygiene. **Signing key needs its own second GO** — a real
   key signing a published listing is irreversible.
7. **S0b** — blocked on the operator's nonprofit/tax-deductible business
   decision. Not a code question.

## Standing facts a fresh session will otherwise re-derive

- Vendor library lives in the `New folder` directory under `D:/Downloads/Video`,
  reached via `scripts/catalog/vendor_paths.py` (`FITNESS_VENDOR_DIR`
  overrides). It is NOT directly under `D:/Downloads`.
- Baselines: `flutter test` 1206 · `pytest scripts/catalog/` 98 ·
  `flutter analyze` 6 issues, all pre-existing · `audit_doc_links.ps1` 40
  broken, pre-existing since before this work.
- `kSafetyTagsClinicallyReviewed = false`. No clinician has reviewed the eight
  CSV twins in `core/contraindications/`. The weaker disclosure shows because
  of it.
- **Nothing is deployed.** Firestore rules and Cloud Functions in production
  are still pre-session, including the donor-wall denial (N4) and — until a
  redeploy binds the secrets — the tier mapping fixed in N3.
- Commit format is mandatory: see the volume-level `CLAUDE.md`, section
  "Every Commit Carries Its Plan". Retro blocks for the first ten commits are
  in `core/COMMIT_PLANS_2026-08-04.md`.

## What to do first

1. Confirm the plan doc still matches the current tree (git has moved since
   it was written — spot-check a couple of its `file:line` citations before
   trusting them, per the No-Guessing rule). Note the plan is deliberately
   NOT retro-edited as gates land: it is the consensus artifact of
   2026-08-04, and this section is where progress against it is tracked.
2. Ask the operator which gate to build, or wait for them to name one. The
   chain's next link is **S0a** (honest banner + the eight always-false
   safety affordances); **C0**, **W0**, **L0a** and **M0** are independent
   of it and can go first if the priority is different.
3. Do not start building any gate without an explicit `GO` / `ГО` (case-
   insensitive, exact command per the operator's global CLAUDE.md — "yes",
   "sounds good", "approved", "go ahead" do NOT count). Do not push anything
   without a separate, later `push` command.
4. If the operator's message doesn't name a gate and doesn't look like
   authorization, treat it as a normal request and re-state the relevant
   part of the plan, then ask for `ГО` before touching any file.

## Also still open, separately, not part of this plan

**Backlog E4.1** (see `core/BACKLOG_2026-07-31.md`): four equipment pages
with zero video coverage — `recumbent_bike`, `glute_kickback_machine`,
`t_bar_row`, `rotary_torso_machine`. Three options were written up in an
earlier gate; the operator explicitly deferred the decision ("потом будем
решать" — later, we'll decide). Do not pick an option without being asked.

## Standing rules that apply here (already in `~/.claude/CLAUDE.md` + `D:\test 2\CLAUDE.md`, restated because this is the part that's easy to drop across a session boundary)

- Approval is ONLY the literal word `GO` / `ГО`, optionally with a gate name.
  A separate `push` authorizes pushing and nothing else.
- Small scope → verify → local commit → **stop and report** → separate
  push-GO. Never build more than one gate on one GO.
- Every factual claim about the code needs an inline `file:line` or command
  output citation — this project's audit found real, costly drift between
  what a prior pass claimed and what the code actually did (see the plan's
  Part 0 for two examples from this very session).
- Russian in chat, hide nothing, no unstated assumptions.
