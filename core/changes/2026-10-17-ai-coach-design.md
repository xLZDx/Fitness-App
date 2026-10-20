# AI Coach documentation: technical design, ADR proposals, UI spec

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/ai-coach/03_DESIGN.md: technical design revision 1; resolves the 17 draft-vs-code disagreements; live sessions live in a new collection and only a finished session is written to workout_sessions; three confirmation levels (journal-committed, replica-queued, server-confirmed); device-side safety gate; section of decisions needing the operator.
- docs/ai-coach/03a_ADR_PROPOSALS.md: ADR-001 to ADR-010, all PROPOSED.
- docs/ai-coach/03b_UI_SPEC.md: journeys, screens, states, components, copy and accessibility rules, all DRAFT.
- docs/sdlc/STATE.md: phase 3 recorded.

## Why
SDLC phase 3 for the TDD-001 documentation program. The design had to start from the code map, not the draft.

## Affected contracts and paths
Documents only under docs/ai-coach/. Known stale items in earlier documents (requirements AICR-021, 022, 028, 032; code map naming of marketplace) are listed in 03_DESIGN.md and are fixed in the review remediation batch, not here.

## Verification state
Documentation only. Agents (Sonnet 5.5): technical-writer, ui-designer. The design agent opened and confirmed in code that totals() and weeklyVolume count every workout_sessions document without a status filter. Realtime provider availability, Play foreground-service policy and Android 13 to 16 behavior are UNKNOWN. No tests run.
