# S02 test epic 1: findings (plan versus design versus code)

Scope: ids U01-U09, U12, U13, U27-U32, U37-U41 (Dart unit tests, stories S02-00 and S02-01).

## Corrections to the plan

1. Latitude sentinel precision (plan 2.1 says: round to 6 decimals, then force the tail `7351`). Forcing the last four digits of a 6-decimal value moves a position by up to 0.01 degree (about 1.1 km), which collapses a 3-9 m random walk onto a coarse grid. The generator uses 10 decimals, so the byte tail `7351` is kept and the geometry stays real-shaped. Longitudes use 6 decimals.
2. Plan 2.1 counts "9 named records" for the hostile set while plan 2.4 lists 1 + 2 + 4 + 1 = 8. The generator has 9: the 8 of section 2.4 plus one `schema = 99` record (H-6), which U03 needs.
3. Plan U08 says the payload must not contain `heartRate`. The builder copied the NAME `heartRate` into `fieldsContributed` of the provenance records. Read literally the oracle fails, so the builder now drops heart-rate-named entries from that list (production fix, see below).
4. Plan G17 says the already recorded candidate stays recorded after a server-only change is adopted. `adoptServerValue` replaced the override and lost the candidate. The candidate is now carried over (production fix).
5. Plan G32 says only `atVersions` changes in the record when a record is loaded under a new version triple. `SummaryProjection.reconcile` also advances the three session-level version strings (`formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion`). The pure test asserts the override part exactly and tolerates these three keys. NOT changed in production: it needs a design decision (design 3.3 does not say whether a loaded record is re-stamped).
6. Plan G18 "keep this device removes an older override" has no pure function in the production code (only the repository can do it). Not testable in this epic; belongs to the repository tests (I-series).
7. Plan U08/U32 "a GPS sample map carrying an extra `hr` key": `SampleStream` has no extras, so the key cannot exist on a stream object. The test feeds the stored map through the tolerant reader and asserts the key is gone from the payload.
8. The golden file layout of `s02_summaries_100.json` is not defined by the plan: `{version, note, summaries: [{id, summary}]}`, timestamps as ISO-8601 UTC strings. The rules test R25 must convert them.

## Production defects found and fixed (smallest change)

| File | Defect | Found by |
|---|---|---|
| `activity_session.dart`, `lap.dart`, `sample_stream.dart` | The tolerant reader threw (`Infinity or NaN toInt`) on non-finite numbers for `utcOffsetMinutes`, `schema`, lap `index`/timing/`strokeCount` and stream offsets | U12 fuzz |
| `activity_stream_payload.dart` | Heart-rate-named entries leaked through `fieldsContributed` | U08 |
| `summary_projection.dart` | `adoptServerValue` dropped an existing `recalcCandidate` | U41 G17 |

## Not covered here

Integration rows of plan 1.16 (restart through a real journal, lost-acknowledgement replay against a fake backend, two-device chains) belong to the I-series and E04; this epic covers them at the pure level only.
