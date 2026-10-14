# Fitness App — Figma vs. Development Completion Matrix v1.5 (English Companion)

**Source:** [`HANDOFF_GAP_MATRIX_v1.5.md`](HANDOFF_GAP_MATRIX_v1.5.md), original Git blob `7a0dd462bfecb58dd6d4b4c8e010154785a00571`. A byte-identical second source copy has the same SHA. This document translates the historical design-to-engineering division of responsibilities, **not** a new product requirement approval or code implementation.

## Primary conclusion

A fully connected, end-to-end clickable Figma prototype is **not a mandatory prerequisite** for beginning Flutter development.

The development agent may proceed when the following are genuinely available: approved design system; finished key screens; specified user flows and UI states; resolved necessary product decisions; Figma links/PNG references; and the existing repository's actual business logic.

Spend remaining Figma effort **only on visually critical gaps** that cannot reliably be reconstructed from approved patterns. Do not take an unfinished Figma route as evidence a feature is missing from code.

---

## Category A — Development can complete without new Figma screens

### D3 — Home completion

- Weekly calendar
- Milestones block
- Horizontal recovery list with visible scroll affordance
- Empty/loading/error states
- Safe-area and responsive corrections

Rationale: Home typography, visual language, card patterns and hierarchy had been approved at this checkpoint. Build the missing sections using existing components and tokens.

### D4 — Scanner completion

- Scan history
- Saved equipment cards
- Offline fallback state
- Unknown equipment flow
- Route wiring
- Retry/error/permission states

The historical source says the repository already contained recognition history, cloud recognition, local fallback and history in the visual equipment layer. **Verify in current code before assuming this still holds.** Preserve behavior and refit the UI to the approved design system rather than replacing the scanner.

### D6 — Navigation and summary consolidation

- Contextual Technique Coach entry from the new Exercise Page
- Exercise context and arguments passed into the existing `/form-check` route
- Unify the parallel `WorkoutDone` and `WorkoutSummary` flows
- Redirect/compatibility migration
- Preserve workout completion data
- Regression tests

**Product decision Q26 is still required**, but an additional Figma flow is not mandatory.

Historical recommended default (not automatically approved): **WorkoutSummary becomes canonical**, and the old WorkoutDone UI is removed **after transferring all logic**, or temporarily kept as a thin compatibility wrapper. Do **not** maintain two independent completion routes.

### D8 — AI Coach integrations

Add contextual entry from scan results, equipment page and recovery, passing explicit context plus loading/offline/error/cache handling, navigation and analytics wiring. Reuse the existing AI Coach sheet/service pattern; **do not create parallel chat architecture or a new design language**.

### D9 — Engineering completion

Android safe areas; iOS safe areas, navigation gestures and modal behavior; Dynamic Island/notch handling; accessibility semantics; large text; reduced motion; offline states; complete route wiring; screenshot/golden comparisons.

These are chiefly **implementation and validation** tasks, not reasons to extend Figma indefinitely.

### General — Rest Timer

If the Rest Timer frame already exists, development must connect **Complete Set → Rest Timer**, support **skip / +30 seconds / pause / ready**, handle background/lifecycle behavior, return to the next set and remove any unreachable/dead screen type.

No new Figma work is needed for this already represented flow.

---

## Category B — Development can implement, but a small visual anchor is preferred

### D7 — Real progress charts

- Strength progression
- Training volume
- Consistency
- Muscle load

Use actual data and proper missing/partial/loading/error states within the established Progress layout and design tokens.

Preferred minimum from Figma: one representative Progress screen, selected chart type for each metric, axes/legends/period selector, empty/loading treatment and semantic chart colors.

If Figma capacity is exhausted, development may create a first pass and submit **emulator screenshots** for visual review.

Recommended defaults:

- **Strength:** Line chart for the selected exercise
- **Volume:** Weekly bars
- **Consistency:** Completion calendar or weekly bars
- **Muscle load:** Anatomical map or horizontal ranked bars
- **Never:** Decorative 3D, misleading smoothing, or fabricated percentages

### D9 — Light theme

A full light theme can be implemented from **semantic tokens**, although that necessarily involves visual judgment.

Preferred low-budget Figma scope: approve a light semantic palette and show **three** representative anchors — Home, Scanner result, and Workout Player or Exercise Page.

If none can be designed, development may produce a first light-theme version, but **the operator must review real emulator screenshots** before signoff.

### D9 — Platform adaptations

Development can handle safe areas, Android back/predictive back, iOS swipe-back, native permission prompts, modal behavior and keyboard/insets.

Separate full iOS design sheets are needed **only** if Android and iOS intentionally differ significantly in visual form. A shared brand with appropriate native behavior does not require cloning every frame.

---

## Category C — Finish a minimal Figma frame before the corresponding development gate

### D5 / General — Exercise Page

The source explicitly identifies this as the **only critical screen entirely absent from the approved design set at that checkpoint**.

Minimal Figma deliverable:

1. Canonical Exercise Page — loaded state
2. Poster-to-animation/video media area
3. Exercise title, primary/secondary muscles
4. Equipment, level, suitability
5. **Why recommended to you**
6. Three concise technique steps
7. Common mistakes
8. Restrictions/safety
9. Previous performance/history
10. Actions: Start Exercise; Add to Workout; Technique Coach; AI Coach
11. Loading state
12. Media-unavailable state
13. Long Russian UI copy / large-text state
14. Contextual Technique Coach entry

Do not create dozens of redundant variants. **One canonical screen and two or three critical states** are sufficient for this narrow Figma gate.

After receiving this screen, development implements a separate route, page, provider/data mappings and tests.

---

## Work Figma no longer needs to finish before development

- The fully connected **22-step** happy-path prototype
- Every offline/error branch as its own fully linked Figma journey
- Duplicated Android and iOS screens for every page
- Every accessibility variation in a static design file
- Real chart calculations
- Scanner backend state implementation
- Flutter navigation/route wiring
- Rest Timer lifecycle
- AI context payload implementation
- Consolidation of legacy Flutter completion screens

Those tasks belong to development and validation, not to extra visual mockups.

## Final minimum Figma request

Use the remaining design budget for **only**:

1. Canonical Exercise Page
2. Its critical UI states
3. Clear Technique Coach entry placement
4. If possible, the light semantic palette and one to three representative light-theme anchors

**After that, freeze the design and hand off to engineering.**

## Provenance and safety

This is a v1.5 **historical allocation-of-work decision**, not evidence that the feature routes, charts, permissions or onboarding actually work on the latest branch. Any real changes to health/fitness claims, storage, tests or user-visible behavior require their own engineering acceptance.

**Status:** Complete source-linked English explanatory companion for review; no repository code, original design files, product decisions or owner approval were changed.
