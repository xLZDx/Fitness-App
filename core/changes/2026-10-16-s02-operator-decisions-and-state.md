# S02 start: operator decisions D-16, D-17, D-6, D-7 recorded; S01 closed in the SDLC state

Date: 2026-10-16. Branch: `phase2/s02-unified-activity` (from `phase2/main` at `5bb61f15`, which contains the merged S01 PR #9).

## What changed
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md`: new subsection "Operator decisions recorded" in section 9 with the four answers given in chat on 2026-10-16, their binding interpretation for S02 and later, and what stays open inside each decision (default expiry value, retention clock, region of the first release, sub-options E, F, G). The status line no longer says that no decision is taken.
- `docs/phase2/s01/RIGHTS_STUDY_TILES_ROUTES_POI.md`: header and section 9 title record that the operator answered "open source" for D-6 and D-7, matching the recommendation; the region is still not named.
- `docs/sdlc/STATE.md`: S01 closed (PR #9 merged, GPT-PM APPROVE on `d16a5b65`), S02 entered at phase 3 Design.
- `docs/DOCUMENT_REGISTRY.md` regenerated.

## Why
The decisions are entry conditions of S02 (D-16) and S07 (D-6, D-7); recording them in the repository avoids relying on chat history. The answers were short, so the interpretation is written out and every point the answers did not settle is listed as open instead of being assumed.

## Affected contracts and paths
Documentation only. No requirement text changed; labels stay PROPOSED.

## Verification state
No tests or checks were run (documentation). Operator answers are quoted from chat: D-16 "GPS in the cloud with a user-set expiry, heart rate on the phone only"; D-17 "friends by mutual accept allowed, public not allowed, age stated by the user"; D-6 "open source"; D-7 "open source tracks and maps".
