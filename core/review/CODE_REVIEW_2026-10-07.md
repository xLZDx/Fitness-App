# Fitness App / SPTR — предметное код-ревью, 2026-10-07

## Граница проверки

Локальный проект: `D:\Repo\Fitness_App`, ветка `master`, HEAD `a6e8005`, ahead 2. Перед этим дополнением рабочее дерево было чистым. Удалённый `master` повторно проверен: `3da7737e388434250ef61a1e24cd67f8cab5c4ad`. Номера строк ниже привязаны к этому удалённому SHA, а не к будущей версии файлов. Два локальных коммита по сообщениям относятся к отчётам; автоматически отправлять их нельзя.

Это риск-ориентированный review конкретных участков исходников и CI, не утверждение о построчном чтении всего репозитория. Десять независимых AI-агентов не запускались. Ролевые проходы предыдущего анализа выполнены одним ревьюером и не являются независимым консенсусом.

В этом задании выполняются чтение, проверка и обновление документации. Исправления application code, commit, push, deploy и изменение облачных настроек НЕ выполнены. План следующего исполнения: [AUTONOMOUS_TAIL_CLOSURE_2026-10-07.md](../plans/AUTONOMOUS_TAIL_CLOSURE_2026-10-07.md). Текущий статус: [REVIEW_STATUS_2026-10-07.md](../state/REVIEW_STATUS_2026-10-07.md).

## Свежая проверка на локальном компьютере

Через DC_MCP выполнен `npm test` в `functions/`: exit 0; **606 passed / 606, 24 suites / 24**, Jest time 43.803 s, длительность команды 46.086 s. Это реальный новый запуск, не цитата старого отчёта. Но Jest сообщил о worker, который не завершился корректно и был принудительно остановлен. Assertions PASS, teardown не чистый — CR-09.

`pytest` в `scripts/review/` достиг лимита 60 секунд: exit_code отсутствует, timeout=true. В выводе есть прогресс 32%, полного итога нет. Статус **TIMEOUT**, не PASS и не доказательство дефекта тестируемого кода. Свежие Flutter, Firestore emulator, Android device и production tests в этом дополнении не выполнены. Наборы не подменяются друг другом.

## Реестр код-ревью

`SOURCE_CONFIRMED` означает подтверждение по исходнику, но не новый runtime-прогон. `OPEN` означает, что исправление не реализовано. Приоритет P1 — до соответствующего релиза/активации; P2 — следующая очередь надёжности. Привязка к marketplace/store не делает замечание блокером любого личного теста.

| ID | Приоритет / граница | Статус | Место | Дефект или незакрытый механизм |
|---|---|---|---|---|
| CR-01 | P1 / воспроизводимость | OPEN, SOURCE_CONFIRMED + CI | `.gitignore:42–51`; `flutter.yml`, job dependency-scan | App lockfile исключён из Git; OSV нечего проверять в чистом checkout |
| CR-02 | P1 / security tests | OPEN, SOURCE_CONFIRMED + CI | `functions/scripts/run_emulator_tests.js:109–128`; `functions/package.json` | CLI Firebase не закреплён, `npx firebase` не запускает CI emulator tests |
| CR-03 | P1 / account lifecycle | OPEN, SOURCE_CONFIRMED | `mobile/lib/core/router/app_router.dart:100–115`, `resolveRedirect` | Удаление аккаунта перехватывается onboarding redirect |
| CR-04 | P1 / store-сборка | OPEN, SOURCE_CONFIRMED | `subscription_providers.dart:120–157`; `build_release.ps1:174–193` | Release wrapper не отключает разрешённый по умолчанию tier override |
| CR-05 | P2 / canary isolation | OPEN, SOURCE_CONFIRMED | `firestore.rules:45–73,180–217`, специальные grants | Canary исключён из wildcard, но разрешён отдельными правилами |
| CR-06 | P1 / качество scanner | OPEN, SOURCE_CONFIRMED | `gemini_equipment_service.dart:269–340`, `parseResponse` | Фильтр predicted label не исправляет описанную ошибку true-class → другой label |
| CR-07 | P2 / повреждение данных | OPEN, SOURCE_CONFIRMED | `local_sensitive_store.dart:54–68`; `sensitive_profile.dart`, `fromJson` | Обрабатывается FormatException, но не структурно неверный JSON с ошибкой типа |
| CR-08 | P1 / активация marketplace | OPEN, SOURCE_CONFIRMED | `functions/src/index.ts:1523–1548`, `bookCoachSession` | Timestamp booking ID и создание PaymentIntent без устойчивого idempotency key |
| CR-09 | P2 / test lifecycle | OPEN, OBSERVED_WARNING | `functions/jest.config.js`; Jest teardown | Свежие 606 PASS сопровождаются принудительным завершением worker |

### CR-01 — lockfile отсутствует не из-за неверного cwd

Код: `.gitignore` содержит `mobile/pubspec.lock`. OSV job запускается для mobile, но checkout не содержит lockfile; шаг не выполняет скан зависимостей. В других job `pub get` разрешает диапазоны заново. Один SHA приложения поэтому не фиксирует один граф зависимостей.

**Проверка:** чистый checkout проверенного SHA → наличие tracked lockfile → запустить scan. В прочитанном CI job `112625330641` отсутствует именно `/mobile/pubspec.lock`, exit 127. Старое объяснение «не та рабочая директория» не использовать.

**Исправление:** осознанно разрешить и проверить граф на выбранном Flutter, исключить app lockfile из ignore, добавить его в Git, проверять отсутствие дрейфа и сканировать этот же граф. Не генерировать произвольный свежий lockfile только ради зелёного сканера.

**Закрытие:** два чистых разрешения используют одинаковый проверенный lockfile; скан действительно отработал. Отсутствующий lockfile должен давать FAIL, не SKIP. Нельзя заявлять отсутствие уязвимостей при неисполненном сканере.

### CR-02 — Firebase emulator suites не доходят до assertions

Фрагмент `run_emulator_tests.js:109–113`:

```js
const result = spawnSync(
  `npx firebase emulators:exec --only ${emulators} ` +
    configFlag +
    `--project ${projectId} ` +
    `"npx jest --config ${config}"`,
```

В прочитанном `functions/package.json` отсутствует закреплённый `firebase-tools`. CI rules job `112632747579` заканчивается `npm error could not determine executable to run`. Это ошибка запуска инструмента, не провал assertions Firestore Rules.

**Исправление:** добавить совместимый закреплённый CLI в dev-toolchain, вызывать его однозначно, сохранить Java 21+ только для emulator path и тестовые `demo-*` project IDs. Не менять production project и не выключать security assertions.

**Закрытие:** `npm run test:rules` и `npm run test:e2e` проходят на чистом runner без глобального Firebase CLI; намеренно нарушенное правило делает соответствующий тест красным. Проверить Windows и Linux. Отдельно от 606 unit tests.

### CR-03 — account deletion недоступен до окончания анкеты

Фрагмент `resolveRedirect`:

```dart
if (isSignedIn &&
    !isOnboarded &&
    location != '/onboarding' &&
    !isEquipmentOrWorkout &&
    !isPublic) {
  return '/onboarding';
}
```

`/delete-account` не public и не equipment/workout. Для авторизованного пользователя с незавершённой анкетой запрос этого маршрута детерминированно возвращает `/onboarding`.

**Исправление:** ввести узкий набор authenticated account-actions, доступных до onboarding. Не делать удаление публичным и не удалять повторную проверку личности на чувствительном действии. Добавить понятный вход в удаление/отказ из незавершённого onboarding, а не только исключение для deep link.

**Регрессия:** новый аккаунт, гость, авторизованный завершивший анкету, прерванная анкета, ошибка загрузки профиля, signed-out. Для signed-in/not-onboarded `/delete-account` должен стать доступен; signed-out по-прежнему получает `/login`. После теста маршрута проверить реальный UI-вход.

### CR-04 — личный тестовый режим не отделён от store release

```dart
const bool kAllowTierOverride =
    bool.fromEnvironment('ALLOW_TIER_OVERRIDE', defaultValue: true);
```

Штатный `build_release.ps1:174–178` передаёт GIT_SHA, BUILT_AT и build-number, но не `ALLOW_TIER_OVERRIDE=false`. Поэтому один только флаг `--release` не обеспечивает отключение override. Это не доказанный обход всех серверных entitlement-проверок.

**Исправление:** явные personal/test/store build profiles; store задаёт false и отказывается от недопустимого сочетания. Не ломать личный режим оператора. Проверять guard в месте вычисления tier, а не только скрытие настройки. Отдельно проверить, что сервер сам защищает платные ресурсы.

**Закрытие:** тесты для разрешённого personal и запрещённого store; store артефакт с заранее сохранённым premium override не повышает tier без реальной подписки. Default wrapper не должен выдавать себя за безопасный store-профиль.

### CR-05 — canary policy не совпадает с эффективными Rules

Общий `/users/{uid}/{coll}/{document=**}` исключает `isCanaryToken()`. Но отдельный профильный grant проверяет uid без этого условия:

```text
allow read: if request.auth != null && request.auth.uid == uid;
```

Профильная запись также не исключает canary; каталоги допускают любую авторизацию. Следовательно, canary может получить доступ за пределами `_canary`, например к собственному профилю. Пересекающиеся Firestore grants объединяются разрешающим образом — запрет в wildcard не отменяет разрешение специального правила.

**Граница:** доступ к чужому uid не показан; массовая утечка НЕ доказана. Public donor wall и иные сознательно public поверхности следует отдельно классифицировать, а не требовать их блокировки для canary без продуктового основания.

**Исправление:** единый predicate обычного пользователя, сверка всех non-public grants, синхронизация canary-контракта и тестов. Не ослаблять обычный owner access.

**Закрытие:** настоящие emulator tests для canary/owner/other-user/anonymous/signed-out и всех специальных коллекций. Canary negative tests должны проверять собственный профиль, recognised_models, debug_sessions и каталоги, а не только wildcard.

### CR-06 — направление ML-ошибки перепутано с направлением фильтра

Комментарий говорит, что реальные rotary torso на тестовых фото распознавались как другие тренажёры. Реализация отбрасывает ответ, только если модель НАЗВАЛА его rotary torso:

```dart
if (kKnownUnreliableMachineNames.contains(name.trim().toLowerCase())) {
  return;
}
```

Такой фильтр не ловит истинный rotary → predicted treadmill/другая категория. Более того, он может отклонить будущий правильный predicted rotary. Наличие других подтверждающих этапов pipeline не делает эту конкретную меру доказанным исправлением описанной ошибки.

**Исправление:** regression fixture с true label и predicted label отдельно; confusion matrix; проверяемое подтверждение/уточнение вместо уверенного продвижения. Не удалять guard вслепую и не добавлять новые произвольные запреты. Сперва показать измеренное поведение всего пути.

**Закрытие:** отрицательный кейс реальный rotary/предсказан другой id не проходит как подтверждённая exact identity. Публиковать отдельно качество классификации, abstention, неверное уверенное продвижение и время до подтверждения. Старые 33 фото не считать рыночной точностью.

### CR-07 — структурно повреждённый health JSON не обработан

`PrefsSensitiveStore.read` ловит только `FormatException`. `SensitiveProfile.fromJson` использует `j['health'] as Map?`. JSON `{"health": []}` синтаксически корректен, но даёт ошибку типа, а не FormatException. Обещанное graceful-восстановление для такого содержимого не покрыто этим catch.

**Исправление:** явная schema validation и типизированный результат отсутствия/успеха/повреждения; безопасное восстановление без автоматической перезаписи исходного blob. Не делать широкий catch, превращающий любое повреждение в отсутствие ограничений.

**Закрытие:** malformed JSON, неверные типы health/списков/enum, старые схемы, два uid, сохранность исходных данных и UI восстановления. SafetyContext остаётся fail-closed. Гипотеза «пустой screening разрешает тренировку» снята — код screening блокирует неполную анкету.

### CR-08 — повторное бронирование создаёт новые объекты

```ts
const bookingId = `bk_${Date.now()}_${auth.uid}`;
const intent = await stripe.paymentIntents.create({ /* ... */ });
```

Повтор одной логической операции в другой миллисекунде создаёт новый ID и новый PaymentIntent. Ошибка Firestore после успешного Stripe-create оставляет orphan intent. В одной миллисекунде возможна и коллизия ID. Это не доказательство повторного списания: создание PaymentIntent и подтверждение платежа — разные события.

**Исправление:** устойчивый request ID, привязанный к uid, проверка совпадения параметров повторного запроса, Stripe idempotency key, durable booking state machine, reconciliation между Stripe и Firestore. Нельзя начинать с маскировки кнопки.

**Закрытие:** последовательный и параллельный повтор, тот же ключ с изменённой суммой/слотом, разрыв сети после Stripe, retry Firestore, expiry/cancel/refund. Проверять slot validation отдельно. Пока live marketplace не активирован, это его activation blocker, не обязательное расширение основного MVP. Клиентский demo-баннер не доказывает, что backend callable выключен.

### CR-09 — test worker завершается принудительно

Свежий локальный Jest: 24 suites PASS, 606 tests PASS, но `A worker process has failed to exit gracefully and has been force exited`. Источник утечки конкретного timer/listener ещё не установлен.

**Исправление:** отдельный диагностический запуск с `--runInBand --detectOpenHandles`, сужение по suite; завершение timers/listeners/servers/SDK clients в teardown. Не включать `--forceExit` ради зелёного вывода.

**Закрытие:** повторяемый нормальный выход без предупреждения при сохранении 606 или актуального большего числа реально выполненных assertions. Возможную деградацию runtime отделить от времени подготовки.

## Кандидат, который нельзя объявлять доказанным дефектом

**CAND-01 — `profileWatchOf` в app_router.dart, async auth-listener и await отмены подписки.** Быстрые auth-события могут пересечь отмену и создание profile streams. Нужен детерминированный тест back-to-back A → B → sign-out с задержанной cancel, учитывающий старые emissions. До красного reproducer статус VERIFY, не CONFIRMED. При подтверждении — serialisation/generation fence; иначе снять гипотезу. Нельзя менять router на основании одного предположения.

## Проверки релиза, а не новые доказанные баги кода

| ID | Наблюдение | Следующее действие | Граница автономии |
|---|---|---|---|
| VER-01 | npm production audit: 18 записей, 10 moderate / 7 high / 1 critical; job 112632747596 | Зафиксировать audit JSON, dependency path и достижимость; совместимые обновления | Без `audit fix --force` вслепую; live exploit не проводить |
| VER-02 | Flutter release job остановился на GOOGLE_SERVICES_JSON_B64 | Сделать preflight; сверить secret supply path, build/config/signing | Чтение секретных значений в отчёт запрещено; настройка credentials отдельно |
| VER-03 | Flutter test job красный | Реальный новый suite, сопоставление golden diffs на закреплённом окружении | Не считать все падения шрифтами заранее; не массово перезаписывать goldens |
| VER-04 | Emulator integration job красный | Разделить boot/build/assertion failure, прогнать весь каталог integration_test | Физическую биомеханику эмулятор не подтверждает |
| VER-05 | CT-1 job падает на ML lifecycle/manifests; дальнейшие шаги пропущены | Исправить сравнение provenance с immutable evidence, а не подгонять SHA | Не придумывать human labels; scripts/review timeout отдельно |
| VER-06 | RU/EN drift job красный | Сверить реальные пары и смысл отрицаний, добавить focused tests | Heuristic finding не равен доказанной ошибке перевода |
| VER-07 | В майских roadmap/queue смешаны текущие и устаревшие утверждения | Обновить входные точки и очередь, сохранить историю | Generated CURRENT_STATE.md не редактировать вручную |

Источники CI: Flutter run `37569707786`, Functions run `37572085504`, удалённый SHA указан вверху. Это прочитанные результаты 7 октября, не свежие запуски из данного дополнения. Ссылки: https://github.com/xLZDx/Fitness-App/actions/runs/37569707786 и https://github.com/xLZDx/Fitness-App/actions/runs/37572085504 .

## Снятые и ограниченные выводы

1. Ошибка «страницы исчезают из-за FadeTransition» СНЯТА. Второй переход читает secondary; менять его по прежнему замечанию нельзя.
2. «OSV падает из-за cwd» ЗАМЕНЕНО CR-01: lockfile игнорируется.
3. «Corrupt/empty health автоматически разрешает тренировку» НЕ ПОДТВЕРЖДЕНО: incomplete screening блокируется. Реальная проблема CR-07 — типизация и восстановление.
4. Отсутствие отдельного переключателя Crashlytics не доказывает отсутствие раскрытия: документация описывает diagnostics. Правовые основания и runtime-потоки требуют отдельной проверки.
5. Canary mismatch не является доказательством доступа к чужим аккаунтам; npm audit не доказывает exploit; повтор PaymentIntent не равен повторному списанию.
6. Код, тесты, release artifact и production deployment — четыре разных уровня доказательств. Ни один не заменяет остальные.

## Итог

**Кодовая база существенно реализована; остатки исправлений OPEN; публичный коммерческий release readiness не подтверждён.** Ближайшая работа — CR-01/02/03/04, разбор VER-01…06, затем CR-05/06/07/09 и проверка CAND-01. CR-08 закрывается до активации marketplace. Внешнюю клиническую оценку, живой S23 Form Coach и запуск магазина нельзя объявлять выполненными инженерной записью в Markdown.
