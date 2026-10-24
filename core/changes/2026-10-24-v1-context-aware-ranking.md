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
