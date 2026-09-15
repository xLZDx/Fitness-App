# Full-app consensus review — 2026-09-12 (external, pasted by operator)

**Provenance**: this document is pasted verbatim from the operator's message in a Claude Code chat
session (working directory `D:\Repo\Fitness_App`, session id `b52e8d56-f20e-4b60-a69e-3dcce891016a`,
UTC ~22:19). It was NOT produced by this session, and none of its `file:line` citations or test
results have been independently re-verified by this session as of this save — per this repo's own
evidence-over-inference discipline (`~/.claude/CLAUDE.md` §3), treat every claim below as
**UNVERIFIED / reported-as-fact-by-source** until re-checked against the actual files and a real
test run. The reviewer identity ("Architecture / Flutter / Firebase", "QA / ML / safety logic",
"Security / privacy / abuse prevention") and methodology (which tool/model produced this, whether
it is a `code-review`/`agent-consensus` run or an external tool) were not stated by the operator and
are unknown to this session.

**Why this file exists**: saved for later analysis on operator instruction ("сохрани для
анализа"). No remediation work has started on any finding below — this is out of scope of the
Rosetta plan currently open in this session (`fitness_app-2026-09-12T21-27-25-820Z-b29fad`,
P2.G5-readiness shadow telemetry) and no GO has been given for any of it. Acting on any P0/P1 item
below requires its own plan and GO per this repo's standing rules.

---

## Original text (verbatim)

Статус: **BLOCK для release candidate / NEEDS REVISION**.

Проект архитектурно зрелый и хорошо документирован, но сейчас есть несколько блокирующих проблем: safety-фильтрация упражнений, нестабильный полный Flutter-suite, неполный release pipeline и условно отключённая защита App Check.

## Ревьюеры

- Architecture / Flutter / Firebase
- QA / ML / safety logic
- Security / privacy / abuse prevention

Внешних MetaGPT/Aider-отчётов не использовал.

## Проверки

| Проверка | Результат |
|---|---|
| `flutter analyze` | ❌ exit 1, 17 warning/info |
| полный `flutter test` | ❌ 3 808 тестов, 25 падений |
| изолированные проблемные widget suites | ✅ проходят |
| последовательный запуск | ✅ 1 133 теста без падений, остановлен вручную |
| `functions npm test` | ✅ 601 тест |
| `functions-equipment-identity npm test` | ✅ 473 теста |
| catalog pytest | ✅ 211 тестов |
| RU/EN drift | ❌ 2 новых semantic mismatch |
| lifecycle coverage | ❌ 2 коллекции без policy |
| docs link audit | ❌ 54 битые ссылки |
| npm audit | ⚠ по 11 moderate vulnerabilities в каждом backend |

## Подтверждённые блокеры

### 1. Injury safety работает fail-open

Если у упражнения нет `contraindications`, оно автоматически считается безопасным:

[exercise_filter.dart](D:/Repo/Fitness_App/mobile/lib/features/equipment/data/exercise_filter.dart:38)

В каталоге ранее зафиксировано примерно 360 таких строк из 1 887. То есть пользователь с травмой может получить упражнение без доказанного safety-тега.

Дополнительно:

- `safeFor(null)` возвращает весь список, пока профиль ещё не загружен;
- recommendation/session paths и browse paths фильтруются по-разному;
- AI-generated упражнения не имеют обычных contraindication-тегов и защищены только в отдельных resolve-путях.

[equipment_providers.dart](D:/Repo/Fitness_App/mobile/lib/features/equipment/state/equipment_providers.dart:434)

Что сделать:

1. Для injury-sensitive surfaces использовать deny-by-default.
2. Unknown/untagged упражнения отправлять в quarantine.
3. Не показывать prescription/session content до завершения profile hydration.
4. Добавить integration tests для deep links, cache, reminders, scheduled sessions и AI-generated exercises.
5. Ввести CI-gate: `untagged contraindications == 0` либо явный signed-off allowlist.

### 2. Полный Flutter suite нестабилен

Первый полный запуск дал:

```text
3808 tests, 25 failures
```

Проблемные widget-тесты при изолированном запуске проходят. Последовательный запуск дошёл до 1 133 тестов без падений, но был остановлен вручную из-за длительности.

Это похоже на утечки общего состояния, глобальные mocks, semantics/rendering state или проблемы с параллелизмом. Пока это не исправлено, нельзя считать мобильную часть release-ready.

Что сделать:

- найти тесты, оставляющие глобальные singleton/provider/render state;
- временно прогонять полный suite с `--concurrency=1`;
- затем вернуть parallel execution и доказать стабильность;
- добавить отдельный CI job с повторным запуском suite 2–3 раза.

### 3. Release pipeline не собирает реальный APK/AAB

Workflow проверяет analyze/test и integration, но не выполняет полноценный release build:

[flutter.yml](D:/Repo/Fitness_App/.github/workflows/flutter.yml:75)

Отсутствуют обязательные проверки:

- `flutter build apk --release`;
- `flutter build appbundle`;
- Gradle release assembly;
- signing;
- ProGuard/R8;
- native ML packaging;
- реальный mobile smoke после сборки.

Integration job также не запускается на обычных push-событиях.

Отдельно `equipment-identity` при deploy делает только build:

[firebase.json](D:/Repo/Fitness_App/firebase.json:40)

Там нет `npm test`.

### 4. App Check fail-open для большинства callable functions

Общие функции получают:

```ts
APP_CHECK_ENFORCED = envFlag("APP_CHECK_ENFORCED")
```

При отсутствии или ошибке environment variable значение становится `false`:

[scaling.ts](D:/Repo/Fitness_App/functions/src/scaling.ts:184)

AI-путь защищён fail-closed, но остальные callable-функции — Stripe, reports, bookings, donor wall, video и прочие — зависят от корректности deployment environment.

Это условный блокер: production environment из репозитория не доказан.

Что сделать:

- fail-closed default для production;
- deployment guard, который падает при отсутствии явного production flag;
- smoke-test callable endpoints с Auth без App Check;
- отдельная проверка фактических Cloud Functions environment variables.

## Важные security/privacy риски

### Firestore wildcard слишком широкий

Правила разрешают authenticated user читать и писать практически любые подколлекции внутри собственного user document:

[firestore.rules](D:/Repo/Fitness_App/firestore.rules:49)

Проблемы:

- произвольные client-created collections/documents;
- storage/write-cost abuse;
- отсутствие общих field/payload limits;
- новая server-only collection может случайно стать доступной клиенту, если её забыли добавить в denylist.

Лучше перейти к явному allowlist-подходу: каждая коллекция разрешается отдельно, неизвестные пути запрещаются по умолчанию.

### Legacy health data мигрируется лениво

Код переносит старые health answers с сервера только когда аккаунт открывается:

[device_health_profile_repository.dart](D:/Repo/Fitness_App/mobile/lib/features/profile/data/device_health_profile_repository.dart:64)

Неактивные аккаунты могут сохранять старые медицинские данные в Firestore неопределённо долго. Privacy policy уже раскрывает historical exception, поэтому это не просто ошибка текста, но остаётся operational/privacy debt.

Нужны:

- одноразовая server-side migration;
- проверка `legacy health documents == 0`;
- retention/deletion evidence в release gate;
- явный hydration/migration state вместо временной смеси local и server profile.

### Регион Firebase Functions указан непоследовательно

Большинство сервисов используют regional helper, но data export использует глобальный singleton:

[server_export.dart](D:/Repo/Fitness_App/mobile/lib/features/data_export/server_export.dart:18)

Это может отправлять вызовы в `us-central1`, когда основная инфраструктура работает в `europe-west1`.

### Dependency vulnerabilities

Оба backend-а имеют по 11 moderate vulnerabilities, включая транзитивные цепочки:

- `uuid`;
- `qs`;
- `express/body-parser`;
- `firebase-admin`;
- Google Cloud libraries.

High/critical npm severity нет, но исправление основной цепочки требует major-обновления `firebase-admin`. Нужен отдельный dependency upgrade plan и regression run.

## QA/ML и скрытые технические риски

- OCR не различает plugin failure, timeout и настоящий "no match".
- Для AI-generated exercises нужно доказать защиту всех cached/deep-link/reminder/session paths.
- Нет device-level теста native ML bridge.
- Нет release artifact test для camera, ML Kit, R8 и permissions.
- `flutter analyze` локально завершается с ошибкой из-за 17 warning/info, а CI их подавляет через `--no-fatal-warnings --no-fatal-infos`.

## Design / UX

Положительные стороны:

- есть semantic color system;
- WCAG contrast tests;
- accessibility semantics tests;
- blur budget и glass surface tests;
- widget-набор в целом хорошо покрыт.

Проблема не в отсутствии design system, а в отсутствии подтверждения на реальном release APK: сейчас host widget tests проходят, но native/release rendering не проверяется.

Wear release также остаётся отдельным блокером: в документации указано, что release pairing сломан из-за отсутствующего `signingConfig`:

[CLAUDE.md](D:/Repo/Fitness_App/CLAUDE.md:66)

## Документация и data governance

- 2 новых RU/EN semantic mismatches:
  - `formcheckExplainTitle`;
  - `formcheckExplainPushupTuck`.
- Lifecycle policy отсутствует для:
  - `equipment_identity_latest_session`;
  - `equipment_model_text_keys`.
- 54 битые ссылки в non-planning документации.
- `core/CONVENTIONS.md` утверждает, что integration tests отсутствуют и есть только 71 test file, что уже не соответствует проекту:

[CONVENTIONS.md](D:/Repo/Fitness_App/core/CONVENTIONS.md:63)

- `mobile/README.md` всё ещё Flutter starter template:

[mobile/README.md](D:/Repo/Fitness_App/mobile/README.md:1)

## Спорные / условные пункты

- Public donor wall — намеренное product behavior, не false positive, но PII глобально читаем.
- App Check risk зависит от production env; из репозитория нельзя доказать, что флаг включён.
- 25 Flutter failures могут быть test-isolation defect, а не production widget defect, но release gate всё равно должен быть зелёным.
- Untagged exercise behavior сейчас явно закодирован и покрыт тестами, однако с точки зрения safety policy это опасная спецификация, а не нормальная защита.

## Приоритетный план исправлений

### P0

1. Сделать injury filtering fail-closed.
2. Закрыть все profile hydration/session bypass paths.
3. Починить нестабильность полного Flutter suite.
4. Добавить release APK/AAB build и native ML smoke.
5. Доказать production App Check enforcement.

### P1

1. Переписать Firestore rules на explicit allowlist.
2. Выполнить legacy health migration и подтвердить нулевое server residue.
3. Исправить region helper для всех Functions.
4. Добавить тесты для equipment-identity deploy.
5. Добавить OCR failure/timeout state.
6. Обновить Firebase/Google dependencies.

### P2

1. Удалить неиспользуемый `authListenable` и глобальный второй `ProviderContainer`:

[app_router.dart](D:/Repo/Fitness_App/mobile/lib/core/router/app_router.dart:258)

2. Разделить monolithic route table.
3. Обновить README, CODEMAP, CONVENTIONS и test counts.
4. Закрыть docs links и RU/EN drift.
5. Отдельно решить Wear signing/pairing.

Изменений в файлы я не вносил. В рабочем дереве уже были пользовательские изменения: `core/DECISION_LOG.md` и untracked `core/design/p2_g5_readiness/`.

---

## Overlap note with the currently open gate (added by this session, not part of the pasted text)

None of the above overlaps the P2.G5-readiness shadow-telemetry plan open in this session
(`fitness_app-2026-09-12T21-27-25-820Z-b29fad`) — that plan touches
`functions-equipment-identity/src`, mobile equipment-identity outbox/UI, `scripts/legal/legal_text.py`
and `scripts/ci/data_lifecycle_policy.json`. One item above (P1.5, "Lifecycle policy отсутствует
для ... `equipment_model_text_keys`") is adjacent territory (the same `data_lifecycle_policy.json`
file this plan's step 4 will also touch) and should be checked for conflict before that step edits
the file, but is not itself in scope of this plan and was not investigated as part of saving this
report.
