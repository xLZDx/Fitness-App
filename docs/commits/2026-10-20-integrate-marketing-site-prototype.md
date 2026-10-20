# Integrate marketing/site-prototype-2026-08-19 (f95e1c88)

Decision: take the marketing site prototype, claim register, lint, plans and reports; keep BASE for all mobile code and for two report pages that BASE already carries in newer form. Result: mobile/ and functions/ are byte-identical to the previous integrate HEAD (verified: empty `git diff --cached HEAD -- mobile functions`).

What was added (29 new files): core/marketing/* (claim register, governance, QA), core/plans/SPTR_MVP_CLOSURE_PLAN_2026-08-19.md, public/index.html + public/assets/sptr/* (internal, noindex site prototype), scripts/marketing/claim_lint.py, reports/GATE_D_*, SPTR_MVP_*, SPTR_SESSION_RECORD_* pairs.

Evidence that the branch's mobile work is already on BASE (master) in a newer form:
- Gates D, E, F, G were cherry-picked to master earlier (add/add conflicts on answer.dart, setup_note_card.dart, last_session_card.dart, step_equipment_test.dart etc.), and master carries later codex-review fixes. MVP-1/MVP-3 (auth-restore, splash waits for auth) is master commit 74f2f767.
- Lost-content script (scripts_FitnessApp/missing.py): of all lines the branch added to mobile/ since its merge-base 78b24dcc, only these are absent from BASE, each checked and a newer BASE form exists: equipment_detail_page.dart gymId lookup (BASE resolves gymId through `equipment?.hasGymAccess`), GlassCard vs HudPanel in last_session_card/setup_note_card (BASE redesign), `runtimeType` equality guard (BASE is stricter), enum without `quotaExhausted` (BASE adds it), splash_page_test test names reworded in BASE, profile_providers_test StreamController use present in BASE under another name.
- Trap 2 (splash `_maxAuthWait` / `_minDwell` declared twice) cannot occur: splash_page.dart is the BASE version unchanged.
Conflicts and decisions (each file compared both sides):
- 15 mobile files (ai_planner_providers, firebase_auth_repository, equipment_detail_page, last_session_card, setup_note_card, profile_providers, programme_providers, splash_page, scheduled_session_providers, workout_session_providers, answer.dart, step_equipment_test, profile_providers_test, splash_page_test, answer_test): BASE version kept, branch side is an older form of the same change.
- core/product/GATE_E_SHARED_UNCERTAINTY_D0_NOTE_2026-08-19.md: BASE kept (it contains the quotaExhausted correction the tip lacks).
- reports/SPTR_STATUS.html and .ru.html: BASE kept (newer consolidated report 6244b45d); the branch version stays reachable at f95e1c88.
- core/DECISION_LOG.md: both sides kept.
Risk to review: public/ is the Firebase Hosting root (firebase.json "public": "public"), so a hosting deploy would now publish public/index.html. The page is marked noindex, its claims are `internal-only`, and its own comment says it must only be served from a preview/VPN. Operator should decide before any hosting deploy (move it out of public/ or exclude it via firebase.json ignore).
Checks: no deleted files; no conflict markers; claim_lint.py PASS (22 claims); claim_register.json parses; site.js passes node --check; claim_lint.py compiles. No Dart or TypeScript change, so analyze/test results equal the previous merge.
