# SPTR Equipment Recognition v4.4 — AC/DoD authoring timing: question to GPT-PM and verdict

Captured via PM Bridge (Playwright transport, direct DOM read under the browser lock), conversation
`https://chatgpt.com/c/6a821d86-5720-83eb-b20b-a33f5b3cb5dc`, 2026-08-22, immediately after the
round-4 CONSENSUS verdict.

## Question (operator-raised process question, sent verbatim)

Should full, structured Acceptance Criteria / Definition of Done (the same format P6.G0 already
uses -- Purpose, Inputs, Deliverables, Verification, Required review, Exit, Rollback/failure mode)
be authored for EVERY gate in the v4.4 phased plan NOW, as one upfront pass before any
implementation starts -- or is it better to write each gate's AC/DoD just-in-time, immediately
before that specific gate opens? Stated lean going in: just-in-time, gate-by-gate, on the theory
that it matches GPT-PM's own phased/evidence-driven recommendation and avoids speculative AC/DoD
for a gate whose real constraints won't be clear until implementation is closer.

## GPT-PM's verbatim reply

> Твой lean в целом правильный: полный детальный AC/DoD для всех P0–P6 сейчас писать не стоит. В
> этом проекте это почти гарантированно создаст stale-spec/rework, потому что реальные ограничения
> уточняются по мере прохождения предыдущих гейтов. История с P0.G0 и P6.G1 как раз это уже
> доказала.
>
> Но и полностью откладывать определение каждого будущего gate до дня его открытия я бы не стал.
> Лучший вариант для v4.4 — двухуровневая схема: upfront skeleton для всех gates + полный binding
> AC/DoD just-in-time перед открытием конкретного gate.
>
> Сейчас для каждого gate достаточно зафиксировать минимальный Gate Contract: Purpose,
> prerequisites/dependencies, что gate блокирует, основные deliverables/evidence classes, required
> reviewer roles, high-level exit condition, rollback class и known external dependencies. Не надо
> заранее фиксировать точные test counts, команды, filenames, latency thresholds, sample sizes,
> implementation mechanism или окончательную структуру evidence packet, если они зависят от
> результатов предыдущих gates.
>
> А непосредственно перед открытием gate делается полный structured AC/DoD в том формате, который
> сейчас у P6.G0: Purpose / Inputs / Deliverables / Verification / Required review / Exit /
> Rollback-failure mode. Конкретные измеримые thresholds, negative tests, mutation tests, команды,
> CI jobs, artifact paths и evidence requirements. Проверка против фактического HEAD репозитория и
> результатов уже закрытых предыдущих gates. Один короткий independent pre-flight review AC/DoD;
> только после его закрытия gate считается OPEN и implementation может начаться.
>
> Главный rework-risk при чистом JIT действительно существует: можно поздно обнаружить, что будущий
> gate требует данных, instrumentation или архитектурного hook, который надо было заложить тремя
> фазами раньше. Поэтому upfront skeleton нужен именно для dependency discovery, а не для попытки
> заранее написать подробную спецификацию будущего мира. Например, уже сейчас обязательно знать,
> что P6.G2 потребует sealed sets, поэтому P3 должен создать их правильно. Но сейчас не обязательно
> расписывать каждую команду P6.G2 evaluation runner — к моменту P6 изменятся реальные artifacts, CI
> и поддерживаемые модели.
>
> Binding процесс для проекта:
>
> DESIGN CONSENSUS → ALL GATES HAVE MINIMUM GATE CONTRACTS → before Gate X implementation: verify
> current HEAD + predecessor evidence → author FULL Gate X AC/DoD → independent AC/DoD pre-flight
> review → 0 BLOCKER/CRITICAL → GATE X = OPEN → implementation → evidence + independent gate review
> → GATE X = CLOSED.
>
> Важный принцип: AC/DoD freeze должен происходить до начала работы, которую он оценивает. Иначе
> появляется соблазн после реализации подогнать acceptance criteria под то, что получилось.
>
> Мой выбор для v4.4: не писать сейчас полный detailed AC/DoD для всех P0–P6; написать сейчас
> lightweight Gate Contracts для всех gates; полный measurable AC/DoD — JIT, непосредственно перед
> открытием каждого gate. Исключение для ближайших gates: P0 и следующий реально исполняемый P1/P2
> gate можно детализировать полностью уже сейчас, потому что вероятность изменения контекста мала и
> это сразу создаст рабочий шаблон для всей программы. Для P3–P6 сейчас достаточно skeleton.

## Verdict adopted

Two-tier gate specification, effective immediately for the v4.4 phased implementation plan:

1. **Now:** author a lightweight Gate Contract (Purpose, prerequisites/dependencies, what the gate
   blocks, high-level deliverables/evidence classes, required reviewer roles, high-level exit
   condition, rollback class, known external dependencies) for **every** gate P0–P6, primarily for
   dependency discovery (e.g. P6.G2 needing sealed sets means P3 must build them correctly) rather
   than detailed specification.
2. **Exception, full detail now:** P0 and the next actually-executable P1/P2 gate get the full
   structured AC/DoD (the P6.G0 format) immediately, since context-drift risk is low there and it
   establishes a working template for the whole program.
3. **Just-in-time, per gate:** full structured AC/DoD authored immediately before each remaining
   gate opens, verified against the actual repository HEAD and predecessor gates' evidence, gated by
   one short independent pre-flight review (0 BLOCKER/CRITICAL) before the gate is marked OPEN.
4. **Binding principle:** AC/DoD freeze happens before implementation work for that gate begins,
   never retrofitted afterward to match what was actually built.

**Not yet done as of this record:** the Gate Contracts skeleton pass itself, and the full AC/DoD for
P0/the next P1-P2 gate. This is a scoping decision for a future gate, not implemented in this
session — recorded here as the agreed process, pending the operator's GO to start it.
