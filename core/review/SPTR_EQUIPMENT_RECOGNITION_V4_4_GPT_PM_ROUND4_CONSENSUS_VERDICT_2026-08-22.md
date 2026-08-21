# SPTR Equipment Recognition v4.4 — GPT-PM round-4 verdict (verbatim)

Captured via PM Bridge (Playwright transport, direct DOM read under the browser lock — not
retyped), conversation `https://chatgpt.com/c/6a821d86-5720-83eb-b20b-a33f5b3cb5dc`, 2026-08-22.

This is the reply to the v4.4 document text (full text sent earlier in the same conversation,
identical to `SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.4_MECHANICAL_PATCH_2026-08-22.md`
on disk) plus a short follow-up asking GPT-PM to answer in plain text (its analysis/code-interpreter
tool had gotten stuck mid-run on an earlier attempt at the requested downloadable HTML artifact).

## Verbatim reply

> VERDICT: v4.4 CONSENSUS — APPROVE FOR PHASED IMPLEMENTATION
>
> Да. По тому literal v4.4 тексту, который ты прислал выше, оба оставшихся пункта закрыты именно
> так, как требовалось. Ничего существенного открытым после этой механической проверки я не вижу.
>
> #3 RecognitionAuthorityTuple — CLOSED. Добавление ocrVersion и identityParserVersion? в сам
> pinned tuple закрывает последнюю дыру multi-view authority. Ключевой binding теперь присутствует:
> все views одного recognitionSessionId обязаны использовать одинаковую OCR/parser authority; если
> rollout/implementation не может сохранить эту версию, session завершается и создаётся новая, а не
> продолжает агрегировать evidence под другим OCR/parser version. Удаление отдельного ocrVersion из
> response также правильно устраняет второй источник истины. verifierModel как display-only mirror
> authority.verifierModelVersion, без самостоятельной resolution semantics, тоже корректен.
>
> MINOR по UNAVAILABLE_CATALOG_VERSION — CLOSED. CATALOG_VERSION_UNAVAILABLE теперь существует в
> failureCode и явно соответствует decision: UNAVAILABLE_CATALOG_VERSION. То есть terminal outcome
> теперь полностью представим в схеме и больше нет состояния, для которого обязательный failure
> code невозможно выразить.
>
> Финальная closure-картина:
>
> Original B-01..B-04                         CLOSED
>
> Round-2 invariants:
> 1. server-derived TEXT_ONLY | VISUAL lane   CLOSED
> 2. infra failure != ABSTAIN                 CLOSED
> 3. complete immutable authority tuple       CLOSED
> 4. client/server contract negotiation       CLOSED
> 5. NEED_MORE_VIEW in denominator            CLOSED
> 6. App Check transition invalidation        CLOSED
> 7. revocation correctness boundary          CLOSED
>
> Round-3 schema MINOR:
> 8. catalog-version failure representable    CLOSED
>
> NEW BLOCKER   = 0
> NEW CRITICAL  = 0
> NEW MAJOR     = 0
> NEW MINOR     = 0
>
> Поэтому статус документа можно менять с:
>
> v4.4 MECHANICAL PATCH CANDIDATE
>
> на:
>
> v4.4 CONSENSUS
> APPROVE FOR PHASED IMPLEMENTATION
>
> Это именно approval архитектуры и implementation plan, а не разрешение объявить Exact Model
> production-ready. Production остаётся за уже определёнными fail-closed gates:
>
> P0.G0 App Check readiness
> P6.G0 evidence-lane enforcement
> P6.G1 mandatory shadow
> P6.G2 sealed independent evaluation
> P6.G3 model-by-model promotion
> P6-T or P6-V statistical lane requirements
> calibration / OOD / Clopper-Pearson gates
> rollback + revocation readiness
>
> Round-cap на design review считаю закрытым. Дополнительный adversarial круг для v4.4 не нужен.
> Следующий разумный этап — реализация по фазам и независимый review уже реального кода/evidence
> каждого gate, а не очередной review самого design document.

## Independent verification before acceptance (per the operator's standing "не верь гпт, все проверяй сам" rule)

Both claims re-checked against the actual v4.4 text on disk before this verdict was accepted as the
basis for closing the design-review loop:

- §4.6 `RecognitionAuthorityTuple` — confirmed it lists `ocrVersion` and `identityParserVersion?`
  (file lines 111-112), and §6.5's response contract no longer carries a standalone `ocrVersion`
  field (confirmed by grep — the only remaining `ocrVersion` occurrences are inside `authority` /
  prose explaining its removal).
- §6.5 `failureCode` enum — confirmed it lists `CATALOG_VERSION_UNAVAILABLE` (file line 222) mapped
  to `decision: UNAVAILABLE_CATALOG_VERSION`.

Both match GPT-PM's own description exactly. No discrepancy found between the verdict's claims and
the actual binding text.
