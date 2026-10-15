# Change record: C03 client-flags-and-gates (Body Scan + Nutrition Coach, epic E0)

## What changed
- NEW `mobile/lib/core/config/body_scan_flags.dart`: `BodyScanFlags {cloudPhotos, foodAi, foodLookup}` (all default false), compile-time values in `BodyScanFlags.compileTime` from `bool.fromEnvironment('BODY_SCAN_CLOUD' | 'FOOD_AI' | 'FOOD_LOOKUP')`, exposed through `bodyScanFlagsProvider` (tests override it). Same shape as the existing `core/config/demo_features.dart` (VERIFIED: config folder exists, one flag file with a const plus a provider).
- `mobile/lib/features/subscription/data/feature_gates.dart`: `AppFeature` gains `bodyScan`, `nutritionPlan`, `weeklyReview`, `foodDiary`, `foodAiRecognition`, `foodBarcodeLabel`. Default (Q-2, D-26): `bodyScan` is gated exactly like the existing `ScanAccess.needsSupporter` (standard or celebrityTrainer tier); the other five return true. The `canAccess` switch stays exhaustive. VERIFIED: no other code switches over `AppFeature`, and `scanAccessProvider` is unchanged.
- NEW `mobile/lib/core/privacy/data_notice.dart` (D-79): `DataNoticeStore` (prefs-backed `PrefsDataNoticeStore`, key `data_notice.v1.<uid>`, `InMemoryDataNoticeStore` for signed-out/tests), `dataNoticeStoreProvider`, `dataNoticeAcknowledgedProvider`, `ensureDataNoticeAcknowledged(context, ref)` (shows the sheet when needed; false means the caller defers its write) and a one-tap modal sheet (scrollable body, header semantics, extra Vertex AI paragraph only when `BodyScanFlags.foodAi`). Modelled on `progress_photos/data/photo_consent.dart` (in-session answer survives a failed write).
- `mobile/lib/l10n/app_en.arb`, `app_ru.arb`: `dataNoticeTitle`, `dataNoticeBody`, `dataNoticeBodyFoodAi`, `dataNoticeAcknowledge` (SD-3: keys land with the only UI that uses them). RU text is product content.
- `core/DECISION_LOG.md`: C03 entry.

## Why
Every operator-blocked capability needs a flag, a default and a fallback (E0-S4), and the tier decision must be a one-line change per feature (D-26). The data notice must exist before the first server-stored weight/plan/diary write (C14+).

## Affected contracts and paths
New compile-time `--dart-define` names; `AppFeature` enum (+6 values); new device-local preference key `data_notice.v1.<uid>` (joins the account-deletion wipe list in C25); 4 ARB keys EN+RU. Nothing calls the notice yet.

## Deviations
The coordinator said l10n was not needed yet, but the sprint plan lists the `dataNotice*` ARB keys in C03 and the sheet cannot render without them, so they are included.

## Verification state
Not run, per DEVELOPMENT RULES v4. Not analyzed or compiled; the generated `flutter_gen` localizations are not regenerated here.
