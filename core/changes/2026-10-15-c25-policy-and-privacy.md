# C25 part 4: lifecycle policy rows and privacy policy rewrite

## What changed
- `scripts/ci/data_lifecycle_policy.json`: rows for `body_scans`, `body_scan_settings`, `weight_entries`,
  `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods` (classification BOTH) and
  `nutrition_cache`, `body_scan_purge_state` (EXEMPT, all client access NONE). `clientAccess` follows
  `firestore.rules`: reads OWNER; `body_scans` create/delete NONE, update CONDITIONAL;
  `nutrition_plan_reviews` update NONE; other creates/updates CONDITIONAL (shape-validated); deletes OWNER.
- `public/privacy.html` (bilingual EN + RU, structure kept): new sections on the body scan (on-device
  provisional result, on-device face blur, consent, birth-year age gate), cloud scan photos (default
  retention 0 with "within 48 hours", 30/90/365 options, one-tap deletion), weight/plan/diary under the
  first-use notice, meal/label photos processed by Vertex AI when AI food recognition is on and not stored,
  public nutrition databases, no analytics SDK receiving photos or body metrics; retention, export and
  deletion paragraphs updated; processors list extended. Date stamp 15 October 2026. An HTML comment marks
  the wording as a draft pending review (Q-10).

## Open for the test agents (not done here by instruction)
Each CONDITIONAL cell names a test `CONDITIONAL cell <collection>/<op>: ...` in
`functions/src/__rules__/data_access_policy.test.ts` (the checker needs inline `doc(db, "...")` paths plus an
assertSucceeds and an assertFails call). Those tests do not exist yet and must be added; the todo block
"Body Scan + Nutrition Coach policy rows (DEFERRED to C25)" in that file can then be turned into real tests.

## Verification state
JSON parse only. The data-lifecycle and legal verification scripts were not run (sprint rule).
