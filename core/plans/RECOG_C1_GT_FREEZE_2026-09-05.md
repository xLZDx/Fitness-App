# RECOG-C1 — ground-truth freeze

Plan `fitness_app-2026-09-05T11-25-16-919Z-377ee0`, hash `b78bffa5...`, step 4.

**No cloud call has been made.** This freeze exists so that it cannot be said
afterwards that the ground truth moved to meet the results. Everything below is
recorded before the first observation, and `git log` order is the proof.

## What is frozen

| file | sha256 (working tree, CRLF on this machine) | sha256 (newline-normalised) | bytes |
| --- | --- | --- | --- |
| `core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv` | `2e631f5c80011ef350ff483c4fd47bbefd9fc46f1faa7ca2c72d7954664921c3` | `2e631f5c80011ef350ff483c4fd47bbefd9fc46f1faa7ca2c72d7954664921c3` | 42525 |
| `core/plans/RECOG_C1_LABELS_2026-09-05.csv` | `6024192f1f7e586ee01cdd655e55967661323cdfe4de062a1e96b6a5d70f6242` | `13e56867ed2eac60ffba75f85f0dbb707e9339ca7ac9b4b41fe37f1fcfe7ef1a` | 25222 |
| `core/plans/RECOG_C1_ARM_MANIFEST_2026-09-05.csv` | `dfde087a8532173d425714bd24fe5d3497984334d614720a7678a7ff6491f7e6` | `b8522ae6b63b870b3223c8b9e295d54209e162f0b0fd099dfd0ecd33e56bccad` | 12697 |

Two hashes per file, deliberately: git checks these CSVs out as CRLF on this
machine while the generators write LF, so the working-tree hash and the hash a
reader gets from the generator's own output differ for a file the generator
wrote. Recording only one of them would look like a reproducibility failure to
whoever compared the other. The image bytes — which is what the reproducibility
claim is actually about — are identical either way.

The ground-truth content commit is `5f1ddde`; this file is its successor and
the direct ancestor of the harness commit.

## What is in it

- 104 rows, 52 photographs × 2 arms, keyed by `(image_id, arm)`.
- Per arm: 26 `canonical_single`, 26 `multiple`, **0 `out_of_catalog_single`,
  0 `none`**, 3 `unresolved`.
- 9 distinct labels → 9 distinct equipment ids, every one an exact alias in the
  production catalogue and a member of the server's `CANONICAL_MACHINES`.
- `gt_equivalent` is `true` for all 52 photographs — derived from the frozen
  rule over two separately-authored labellings, not asserted.

## The three rows that are deliberately NOT settled

`20260730_135543.jpg` (#15), `20260806_140012.jpg` (#29) and
`20260810_131311.jpg` (#47) are the same Star Trac plate-loaded unit from three
angles; #47 is the frame from the failing recognition the operator raised. They
carry the provisional label `lat pulldown` with `gt_status = unresolved`.

`unresolved` is not a placeholder for "we will decide later once we see what the
model said". It is a scoring state: **every correctness metric in step 8 is
computed over `gt_status = resolved` rows only**, so these three photographs
(six rows) contribute to no accuracy number in either direction.

The identity question is with the operator, with the images, in
`reports/RECOG_C1_BASELINE_2026-09-05.ru.html`. If an answer arrives **before
the first inference**, exactly those six rows are relabelled, the ground truth
is re-frozen with new hashes recorded here, and the harness commit is rebuilt on
top — cheap, because nothing has been measured yet. If an answer arrives after
the first inference, the rows stay frozen as they are and the answer is recorded
in the results as a limitation, because a ground truth edited in sight of the
outputs is not a ground truth.

## What this freeze does not claim

- Both arms were labelled by the same person, in the same sitting, aware of the
  other arm. The per-arm structure makes a genuine A/B difference representable
  and visible; it does not make the two judgements independent.
- `20260810_131311.jpg` is not prediction-blinded: it is the photograph whose
  failing recognition started this work.
- One gym, one photographer, one phone. This is a baseline, not a benchmark.
