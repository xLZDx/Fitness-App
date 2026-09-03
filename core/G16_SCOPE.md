# G16 — the remaining 14 pre-existing golden failures (M8, OBS-1)

## What this gate covers

The 14 goldens GPT-PM named as the next golden-infrastructure item at G15's
closure: `hud_golden_test.dart` (10 of its 13 HUD-primitive goldens, M8
gate) and `composed_screen_golden_test.dart` (all 4, OBS-1 item). Both were
captured on Windows and showed real 2.13%-13.91% pixel drift against actual
CI-matching Linux rendering, confirmed during G15's investigation in two
independent Linux environments (`ghcr.io/cirruslabs/flutter:3.27.1` and
`act` running the real `subosito/flutter-action@v2` action).

## What was found

Same underlying situation `test/golden/README.md`'s own "Exact-pixel
comparison" section already named for these specific goldens: they were
"generated and verified on a Windows host... not on `ubuntu-latest`," and
the README already predicted this risk and prescribed the fix
("regenerate the goldens from a Linux environment that matches CI"). This
gate is that regeneration, now that G15 built and validated the tooling to
do it credibly.

Unlike G15, there was no wrong hypothesis to correct here — the drift
mechanism (sub-pixel antialiasing/font rendering differences between a
Windows-built Skia and the Linux one CI actually uses) is consistent with
the Windows-vs-Linux rasterization/antialiasing differences the README
already predicted, and the fix is exactly what it already prescribed.

## The fix

Regenerated all 14 PNGs with `flutter test --update-goldens
test/golden/hud_golden_test.dart test/golden/composed_screen_golden_test.dart`
inside `ghcr.io/cirruslabs/flutter:3.27.1`. `git diff --stat` confirms
exactly the 14 expected PNGs changed (no code, no other fixture).

**All 14 old-vs-new pairs inspected by eye**, not just 2 (GPT-PM round 1
MAJOR: regeneration proves Linux self-consistency, not semantic
correctness — a real layout/text/token regression could ride along and
every automated check would still pass, since both environments compare
against the newly-blessed file). Extracted each pre-regeneration PNG via
`git show HEAD:...` and viewed it side by side with its replacement:
`hud_panel_dark`, `hud_panel_light`, `hud_button_accent_dark`,
`hud_button_glass_dark`, `hud_button_glass_light`,
`hud_chip_selected_dark`, `hud_chip_selected_light`,
`hud_chip_unselected_dark`, `hud_nav_bar_dark`, `hud_nav_bar_light`,
`composed_home_dark`, `composed_home_light`, `composed_workouts_dark`,
`composed_workouts_light`. In every one of the 14: identical layout, text
content, and colour to the eye — no structural change, no missing element,
no wrong copy, in either the small HUD-primitive widgets or the full
composed screens. The byte-level diff is real (that is what failed the
comparator) but visually imperceptible in all 14 cases, which is what a
purely raster-level difference looks like and what a real content/layout
regression would not.

Softened per GPT-PM's own note: the claim is that this is *consistent
with* Windows-vs-Linux rendering/antialiasing differences (matching what
`test/golden/README.md` already predicted for exactly these goldens), not
a categorical proof of the precise mechanism for all 14 individually — the
14-pair visual audit above is what actually rules out a semantic
regression, independent of the mechanism explanation.

## Verification

- Full `hud_golden_test.dart` + `composed_screen_golden_test.dart`: 17/17
  pass on regeneration, and again on an independent fresh container run
  (fresh `pub get`, fresh container) — deterministic, not flaky.
- Full package suite (`flutter test --no-pub --reporter=expanded`) inside
  the container: **3497 tests, 0 failures** — every previously-failing
  golden (both G15's 3 and this gate's 14) now passes, and nothing else
  regressed.
- Independent second-environment confirmation via `act` running the real
  `analyze-and-test` job end to end (`subosito/flutter-action@v2` on
  `catthehacker/ubuntu:act-latest`, the same tooling G15 validated against
  GPT-PM's round-1 MAJOR): **all tests passed, job succeeded** — a fully
  clean run of the actual CI action, not an approximation.

## What this gate does not cover

- Any non-golden test failure (none exist; the full suite is green in both
  environments).
- Any production code change — this gate is fixture-only, same as G15.
- Actually confirming GitHub's own hosted `ubuntu-latest` runner produces
  byte-identical output to `act`'s `catthehacker/ubuntu:act-latest` image —
  not literally the same machine, though it is a purpose-built emulation
  running the real composite action end to end. The next real push+CI run
  on `origin/master` is the first genuine confirmation of that; this is
  recorded honestly rather than overclaimed, per G15's own round-1 lesson.
