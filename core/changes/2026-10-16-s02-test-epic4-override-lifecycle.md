# S02 test epic 4: override value rule, explicit edit, recalculation and source candidates (I50-I53, I56, I57)

## What
- `activity_override_value_rule_test.dart`: I50 (metadata-only mutations keep the override across restarts, generation number grows), I51 (rows G10-G16 passive change, explicit-value case g, g2), I52 (G7-G9, G30, G31, version reconciliation durable and idempotent), I53 (recompute equals the server field by field after restart, then new edits on both devices). Cross-checks the epic 1 literal oracle `golden_override_scenarios.dart`.
- `activity_override_explicit_edit_test.dart`: I56 (1)-(5) and (9) bounded history for 63/64/65/100 operations in two shapes, with every summary accepted by the rule-enforcing fake (userEditCount 0..64).
- `activity_override_recalc_candidate_test.dart`: I57 recalcCandidate (G14, G17, G24-G29), sourceCandidate (G33-G38) and the atomic resolution beneath a cloud override (G41-G46) incl. restart, dropped acknowledgement and idempotent delivery.
- No production change.

## Why
Test plan epic 4, design 3.2 rule 2 and the ATOMIC candidate resolution paragraph.

## Affected paths
The three files above under `mobile/test/features/activity/repository/`.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/repository/activity_override_value_rule_test.dart test/features/activity/repository/activity_override_explicit_edit_test.dart test/features/activity/repository/activity_override_recalc_candidate_test.dart`
Result: green on the last run of each file (final epic run in the findings document).
