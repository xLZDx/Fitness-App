# S02-08 change record: activity stream bucket runbook completed

Date: 2026-10-16. Story: S02-08 (design 5, 6.1, 6.2, 6.3, 8.1; GPS-PRIV-078; test id F92 name parity).

## What changed

`runbooks/activity_stream_bucket.md` completed: soft-delete window command and the OPEN decision (GPS-PRIV-078); IAM table (activity runtime identity, `fn-account-delete`, nobody else) with a canary; tombstone TTL policy on `activity_tombstones.expireAt` as an operator step and release prerequisite, plus the index prerequisite; deploy order (functions, telemetry callable -> client -> rules, permanent rules floor, flag order); fence and late-sweep semantics; signals and alert table keyed by the event names the code emits; rollback.

## Why

Design 5 and 6.3 name this runbook a deliverable; S02-04a left the identity and the TTL open.

## Deviations and notes

- FACT: the activity functions set no `serviceAccount`, so they run as the default runtime identity; the design assumed a dedicated stream identity. The runbook states the real situation and leaves "dedicated `fn-activity` identity or accept the default" as an OPEN operator decision (the grant to a shared identity widens its reach).
- The alert table maps signals to the event names found in the code (`ACTIVITY_*_EVENT`, `DEBUG_TELEMETRY_*`); exact payload field names were not re-verified per metric, the runbook says the code wins. F92 name parity must be checked by the test agents.
- No release-guard check (as exists for Body Scan) was added; that would be code and is not in S02-08.

## Verification state

No checks were run; the commands in the runbook are unexecuted.
