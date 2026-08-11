# Полный аудит Fitness App

Дата аудита: 11 августа 2026 года  
Итоговый статус: **BLOCK — к публичному production-релизу не готово**

## Резюме

Приложение находится на уровне сильной Android private beta: большая функциональная база, хорошая локализация, рабочая дизайн-система, 1886 зелёных Flutter-тестов и 107 зелёных backend-тестов.

Публичный выпуск, особенно с реальными платежами, progress photos и заявленными AI-функциями, сейчас не рекомендуется. Независимые ревьюеры и второй раунд «адвоката дьявола» подтвердили системные проблемы с удалением пользовательских данных, Stripe, production-конфигурацией Firebase и валидностью ML.

Аудит выполнен в read-only режиме по схеме независимого reviewer consensus. Отдельно проверялись:

- архитектура, code design, backend, security и Git;
- Flutter, UX/UI, accessibility и performance;
- ML, E2E, functional testing и silent failures;
- повторная проверка критических выводов в режиме «адвоката дьявола».

FastAPI-review оказался неприменим: FastAPI в проекте отсутствует. Фактический backend построен на Firebase Authentication, Firestore и Node/TypeScript Cloud Functions.

## Состояние компонентов

| Компонент | Оценка |
|---|---|
| Основные workout/catalog/profile-потоки | Beta, в целом содержательные |
| Flutter unit/widget слой | Хороший: 1886 тестов зелёные |
| Backend Functions | Код покрыт тестами, но production отстаёт |
| Stripe/subscriptions | **Release blocker** |
| Удаление и экспорт данных | **Release blocker** |
| Progress photos | **Privacy blocker**, capture требует device-подтверждения |
| Scanner/Form Coach/Posture | Экспериментальные, accuracy claims не подтверждены |
| Social/community/marketplace | В значительной части mock/demo |
| Wear OS | Нерабочий scaffold |
| iOS | Не поддерживается |
| E2E/release pipeline | Красный и недостаточный |

## Подтверждённые блокеры

### 1. Удаление аккаунта не удаляет все данные

`deleteAccount` удаляет только `users`, `donor_wall` и `coach_listings`, но оставляет `coach_bookings` и `equipment_reports`. Клиент после серверного вызова только выполняет sign-out.

Доказательства:

- `functions/src/index.ts:1287-1332`;
- `functions/src/__tests__/delete_account.test.ts:122-143`;
- `mobile/lib/features/account_deletion/state/account_deletion_providers.dart:32-50`.

Локальная часть также не очищается:

- sensitive health blob остаётся на устройстве;
- progress photos используют общий каталог и общий AES-ключ без UID;
- следующий аккаунт на том же устройстве может получить данные предыдущего аккаунта;
- server-side тест сейчас закрепляет неполное удаление как ожидаемое поведение.

Это расходится с обещаниями `delete everything` в `public/privacy.html:65,85,88-89` и `public/terms.html:86`.

### 2. Экспорт данных неполный

Экспорт содержит профиль, тренировки, расписание, программы и metadata фотографий, но исключает сами изображения и не включает:

- recognition history;
- machine cards и notes;
- generated exercises;
- subscriptions и receipts;
- equipment reports;
- coach bookings;
- donor entry;
- debug telemetry.

Реализация: `mobile/lib/features/data_export/data_export.dart:13-22,33-86`.

Необходимо либо реализовать полный экспорт, либо изменить юридические и UI-обещания. Сейчас контракт продукта и фактическое поведение несовместимы.

### 3. Возможны две активные Stripe-подписки

Checkout создаётся без idempotency key и без server-side проверки существующей активной подписки. Webhook хранит только один `stripeSubscriptionId`, а account deletion отменяет только его.

Сценарий отказа:

1. Пользователь открывает или повторно завершает две Checkout-сессии.
2. Stripe создаёт две recurring subscriptions.
3. Последний webhook перезаписывает единственный сохранённый subscription ID.
4. При удалении аккаунта отменяется только одна подписка.
5. Вторая может продолжить списания без доступного пользователю аккаунта.

Критические места:

- `functions/src/index.ts:413-457`;
- `functions/src/index.ts:607-617`;
- `functions/src/index.ts:1287-1300`.

### 4. Production Firebase и локальный репозиторий разошлись

На 11 августа 2026 года live App Check показывает `UNENFORCED` для Firebase AI/ML, Firestore и Identity Toolkit. В Cloud Functions нет `enforceAppCheck`, anonymous auth включён.

Следствие: автоматизированные anonymous-аккаунты могут расходовать Gemini, Functions и trial quota. Это не доказанный обход Firestore Rules, но подтверждённый cost/abuse risk и blocker для публичного AI.

Также установлено:

- deployed Stripe Functions датированы 5 августа;
- важный Acacia/Basil compatibility fix от 8 августа не задеплоен;
- активные Firestore Rules не содержат локальный блок `debug_sessions`;
- live privacy/terms отличаются от локальных файлов;
- документация заявляет, что App Check уже enforced, хотя live-конфигурация это опровергает.

### 5. ML-функции нельзя представлять как валидированные

Подтверждены три отдельных methodological blocker.

#### Equipment recognition

Локальная модель даёт уверенные OOD-ошибки вплоть до `0.892`. Сглаживание проверяет повторяемость результата, а не его правильность или принадлежность входа известному классу.

Live mode по умолчанию выключен, поэтому это feature-level blocker, а не blocker всего мобильного приложения.

Ключевые файлы:

- `mobile/lib/features/visual_equipment/data/mlkit_live_equipment_service.dart:116-129`;
- `mobile/lib/features/visual_equipment/domain/live_recognition.dart:29-96`;
- `mobile/lib/features/visual_equipment/state/live_equipment_providers.dart:41`.

#### Form Coach и rep counting

MM-Fit evaluation измеряет другой алгоритм: усреднённые двусторонние 3D-углы и простой двухфазный counter. Production использует одну сторону, 2D и четырёхфазный counter.

Текущие accuracy-цифры не доказывают качество production Form Coach.

Ключевые файлы:

- `scripts/pose/extract_mmfit_targets.py:104-136`;
- `mobile/lib/features/form_check/data/measured_rep_configs.dart:103-228`;
- `mobile/lib/features/form_check/domain/rep_counter.dart:224-387`.

#### Posture

Posture требует side-on кадр, но shoulder/pelvis symmetry требуют front-facing геометрии. Forward-head measurement действительно требует профиль. Все показатели рассчитываются по одному кадру, поэтому часть метрик геометрически несовместима.

Ключевые файлы:

- `mobile/lib/features/posture/domain/posture_metrics.dart:24-79`;
- `mobile/lib/features/posture/data/measured_posture_config.dart:1-20`.

## Progress photos: уточнение после devil’s advocate

Первоначальный аудит классифицировал capture как гарантированно сломанный: sheet закрывается, camera session останавливается, затем вызывается `captureStill()`.

Повторный ревью справедливо ослабил вывод: Future bottom sheet может завершиться до окончательного `dispose` после reverse-анимации. Поэтому это не доказанное «всегда возвращает null», а недетерминированная гонка capture и dispose.

Итоговая оценка:

- гарантированный отказ не доказан;
- ordering race существует;
- полного теста `shutter → capture → encryption → visible tile` нет;
- нужен реальный device-тест перед исправлением;
- privacy-проблемы функции подтверждены независимо от capture.

При этом защита фотографий неудовлетворительна:

- AES-ключ хранится base64 в SharedPreferences;
- каталог и ключ не привязаны к UID;
- plaintext camera temp после шифрования не удаляется;
- metadata индекса не зашифрована;
- UI называет это end-to-end encryption, хотя это локальное at-rest encryption с ключом рядом с данными.

Ключевые файлы:

- `mobile/lib/features/progress_photos/widgets/photo_capture_sheet.dart:75-81,153-169`;
- `mobile/lib/features/progress_photos/progress_photos_page.dart:81-89`;
- `mobile/lib/features/progress_photos/state/progress_photos_providers.dart:69-75`;
- `mobile/lib/features/progress_photos/data/photo_key_store.dart:8-65`;
- `mobile/lib/features/progress_photos/data/local_progress_photos_repository.dart:35-39`.

## Основные функциональные и дизайн-гэпы

### Product

- `/community` использует нераскрытый in-memory mock. Посты и лайки исчезают после restart и не видны другим пользователям.
- Marketplace и team feed также mock, но помечены как demo.
- `Edit health questionnaire` ведёт на onboarding, откуда onboarded user немедленно возвращается на home.
- Paywall продаёт QR-функцию, которую Scanner объявляет удалённой.
- AI Planner является deterministic greedy heuristic, игнорирует выбранное пользователем оборудование и генерирует часть текста только на английском.
- Subscription loading/error визуально превращается в Free tier, что может ошибочно блокировать платного пользователя.
- Notification setting оптимистично сохраняется, но не гарантирует разрешение и реальное создание reminder.

Ключевые места:

- `mobile/lib/features/social_feed/state/social_feed_providers.dart:6-10`;
- `mobile/lib/features/social_feed/data/social_feed_repository.dart:17-89`;
- `mobile/lib/features/profile/profile_page.dart:90-101,176-189`;
- `mobile/lib/core/router/app_router.dart:92-94,337-339`;
- `mobile/lib/features/ai_planner/plan_builder.dart:19-98`;
- `mobile/lib/features/subscription/state/subscription_providers.dart:36-41,102-103`.

### UI и accessibility

- Подтверждён overflow Home CTA на ширине 320 dp: 19 px. В `Row` текст не обёрнут в `Flexible/Expanded` (`mobile/lib/features/home/home_page.dart:452-476`).
- Subscription error card использует практически одинаковый цвет фона и текста; там же пользователю показываются raw exception и stack trace.
- Onboarding CTA, выбор вариантов, timer controls и difficulty selection построены на bare `GestureDetector`: отсутствуют button/selected semantics, keyboard activation и корректное объявление disabled-state.
- Есть touch targets 36-40 dp вместо 44/48 dp.
- Login не scrollable и уязвим к overflow при keyboard или увеличенном text scale.
- Dynamic Form Coach/Posture results не объявлены как live regions.
- Обычный `ShellRoute` уничтожает scroll, filters и transient state вкладок при переключении.
- Runtime-шрифты Google Fonts не bundled: offline/TLS failure даёт fallback и возможный layout shift.

### Reliability и performance

- Несколько необязательных сервисов ожидаются до `runApp`; ошибка Firebase/plugin/prefs/assets может оставить native splash без recovery UI.
- Progress-photo grid строит всю историю, хранит расшифрованные JPEG в памяти без bounded cache и thumbnails.
- Video cache не имеет quota/LRU; `.part` может оставаться после ошибки.
- PoseDetector может не закрыться при failed camera start.
- AI Coach не имеет timeout и повторно расходует Gemini-запросы после закрытия sheet.
- Loading/error часто преобразуются через `.valueOrNull ?? []` в ложное состояние «данных нет».

### Platform scope

- iOS-папки и конфигурации нет; Firebase бросает `UnsupportedError`. Если продукт заявлен как Android-only, это допустимый scope; иначе blocker.
- Wear OS — scaffold: отсутствует Gradle wrapper, build-script не работает, `Done` не реализован, production-клиентов синхронизации нет.
- Android build использует compile SDK 35, тогда как `flutter_tts` требует 36.
- Release Gradle может молча использовать debug signing при отсутствии `key.properties`.
- `npm audit --omit=dev` обнаружил 15 advisory: 1 critical, 3 high, 10 moderate, 1 low. Достижимость каждой уязвимости конкретными handlers отдельно не доказана.

## Backend, security и deployment findings

### App Check и abuse protection

- Live enforcement отсутствует.
- Клиентская активация App Check сама по себе не обеспечивает server enforcement.
- Anonymous-account rotation позволяет обходить trial-per-UID.
- `maxInstances` ограничивает скорость расходов, но не заменяет quotas и abuse detection.

Рекомендация: staged enforcement, release-token validation, per-UID/device/IP quotas, trial-abuse protection и cost anomaly alerts.

### Stripe deployment

Deployed webhook не содержит локальных Acacia/Basil helpers. Это подтверждённый deployment drift, но активный production-инцидент зависит от реальной Stripe webhook API version.

До релиза необходимо проверить endpoint API version и replay test-mode событий обоих форматов.

### Invalid redirect domains

Billing Portal и Stripe Connect используют `fitnessapp.example.com`:

- `functions/src/index.ts:495-498`;
- `functions/src/index.ts:1031-1035`.

После завершения внешнего Stripe-потока пользователь может получить browser error.

### Firestore Rules

- Ownership в целом защищён.
- Schema/type/size validation для пользовательских документов недостаточна.
- Rules emulator tests отсутствуют.
- Live ruleset отличается от локального и не разрешает `debug_sessions`, поэтому live debug telemetry сейчас default-denied.

### Release integrity

- Build может пройти с debug signing, если release key отсутствует.
- Release script не проверяет signer готового APK/AAB.
- Release script не гарантирует чистый Git и прохождение всех gates.
- Канонический debug daemon использует чужой Firebase project ID `traidingbot-b4061`, что может скрывать реальные production errors.

## Результаты проверок

- Flutter unit/widget: **1886/1886 passed**.
- Functions Jest: **107/107 passed**.
- TypeScript build: passed.
- Catalog pytest: **169/169 passed**.
- Flutter analyze: 7 diagnostics, production compile errors нет.
- Android integration test: **3 passed / 7 failed**, 290.9 секунды.
- Wear build: падает сразу из-за отсутствующего `gradlew.bat`.
- Documentation link audit: красный; 87 текущих и 13 planned references, хотя часть результата является ложным срабатыванием скрипта.
- ARB parity: **910/910 RU/EN keys**.

### Интерпретация E2E

Результат `3 passed / 7 failed` нельзя трактовать как семь независимых production-багов:

- Home overflow — реальный дефект.
- Ожидание `Тренировка` вместо текущего `Тренировки` — устаревший тест.
- Тест ожидает только `squat`, хотя продукт поддерживает шесть движений — устаревший тест.
- Старый Home-текст также является stale assertion.
- Несколько сценариев каскадно падают из-за общего `boot()`.

Тем не менее release gate сейчас красный, а integration suite почти не покрывает real auth, payments, progress photos, workout logging, community и posture.

## Подтверждённые silent failures

- Ошибки/loading ряда Riverpod providers превращаются в пустые списки, Free tier или отсутствие данных.
- Notification permission denial приводит к тихому отсутствию reminder, хотя session сохраняется успешно.
- Live `debug_sessions` запрещён текущими production Rules, а upload failure только печатается локально.
- AI Coach может зависнуть без timeout.
- Subscription error показывает техническое исключение вместо безопасного recovery flow.
- Scanner и progress photos оставляют plaintext temp-файлы.
- Runtime font failure приводит к тихому fallback.

## Недостающие критические тесты

- Полная delete/export matrix по каждой server/local коллекции.
- Account A → delete/sign-out → Account B на одном устройстве.
- Две одновременные Checkout-сессии и deletion при нескольких subscriptions.
- Live Stripe Acacia/Basil webhook replay.
- Portal/Connect redirect contract tests.
- Firestore emulator rules tests и negative cases.
- App Check enforcement и quota-abuse tests.
- Hosted legal/rules/functions deployment drift test.
- Release signer verification.
- Progress photo shutter → capture → encryption → visible tile.
- Capture timeout/null/permission denied с видимой ошибкой.
- Real auth/onboarding/profile offline/error flow.
- Subscription purchase, restore, downgrade и revoked entitlement.
- Notification denied/re-enable/reboot reconciliation.
- Camera/ML retry/background/foreground leak tests на реальном устройстве.
- 320 dp, landscape, split-screen и 200-300% text scale.
- Semantics, keyboard traversal, focus restoration и live-region tests.
- 50-200 high-resolution progress photos с heap/jank profiling.
- Offline first launch без font cache.
- Real Wear round trip и настоящий iOS smoke-test, если платформы входят в scope.

## Что сделано хорошо

- Большая unit/widget test suite сейчас полностью зелёная.
- ARB RU/EN полностью синхронизированы.
- Camera session содержит readiness, watchdog и lifecycle safeguards.
- Posture page аккуратно обрабатывает pause/resume и stale async starts.
- Form Coach отделяет per-frame noise от per-rep verdict.
- Навигационная панель имеет selected/button semantics и крупные основные touch areas.
- Есть semantic light/dark palette и общие button tokens.
- Stripe webhook проверяет raw-body signature.
- Secrets используют `defineSecret`; committed Stripe secret/private key не найден.
- Firestore запрещает клиенту менять subscription.
- Customer creation имеет собственную идемпотентность.
- Functions ограничены `maxInstances`.

Зелёный unit/widget suite доказывает стабильность проверенных компонентов, но не корректность сквозных пользовательских сценариев.

## Git-аудит

- Рабочее дерево до сохранения этого отчёта было чистым.
- Исходники приложения во время аудита не изменялись.
- Ничего не отправлялось в remote.
- `master` опережает `origin/master` на один локальный коммит.
- Local HEAD: `3cc81266579f012f0583ec39e150adbe16632adc`.
- Remote HEAD: `8092b871861ecac4974d4dc32de819f66b8fd35c`.
- Локальный коммит содержит navigation/UI изменения и ещё не прошёл GitHub CI.
- `git diff --check` чистый.
- Закоммиченных private keys и Stripe secrets не найдено.
- Состояние удалённых GitHub Actions проверить не удалось: `gh` отсутствует, а GitHub connector не имеет доступа к репозиторию.

## Приоритетный план исправлений

### P0 — до любого публичного релиза

1. Закрыть data inventory: удалить или документированно анонимизировать все UID-связанные server и local данные.
2. Разделить photo directories/index/keys по UID, перенести ключ в Android Keystore и удалять plaintext temp.
3. Привести экспорт, privacy policy, terms и UI-copy к одному реальному контракту.
4. Сделать Stripe Checkout идемпотентным, исключить несколько активных subscriptions и при удалении отменять все.
5. Проверить Stripe endpoint API version и задеплоить Acacia/Basil fix.
6. Включить контролируемый App Check enforcement, quotas и anomaly alerts; защитить anonymous trial от account rotation.
7. Убрать или явно пометить как experimental live recognition, rep accuracy и posture reporting.
8. Исправить Home overflow и добиться зелёного E2E на текущем commit.

### P1 — перед расширением beta

1. Добавить Firestore Rules emulator tests и schema/size validation.
2. Добавить сквозные тесты account deletion и multi-account isolation.
3. Проверить две параллельные Checkout-сессии и Stripe reconciliation.
4. Добавить реальный device photo-capture ordering test.
5. Не показывать mock community/marketplace как production-функции.
6. Исправить entitlement loading/error, cold-start recovery и notification reconciliation.
7. Сделать CI fail-closed: Functions tests, integration tests, signer verification, dependency audit и deployment drift.
8. Определить официальный scope Android/iOS/Wear.

### P2 — качество и масштабирование

1. Bundle fonts и завершить semantic color migration.
2. Исправить accessibility targets, semantics, live regions и 200-300% text scale.
3. Добавить thumbnails, pagination и cache quota/LRU.
4. Разбить крупные страницы и `main.dart` на более узкие компоненты и контроллеры.
5. Обновить CODEMAP, AGENTS и release-документацию по фактическому состоянию.
6. Ввести production manifest: Git SHA, Functions revisions, ruleset ID, Hosting version и App Check modes.

## Финальный вердикт

Архитектура и объём реализации выше уровня обычного прототипа, но доверительные контуры — privacy, payments, production drift и ML validity — ещё не соответствуют публичному production-релизу.

После закрытия P0 приложение можно повторно оценивать как release candidate. Сейчас допустимый статус — закрытая Android beta с отключёнными или явно экспериментальными AI, progress photos, social, marketplace и Wear.

## Ограничения и побочные эффекты аудита

- Полный store-signed release build не выполнялся.
- Реальные Stripe-транзакции не проводились.
- ML не тестировался на новой независимой gym/OOD выборке в рамках этого аудита.
- GitHub Actions remote state был недоступен.
- Во время Android E2E произошёл signature conflict. Исходный APK был восстановлен, но после восстановления отображался Welcome/Login, поэтому прежняя авторизованная сессия эмулятора, вероятно, была сброшена.
- Эмулятор после аудита остановлен, временные APK и screenshot удалены.
- Исходники приложения не изменялись; единственный новый файл — этот отчёт.
