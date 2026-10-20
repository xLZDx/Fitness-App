# Change record: C08 activity model foundation and pure merge/dedup

## What changed
New logic-only feature `mobile/lib/features/activity/data/` (no Flutter imports, no UI, no persistence, no adapters):
- `sport_type.dart` (`SportType`, unknown -> `other`, compatibility families), `sample_stream.dart` (`StreamKind` with canonical units, `SampleStream` with strictly increasing offsets and parallel GPS lists, validated by `checked` / `tryFromJson`), `lap.dart`, `source_record.dart`, `activity_summary.dart` (nullable SI fields, pace derived never stored), `activity_session.dart` (`ActivitySession`, `ActivityPrivacy`, stable id `act_<sha1>` via `activityIdFor`, tolerant JSON with unknown-key passthrough, canonical-JSON equality).
- `device_source.dart`: `DeviceSource`, `SourceKind`, `SourceCapabilities`, `SourcePermission`, `LiveSample` and the design 31.6 capability matrix constants (hypotheses; vendor clouds all unknown).
- `merge_policy.dart` and `activity_merger.dart`: `merge(candidates, policy)` implementing design 31.3 rules 1-6 deterministically: exact-duplicate removal, same-workout matching (sport family, time IoU >= 0.8 or start 120 s / end 300 s, distance within 15 %, mean GPS distance <= 100 m), echo detection (platform record naming a held source, ranked last), brick/pool-vs-open-water kept apart, per-kind stream choice (>= 80 % coverage, never mixed within a kind), complementary streams aligned by start-time skew (> 5 s not aligned), summary recomputed from merged streams, > 10 % disagreement noted in `mergeNotes`, user edits always win, provenance of every contributing record kept, optional `joinSplits` (default off).
- `fake_device_source.dart`: in-memory `DeviceSource` for tests.

## Why
Sprint plan commit C08; design s31, D-34. Foundation only: no sport UI, no persistence, no adapters.

## Deviations (simplifications, recorded)
- Clock skew of a complementary stream is the difference of session start times, not a cross-correlation search; beyond 5 s the stream is not taken.
- When no source covers a stream kind >= 80 % the kind is left out of the merged session (the originals stay in provenance).
- Merged-session id is the id of the highest-priority member.
- Capability levels use a four-value enum (yes/partial/no/unknown) instead of booleans so the unknown vendor row is expressible.

## Affected contracts and paths
New files only; `crypto` (already a dependency) is used for the stable id.

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests: coverage map T28, T29, T37.

## Review state
Pending the test phase and specialist reviewers.
