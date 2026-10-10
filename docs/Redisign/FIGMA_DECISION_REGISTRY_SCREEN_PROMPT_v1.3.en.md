# Figma Prompt — Interactive Decision Registry Screen v1.3 (English Companion)

> **Fitness-App local translation adoption:** The local source `docs/Redisign/FIGMA_DECISION_REGISTRY_SCREEN_PROMPT_v1.3.md` has exactly the same Git blob SHA `230fc80a994c11c324f3b97f0c212590dd754525` as the originally translated source in `ReviewExistingExamples`. This English copy is historical documentary text, **not a current accepted product implementation, production UI locale or release decision**. No original file was changed.

**Originals:** [Figma decision registry prompt v1.3](FIGMA_DECISION_REGISTRY_SCREEN_PROMPT_v1.3.md) and [its identical -1 copy](FIGMA_DECISION_REGISTRY_SCREEN_PROMPT_v1.3%20%281%29.md). Both source files share Git blob `230fc80a994c11c324f3b97f0c212590dd754525`. The English text below translates the original design request; it does not modify the prototype or approve any product decision.

## Requested internal screen

Add a **fourth tab** to the internal `ResearchScreen`, labeled **"Decisions · 44"** in English (the original requested Russian-language label is preserved in the source).

This is a **stakeholder governance screen**, not a customer-facing Fitness App view.

### Functional and visual requirements

- Show summary counts: **22** decisions carried forward from completed gates, **8** D6 questions, and **14** D8–D9 questions, for **44 total**.
- Provide filters by gate, status, owner, priority and blocking status.
- Use compact rows with a detail drawer; **do not** create 44 oversized cards.
- Use the exact decision statuses `Open`, `Needs Research`, `Needs Product`, `Needs Tech`, `Blocker`, `Decided`, `Deferred` and `Locked`.
- Add badges for conflicting, duplicate and locked decisions.
- Provide a **D6 blocker** filter preset.
- Show linked rationale, dependencies and the gate before which a decision must be resolved.
- Mark **Q39** as **Flutter — locked**.
- Mark **Q1 and Q41** as one duplicated decision about the light theme.
- Correct **Q19** to **Flutter on-device ML versus demo**, not React Native.
- Reframe **Q4** as platform health-data integration scope, not a fabricated iOS stub.

### Prototype interaction

`Research → Decisions → D6 → Q19 → details → provisional recommendation → Q20`

**Authority/translation boundary:** The [source decision register](OPEN_DECISIONS_REGISTER_v1.3.md) determines the 44 decisions, their owners and their statuses; its [English companion](OPEN_DECISIONS_REGISTER_v1.3.en.md) is explanatory. The design prompt is not a decision to unlock Q19, to implement Form Coach, or to change the application's actual localization.

**Status:** Historical imported design request — **not implementation or stakeholder signoff**.
