# AUTONOMOUS PROGRAM AUTHORIZED — Fitness_App backlog closure run

**Purpose:** a self-contained operating brief a Claude Code session (this one, or a future one) reads
first and then works from, closing every item in the Fitness_App backlog that is genuinely
closeable by engineering work alone — without stopping to ask the operator after each gate.

**How to (re-)activate this run:** paste this whole file as the first message of a session (or as
the argument to `/loop`), or reference it by path and say "continue the autonomous backlog run."
The phrase `AUTONOMOUS PROGRAM AUTHORIZED` above is load-bearing — it is one of the operator-message
markers `~/.claude/hooks/_report_common.PROGRAM_MODE_RE` recognizes, so a session that reads this
file as a genuine user-authored message gets program-mode report cadence (write the report, don't
stop) mechanically, not just by intention. First executable step of the run, every time it (re)starts:
call `pm_bridge_mode_on` if PM Bridge orchestrator mode isn't already on (`pm_bridge_mode_status`) —
that is the *other* real mechanism (not just a text pattern) that makes `report_due.py` nudge
"continue" instead of "stop" after each report, per `~/.claude/CLAUDE.md` §18.

Everything below is specific to *this run*. It does not restate `~/.claude/CLAUDE.md` (loaded every
turn already) — it only says how that standing contract applies to this particular backlog, in what
order, and where the run's own boundaries sit inside it.

**Session-staleness check, every time this run (re)starts:** call `pm_bridge_mode_status` before
sending anything to GPT-PM. If it reports "THIS SESSION is the stale one" (the long-lived MCP server
subprocess loaded an older pm-bridge build than what's on disk — a different failure mode than the
daemon being stale, and restarting the daemon does not fix it), do NOT use `gpt_send`/
`gpt_send_and_await`/`pm_rosetta_go`'s own send path from this session — it can misroute content
into a different project's ChatGPT conversation. Use `node src/cli/review.js --cwd <repo> ... ` via
Bash instead for the actual round-trip (a fresh OS process reads current on-disk code every time, so
it is unaffected), read its reply, then record the verdict through the normal MCP state-writing
calls (`pm_rosetta_go`, `pm_set_gate`) — those only write local state and don't route to a chat, so
they stay safe even in a stale session.

---

## 1. Mission

Work through the backlog in §3 top to bottom, one gate/item at a time, using the full
Plan → GO → Act → Validate → Document cycle (skill `rosetta`) for each, until either:

- the backlog is exhausted (every item is closed, or correctly left open with a recorded reason
  it genuinely needs something this run cannot supply), or
- a real operator-only decision is hit (§2), or
- GPT-PM and internal review reach genuine, fact-grounded, still-unresolved disagreement after the
  bounded round budget (§17) — escalate to GPT-PM first per §16; only the operator's own two
  carve-outs in §2 justify stopping for a person.

Do not stop to report progress and wait. Report, then continue in the same turn — that is what
"AUTONOMOUS PROGRAM AUTHORIZED" + PM mode together mean here (§18).

## 2. The only two things that stop this run for the operator

Everything else — push, force-push, branch creation, PR merge, production migrations, external
publishing — proceeds on a genuine GPT-PM `VERDICT: APPROVE` per §20/§22/§24, verified the same way
any reviewer finding is verified (§3/§7) before acting on it. Only these two classes stay
operator-only, no exception, regardless of any GPT-PM approval:

1. **Deletion** — of files, branches, database rows, production data, or anything `git reset --hard`
   / `git clean -f` would touch. (A `git rm` of something already committed, recoverable via
   `git checkout <sha> -- <path>`, is NOT this class — see §25.)
2. **Real-money / live-trading actions.**

Name the specific decision in one line if either is genuinely hit, and keep working every other
open backlog item while it waits.

## 3. Backlog, priority-ordered

Re-derive ground truth before starting each item (§17 "reconstruct state before starting a gate") —
this list is a starting point from the 2026-09-16 full-program status audit
(`reports/program_status_full_2026-09-16.ru.html`), not a substitute for checking
`core/DECISION_LOG.md` / `pm_gate_status` / `core/CURRENT_STATE.md` fresh each time, since this run
itself changes that state as it goes.

### Tier A — clean engineering work, no ambiguity, start here

1. **Row 22 — no CI job builds a real release artifact.** `flutter.yml` never runs
   `flutter build apk`/`appbundle`, signing, or R8/ProGuard. Release-blocking, purely engineering,
   no external dependency. **Start here.**
2. **Row 25 — `server_export.dart` calls the wrong Functions region.** One-line fix
   (`FirebaseFunctions.instance` → the project's own `kFunctionsRegion`-pinned helper). Trivial,
   do it early for a quick real close.
3. **Row 23 — `functions-equipment-identity` deploy predeploy hook has no test step**, unlike the
   sibling `default` codebase (`firebase.json:23-27` vs. `:40-42`). CI-authoring fix.
4. **P2.G5-readiness step 3b** — durable mobile-side outbox (retry-on-failure delivery) +
   `ENRICHMENT_DISABLED` network-send wiring + mobile `genericOutcome` population. Explicitly
   deferred scope from step 3a (`core/design/p2_g5_readiness/`), pure engineering.
5. **OBS-1 item 13 — composed-screen visual regression coverage.** Extend the existing golden-test
   harness (`hud_golden_test.dart`) to Home/Workouts. Closes §9 rows 7/8 (HUD migration debt,
   M1-M9 visual fidelity) as a byproduct.
6. **OBS-1 items 2/5/12 — unconfirmed status.** Verify each against current CI/repo state first
   (they may already exist and just weren't traced in the 09-16 audit); build whichever are
   genuinely missing (Functions test-health CI gate, RU/EN semantic-drift check, secret-scanning
   extended to git history).
7. **OBS-1 item 7 / row 26 — data-lifecycle sweep verification.** Turn the existing one-off script
   (`scripts/ops/strip_health_from_profiles.py`) into a real scheduled, evidenced mechanism. No real
   users exist yet (`fitness-app-no-real-users-yet` memory) — escalation bar for touching this path
   is low, but it still touches user-data deletion logic: write real tests proving it targets only
   the intended lazy-migration blind spot, nothing broader.

### Tier B — needs a fresh look at whether the existing authorization still applies

8. **FORM_COACH_HUD_ALIGNMENT.** GPT-PM gave `APPROVE + GO` on 2026-08-29 for aligning the 4 Form
   Coach screens to the HUD visual language; the tracker shows zero movement since. Before resuming
   under that old GO: confirm the plan hash still matches nothing material changed underneath it in
   the intervening 2.5 weeks (Rosetta GOs bind to a hash, not a date — a materially changed repo
   state is grounds for a fresh plan, not an assumption either way). Bottom-nav icon redesign stays
   `REFERENCE_BLOCKED_DEFERRED` — do not touch it without an operator-supplied reference image.
9. **Row 24 — Firestore wildcard-with-denylist pattern.** Migrating `/users/{uid}/{coll}/**` to an
   explicit per-collection allowlist is a real rules-migration with real blast radius (getting it
   wrong either breaks legitimate client reads or opens a new collection by omission — the exact
   failure mode row 24 itself describes). Full Rosetta plan, real `firestore_rules.test.ts` coverage
   proving DENY/ALLOW for every current collection before this is anywhere near a push.
10. **MVP1.G3 Step 10A** — live enforcement-state visibility (Firebase App Check / Firestore rules /
    Identity Toolkit), machine-readable, fail-closed on staleness/error, not built atop the
    currently-broken GitHub Actions runner GPT-PM already excluded. Read-only against production
    config, no write path — should be tractable without device access.
11. **MVP1.G3 Step 10B** — real Android device telemetry proof for the already-built Crashlytics/perf
    signals (camera-init failure, permission-denial, OCR/inference failure, slow-success, no PII).
    Needs a real connected device (`project-sptr-fitness-app-test-devices` memory: S8 adb-connected
    default, S23 over network). If neither is reachable when this item comes up, record that
    plainly and move on rather than fabricating device evidence — this is the one item in Tier B
    that may turn out to be blocked on physical setup rather than a decision, which is a different,
    honestly-reportable kind of stop, not a silent skip.
12. **MVP1.G3 Step 10C** — reconciliation of all 13 original OBS-1 rebaseline items
    (`core/OBS1_G3_REBASELINE_2026-08-27.md`) against current HEAD + live production; only doable
    once 10A/10B evidence exists to reconcile against.

### Tier C — needs a GPT-PM product/scope decision before implementation, not just engineering

13. **Row 12 — nonprofit/subscription ARB copy contradiction.** This is a product-copy decision, not
    an engineering one. Ask GPT-PM (product owner, §17) which framing is correct, then implement
    whichever it picks — do not silently pick one yourself.
14. **Row 19 — photo export policy (R11f-2).** Same shape: ask GPT-PM for the decision, then build it.

### Tier D — the real deploy (highest-risk item in this whole backlog; handle with extra care)

15. **P2.G3's actual production deployment** (real, non-dry-run `firebase deploy` of
    `functions-equipment-identity`'s function + Firestore indexes to `fitness-app-korostelev`).
    Production migrations are reversible-class under §20 and can proceed on a genuine GPT-PM
    APPROVE — but this specific action shares a production project with the live `stripeWebhook`
    function, and P0.G6's entire isolation design exists specifically to protect that function
    during an identity-codebase deploy. Do not treat the 2026-09-11 implementation-review APPROVE as
    covering this: get a **fresh, specific** GPT-PM APPROVE naming the deploy action itself, run
    every available dry-run/isolation check first (P0.G6's own deploy-isolation test harness), and
    if genuine doubt remains about blast radius to the production Stripe path, treat it as the
    operator's call rather than stretching §20 to cover it. This is the one item where "when in
    doubt, the smaller reading is the safer one to act on first" (§21) should actually bite.

### Explicitly NOT in this run's scope — do not manufacture progress on these

- **Row 0 (D1/H3 clinical validation authority)** — external authority, not engineering-closeable.
  Leave it exactly as `core/CURRENT_STATE.md` records it.
- **Row 13 (Roboflow key reissue)** — a Roboflow-console action this repo cannot perform or observe.
- **Row 11 (vendor-clip AI-training licence conflict)** — irrelevant while P4 stays deferred; do not
  resume P4 as a side effect of working this backlog.

## 4. Per-item process (applies to every Tier A/B/C/D item)

1. Read the real current state of the relevant code/config before writing a plan (§17).
2. `pm_rosetta_plan` — print the plan as prose in the session (never JSON), verification stated up
   front.
3. Send for GO. Ask GPT-PM for a Definition of Done per step, not a self-authored one (`rosetta`
   skill). Scope the review request as a full sweep of the gate/mechanism/integrations, not just the
   diff (§17's 2026-09-13 addition) — every `--scope-note-file` says this explicitly.
4. Act: implement, running internal specialist reviewers BEFORE GPT-PM sees the diff (§17).
5. Remediate the complete reported batch in one pass, fix the class not the instance.
6. GPT-PM review: round 1 (full sweep) → remediation → round 2 (verification only) → APPROVE.
   Hard cap 3 rounds (`feedback-review-round-hard-cap-3` memory); a genuine regression from THIS
   remediation is the only thing that earns round 3.
7. Verify a green suite actually proves something (§17's "a green test suite is a claim that has to
   be earned") before citing it as evidence.
8. Commit, push (an approved GO already authorizes the push, §22 — no separate word needed).
9. `core/DECISION_LOG.md`: both what was planned and what actually happened, item by item — not
   just the outcome.
10. `pm_set_gate` for anything that maps to a named gate; for backlog rows that are not a formal
    gate, a decision-log entry closing that row is sufficient.
11. Update the rolling status report in place (`reports/program_status_full_2026-09-16.ru.html` /
    `.html`, same house format, same provenance-injector, same Artifact URL — republish, don't
    create a new report file per item) rather than writing a fresh report per gate. Hand it over per
    program-mode rules: report, then continue.
12. Move to the next backlog item in the same turn.

## 5. What "done" means for this run

Every Tier A/B/C item is either closed (commit+push+decision-log+gate-record+report all present) or
has an honest, recorded reason it is not (Tier D's own extra-caution gate, a genuinely unreachable
device for Step 10B, or a GPT-PM decision still pending for Tier C). The rolling status report
reflects the true end state, not a partial snapshot. Only then does this run actually end — and even
then, per §18, only stop, don't ask; state plainly that the backlog is exhausted.
