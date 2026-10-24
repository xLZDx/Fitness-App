# Change record: rank recommendations and programmes by training context (2026-10-24)

Base: master 06479b94. Operator report from a real phone: the home recommendations and the generated programme were nearly the same for gym, home and outdoors.

## What changed
- mobile/lib/features/training_context/data/training_context.dart: new `contextAffinity(item, context, access)` and `rankForContext(pool, focus:, context:, access:)`. The context used to only remove items (gym removed nothing); it now also orders them. Gym prefers machines, cables, barbells, then dumbbells and kettlebells, and deprioritises bodyweight; home prefers kit the person owns, then bodyweight; outdoors prefers bodyweight, bands, bars, rope and outdoor movements, and deprioritises machines and barbells; stretch and mobility items and yoga are neutral. Equipment kind is decided by the equipment label first; an equipment id counts as a machine only from an explicit id set taken from the catalogue.
- mobile/lib/features/home/data/suggestion_builder.dart: additive bonus 0.5 * affinity when a training context is present (applied after the filters, so it never readmits a removed item).
- mobile/lib/features/programmes/state/programme_providers.dart: the programme rank callback orders by affinity, then focus-muscle hits, then pool order (still a permutation of the pool, deterministic).
- Tests (test agent): context_affinity_test.dart, suggestion_context_ranking_test.dart, programme_context_ranking_test.dart.

## Affected contracts and paths
Order only; hard filters (safety, difficulty ceiling, equipment access) are unchanged. The AI planner is not changed.

## Verification state
Test agent: 41 + 24 + 18 new tests passed, and 28 existing files that import the touched modules passed. One existing test (account_switch_journey_test.dart, scan reminder state) fails identically on a clean master, so it is not caused by this change. On the real catalogue the top-5 suggestions differ in 5 of 5 items between gym, home and outdoors, and the first programme day differs in 4 of 4. Known limits: ties inside the best tier fall back to catalogue order (the gym list shows hyperextension and airbike items near the top); not verified on a device; no analyzer run.

## Addendum: the "План на сегодня" planner (same PR)
The real-phone test (Samsung S8) showed the Home recommendations differ per context after the ranking change, but the adaptive plan screen (AI planner, plan_builder.dart) still gave the same four exercises for gym, outdoors and home.
- mobile/lib/features/ai_planner/data/plan_builder.dart: buildPlan keeps the weekly deficit as the primary order; on equal deficit the context affinity decides; a one-per-primary-muscle diversity pass (reserved goal items count as used groups; untagged items are their own group; second pass fills the remaining slots) stops one muscle taking every slot. Without a training context only the diversity pass is added to the old order.
- mobile/lib/features/training_context/data/training_context.dart: the hyperextension bench is "other loaded kit", not a machine (id and label removed from the machine sets).
- Test: mobile/test/features/ai_planner/plan_builder_context_ranking_test.dart (29 tests). Rerun of 40 files: all passed except account_switch_journey_test.dart (fails identically on clean master).
- Real catalogue, no history, 45 minutes: gym = ab crunch machine, airbike, assisted chin-up machine, barbell curl; home = dumbbell curls, press and fly; outdoors = jump turns, curtsy, punching, hamstring curl; the three plans differ in 4 of 4 exercises. Known limit: untagged dumbbell rows count as separate muscle groups.
