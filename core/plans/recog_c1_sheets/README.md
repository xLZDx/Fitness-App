# RECOG-C1 — contact sheets, both arms

Step 9 of plan `fitness_app-2026-09-05T11-25-16-919Z-377ee0`. Its Definition of Done: *a future
reviewer sees which image is in row N without a local screenshot.*

52 photographs, each used twice. `arm_a/` is the full frame the operator shot; `arm_b/` is the
same photograph cropped to what the scanner's viewfinder actually keeps — the crop discards 57 %
of a portrait frame's height, which is visible here and is worth seeing before reading any
accuracy number. Every tile is captioned `#<index> <filename>`, and that index is the `image_id`
used in `RECOG_C1_GROUND_TRUTH_2026-09-05.csv` and `RECOG_C1_RUN_PLAN_2026-09-05.csv`.

`../RECOG_C1_SHEET_MANIFEST_2026-09-05.csv` carries the sha256 of every sheet, so a reader can
tell whether the sheet they are looking at is the sheet this measurement was reviewed against.
The per-photograph hashes — originals, crops, and the crop geometry each one used — are in
`../RECOG_C1_ARM_MANIFEST_2026-09-05.csv`.

**These are the operator's own photographs of their own gym, and identifiable people appear in
them, including a child.** They are committed because the measurement cannot be audited without
seeing what was measured, and because this repository is private. They are not fit to leave it:
do not publish these sheets, attach them to an external review, or make the repository public
without the operator's explicit say-so. If the sheets ever need to travel, blur faces first —
nothing about the measurement depends on a face being legible.
