# G15 — form_coach golden-test infrastructure regression

## What this gate covers

The pre-existing flake in `mobile/test/golden/form_coach_golden_test.dart` (3
goldens: `form_coach_live.png`, `form_coach_faulted.png`,
`form_coach_selection.png`), named by GPT-PM as the next Form Coach work item
at G14's closure ("The next legitimate Form Coach work item is the separate
golden-test infrastructure regression — not another G14 round").

## What was found

All 3 goldens failed — both together and each individually via `--plain-name`
— at 54.73%/54.46%/95.55% pixel diff on Windows. The leading hypothesis going
in, grounded in this repo's own `test/golden/README.md` (written for the
original 13 HUD-primitive goldens, M8 gate), was Windows-vs-CI
(`ubuntu-latest`) rendering-engine drift.

**That hypothesis was tested and disproven, in two independent Linux
environments.** First, `docker pull ghcr.io/cirruslabs/flutter:3.27.1` (a
Flutter-maintainer-built image bundling that exact SDK version) succeeded —
Docker Desktop, which a prior session in this repo recorded as unresponsive,
now works. Running the same 3 goldens inside that container reproduced
near-identical failures (55.31%/55.40%/95.80%), and a second, fully
independent container run (fresh `pub get`, fresh container) reproduced
**bit-identical** diff percentages and pixel counts both times. A worktree
pinned to the exact commit the goldens were last regenerated at (`2a1307e`,
G13) reproduced the same failures too — ruling out any code drift since.

Round-1 GPT-PM review (MAJOR) correctly flagged that the CirrusLabs image is
NOT what `.github/workflows/flutter.yml` actually runs — CI executes
directly on GitHub's `ubuntu-latest` via `subosito/flutter-action@v2`, a
materially different environment (different base image, different Flutter
build/packaging) even at the same pinned SDK version, and this gate had
overclaimed it as "the same image used by CI." Addressed with a second,
independent line of evidence: installed `act` (nektos/act, a local GitHub
Actions runner) and ran the workflow's actual `analyze-and-test` job —
`catthehacker/ubuntu:act-latest` (an image purpose-built to emulate
GitHub-hosted runners) executing the REAL `subosito/flutter-action@v2`
composite action, which fetched Flutter `stable-3.27.1-x64` at the exact
same framework revision (`17025dd88227cd9532c33fa78f5250d548d87e9a`) both
other environments reported. This is the closest reproduction of actual CI
achievable without pushing to a branch.

Visual inspection of the diff images (`test/golden/failures/*_masterImage.png`
vs `*_testImage.png`) showed the actual defect: the committed master PNGs and
what the current code deterministically renders show **different backdrop
photographs** (e.g. `form_coach_selection`'s ambient background is a warm
sunset/mountain scene in the master, a cool blue-grey mountain scene in the
fresh render) — not sub-pixel antialiasing noise. `coachBackdropProvider`
(`form_check_providers.dart:391-409`) picks a scene via a seeded
`math.Random(7)`: `build()` consumes the first `nextInt()` call, and
`FormCheckPage`'s `initState` unconditionally schedules a `shuffle()` call
(a second `nextInt()` call) in a post-frame callback on every mount
(`form_check_page.dart:142`), regardless of the page's initial phase. This is
fully deterministic given a fixed Dart/Flutter version — the mismatch is
between whatever produced the previously-committed PNGs and what Flutter
3.27.1 / Dart 3.6.0 (the version this repo, CI, and this container all use)
actually produces now. The committed goldens were stale, not the code buggy
and not the test flaky.

## The fix

Regenerated the 3 PNGs with `flutter test --update-goldens
test/golden/form_coach_golden_test.dart`, run inside the Linux
Flutter-3.27.1 container used for regeneration (`ghcr.io/cirruslabs/
flutter:3.27.1`, the same image used for diagnosis — not literally the
GitHub-hosted runner; see "What was found" for the independent `act`-based
confirmation against the real CI action). `git diff --stat` confirms only
the 3 expected PNGs changed
(no code, no other fixture). Each new image was inspected by eye and is
correct: legible layout, correct HUD readouts, correct demonstration
silhouette, a real (if different) backdrop photograph in every case — not a
blank/broken render.

## Verification

- Full `form_coach_golden_test.dart` file: 3/3 pass, inside the
  `ghcr.io/cirruslabs/flutter:3.27.1` container.
- Each of the 3 tests individually via `--plain-name`: pass in isolation
  (the specific order-independence concern this test file's own comments
  already worried about, from G13's prior fix).
- Repeated (2 independent fresh container runs, fresh `pub get` each time):
  identical pass result both times — not flaky.
- Full package suite (`flutter test --no-pub --reporter=expanded`, matching
  CI's own step) inside that container: 3483 tests, 14 failures — **zero**
  are in `form_coach_golden_test.dart`. The 14 are all pre-existing, in
  `hud_golden_test.dart` (10) and `composed_screen_golden_test.dart` (4) —
  see "Related finding" below.
- **Independent second-environment confirmation via `act`**: ran the
  workflow's real `analyze-and-test` job end to end (real
  `subosito/flutter-action@v2`, `catthehacker/ubuntu:act-latest` runner
  image) — 3481 tests, 14 failures, exactly the same 14 (`hud_golden_test`
  ×10, `composed_screen_golden_test` ×4), **zero in
  `form_coach_golden_test.dart`**. Two independent Linux environments, one
  running the literal CI action, agree.

## Related finding — NOT fixed under this gate, flagged instead

The ORIGINAL 13 HUD-primitive goldens (M8 gate) and the 4 composed-screen
goldens (OBS-1 item) — all captured on Windows — show real 2.13%–13.91%
pixel drift against actual `ubuntu-latest`-equivalent rendering, confirmed
now in TWO independent Linux environments including the `act`-run of the
literal CI action. This is exactly the risk `test/golden/README.md`'s
"Exact-pixel comparison" section already named in writing ("the first CI
run after this change lands is the real test... it may fail even though
nothing is wrong with the widgets") — and given the `act` run reproduces
the real workflow action closely enough to fetch the identical Flutter
build CI itself fetches, this is very likely CURRENTLY true on master's own
GitHub Actions CI right now, not merely a theoretical risk (this session
could not directly confirm the live Actions history — the fetch was
unauthenticated and the repo returned 404 — but the evidence gathered here
strongly suggests it). If so, it predates this gate and is a separate,
pre-existing gap in the M8/OBS-1 goldens, not something this gate's
`form_coach_*` fix touches or introduces. Per SS17's own gate-scoping
discipline ("a closed gate is not reopened for an unrelated improvement
discovered later"), fixing those 14 is out of scope here and is recorded as
a distinct backlog item for a future gate, using the exact same
regenerate-from-a-CI-matching-environment method this gate just validated
(and now has two independent tools for: the CirrusLabs container, and
`act` running the literal action).

## What this gate does not cover

- The 14 HUD-primitive/composed-screen goldens above (flagged, not fixed).
- Any non-golden test failure (none were found attributable to this change).
- Any production code change — this gate is fixture-only.
