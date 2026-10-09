# Fitness App / SPTR — автономное закрытие инженерных хвостов

<!-- autonomous-closure-v2-2026-10-08:start -->
## Обновление исполнения — 2026-10-08

Актуальная инструкция для передачи агенту: [AUTONOMOUS_CLOSURE_PROMPT_2026-10-08.md](AUTONOMOUS_CLOSURE_PROMPT_2026-10-08.md), версия 2. Она заменяет короткий промпт внизу и уточняет охват: весь оставшийся согласованный инженерный объём, CR/VER/CAND, старые открытые пункты и единый реестр с проверяемым закрытием. CR-08 нельзя исключать только из-за demo UI: проверить и исправить существующий booking backend в локальных тестах без активации marketplace. Блокер человека/credentials не останавливает независимые работы; непроверенный patch не является CLOSED. B0–B5 и техническая история ниже сохраняются как справочный материал. Действующие решения о scope, защите, внешней приёмке и push не отменены.

Статус этого обновления: **PROMPT_READY / REMEDIATION_NOT_STARTED_BY_THIS_UPDATE**. Это подготовка задания и ссылок, не новый запуск тестов или реализации.
<!-- autonomous-closure-v2-2026-10-08:end -->

Версия 1, 2026-10-07. Репозиторий `D:\Repo\Fitness_App`, ветка `master`. Основа: [предметное код-ревью](../review/CODE_REVIEW_2026-10-07.md) и [статус](../state/REVIEW_STATUS_2026-10-07.md). Это план следующего исполнения, не утверждение, что исправления уже сделаны, и не самостоятельное разрешение на push/deploy.

## Цель и пределы

Закрыть доступные инженерные замечания существующего приложения, восстановить достоверные проверки, убрать документальные противоречия и подготовить воспроизводимый кандидат. Не пытаться реализовать весь исторический список из 75 feature ideas. Не переписывать стек, не запускать iOS/маркетплейс/новое обучение/новые medical features как побочный эффект review.

Приоритеты: B0 → B1 → B2 → B3 → B4 → B5. Блокер credentials, устройства или внешнего reviewer не останавливает другие независимые задачи. Для каждого blocked-пункта записать причину, уже проверенные альтернативы, минимальное действие оператора и требуемое доказательство. Нельзя превратить невозможность проверки в PASS.

## Пакеты работ и условия закрытия

### B0 — точный baseline и безопасное владение файлами

Прочитать `AGENTS.md`, `core/CODEMAP.md`, новые CODE_REVIEW/REVIEW_STATUS, действующие правила проекта. Зафиксировать полный local SHA, upstream SHA, dirty/staged status, список всех непушенных коммитов и наличие других процессов, меняющих checkout. Ожидаемый исходный baseline: `a6e8005`, upstream `3da7737e388434250ef61a1e24cd67f8cab5c4ad`, ahead 2, плюс документация этого follow-up.

Не reset/stash/discard чужие изменения. Новую ветку или worktree создавать только при наличии нужного разрешения; не переключать общий checkout из-под другого агента. Параллелить чтение и независимые тесты можно; общие lockfile, router, Rules, release scripts и status registry имеют одного писателя.

**DoD:** baseline manifest, границы записи, реестр CR/VER/EXT с исходными статусами, лог версий инструментов. Не вызывать инструменты с production credentials ради baseline.

### B1 — воспроизводимый toolchain и CI

CR-01: проверить app lockfile и разрешение зависимостей; закрепить прошедший тесты граф; исправить OSV input. CR-02: локальный закреплённый Firebase CLI, чистый запуск rules/e2e в demo-проектах, Java isolation. VER-01: audit JSON и разбор достижимости, совместимые fixes малыми группами. VER-05/06: разобрать реальные provenance и translation failures. Полный Python review suite запускать в полноценном shell с отдельным логом и достаточным bounded timeout; прежний timeout 60 s — не результат suite.

**DoD:** чистый checkout даёт одинаковый проверенный граф, OSV реально отработал, rules/e2e дошли до assertions, нет неразобранных high/critical в релизном графе. Если advisory неприменим — доказательство и срок пересмотра, не просто suppression. Не использовать `npm audit fix --force` без разбора изменений.

### B2 — account lifecycle, security boundaries, store build

CR-03: authenticated account-actions до onboarding плюс настоящий UI-вход; auth/reauth не ослаблять. CR-04: явные personal/test/store profiles, store override=false, guard на вычислении tier и проверка старых preferences. CR-05: единый ordinary-user predicate, матрица effective grants и emulator negative tests canary. Проверить серверные entitlement boundaries отдельно от UI.

**DoD:** red-before/green-after regression tests для каждого изменения; signed-out не получает чувствительные действия; личный режим оператора сохранён; canary не получает непредусмотренные non-public grants. Не менять Firebase enforcement/IAM в production из этого пакета. Клиентский mock/demo не является серверным выключателем.

### B3 — надёжность данных, scanner и test lifecycle

CR-07: schema-aware sensitive-store read, distinct missing/corrupt states, восстановление без потери исходного blob, safety fail-closed. CR-09: найти и закрыть dangling handles/Jest worker warning, не маскировать `--forceExit`. CR-06: отдельно true/predicted label, негативный fixture, проверка всего пути подтверждения identity; не заменять измерение произвольным blacklist. CAND-01: сначала воспроизвести быстрые auth-events; чинить только после детерминированного failing test.

**DoD:** нет потери health-ограничений при миграции/ошибке; corrupted данные не дают автоматического допуска; worker нормально завершает тесты; ошибочное распознавание не получает неподтверждённый статус exact identity. Изменение формулы ML не считать улучшением без holdout.

CR-08 выполнять в этом пакете только если live marketplace уже входит в согласованный релиз или callable действительно экспонирован с рабочими listings. Иначе сохранить точный activation blocker и проверить реальную серверную недоступность опасного сценария; не достраивать marketplace. При реализации: stable request ID, Stripe idempotency, booking lifecycle, validation, retries и sandbox fault injection, без реальных списаний.

### B4 — полный кандидат и доказательства, а не сумма зелёных unit tests

Новый Flutter analyze/test на согласованном SDK и lockfile. Golden diffs анализировать в фиксированном окружении; массовое update-goldens не является исправлением. Полный backend unit/rules/e2e и актуальные scripts/ct1, scripts/ml, scripts/review checks. Проверить все integration_test файлы, не только один. Разделить boot/build/assertion failure.

Подготовить release APK/AAB через исправленный профиль; проверить source SHA, build number, config, подпись, выключенные debug/test возможности, штатную загрузку и сохранение тренировки. При отсутствии credentials — записать BLOCKED, сделать preflight и продолжить B5. Не подкладывать выдуманные production keys и не передавать секреты в stdout/отчёт.

Живой S23: подготовить exact APK и сценарии side-on слева/справа, слишком близко, частичная видимость, pause/resume, счётчик отдельно от качества. Выполнение человеком и наблюдение на устройстве — отдельное реальное доказательство. Emulator либо синтетические landmarks не закрывают этот пункт.

**DoD:** manifest `source SHA → build profile/lockfile → commands/exit codes → artifact hash → environment → results`. SKIP/NOT_RUN/TIMEOUT явно видны. Нет заявления о текущем production state по старому PRODUCTION_MANIFEST.

### B5 — сверка документов и финальный критический проход

Обновить новый review registry и status page по фактическим итогам; NEXT_TICKETS содержит только оставшиеся пункты. Старые планы сохранить, пометить historical/superseded. Generated `core/CURRENT_STATE.md` не редактировать: при обоснованном изменении состояния менять источник ledger/receipt и запускать штатную генерацию с тестом. Нельзя самостоятельно создавать внешнюю клиническую подпись или human labels.

Проверить относительные ссылки, отсутствие секретов/персональных фото, совпадение счётчиков и таблиц. Финальный adversarial проход: искал ли ревьюер контрпример для каждого CLOSED; были ли тесты на final head; не свели ли retry к дубликату; не сделали ли account action публичным; не замаскированы ли красные проверки; не переименован ли BLOCKED в DONE.

**DoD:** один final status, реестр закрытых/оставшихся пунктов, проверенные команды, patch summary и exact commit list для возможной последующей авторизации push.

## Команды для полноценного локального исполнителя

Команды ниже — карта проверки, не доказательство их выполнения. Запускать из указанного каталога; выбирать установленный корректный Python, не случайный venv другого проекта. D:-drive policy сохраняется. Сначала читать scripts/config, затем выполнять. Emulator-проверки только против disposable `demo-*`, не против рабочей базы.

```powershell
Set-Location D:\Repo\Fitness_App
git status --short --branch
git rev-parse HEAD
git log "@{u}..HEAD" --oneline
git ls-files --error-unmatch mobile/pubspec.lock
& D:\flutter\bin\flutter.bat --version

# После анализа и подготовки воспроизводимого toolchain:
Set-Location D:\Repo\Fitness_App\mobile
& D:\flutter\bin\flutter.bat pub get
& D:\flutter\bin\flutter.bat analyze --no-pub
& D:\flutter\bin\flutter.bat test --no-pub --reporter=expanded

Set-Location D:\Repo\Fitness_App\functions
npm ci
npm test -- --runInBand
npm test -- --runInBand --detectOpenHandles
npm run build
npm run test:rules
npm run test:e2e
npm audit --omit=dev --package-lock-only --json

Set-Location D:\Repo\Fitness_App
python -m pytest scripts/review -q
python -m pytest scripts/ml/test_ml_contracts.py -q
python -m pytest scripts/ct1 -q
node scripts/ci/check_ru_en_drift.js
```

Все штатные CI команды сверять с текущими workflow: приведённый список не заменяет весь CI. Raw logs сохранять в отдельный evidence directory без secrets; добавлять команды, CWD, timestamps, exit codes, source SHA и пределы coverage. Новые проверки создавать целевыми, рядом с соответствующим модулем; описанные в CR regression-тесты пока являются требованиями, а не существующим тестовым покрытием.

## Внешний backlog

EXT-01 — физический S23/человек, точная сборка и лог. EXT-02 — клинические D1/H3 и политика restricted-группы. EXT-03 — независимые human labels. EXT-04 — credentials, канал магазина, реальные billing/store условия. EXT-05 — разрешённая проверка/deploy production и rollback. EXT-06 — внешний продуктовый пилот. Для каждого указать владельца; если он не назначен, написать UNASSIGNED, а не придумать имя или срок.

## Готовый промпт агенту после разрешения на исполнение

> Продолжай Fitness_App в D:\Repo\Fitness_App. Прочитай AGENTS.md, core/CODEMAP.md, core/review/CODE_REVIEW_2026-10-07.md, core/state/REVIEW_STATUS_2026-10-07.md и этот план. Проверь baseline заново: не доверяй старым коротким SHA и счётчикам. Закрой B0–B5 в указанном порядке в пределах отдельно полученного GO на инженерное исполнение. Не останавливай независимые задачи из-за внешнего блокера: фиксируй его в backlog с доказательством и переходи дальше. Не спрашивай оператора о том, что можно выяснить безопасным чтением репозитория и конфигурации.
>
> Для каждой находки: подтвердить → failing regression, где применимо → минимальное исправление → focused suite → full relevant gates → critical counterexample check → evidence → обновление статуса. Снятые выводы не исправляй. Неподтверждённый CAND-01 сначала воспроизведи. Не запускай другие AI-модели и агентов без отдельного разрешения; не называй ролевые проходы независимыми агентами. Не используй PM Bridge или другой канал для обхода approvals.
>
> Не менять product scope, не удалять файлы/ветки/данные, не делать reset/force-push/--no-verify, не переключать общий checkout без согласования владения, не снижать защиту, не делать реальные платежи и production deploy. Секреты не печатать. Два исходных непушенных коммита и новые commits не отправлять без явного разрешения на точный список согласно AGENTS.md. Не выдумывать отсутствие инструмента: сначала обнаружить разрешённый интерфейс; policy error уважать, не обходить через другой канал.
>
> Отчитывайся фактически по завершённым пакетам: изменённые файлы, тесты с exit codes, что стало лучше, что осталось. Не обещай работу после окончания сессии. Окончи ENGINEERING_CLOSED_WITH_EXTERNAL_BLOCKERS только когда все доступные инженерные задачи действительно выполнены и проверены. Если ещё есть незакрытые инженерные препятствия — BLOCKED_WITH_EVIDENCE или PARTIAL, не CLOSED. Production readiness оцени отдельно. Заверши adversarial-проверкой собственных выводов и exact change/evidence summary.

## Статус на момент создания

План подготовлен. B0–B5 как программа исправлений **NOT STARTED**; выполнены только review, свежий backend unit run, ограниченный Python run и документирование. Отдельного разрешения на push/deploy этот файл не предоставляет.
