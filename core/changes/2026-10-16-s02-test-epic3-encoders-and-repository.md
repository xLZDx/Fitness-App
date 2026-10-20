# S02 test epic 3: GPX and FIT encoders, test-only FIT decoder, summary-only upload and offline queue (U17, U18, U19, U20, I11, I12)

## What
- `mobile/test/support/fit_test_decoder.dart`: test-only FIT decoder with its own bitwise CRC-16/ARC (independent of the encoder's nibble table), header CRC, file CRC, size checks, definition and data messages, invalid values mapped to null.
- `mobile/test/features/activity/data/fit_encoder_test.dart` (U19): decoder self-tests (CRC vector 0xBB3D, encoder CRC equals the independent CRC, a flipped byte at EVERY position of a small file is detected, truncation / extension refused) and the structural round trip of the 100 valid sessions (file_id, session fields, sport and sub_sport literals, lap and record counts, timestamps, semicircle lat/lon, heart rate, cumulative distance).
- `mobile/test/features/activity/data/gpx_encoder_test.dart`: U17 (XML parse, trkpt count, lat/lon within 1e-6, exact times strictly increasing, `ele` where altitude exists and not invented elsewhere), U18 (62 non-GPS sessions give `no_geometry` for both audiences while FIT and JSON still encode; GPS sessions never give it; stream-lost entry exports only JSON), local export hook over a real in-memory journal, U20 (owner = full stream; shared trims the first and last 200 m by an independent along-route sum; 0 m and 500 m privacy values; short route; no heart rate in shared).
- `mobile/test/features/activity/repository/firestore_activity_repository_test.dart` (I11, I12): the backend map keys are inside the `hasOnly` list parsed from `firestore.rules`, no geometry or heart-rate text, no Firestore delete in the interface or the adapter (delete goes through the `deleteActivity` callable); offline -> reconnect -> second flush leaves one document per id, also across a restart.
- No production change.

## Why
Design 7 (export encoders, structural round trip through a test-only decoder), design 3.1 / 4 (summary-only upload), design 6.2 (offline queue).

## Affected paths
The four test files above (support decoder included).

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/data/fit_encoder_test.dart test/features/activity/data/gpx_encoder_test.dart test/features/activity/repository/firestore_activity_repository_test.dart`
Result: `All tests passed!` (11 + 16 + 10 tests).
