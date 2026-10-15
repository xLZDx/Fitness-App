# Fitness App: UI/UX direction for the four-mode product (planning, not approved)

> **CURRENT STATE (2026-10-15, after S00 execution).** This document is the approved planning baseline (GPT-PM APPROVE on revision 3; operator approval on 2026-10-15). Wording below such as "draft", "nothing has been executed" or "PR #5 is open" is historical. Executed so far: the snapshot, tag `phase1-baseline`, branches `phase1/main` and `phase2/main`, PR #5 retargeted to `phase2/main` and merged as `5137ccda`, the worktrees, and the S00 documentation and deploy-line guard work (still under review). Recorded operator decisions: D-1, D-2, D-4, D-5 (see `core/DECISION_LOG.md` and `docs/phase2/README.md`). Where this text and those two files disagree, the decision log and the README win.

Date: 2026-10-15. Status: DRAFT FOR GPT-PM REVIEW, then operator approval. This is direction and a design-contract backlog, not final screens. Each UI task is its own sprint (design contract first, build second), as the operator requested.

## 1. Sources and honesty limits

- The film `gemini_generated_video_18467594.mp4` (20 s, 1280x720, 24 fps, AI-generated): 20 frames were extracted at 1 fps and viewed as contact sheets (FACT). Overlay text in the film is partly garbled by the generator ("#C9FF47" appears as a label, numbers and words in panels are nonsense). It is therefore a mood board and composition reference, NOT a specification. No numeric values from it are used. The audio track was not analysed (no speech tool used; the blueprint holds the intended voice-over).
- The blueprint (`FITNESS_APP_4_MODES_PRODUCT_BLUEPRINT_RU_2026-10-15.docx`) states the approved design tokens were checked in `mobile/lib/core/theme/app_semantic_colors.dart`, `app_palette.dart`, `hud_tokens.dart` and refers to `docs/Redisign/DEV_SINGLE_FILE_MASTER_PROMPT_v2.0_EN.md`; this plan did not re-open the token files (UNVERIFIED by this session; the UI baseline sprint verifies them).
- `docs/*.png` screenshots are historical and not a specification (project rule).
- We do not copy any competitor interface; competitor patterns are used as evidence of what users expect.

## 2. What the film shows (frame by frame)

| t (s) | What is on screen | Design takeaway | Caveat |
|---|---|---|---|
| 1 | Lacing shoes, dark gym, headline "ONE APP. EVERY WAY YOU MOVE.", a small glass chip with the accent colour code | Entry tone: human first, one short headline, glass chip as a label primitive | Chip text is the generator's placeholder |
| 2 | Barbell athlete, corner brackets, glass labels (GYM / smart training), lime blocks in the corners | HUD corner brackets and lime corner wedges as the identity device; labels attach to the subject with a thin leader line | Label copy garbled |
| 3 | Yoga silhouette at sunrise in a rounded glass frame | Calm context uses the same glass frame, softer colour, no lime blocks: modes can change mood but share the frame | None |
| 4 | Track sprint, big word "OUTDOORS" | One-word context headings are large and plain | None |
| 5 | Cyclist on a forest road, "RIDE / OWN THE ROAD", vertical tick scale on the left, a small chip top right | A vertical ruler/tick motif for speed or elevation; label bottom-left | Ticks have no real values |
| 6 | "ROUTES NEAR YOU": map panel with route line, start/end pins, stat strip (distance, ...), right filter column (route type, difficulty, bike type) with sliders, cyclist reading the phone | Route discovery = map card + stats strip + filter rail with sliders; the answer to "why this route" belongs here | Values are noise; filter names garbled |
| 7 | "WALK / MAKE EVERY STEP COUNT": two friends on a riverside path, a thin metric chip with distance and pace | Walk is social and calm; metric chip small, not a dashboard | Values noise |
| 8 | Runner checking a watch, "RUN", right panel with big numbers (pace, distance, elevation) and bottom playback-style controls (previous / skip / menu) | Running live panel = big numerals with small captions; large touch controls at the bottom | Numerals noise |
| 9 | "BODY SCAN / SEE YOUR PROGRESS": fully clothed person in a large glass frame, joint markers on wrists and ankles | Body scan is framed as guided posture capture of a clothed person; neutral, non-clinical | Markers are decorative |
| 10 | Phone mock (2x2 cards TRAIN lime-highlighted, RIDE, EXPLORE, BODY; search and bell on top; five-item bottom bar) over a hand photographing a salad | The 2x2 photo-card grid is the phone mode chooser; five-item bottom navigation persists | Mock text partly garbled; it is the strongest UI frame |
| 11-12 | Body scan viewfinder: lime corner brackets, horizontal scan line sweeping the body, small progress readout ("15 %"), a mini ghost silhouette, counter chip | Capture state machine visual: bracket frame, sweep line, progress chip, pose ghost | Numbers noise |
| 13-14 | Nutrition coach: phone camera on a bowl, lime focus brackets appear over the food, label "NUTRITION COACH / FUEL YOUR GOALS" | Meal capture = camera with focus brackets; result must go to a confirm step (project rule: never auto-save) | Not shown: the confirm step |
| 15-16 | Smiling person in front of a dark glass frame; four photo cards in a row TRAIN / RIDE / EXPLORE / BODY with a focus bracket on TRAIN and a page indicator | Carousel chooser variant; focused card gets the bracket and the lime label | The film shows TRAIN with a cyclist image (generator) |
| 17-18 | Tablet/desktop dashboard: left icon rail, top tabs, search, primary action button, summary tiles with big number and progress bar, photo tiles RIDE / EXPLORE / BODY / a runner, a personal-records card and a green area-line trend chart | Global dashboard = summary tile + personal records + trend chart + per-mode photo tiles; wide screens get a side rail | Labels garbled; a large-screen layout we do not currently have |
| 19-20 | End card: logo, "FOUR WORLDS. ONE JOURNEY.", "YOUR JOURNEY STARTS HERE", lime CTA button | Brand outro, one primary CTA | The placeholder footer text is generator noise |

Consistent visual language across frames (FACT from the frames): near-black ground, one lime accent, rounded translucent glass panels with thin outline, corner brackets, large sans-serif headings, real photography (not illustration), one-word mode names in capitals.

## 3. Design system contract (to be verified against the repository in S03-D)

| Element | Value (per blueprint, UNVERIFIED here) | Rule |
|---|---|---|
| Background | `#06060F` | Main dark surface |
| Panel | `#0D0D1A` with glass (outline + backdrop blur) | Keep the approved blur tier; do not introduce new blur radii |
| Accent | `#C9FF47`, secondary `#A8D93A` | Primary CTA and active state only; never as body text on light surfaces |
| Text | `#F0F0F8`, secondary `#B1B1C6` | Contrast must pass WCAG AA; verify the secondary text on glass over photos |
| Shapes | rounded glass cards, thin outline, corner brackets for capture/live contexts | Brackets are a capture/live-state device, not decoration everywhere |
| Photography | real people, licensed | Every photo needs a licence record; no stock-looking AI faces for health claims |

Mode identity: the four modes share the frame, type and accent; each mode gets a hero photo, a one-word name and a small icon, not a different colour theme (avoids "four apps").

## 4. Navigation and shell

- Today: five bottom tabs (Home, Workouts, Scan, Progress, Profile) and about 45 routes.
- Proposed shell (design contract to confirm in S03-D): header with the current mode name and a mode switcher; bottom navigation stays at five items: **Home** (adaptive Today for the current mode), **Mode tab** (its label and icon change with the mode: Train, Ride, Explore, Body), **Record** (centre action, context-sensitive: start session / start GPS / scan / log meal), **Progress** (global dashboard, always the whole picture), **Profile**. Open question U-1: the centre Record action replaces the current Scan tab; the Scan flows move into BODY and the Record action.
- Mode switch is a 1-2 tap gesture: tap the title sheet, or long-press the mode tab. Switching never stops or resets a running recording; a visible "recording in progress" strip persists across modes.
- First run: 4 big photo cards (2x2 on phone, carousel on tablet), then 3-5 context questions for the chosen mode only (goal, experience, equipment, time). Location permission is asked when the user taps "Find nearby" or "Start GPS", never at launch.
- Large screens (tablet/web preview): side rail + dashboard tiles, as in the film's dashboard frame. Decision U-2: do we support tablet layouts in R2-R4 or only phone? (Recommended: phone first, tablet layout as a later sprint.)

## 5. Per-mode UI directions (design contracts to be written in the -D sprints)

### TRAIN (S12-D, S13-D)
Sections: Gym (existing flows unchanged: equipment QR, visual recognition, catalogue, form coach), Home (filters: no equipment, small space, quiet/no jumps, 5-45 min, beginner, recovery), Outdoor (stations, pull-up bars), Yoga (separate session model: style, duration, pace, voice, focus, avoided poses). Yoga screen is timer and sequence based (hold timer, pose name, next pose preview), not sets and reps. States to design: no equipment found, offline, video unavailable, injury filter excluded all options, session resume after kill.

### RIDE (S06-D, S10-D)
Pre-ride: bike type, route choice (nearby, saved, create), sensor status. Live ride: glanceable (speed, time, distance, elevation, optional power/HR), large stop/pause, auto-pause indicator, GPS signal state, battery guard. Post-ride: map, elevation profile, splits, source chips, share options (private default). Rule: no dense interaction while moving; hard cap on text per live screen.

### EXPLORE (S05-D, S10-D)
Walk/run/hike switch inside the mode; walk shows steps, time and distance first; run shows pace and splits first. Discovery: nearby map and list, filters (distance from start, duration, elevation, surface, lighting, accessibility only where verified), a skill tier (beginner / comfortable / experienced) and the **reason** line on every suggestion. Safety copy for hiking: the app does not replace offline navigation and local safety rules (blueprint).

### BODY (S14-D)
Landing with three tiles: Scan (existing three-pose flow, provisional labelling stays), Nutrition (diary, add via search / barcode / label / photo with confirmation), Weight (trend with range). Consent screens per purpose; "progress without photos" path. No body-shaming language; no medical claims; minors see no nutrition plan.

### Global dashboard (S15-D)
Sections: Today, This week, Progress, Personal best, Goals, Sources (per blueprint). Rules: compare only within a discipline; missing data is shown as missing, never as zero; each tile shows its source chip (phone GPS, watch, Health Connect, manual, camera estimate, imported) and an estimate marker where a value is derived; energy is never summed across sports as one number.

## 6. Cross-cutting UX rules

1. Glanceable live screens; no modal dialogs while recording; one-handed controls.
2. Data honesty: estimates carry a label and range; unknown is "unknown"; every derived number can open "how this is calculated".
3. Consent as a screen the user can find again: a Consent centre listing GPS, background location, health import, body photos, food photos, route visibility, with a switch and a delete/export link each.
4. Permissions requested in context, with a one-line reason, with a fully working denial path.
5. Offline-first for recordings and downloaded routes; sync state visible but quiet.
6. Accessibility: 200 % text scale, screen-reader labels for every control and chart (with a data table alternative), colour is never the only signal, touch targets at least 48 dp, reduced-motion respect, EN and RU strings with plurals and no truncation of Russian.
7. Motion: bracket and scan-line animations are short and optional; disabled under reduced motion; never on the live recording screens.
8. Photography and copy: real people and honest claims; the 40-second ad is labelled concept film until features ship.
9. Safety UI: injury filter and contraindications surface before a session starts, not after.

## 7. UI sprint matrix (each is a separate sprint; design before build; revision 2 after GPT-PM F-10)

Every row has its own scope, DoD and approval. A build sprint implements exactly the approved contract. UI-0 is part of S01 (roadmap Stage 0).

| ID | UI task | Output (design contract) | DoD of the contract | Build sprint | Depends on |
|---|---|---|---|---|---|
| UI-0 | Baseline audit | Token verification against `app_semantic_colors.dart`, `app_palette.dart`, `hud_tokens.dart`; component and screen inventory; HUD migration status; list of states | Report reviewed by product-ux and a11y reviewers | (S01) | none |
| S03-D | Shell, mode chooser, dashboard skeleton | Navigation model, chooser (2x2 phone; the carousel/tablet variant is design-only while U-2 is OPEN), mode switch, recording strip across modes, first-run questions per mode, empty/loading/error states; resolves U-1 | Journey maps for first run, switch mid-recording, return to an unfinished workout, notifications; RU/EN copy; accessibility spec | S03 | UI-0, U-1 |
| S04-D | GPS permission and recording-state contract (shared by EXPLORE and RIDE) | Permission journey (foreground then background), denial paths, recording states (acquiring, poor accuracy, offline, paused manual/auto, background, restoring, recovery failed, battery critical, permission revoked mid-recording) | State diagram; glanceable rules; battery guard copy; approved before S04 | S04 | UI-0, S01 contract |
| S05-D | EXPLORE journey | Walk/run live, summary, history, manual walk; reuses the S04-D states | Journey maps and summary rules | S05 | S03-D, S04-D |
| S06-D | RIDE | Live ride, bike type, summary, sensor sheet preview, maintenance counters | State diagram incl. sensor loss | S06 | S03-D, S04-D |
| S10-D | Discovery, route card, privacy and publication | Nearby list/map, filters, reason line, route trust states, publish with geometry preview, visibility, revoke, delete shared copy, report; built on the S09 data contract | Privacy journeys and trust states complete; copy reviewed by privacy owner | S10 (implements the publish flow; S09 has no screens) | S08, S09 data contract |
| S11-D | Offline and navigation | Ready-offline status, size and licence notices, off-route and recovery, optional emergency-contact live share | States for no connectivity and expired licence | S11 | S10 |
| S12-D | TRAIN lens (Gym entry, Home, Outdoor) | Entry cards and filters; Gym entry keeps existing flows | Regression map of existing gym journeys | S12 | S03-D |
| S13-D | Yoga session player | Sequence player, hold timer, pose preview, substitutions, voice, offline fallback | Timer and interruption states (call, lock, background) | S13 | S12-D |
| S14-D | BODY lens and consent rows | BODY landing, consent centre rows; states: provisional estimate, consent withdrawn, professional referral, provider unavailable, photo-free progress | Safety copy approved; no body-shaming language | S14 | S03-D |
| S15-D | Global dashboard | Tiles, personal best, goals, sources panel, large-screen variant if U-2 yes | Honesty rules (missing vs 0, source chips, estimate markers) | S15 | S03-D |
| UI-A | Accessibility and localisation pass | Per-screen audit against section 6 checklist | Findings closed | after each build | each build |
| UI-M | Motion and brand polish | Bracket and scan-line animations, empty-state art, licensed photography set | Reduced-motion variants; licence records | late | U-3, U-5 |

Each design sprint is staffed by `ui-designer` (authoring), `product-ux-reviewer` and `a11y-architect` (review) and ends with a GPT-PM review of the contract; the build sprint then uses `flutter-reviewer` and focused functional tests written and run by the test agents.

### 7.1 Interaction states that every GPS and shell contract must cover (added from GPT-PM review)

- GPS recording: acquiring signal, poor accuracy, offline, paused (manual and auto), background, restoring after kill, recovery failed, battery critical, permission revoked mid-recording.
- Route trust: unknown surface, unknown safety, stale source, offline maps unavailable, unverified accessibility, reported route.
- Privacy journeys: preview of the public geometry before publishing, who can see it, excluded zones, revoke sharing, delete the shared copy, what remains after deleting the activity.
- Four-mode shell acceptance: switch mode during an active recording, return to an unfinished workout, shared notifications, source provenance visible, no regression of Gym QR and Form Coach journeys, the centre Record action and its conflict with the existing Scan flows (U-1).
- BODY safety: provisional estimate, consent withdrawn, professional referral, provider unavailable, photo-free progress.
- Moving-context accessibility: large targets, no modal while recording, glance duration budget, voice cues optional.

### 7.2 Market evidence used for the UI contracts

See the evidence table in `03_ROADMAP_AND_SPRINTS` section 12 (grade C, blog roundups and support pages; official confirmation required before any requirement is frozen). Patterns adopted: reason line on suggestions (Komoot support pages), explicit ready-offline state (Ride with GPS), sport picker at start (Strava onboarding write-ups), personalised yoga duration/level/focus/voice (Down Dog), verified-only condition warnings (AllTrails-style).

## 8. Ideas and improvements (UI-specific)

1. Mode cards use the user's own last-activity photo or a licensed hero, with a short real stat ("3 rides this week") once data exists; empty state shows an invitation, not a zero.
2. A single "Record" action that adapts to the current mode, with a long-press quick picker for the other recordable modes.
3. A route card pattern shared by RIDE and EXPLORE: map, elevation profile, surface bar, difficulty for **you** (not a generic grade) and the reason line.
4. Capture frames (corner brackets) reused for body scan, label scan, barcode and meal photo so the capture grammar is consistent.
5. "Why this?" sheet on every recommendation (route, plan change, nutrition range), always available, always sourced.
6. A calm "recovery" visual state of the shell (reduced contrast of accent, no streak pressure) on rest days.
7. Large-screen dashboard as a later sprint if tablets matter (U-2).
8. A design-token parity test and a screenshot-less contract test so the shell cannot silently drift (project rule: make standards mechanical).

## 9. Open UI questions for the operator

U-1 Replace the Scan tab with a context-sensitive Record action? U-2 Support tablet/large layouts now or later? U-3 Photo policy: licensed stock, commissioned shoot or generated imagery (generated faces for health claims are discouraged)? U-4 Voice and music for yoga and rides (licensing)? U-5 Do we keep the film's lime corner wedges as brand elements in the app UI or only in marketing? U-6 Final product name and logo (blueprint open item).
