# P0.G3 — source-class priority policy

Priority is **determined by `sourceClass`**, not freely chosen per record —
enforced mechanically by `scripts/equipment_identity/rights.py`'s
`CANONICAL_PRIORITIES_BY_SOURCE_CLASS`, not by reviewer discipline. A
registry entry whose `priority` isn't in its class's allowed set fails
`validate_source_record` outright.

| `sourceClass` | Allowed `priority` | Rationale |
|---|---|---|
| `OFFICIAL_MANUFACTURER` | `P0`, `P1` | Canonical brand/line/model/SKU truth. P0 for the initial brand pack (Technogym, Life Fitness/Hammer Strength, Matrix, Nautilus/Core Health & Fitness — v4.1 plan §5, line 289), P1 for the second wave (Precor, Panatta). |
| `OFFICIAL_BIM` | `P0`, `P1` | Official 2D/3D/BIM/architect portals — same tier logic as the manufacturer itself, since it's the same first-party source relationship. |
| `WGER` | `ENRICHMENT` | Exercise-knowledge enrichment, explicitly not a machine-identity dependency (v4.1 plan §5.1: "must not block exact-machine P1/P2 progress"). |
| `EXERCISEDB` | `STAGING` | Second-opinion coverage pending commercial/media terms review (v4.1 plan §5, line 281). |
| `API_NINJAS` | `STAGING` | Coverage/comparison pending commercial-use terms review (v4.1 plan §5, line 282). |
| `DISTRIBUTOR` | `P1`, `P2` | Secondary truth (regional aliases, legacy models) — never primary spec source (v4.1 plan §5, line 283). |
| `REFURBISHED_USED` | `P2` | Long-tail discontinued-model evidence only (v4.1 plan §5, line 284). |
| `MARKETPLACE_3D` | `STAGING` | The source-strategy document's own table (v4.1 plan §5, lines 285-286) calls this class "LICENSE-GATED" — this schema's `priority` enum has no such value (see §8.1 of GPT's implementation prompt, which specifies the six-value enum verbatim), so `STAGING` is the closest honest mapping: gated, pending, not yet usable. Recorded here explicitly so the mapping is a documented decision, not silent guesswork. **Important scope note (added after P0.G3 review):** a marketplace source's `rights` record covers the PLATFORM, not any individual asset — Sketchfab/3dsky license terms vary per-asset/per-author (the design doc's own "Respect NoAI and per-asset license" line, v4.1 plan §5, line 286). A future human promoting `sketchfab`/`3dsky_sports_models` to `REVIEWED` must not read that as blanket permission for every asset ever pulled from the platform; real per-asset rights tracking is a later-gate (plausibly P3.G1) responsibility, not something `source_registry.json`'s one-record-per-source shape can express today. |
| `SEARCH_DISCOVERY` | `DISCOVERY_ONLY` | The **only** legal priority for this class — structurally impossible to declare any other, which is the mechanical half of "search discovery can never be a training/display source" (`test_search_discovery_can_never_declare_a_non_discovery_priority`). |
| `OTHER` | `STAGING`, `ENRICHMENT`, `P2` | Permissive catch-all for a source class this enum doesn't yet name — deliberately excludes `P0`/`P1`/`DISCOVERY_ONLY` so an uncategorised source can never accidentally outrank a properly classified one or masquerade as discovery-only. |

## Why this table is enforced, not advisory

`rights.CANONICAL_PRIORITIES_BY_SOURCE_CLASS` is the single source of truth
this table transcribes — if the table and the code ever disagree, the code
wins and this table is stale (fix the table, the same discipline
`scripts/ml/lifecycle.py` uses for its own `assert_states_declared`). This
table exists so a human can see the policy at a glance; `rights.py` is what
actually stops a record from violating it.

## What this document does not do

It does not decide whether any source's TERMS are acceptable — that is
`rights_decision.schema.json`'s job (`legalReviewState`, the six `*Allowed`
booleans, `noAiRestriction`). Priority answers "how much do we trust this
kind of source for canonical facts"; rights answers "what are we legally
allowed to do with this specific source's content." A `P0`-priority source
can still be `UNREVIEWED` — priority and rights review are independent
axes, and `source_registry.json`'s current seed proves it: every P0 entry
(Technogym, Matrix, Life Fitness, Core Health & Fitness) is `UNREVIEWED`
today, because being the canonical manufacturer source does not, by itself,
establish what SPTR may legally do with their content.
