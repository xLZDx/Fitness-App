# S02 test epic 6b: export, download URLs, log hygiene and telemetry callable and schema (S02-07, S02-09)

## What
New `export_downloads_telemetry.test.ts`: F29, F30, F31, F70 (export parity, truncation, isolation, worst-case sizing and continuation paging), F32 and F69 (download URLs per state, no existence oracle, 20/21 ids), F33 (log hygiene across upload, commit, delete, export, download), F34, F35 (12 poison cases), F36, F37, F73, F74 (schema table against the shared fixture), F90, F93.

## Why
The export, download link and sanitising telemetry callables carry the GPS-PRIV-050/052/053/094/098 guarantees and had no functions tests. Plan F73 asks for an exactly 16 KiB valid batch; with at most 100 closed-schema events a valid batch cannot reach 16 KiB, so the size gate boundary is asserted on the sanitiser with a padded payload (16384 passes the gate, 16385 is batch_too_large).

## Affected paths
- `functions/src/__tests__/activity/export_downloads_telemetry.test.ts`

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/export_downloads_telemetry.test.ts`: 1 suite, 53 tests passed. No production code changed.
