# Integrate sprint/hardening-followups-2026-10 (74ba5adc)

What: merges the SDLC pointer line in CLAUDE.md and its decision log entry.
Why: the tip was one commit (74ba5adc) ahead of BASE for tracked content; the Stripe settle commits listed in its log are already on BASE.
Conflicts: core/DECISION_LOG.md, both sides appended at end of file; resolved by keeping both (union), with a blank line separator.
Checks: no deleted files; no conflict markers; docs-only change (CLAUDE.md, core/DECISION_LOG.md); no code touched so analyze/test unchanged from baseline.
