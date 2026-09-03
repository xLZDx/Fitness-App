# G17 — the Form Coach figure is the design reference's figure

Rosetta plan `fitness_app-2026-09-03T21-35-35-727Z-06c378` (rev2), GPT-PM
`VERDICT: APPROVE` on hash `75d08377…7a165` (request
`b3e7d2a4-5c16-4f8b-9a0d-2e6f8c1b7d43`). Rev1 (`…6a7e57`) was refused with
`VERDICT: BLOCKER`; what changed between the two is recorded below because
the refusal shaped the gate.

## What this gate covers

Operator instruction, 2026-09-04, verbatim: *«я уже больше 10 раз просил чтобы
демо было 100% похоже на это и при упражнении был тот же силует только
исполняющий упражнения»* — with the design reference screenshot attached
(`core/design/reference/fitness_hud_v1/screenshots/04-form-coach.png`, the
`Fitness Form Coach Phone.dc.html` artboard).

The reference's figure is not a drawing. `Fitness Form Coach Phone.dc.html`
lines 22–25 put a **video** behind the HUD —
`uploads/clip2-1786933639870-ww0q.mp4`, a real person squatting side-on,
dark against a dusk lake, with a lit white skeleton on the body — and
`README.md` §8 (line 109) says the product replaces the clip's glow layer
with a real pose-overlay: bones 3–3.4 px `#FFFFFF`, green/red drop-shadow
glow, dashed pulsing ring on the faulty joint.

What the app showed instead, on the operator's S23 and Mi 9T Pro: a white
filled **target outline** (`_Silhouette` / `_SilhouettePainter`) drawn over
everything, at all times — an abstract shape authored for scoring, never
for looking at. Three rounds of repair (filled, composed, fitted — the last
one yesterday, ce770910, GPT-PM APPROVE, all tests green) each shipped and
each was rejected on device, because the shape itself was never what was
asked for.

## The invariant this gate establishes

**One figure on the panel, in one visual language, everywhere:**

1. **Demonstration** (picker, and the live panel while nobody is tracked):
   - squat → the reference clip itself, bundled
     (`mobile/assets/coach_demo/squat_side.mp4`, 540×960, 10 s loop, 680 KB,
     derived from the reference with ffmpeg: cropped to 9:16 around the
     figure so the prototype's own baked-in chrome — "Form coach" bar,
     "reps 0", the bottom toast — is outside the frame; the one line that
     could not be cropped without cutting the standing head, "stand tall
     to start counting", sits at the top 3–7 % of the frame under the
     exercise chip, exactly where the reference artboard shows it too);
   - every other authored movement → the same figure the avatar draws for
     the user (dark body, faint rim, white glowing bones, joint dots),
     animated between the movement's two authored ends
     (`DemoFigurePainter`, through `coach_figure_paint.dart`). No movement
     lost its demonstration (GPT-PM rev1 MAJOR #2).
2. **Live, body tracked**: the demonstration cross-fades out (300 ms,
   reduce-motion aware) behind the user's own figure — the avatar in avatar
   mode, the darkened camera image with the reference-style skeleton in
   camera mode. The white outline is gone from every screen and every
   state; `form_check.silhouette` exists in no widget tree.
3. **One implementation**: the avatar's body/glow/bone/joint/ring drawing is
   extracted into `coach_figure_paint.dart` and the avatar, the drawn
   demonstration and the camera skeleton all draw through it. The camera
   skeleton was violet 3 px diagnostic lines; it is now the reference's
   overlay — behind the existing toggle, **default unchanged (off)**: GPT-PM
   rev1 BLOCKER #1, flipping the default needs real-device tracked-body
   evidence on the production camera path (person off-centre, both
   lenses/flip paths, S23 + S8), which is a separate gate.
4. **Video lifecycle contract** (GPT-PM rev1 MAJOR #3): the decoder runs only
   while the clip is what the user is looking at — `active` from the host,
   false after the fade-out completes, on leaving the screen, on error;
   paused in the background, resumed only if still active; never plays
   under reduce-motion (poster only); disposed on unmount. Controller
   creation is injectable (`coachDemoControllerFactoryProvider`) so every
   clause is a widget test against a recording controller, not a promise.

## What was found while building it

- **The panel's layers were remounting on every status change.** The cue
  column at the end of the panel's `Stack` comes and goes with
  `instructing`, and `Stack` pairs unkeyed children by position from the
  bottom — so when it disappeared, the avatar's slot received the
  demonstration's widget, could not update it, and re-inflated the whole
  layer. For a `CustomPaint` that was an invisible rebuild (it has been
  happening to the avatar and the skeleton since they were added); for a
  video decoder it is a re-initialisation, and in the widget test it was a
  controller used after dispose. All five layers are keyed now
  (`form_check.layer.*`); `live_demo_test.dart` asserts the clip mounts
  exactly once.
- **A demonstration layer that mounts with a body already on screen** has no
  fade to wait out — `AnimatedOpacity` does not animate its initial value —
  so `_LiveDemo` reads its first visibility lazily instead of assuming it
  started visible.
- `flutter test --no-pub` does not regenerate `gen_l10n` output: a changed
  `.arb` string is invisible to a test until `flutter gen-l10n` (or a
  `pub get`) has run. Cost one false failure here.

## Evidence

See `core/DECISION_LOG.md`, entry "G17 — the Form Coach figure is the
design reference's figure", for the test counts, golden regeneration,
device screenshots and the GPT-PM commit review.

## Out of scope, deliberately

Scoring and rule logic (`poseMatchProvider`, the silhouette-match rule read
the same targets as before — only the drawing changed); the ring gauges,
cue chips and counters panel (G12–G16); backdrop scenes; clips for movements
other than the squat (the drawn figure covers them until clips exist);
the intro card; flipping `showSkeletonProvider`'s default.
