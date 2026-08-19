# Onboarding design reference — handoff v4

Extracted 2026-08-20 from `D:\Downloads\Mobile app design (4).zip`
(`design_handoff_fitness_hud/`, archive dated 2026-08-20 00:43), at the
operator's explicit request ("забери онбординг от сюда"). Only the
onboarding-specific files are kept here — not the full handoff, and not
`support.js` (the handoff's own `README.md`/`CLAUDE.md` mark it
prototype-only; it must not ship in the production app).

## Files

- `Fitness Onboarding.dc.html` — overview/index page for this reference.
- `Fitness Onboarding - Dark.dc.html`, `Fitness Onboarding - Light.dc.html`
  — the actual screen specs, one per theme.
- `dark-9-steps.png`, `light-9-steps.png` — full-flow screenshots, one row
  of 9 phone frames per theme.

## What this reference actually shows

A **9-step** flow, materially different in both step count and content
from the onboarding currently implemented and device-verified earlier in
this same session (a 10-step flow ending in a PAR-Q+ health-screening
pair — see `core/DECISION_LOG.md`, 2026-08-19 entries on clearing the test
account's safety block):

1. Splash / value prop ("Тренер в кармане — Камера видит технику. Ты — прогресс.")
2. Goal — Strength / Mass / Definition / Endurance
3. Training experience — first year / 1–3 years / 3+ years
4. Days per week + reminder time
5. Height / weight + unit toggle
6. Available equipment — barbell / dumbbells / blocks / bands / pull-up
   bar / cable / bodyweight-only
7. Camera permission for technique analysis
8. Background picker (ties into the app's existing `AuroraBackground`
   photo set)
9. Plan-ready summary

No PAR-Q+ / safety-screening step appears anywhere in this reference.

**Flag, not yet reconciled**: step 7's screenshot shows *"Техника 94% ·
норма"* — a fabricated technique-accuracy percentage on a permission
screen, before any camera frame has been analyzed. This is exactly the
kind of prototype value the operator has repeatedly ruled out for
production ("no fake Technique %, Tempo, Range, Symmetry", 2026-08-19
continuation directive; reinforced in the 2026-08-20 consolidation
directive's own §26, which names "94% Technique" as its first example of
prototype data that must not become a product fact). Any future
implementation work against this reference must drop or replace that
number with something real or omit the claim, not carry it over literally.

## Status

Reference material only. No code changed against this design in this
commit — reconciling the current 10-step PAR-Q+ onboarding against this
9-step reference (goal taxonomy, equipment step, background-picker step,
camera-permission step, and the fake-94% question) is its own gate, not
yet started.
