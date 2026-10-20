# Compile fixes for the app_router.dart closure (batch 1)

Why: test/router/nutrition_profile_route_test.dart could not compile; code was written without ever being compiled.

Changes (no behaviour change):
- data_export/server_export.dart: CloudFunctionsServerExport and FakeServerExport now `extends ServerExport` instead of `implements`, so they inherit the concrete fetchAll/fetchPage added by C25 (the fake keeps its own fetch; fetchPage stays null).
- body_scan/state/body_scan_flow_driver.dart: added imports for ScanPose (progress_photos/scan/scan_pose.dart) and JobStatus (body_scan/data/body_scan_job.dart).
- body_scan/body_scan_result_page.dart: the mutable `row` is copied to a final `openRow` so null promotion works inside the closures.
- nutrition_plan/widgets/kcal_range_slider.dart: `package:intl/intl.dart` now hides TextDirection so dart:ui TextDirection.rtl resolves.
- trend_chart.dart already imports CustomSemanticsAction from flutter/semantics.dart; no change needed.

Verification: `flutter test test/router/nutrition_profile_route_test.dart --no-pub` -> 8 passed.
