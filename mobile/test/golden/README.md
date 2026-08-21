# Golden tests (M8)

Golden-image regression coverage for the HUD primitives every screen is
built from: `HudPanel`, `HudButton`, `HudChip`, `HudToggle`, `HudNavBar`
(`lib/shared/widgets/hud/`). Both themes (`AppTheme.dark()` /
`AppTheme.light()`) are covered for every widget, plus the visually distinct
states that actually differ in pixels (button tone, chip selection, toggle
value) -- 13 PNGs in `test/golden/goldens/`.

## Why these five, and not a full screen

The brief for this gate asked for low-churn surfaces whose exact pixels
matter, not the whole app. The five widgets above are exactly that: they are
what `hud_tokens.dart`'s colour/blur/shadow recipes and `hud_typography.dart`'s
type scale actually paint, so a token regression breaks a pixel here first,
and cheaply -- these widgets change far less often than a screen does.

A full-screen composition (`HomePage`, `ProfilePage`, ...) was deliberately
left out of this first slice. Every candidate wires through several Riverpod
providers and a `GoRouter` (see `test/features/home_page_test.dart`'s
`_buildApp`, which mocks four repositories and a safety-eligibility context
to render one page) and is still actively iterated product surface -- the
opposite of what a golden should pin. Once a composed screen settles, adding
one golden for it is a natural follow-up; it needs no change to the
infrastructure below.

## Running them

```sh
cd mobile
flutter test test/golden/hud_golden_test.dart
```

They also run as part of the ordinary suite (`flutter test`, and the
`flutter test` step in `.github/workflows/flutter.yml`) -- there is no
separate golden CI job or tag.

## Regenerating after an intentional visual change

```sh
cd mobile
flutter test --update-goldens test/golden/hud_golden_test.dart
```

Then look at the diff. `git diff --stat test/golden/goldens/` should touch
only the PNGs whose widget you actually changed; anything else regenerating
is a sign the change had a side effect you did not intend (e.g. a shared
token moved). Commit the updated PNGs alongside the code change that caused
them to move -- never regenerate to "fix" a red build without first
confirming the new pixels are correct on a real device or a design review.

## Font determinism

`flutter test` does not rasterize the app's real fonts by default; every
`Text` paints with `flutter_test`'s built-in placeholder glyphs unless a
test explicitly loads real fonts. `setUpAll(loadHudGoldenFonts)` in
`hud_golden_test.dart` (helper: `test/support/golden_fonts.dart`) loads
Inter, Barlow Condensed, Archivo and Roboto Mono -- the same four families
`pubspec.yaml` bundles for the app itself -- via `dart:ui`'s `FontLoader`,
the primitive `flutter_test`'s own `loadAppFonts()`-style helpers (e.g. the
`golden_toolkit` package, not a dependency of this project) are built on.

Two reasons this was the right trade, not just the available one:

- **The placeholder font is legible-nothing.** It renders every glyph as a
  uniform box, so two panels with completely different text produce
  visually indistinguishable goldens. That defeats the point of a human (or
  a diff viewer) being able to look at a failing golden and see what
  changed.
- **It is not a new source of cross-platform variance.** `flutter test`
  renders through the Skia build embedded in the Flutter SDK's
  `flutter_tester` host runner, not through the operating system's font or
  text-shaping stack. Two machines pinned to the same Flutter SDK version,
  loading the same font bytes, are rendering with the same rasterizer --
  unlike a real device or a browser, which would each bring their own.

`golden_toolkit`/`alchemist` were not added as dependencies: this project
already has everything `loadAppFonts()` needs (`FontLoader`, `rootBundle`,
and the font list itself, sitting in `pubspec.yaml`), and
`test/theme/font_bundle_test.dart` already established the pattern of
reading that `flutter: fonts:` block as data with the `yaml` package rather
than hardcoding a second copy. `golden_fonts.dart` reuses that same
approach so the font list can only drift from `pubspec.yaml` in one place.

`pinGoldenSurface` (same file) pins `tester.view.physicalSize` and
`devicePixelRatio` explicitly for every golden pump, and resets both via
`addTearDown`. `flutter_test`'s default surface size is an implementation
detail of the test framework, not something this suite should depend on --
if a Flutter upgrade changes it, a golden that relied on the default would
shift for a reason unrelated to the widget under test. Each golden also
captures a `RepaintBoundary` wrapped tightly around only the widget under
test (via a `Key`, not `find.byType(RepaintBoundary)`, since `HudSurface`'s
own internals contain further repaint boundaries), so the pinned surface
size only has to be *large enough*, not exactly matched -- the PNG dimensions
are the widget's own intrinsic size, not the window's.

## Exact-pixel comparison: kept, with one caveat stated plainly

Flutter's default `LocalFileComparator` (unchanged here -- no custom
`GoldenFileComparator`, no tolerance/threshold package added) is a byte-exact
PNG diff. Two things make that viable for this project rather than a source
of flakiness:

- **CI is single-OS.** `.github/workflows/flutter.yml`'s `analyze-and-test`
  job always runs on `runs-on: ubuntu-latest`, on a pinned Flutter version
  (`flutter-version: '3.27.1'`). CI-to-CI, the rendering environment does not
  vary, so exact-pixel comparison there is comparing like with like every
  time -- the classic golden-test flakiness (different fonts installed,
  different OS anti-aliasing, different Flutter patch version) does not
  apply to CI run over CI run.
- **What is NOT proven here:** these 13 PNGs were generated and verified on
  a Windows host (the only environment available while building this gate),
  not on `ubuntu-latest`. `flutter_tester`'s renderer is the SDK's own Skia
  build rather than the OS's, which removes the largest source of
  cross-platform drift, but it is not a guarantee that a Windows-rendered
  PNG is byte-identical to what `ubuntu-latest` will produce -- the engine
  binary shipped per-host platform can still differ at the level of exact
  sub-pixel antialiasing. **The first CI run after this change lands is the
  real test of that**, and it may fail even though nothing is wrong with
  the widgets. If it does: regenerate the goldens from a Linux environment
  that matches CI (a `ubuntu-latest`-equivalent container, or a CI job with
  `--update-goldens` that uploads the results as an artifact / opens a PR)
  and commit those in place of these, rather than loosening the comparator.
  A Docker-based attempt to do this directly during this gate did not
  complete in the available session (the local Docker daemon did not
  respond to `docker pull` within a reasonable wait) -- flagged rather than
  silently skipped.
- **Why not switch to a tolerant comparator instead of solving the OS
  mismatch:** a fuzzy/threshold comparator would paper over exactly the
  regressions these tests exist to catch (a hairline colour drifting by one
  token step, a shadow losing a pixel of blur) as readily as it would paper
  over host-rendering noise. Given CI's own environment is already fixed
  and reproducible, the correct fix for a real host-mismatch failure is
  regenerating from that environment, not widening the tolerance everywhere.
