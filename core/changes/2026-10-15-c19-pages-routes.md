# C19 pages and routes (part 3)

What: `weight_log_page.dart` (add/edit/delete weigh-ins, data-notice gated,
first-review hint), `plan_sources_page.dart`, `plan_explainer_page.dart`, and
routes `/nutrition`, `/nutrition/weight`, `/nutrition/sources`,
`/nutrition/how-it-adapts` appended to `mobile/lib/core/router/app_router.dart`
(imports plus one block before the C15 routes; nothing else touched).

Why: sprint story C19, design D-72, s17.9, s18. The result screen's
"See your plan" already pushes `/nutrition`.

Verification: none run (tests are written and run by the test agents).
