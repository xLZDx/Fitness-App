# Screenshots

Curated evidence for gates whose effect is visual. Not a gallery — a file lands
here only when a decision needed a picture to be reviewable, and it says which
gate it belongs to.

Regenerate with the harness that produced it; do not touch the PNGs by hand.

## `g12b_{dark,light}_{before,after}.png`

Gate **G1.2b** — hardcoded `Colors.white` replaced with the ink token wherever it
sat on brand artwork (an aurora gradient or a solid aurora hue).

Harness: `mobile/test/_g12b_board.dart`. It renders the **real** edited widgets —
`ExerciseThumb`, `WarmupCalculator`, `PlateCalculator` — not mock-ups of them.

```
cd mobile
flutter test test/_g12b_board.dart            # after
git stash && flutter test test/_g12b_board.dart && git stash pop   # before
```

The output filename carries `git describe --dirty`, so the two runs cannot
overwrite each other; rename the pair to `_before` / `_after` afterwards.

What to look at: the warm-up ramp rows. Row 3 sits on teal→lime and row 4 on
orange→yellow, where white scored **1.27:1** and **1.38:1** — the two worst
stops in the palette. The measurement behind the change is in
`mobile/test/theme/app_semantic_colors_test.dart`; these images are what it
looks like.

`GlassNavBar` is deliberately absent: it lays itself out against the shell's
constraints and overflows in this harness, identically before and after, so it
would have shown the harness rather than the change.

## `g12c_{dark,light}_{before,after}.png`

Gate **G1.2c** — six alphas of `colorScheme.onSurface` collapsed into
`textSecondary`. Same harness, same commands; `before` is the G1.2b commit.

This one is subtle to the eye and must be read by measurement, not by
impression: 10,483 pixels differ, all of them caption glyphs. On the **light**
theme the two visible captions go from **4.02:1 → 4.96:1** and **3.92:1 →
4.89:1** — both were under the 4.5:1 AA bar and are now over it. On dark they
go 5.53 → 7.82 and 5.66 → 8.00, which were already passing.

Measure it rather than squinting:

```python
from PIL import Image
a = Image.open('g12c_light_before.png').convert('RGB')
b = Image.open('g12c_light_after.png').convert('RGB')
# rows that differ, then the darkest glyph pixel in each band vs its own
# most-common background colour
```

A caution learned here: taking the darkest changed pixel of the WHOLE image
before and after compares two different glyphs on two different backgrounds,
and reported this change as a regression when it is not one. Band by band, each
against its own background, or the number is meaningless.
