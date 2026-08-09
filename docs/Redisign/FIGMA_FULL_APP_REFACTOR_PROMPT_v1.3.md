# FITNESS APP — FULL FIGMA REFACTOR PROMPT v1.1

Ты — Lead Product Designer, Senior Mobile UX/UI Designer и Design Systems
Architect с опытом в fitness, health, workout tracking, computer vision,
on-device ML и AI-assisted mobile products.

Нужно провести полный UX/UI-рефактор существующего Fitness App для Android и
iOS. Это не новый продукт с нуля и не запрос на создание красивых отдельных
экранов без связи. Приложение уже существует и содержит работающие функции.
Нужно сохранить продуктовую логику, устранить слабую иерархию стандартного
плиточного интерфейса и собрать целостный современный пользовательский опыт.

Используй приложенные скриншоты текущего приложения, референсы и видео как
материал для исследования. Не копируй чужие приложения один в один. Заимствуй
только доказанно полезные UX-паттерны, адаптируй их под реальные возможности
Fitness App и явно фиксируй, что было принято, изменено или отклонено.

---

## 1. Контекст продукта

Fitness App — персональный AI-помощник для тренировок в зале, дома и на улице.

Основные возможности продукта:

1. Каталог из 1 887 уникальных упражнений.
2. Лицензированные анатомические анимации упражнений высокого качества.
3. Техника выполнения и пошаговые инструкции.
4. Персональные рекомендации по цели, опыту, оборудованию, истории и
   ограничениям.
5. Контекстный AI-тренер.
6. Распознавание тренажёров камерой.
7. Страница распознанного оборудования с подходящими упражнениями.
8. Проверка техники камерой и pose detection.
9. Персональные тренировочные планы.
10. Журнал веса, повторений и подходов.
11. Автоматический таймер отдыха.
12. История тренировок и прогресс.
13. Оценка нагрузки и восстановления мышц.
14. Injury-aware filtering.
15. Голосовое сопровождение.
16. Health Connect и носимые устройства.
17. Фото прогресса и визуальное сравнение снимков.
18. Светлая и тёмная темы.

Главный продуктовый цикл:

Пользователь приходит в зал → видит незнакомый тренажёр → сканирует его →
получает релевантные упражнения → смотрит технику и анатомическую анимацию →
выполняет подходы → при необходимости включает Form Check → сохраняет
результат → видит прогресс и следующую рекомендацию.

Приложение должно восприниматься не как каталог карточек, а как персональный
AI-помощник непосредственно во время тренировки.

---

## 2. Главные проблемы текущего интерфейса

Проведи design audit и визуально покажи Before / After для следующих проблем:

1. Все функции представлены одинаковыми плитками — нет иерархии.
2. Главный экран не отвечает, что делать сейчас.
3. Второстепенные блоки могут быть визуально сильнее тренировки.
4. Scanner не ощущается главным уникальным преимуществом.
5. Списки упражнений используют мелкие карточки и слабую media-подачу.
6. Progress показывает пустые одинаковые tiles без полезной интерпретации.
7. AI может выглядеть как generic chat, а не контекстный тренер.
8. Ввод возраста, роста и веса через обычные поля противоречит premium UX.
9. Workout logging может быть слишком плотным и техническим.
10. Empty, loading, error и permission states не являются частью единой системы.
11. Нет цельного перехода от сканирования к упражнению, тренировке и прогрессу.

---

## 3. Что взять из референсов

Принять и адаптировать:

- один вопрос на один экран;
- явный progress onboarding;
- wheel/ruler pickers для возраста, роста и веса;
- анатомическую карту мышц;
- визуальный выбор целей и ограничений;
- preview персонального плана до регистрации или оплаты;
- media-first карточки;
- hero-блок «Сегодня»;
- удобный set logger;
- автоматический rest timer;
- компактные списки программ;
- контекстный AI Coach;
- визуальный progress comparison;
- before/after side-by-side и slider;
- мягкие contextual reminders.

Отклонить:

- countdown timers продаж;
- scratch cards и искусственные скидки;
- paywall до ценности;
- ложную срочность;
- неподтверждённые before/after claims;
- ложные точные сроки достижения цели;
- BMI как диагноз;
- body score и beauty score;
- generic AI chat без контекста;
- рекламу внутри core flows;
- одинаковые плитки для всех функций;
- автоматическую публикацию чувствительных фото;
- ложную AI-точность.

---

## 4. Основные UX-принципы

Каждый главный экран должен отвечать минимум на один вопрос:

- Что мне делать сейчас?
- Почему это рекомендовано мне?
- Как выполнить действие правильно?
- Как быстро сохранить результат?
- Как изменился мой прогресс?
- Что делать следующим?

Используй progressive disclosure:

1. Главное действие.
2. Краткая причина или результат.
3. Дополнительные детали по запросу.

Требования:

- одно доминирующее primary action на экран;
- максимум три крупных смысловых блока до первого scroll;
- важные controls доступны одной рукой;
- во время активной тренировки вторичный контент скрывается;
- не использовать grid как универсальное решение;
- не показывать неподтверждённые метрики;
- не смешивать health guidance с медицинской диагностикой;
- не использовать цвет как единственный сигнал.

---

## 5. Визуальное направление

Сохрани и развивай выбранное направление:

- dark premium foundation;
- lime accent для primary actions;
- крупная выразительная типографика;
- media-first композиция;
- глубокие нейтральные surfaces;
- ограниченные градиенты;
- мягкая глубина;
- округлые поверхности;
- функциональные анимации;
- минимум визуального шума.

Создай полноценную light-theme adaptation, а не простую инверсию.

Glassmorphism использовать только:

- camera overlays;
- floating controls;
- modal sheets;
- временные status overlays.

Не использовать blur на каждом scrolling card.

---

## 6. Information Architecture

Основная нижняя навигация:

1. Home
2. Scan
3. Workouts
4. Progress
5. Profile

Вложенные разделы:

### Home
- Today workout
- Continue workout
- Quick Scan
- Recovery snapshot
- Weekly progress
- Milestones
- Progress photo comparison card при наличии данных

### Scan
- Camera
- Recognition states
- Top alternatives
- Unknown equipment
- Scan history
- Saved machine cards

### Workouts
- Current program
- Calendar
- Workout library
- Exercise library
- Equipment library
- Saved workouts
- Active workout

### Progress
- Summary
- Strength progression
- Volume
- Consistency
- Muscle load and recovery
- Measurements
- Progress Photos
- Achievements
- History

### Profile
- Personal data
- Goals
- Units
- Integrations
- Notifications
- Privacy
- Subscription
- Help

Scanner должен быть наиболее заметной уникальной функцией, но Today Workout
остаётся главным действием Home.

---

## 7. Полный onboarding flow

Создай короткую обязательную часть и optional personalization.

### 7.1 Value Proposition

Заголовок:
«Твой AI-помощник в тренажёрном зале»

Подзаголовок:
«Распознавай тренажёры, получай персональные упражнения и проверяй технику
камерой».

Actions:
- «Настроить мой план»
- «Продолжить без регистрации»
- «Войти»

### 7.2 Главная цель

Single select:
- Набрать мышцы
- Стать сильнее
- Снизить вес
- Улучшить форму
- Повысить выносливость
- Вернуться после перерыва

### 7.3 Уровень

- Начинаю впервые
- Новичок
- Средний
- Опытный

Каждый вариант имеет понятное описание.

### 7.4 Место тренировок

- Тренажёрный зал
- Дом
- Улица
- Смешанный режим

### 7.5 Оборудование

Multi-select:
- Полный зал
- Отдельные тренажёры
- Гантели
- Штанга
- Гири
- Резинки
- Собственный вес
- Не знаю названий — буду сканировать камерой

### 7.6 График

- дней в неделю;
- длительность тренировки;
- предпочтительные дни.

Не запрашивать notification permission здесь.

### 7.7 Ограничения

Интерактивная модель тела:
- плечо;
- локоть;
- запястье;
- верх спины;
- поясница;
- тазобедренный сустав;
- колено;
- голеностоп;
- ограничений нет.

Текст:
«Используем это, чтобы исключить потенциально неподходящие упражнения. Это не
медицинская диагностика».

### 7.8 Приоритетные зоны

Интерактивная анатомическая модель, multi-select:
- грудь;
- спина;
- плечи;
- руки;
- пресс;
- ягодицы;
- ноги;
- всё тело.

Экран optional.

### 7.9 Основное препятствие

- Не знаю, что делать
- Не понимаю тренажёры
- Сомневаюсь в технике
- Не хватает времени
- Трудно сохранять регулярность
- Есть дискомфорт или ограничения
- Ничего из перечисленного

### 7.10 Год рождения

Вертикальный wheel picker:
- selected year крупно;
- соседние значения с меньшей opacity;
- haptic feedback;
- direct input;
- кнопки accessibility;
- возможность пропустить.

Хранить год рождения, возраст рассчитывать.

### 7.11 Рост

Ruler picker:
- cm/ft;
- шаг 1 см;
- major ticks;
- fixed center indicator;
- direct input;
- haptic feedback;
- `−` / `+` controls;
- optional.

### 7.12 Текущий вес

Horizontal ruler picker:
- kg/lbs;
- шаг 0,1 кг;
- fixed indicator;
- direct input;
- haptic feedback;
- optional.

Для взрослых при наличии роста и возраста показывать нейтральную справочную
карточку:
- BMI;
- ориентировочный диапазон для роста;
- разница до ближайшей границы;
- пояснение, что BMI не учитывает состав тела и мышечную массу.

Для пользователей младше 20 лет не показывать взрослую BMI-категорию.

Запрещённые формулировки:
- неправильный вес;
- обязан похудеть;
- страдаешь ожирением;
- плохая форма.

### 7.13 Целевой вес

Ruler picker с маркерами current/target.

Показывать:
- текущий вес;
- целевой вес;
- delta kg;
- delta percent от текущего веса.

Формула:
`(target - current) / current × 100`.

Не обещать срок результата. Целевой вес optional.

### 7.14 Health Connect

Отдельный optional screen:
- шаги;
- сон;
- активность;
- восстановление.

Permission только после CTA «Подключить».

### 7.15 Generating

Показывать только реально введённые параметры.
Не использовать ложный progress и ложные обещания.

### 7.16 Plan Preview

До аккаунта и paywall показать:
- цель;
- тренировок в неделю;
- длительность;
- место;
- приоритетные мышцы;
- первую тренировку;
- реальные exercise posters.

### 7.17 Account

После preview:
- Google
- Apple
- Email
- Продолжить без аккаунта

### 7.18 Notifications

Contextual prompt после выбора конкретного дня и времени.

---

## 8. Home

Перестрой Home вокруг следующего действия.

Порядок:

1. Greeting.
2. Program progress.
3. Hero Today Workout.
4. Start / Continue CTA.
5. Quick Scan card.
6. Recovery snapshot.
7. Weekly calendar and stats.
8. Last achievement.
9. Progress photo comparison card при наличии минимум двух снимков.

Hero пример:

«Сегодня — Спина и бицепс»
7 упражнений · 48 минут
«Начать тренировку»

Quick Scan должен быть вторым по визуальному приоритету после hero.

Не показывать пустой progress-photo блок на Home.

Horizontal recovery list должен иметь scroll affordance и не обрезать
последний item.

---

## 9. Scanner

Fullscreen camera flow.

Состояния:
- permission;
- ready;
- targeting;
- capturing;
- analyzing;
- high-confidence result;
- Top-3 alternatives;
- unknown equipment;
- low light;
- no equipment in frame;
- timeout;
- offline fallback;
- error;
- history.

UI:
- corner brackets;
- sweep line;
- glass instruction pill;
- flash;
- capture;
- cancel;
- retry;
- history.

Результат открывать bottom sheet:
- название;
- назначение;
- мышцы;
- количество упражнений;
- suitability;
- CTA «Открыть тренажёр»;
- alternatives;
- «Это другой тренажёр».

Unknown equipment:
- фото пользователя;
- предполагаемое название;
- описание;
- uses;
- «Контент готовится»;
- сохранить карточку;
- не подставлять ближайший неправильный объект.

---

## 10. Equipment Page

Использовать hero poster связанного лицензированного упражнения.
Не использовать внешние stock images.

Структура:
- cinematic hero;
- name/category;
- purpose;
- muscles;
- suitability badge;
- safety note;
- featured recommended exercise;
- full exercise list;
- AI Coach;
- Add to workout.

Первое рекомендуемое упражнение визуально сильнее остальных.

---

## 11. Exercise Page

Media-first layout:
- anatomical animation;
- title;
- primary/secondary muscles;
- level;
- equipment;
- why recommended;
- 3 key technique steps;
- common mistakes;
- restrictions;
- history;
- AI Coach;
- Form Check;
- Start Exercise.

Полные инструкции раскрываются по запросу.

---

## 12. Workout Player

Immersive active mode:
- large media;
- exercise number;
- set counter;
- total time;
- previous performance;
- weight input;
- reps input;
- optional RPE;
- notes;
- Form Check;
- replace/skip;
- guarded finish.

Primary CTA:
«Завершить подход».

После сохранения:
- haptic;
- confirmation;
- Undo;
- automatic rest timer.

Set history открывается bottom sheet, а не занимает весь экран.

---

## 13. Rest Timer

Overlay или dedicated state:
- circular countdown;
- next target;
- «Готов раньше»;
- `+30 секунд`;
- pause;
- notification/haptic when complete.

---

## 14. Тренер по технике / Live Form Check

Это отдельный ключевой сценарий продукта, а не одна кнопка или технический
camera preview. Пользователь должен понимать:

- куда поставить телефон;
- каким боком или лицом встать;
- помещается ли тело в кадр;
- достаточно ли света;
- начался ли анализ;
- засчитан ли повтор;
- какую одну ошибку исправить сейчас;
- что произошло после подхода.

### 14.1 Проблемы текущего экрана, которые нужно исправить

Используй приложенный скрин текущего «Тренера по технике» как материал аудита.
Зафиксируй следующие проблемы:

- в production UI видна техническая строка вроде `pose[pixels]...` — удалить;
- нижние карточки содержат длинный технический текст и слабую иерархию;
- нет крупного доминирующего счётчика повторений;
- неясно, прошли ли lighting, visibility и angle gates;
- одновременно показано слишком много инструкций;
- текущая подсказка не отделена от setup-инструкции;
- status overlay и skeleton недостаточно объясняют, что делать пользователю;
- иконки вспышки и звука должны иметь явные состояния и доступные labels;
- privacy-сообщение не должно конкурировать с live coaching во время подхода.

Сохрани полезную идею текущего экрана:

- live camera;
- силуэт требуемого ракурса;
- landmark/skeleton overlay;
- предупреждение «Слишком темно или размыто»;
- голосовое сопровождение;
- on-device privacy copy, но только если это подтверждено реализацией.

### 14.2 Точки входа

Покажи запуск «Тренера по технике» из:

1. Exercise Page — CTA «Проверить технику».
2. Workout Player — действие для текущего упражнения.
3. Workout setup — optional режим перед первым рабочим подходом.

Не делай Form Check отдельным generic camera-разделом без выбранного упражнения.
До запуска должны быть известны exercise ID, поддерживаемый ракурс и доступный
тип проверки.

### 14.3 Pre-check / Setup Screen

Перед камерой показать:

- название упражнения;
- poster или короткий reference frame;
- требуемый ракурс: спереди / сбоку / 45°;
- где поставить телефон;
- рекомендуемое расстояние;
- какие части тела должны быть видны;
- короткую privacy note;
- CTA «Открыть камеру».

Пример:

«Встань боком к камере»

«Телефон должен видеть тело от головы до стоп. Поставь его примерно на уровне
таза и отойди на 2–3 метра».

Дай secondary action:

- «Почему нужен этот ракурс?»
- «Не могу поставить телефон так».

### 14.4 Live Camera Composition

Экран должен называться:

**«Тренер по технике»**

Top bar:

- Back;
- название;
- flash on/off;
- sound/TTS on/off;
- optional help.

Камера — главный визуальный слой, минимум 60–70% доступной высоты до появления
клавиатуры или sheet.

Поверх камеры:

- silhouette guide для нужного упражнения и ракурса;
- pose landmarks;
- соединённый skeleton;
- подсветка отдельных сегментов;
- границы безопасной зоны кадра;
- current quality banner;
- компактный rep counter после начала движения.

Не показывать:

- raw landmark coordinates;
- pixel debug values;
- model confidence dumps;
- rule IDs;
- developer logs;
- названия внутренних classifiers.

### 14.5 Quality Gates до начала счёта

Подготовь отдельные визуальные состояния:

1. Камера инициализируется.
2. Слишком темно.
3. Изображение размыто.
4. Человек слишком близко.
5. Человек слишком далеко.
6. Тело не полностью в кадре.
7. Не видны обязательные суставы.
8. Неправильный ракурс.
9. В кадре больше одного человека.
10. Поза найдена, идёт калибровка.
11. Готово к началу.

Quality banner размещать внутри camera area или непосредственно под ней.
Сообщение должно быть коротким и actionable:

- «Добавь света»;
- «Протри камеру или остановись на секунду»;
- «Отойди немного дальше»;
- «Повернись левым боком»;
- «Покажи стопы в кадре»;
- «Готово — начинай движение».

Пока обязательные gates не пройдены:

- не считать повторения;
- не показывать form score;
- не давать положительную или отрицательную оценку техники.

### 14.6 Ready State

После успешной калибровки показать:

- короткую success-индикацию;
- «Поза распознана»;
- «Начинай движение»;
- счётчик `0 повторений`;
- optional 3-second countdown;
- действие pause/exit.

Не требовать отдельного нажатия Start, если продукт поддерживает безопасный
auto-start после обнаружения движения. Если auto-start не подтверждён, оставить
явную кнопку «Начать подход».

### 14.7 Active Coaching State

Во время подхода показать:

- крупный счётчик повторений;
- текущую фазу: вверх / вниз / удержание;
- одну главную live-подсказку;
- короткий status качества;
- pause;
- finish.

Примеры live cues:

- «Опускайся чуть глубже»;
- «Колени направляй по линии стоп»;
- «Сохраняй спину нейтральной»;
- «Не спеши в нижней точке»;
- «Повтор не удалось оценить».

Правило: одновременно показывать не более одной основной корректирующей
подсказки. Не превращать экран в список ошибок.

Visual semantics skeleton:

- neutral — сустав виден, оценки ещё нет;
- green — сегмент в допустимом диапазоне;
- amber — требуется небольшая корректировка;
- red — явная текущая ошибка;
- grey/dashed — сустав или сегмент временно потерян.

Цвет всегда дублировать текстом или символом.

### 14.8 Потеря позы во время подхода

Если пользователь вышел из кадра, повернулся или качество упало:

- поставить оценивание на паузу;
- не увеличивать счётчик;
- не засчитывать неполный повтор;
- показать короткую инструкцию;
- автоматически продолжить после восстановления gates, если это безопасно.

Состояния:

- «Не вижу всё тело»;
- «Вернись в отмеченную область»;
- «Слишком темно для оценки»;
- «Ракурс изменился»;
- «Повтор не оценён».

### 14.9 Голосовые подсказки

Покажи toggle звука в top bar.

Требования к UX:

- видимый текст и TTS используют одну и ту же локализованную фразу;
- новые cues не накладываются на ещё звучащие;
- одинаковая ошибка не повторяется каждую секунду;
- пользователь может выключить голос, сохранив визуальные подсказки;
- важная потеря видимости доступна визуально и голосом.

### 14.10 Нижняя Status Panel

Вместо нескольких длинных технических карточек создай один адаптивный bottom
status panel.

До начала:

- setup instruction;
- quality state;
- readiness checklist.

Во время подхода:

- reps;
- phase;
- current cue;
- pause/finish.

Privacy explanation показывать:

- на pre-check;
- в help/privacy sheet;
- не повторять большой карточкой во время каждого подхода.

Если обработка действительно выполняется на устройстве, допустимый текст:

«Анализ выполняется на устройстве. Кадры не отправляются в облако».

Если это не подтверждено текущей реализацией, пометь текст как Product Decision
и не придумывай privacy promise.

### 14.11 Завершение и Summary

После подхода показать:

- обнаружено повторений;
- оценено повторений;
- сколько повторов не удалось оценить;
- 1–2 сильные стороны;
- максимум 1–2 приоритетные корректировки;
- CTA «Повторить подход»;
- CTA «Продолжить тренировку»;
- CTA «Посмотреть технику».

Не показывать общий score, если значимая часть повторений не прошла visibility
или quality gates.

Не обещать replay проблемных моментов, если приложение не записывает видео.
Запись/сохранение кадров — отдельный opt-in и отдельное product/privacy решение.

### 14.12 Все обязательные состояния

Подготовь high-fidelity экраны и component variants:

- unsupported exercise;
- required angle selection;
- permission explanation;
- permission denied;
- permission permanently denied;
- camera unavailable;
- initialization;
- low light;
- blur;
- too close;
- too far;
- partial body;
- missing required joints;
- wrong angle;
- multiple people;
- calibration;
- ready;
- countdown;
- active rep counting;
- correct cue;
- warning cue;
- error cue;
- pose lost;
- paused;
- cannot evaluate rep;
- detector error;
- thermal/performance warning;
- completed;
- insufficient-data summary.

### 14.13 Компоненты Figma

Добавь в design system:

- TechniqueCoachCameraFrame;
- ExerciseAngleGuide;
- PoseSkeletonOverlay;
- PoseSegmentState;
- QualityGateBanner;
- CalibrationIndicator;
- LiveRepCounter;
- MovementPhaseIndicator;
- LiveCueCard;
- TechniqueCoachStatusPanel;
- VoiceCueToggle;
- FormCheckSummaryCard.

Для каждого — default, active, warning, error, disabled, loading и accessibility
variants, где применимо.

### 14.14 Accessibility

Обязательно:

- не полагаться только на цвет skeleton;
- озвучивать readiness и потерю позы;
- крупные controls 48 px+;
- captions для всех TTS cues;
- возможность выключить animation/voice;
- high-contrast overlay mode;
- управление pause/finish без точного мелкого tap;
- landscape и portrait states;
- длинные русские тексты без перекрытия камеры.

### 14.15 Required Prototype Flow

Связать интерактивный сценарий:

Exercise Page
→ «Проверить технику»
→ Pre-check
→ Camera Permission
→ Low Light
→ Correct Lighting
→ Wrong Angle
→ Correct Angle
→ Calibration
→ Ready
→ Active Rep 1
→ Live Cue
→ Pose Lost
→ Pose Restored
→ Complete Set
→ Technique Summary
→ Return to Workout Player.

---

## 15. Workout Summary

Показывать:
- duration;
- exercises;
- sets;
- volume;
- personal records;
- perceived difficulty;
- form highlights;
- recovery impact;
- next workout.

Не превращать summary в бессмысленную gamification.

---

## 16. Progress

Структура:
1. Summary.
2. Consistency.
3. Volume.
4. Key exercise progress.
5. Goal progress.
6. Muscle load and recovery.
7. Measurements.
8. Progress Photos.
9. Achievements.
10. History.

Recovery labels:
- высокая;
- средняя;
- низкая;
- недостаточно данных.

Каждый график должен отвечать на конкретный вопрос.

---

## 17. Progress Photos

Основной путь:
Progress → Фото прогресса → Gallery → Compare → Export.

Не размещать как основную функцию в Profile и не включать в onboarding.

### 17.1 Empty State

- объяснение пользы;
- CTA «Добавить первое фото»;
- privacy note.

### 17.2 Privacy Explanation

Перед первым сохранением:
- фото приватны;
- не публикуются автоматически;
- пользователь контролирует export;
- не обещать storage policy, пока она не утверждена.

### 17.3 Capture

- angle: front/side/back/free;
- silhouette guide;
- fullscreen camera;
- grid;
- timer 3/5/10;
- flash;
- switch camera;
- preview;
- retake/save;
- optional metadata: date, weight, note, milestone.

### 17.4 Gallery

Основной вид — timeline:
- thumbnail;
- date;
- angle;
- optional weight;
- note/milestone;
- filter;
- multi-select;
- edit/delete/compare.

### 17.5 Compare

Два режима:

A. Side by side.
B. Interactive slider.

Controls:
- swap;
- select other photos;
- hide weight;
- hide date;
- fit/fill;
- reset.

Manual alignment:
- zoom;
- x/y offset;
- rotation;
- reset.

Не использовать body morphing.

### 17.6 Export

Preview before share:
- hide weight/date;
- optional face blur;
- watermark;
- background;
- save/share.

По умолчанию вес скрыт.

### 17.7 Home Card

Показывать только при наличии минимум двух совместимых фото.
Не размещать выше workout и scanner.

### 17.8 Reminder

После первого снимка предложить 2/4/8 недель или без напоминания.

Запрещено:
- body score;
- fat percentage from photo;
- attractiveness score;
- medical conclusions;
- automatic posting;
- fake AI analysis.

---

## 18. Workout Library and Programs

Фильтры:
- goal;
- level;
- location;
- equipment;
- duration;
- muscles;
- limitations;
- return after break;
- short workouts.

Не использовать Men/Women как главную классификацию.

Program card:
- poster;
- title;
- weeks;
- days/week;
- duration;
- level;
- equipment;
- goal;
- honest suitability label.

---

## 19. AI Coach

AI открывается в контексте:
- equipment;
- exercise;
- workout;
- summary;
- recovery;
- plan.

Ответ:
1. Short answer.
2. Reason.
3. Personal context.
4. Practical action.
5. Expandable details.

Использовать suggestion chips.
Не позиционировать AI как врача.

---

## 20. Profile, Settings and Subscription

Profile:
- personal data;
- goals;
- units;
- integrations;
- notifications;
- privacy;
- subscription;
- help.

Paywall только после preview или доказанной ценности.

Показывать:
- free/premium comparison;
- monthly/yearly prices;
- trial;
- billing date;
- cancellation terms;
- restore purchase.

Не использовать fake countdown или fake discount.

---

## 21. Design System

Создай Figma Variables и semantic tokens.

Colors:
- backgroundPrimary
- backgroundSecondary
- surfacePrimary
- surfaceElevated
- surfaceInteractive
- textPrimary
- textSecondary
- textDisabled
- accentPrimary
- accentSecondary
- success
- warning
- danger
- outline
- cameraOverlay
- poseCorrect
- poseWarning
- poseError

Typography:
- Display
- H1
- H2
- H3
- Title
- Body
- Body Small
- Label
- Caption
- Numeric Large
- Numeric Medium

Spacing:
4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48

Radius:
8 / 12 / 16 / 20 / 24 / Full

Core components:
- buttons;
- icon buttons;
- navigation;
- top bars;
- choice cards;
- chips;
- recommendation hero;
- media cards;
- BodyMetricPicker;
- set logger;
- rest timer;
- camera overlay;
- recognition sheet;
- TechniqueCoachCameraFrame;
- ExerciseAngleGuide;
- PoseSkeletonOverlay;
- QualityGateBanner;
- LiveRepCounter;
- MovementPhaseIndicator;
- LiveCueCard;
- TechniqueCoachStatusPanel;
- FormCheckSummaryCard;
- AI insight;
- progress cards;
- progress-photo timeline;
- compare slider;
- empty/loading/error/permission states.

Для каждого компонента:
- default;
- pressed;
- focused;
- selected;
- disabled;
- loading;
- error;
- success.

---

## 22. Accessibility

Обязательно:
- touch targets 44–48 px minimum;
- WCAG AA contrast;
- Dynamic Type;
- text scale 1.0 / 1.3 / 1.6 / 2.0;
- screen-reader order;
- focus states;
- no color-only meaning;
- reduced motion;
- long Russian strings;
- one-hand use;
- drag alternatives;
- safe areas.

---

## 23. Android and iOS Adaptation

Android:
- Material 3 behaviour;
- predictive back;
- edge-to-edge;
- permissions;
- standard bottom sheets.

IOS:
- safe areas;
- swipe back;
- native modal behaviour;
- Dynamic Type;
- permission patterns.

Один brand system, не два разных продукта.

---

## 24. Motion

Использовать:
- 150–250 ms controls;
- 250–400 ms transitions;
- fade-through;
- shared-axis;
- bottom sheet transitions;
- scan result animation;
- set saved feedback;
- rest countdown;
- skeleton-to-content.

Учитывать reduced motion.

---

## 25. Required States

Для каждого feature подготовить:
- loading;
- empty;
- partial data;
- stale data;
- retryable error;
- terminal error;
- offline;
- permission denied;
- permission permanently denied;
- unavailable hardware;
- interrupted flow.

---

## 26. Figma File Structure

00 — Cover
01 — Research & Reference Analysis
02 — Current UI Audit
03 — UX Principles
04 — Information Architecture
05 — User Flows
06 — Moodboards
07 — Visual Directions
08 — Final Design System
09 — Components
10 — Onboarding
11 — Body Metrics
12 — Home
13 — Scanner
14 — Equipment
15 — Exercise
16 — Workout Player
17 — Technique Coach / Form Check
18 — Workout Summary
19 — Progress
20 — Progress Photos
21 — Programs
22 — AI Coach
23 — Profile & Settings
24 — Subscription
25 — States
26 — Android Adaptations
27 — iOS Adaptations
28 — Light Theme
29 — Dark Theme
30 — Interactive Prototype
31 — Before / After
32 — Developer Handoff
33 — Product Decisions

---

## 27. Required Prototype

Связать happy path:

First launch
→ Onboarding
→ Body Metrics
→ Generating
→ Plan Preview
→ Account
→ Home
→ Scan
→ Recognition Result
→ Equipment
→ Exercise
→ Workout Player
→ Complete Set
→ Rest Timer
→ Technique Coach Setup
→ Live Form Check
→ Technique Summary
→ Workout Summary
→ Progress
→ Add Progress Photo
→ Add Second Photo
→ Compare
→ Export Preview
→ Home updated.

Также показать ключевые error/empty/permission paths.

---

## 28. Design Gates

Не проектировать всё одновременно без review.

D1 — Research, audit, IA and design system direction.
D2 — Onboarding and Body Metrics.
D3 — Home and Navigation.
D4 — Scanner and Equipment.
D5 — Exercise and Workout Player.
D6 — Technique Coach setup, quality gates, live Form Check and Summary.
D7 — Progress and Progress Photos.
D8 — Programs, AI Coach, Profile and Subscription.
D9 — States, accessibility, platform adaptations and final prototype.

После каждого gate:
- показать screens;
- показать states;
- показать rationale;
- перечислить unresolved product decisions;
- STOP до review.

---

## 29. Definition of Done

Дизайн завершён только когда:

1. Home больше не является сеткой плиток.
2. Пользователь всегда понимает следующее действие.
3. Scanner визуально выражает уникальность продукта.
4. Onboarding показывает preview до аккаунта/paywall.
5. Body metrics используют удобные pickers и честные формулировки.
6. Workout logging удобен одной рукой.
7. Technique Coach имеет setup, quality gates, rep counter, live cues и не оценивает без достаточной видимости.
8. Progress объясняет реальные данные.
9. Progress Photos приватны и имеют полноценный compare flow.
10. AI встроен контекстно.
11. Light/dark разработаны как системы.
12. Android/iOS адаптации задокументированы.
13. Accessibility states подготовлены.
14. Все core empty/loading/error/permission states существуют.
15. Есть end-to-end clickable prototype.
16. Есть developer handoff с tokens, dimensions, states и interactions.
17. Нет придуманных функций или ложных метрик.

Начни с Design Gate D1.
После D1 предоставь результат и STOP.

---

# UPDATE v1.3 — Decision Registry / Open Questions Governance

Добавь во внутренний Research & Architecture prototype отдельный экран для управления открытыми решениями.

Это **не пользовательский production screen**. Это stakeholder/design governance screen для Product, Design, Dev, Privacy, Legal и Sport Science.

## Размещение

Текущие вкладки:
- Анализ
- Архитектура
- Система

Добавь четвёртую вкладку:
- **Решения**

Label с количеством:
- `Решения · 44`

Не показывай все 44 вопроса одной длинной стеной.

## Структура Decision Registry

### Summary header
Покажи:
- Всего: 44
- Технический / продуктовый долг завершённых gates: 22
- Блокируют D6: 8
- Будущие решения D8–D9: 14
- Критические противоречия: 4

Важно: предыдущая сводка 26 / 8 / 10 математически не сходилась с gate counts.

### Фильтры
- Gate: D1–D9
- Status
- Owner
- Priority
- Blocking / Non-blocking
- Product / UX / Design / Tech / Privacy / Legal / Sport Science

### Status values
- Open
- Needs Research
- Needs Product Decision
- Needs Technical Decision
- Blocker
- Decided
- Deferred
- Locked by Existing Architecture

### Compact row
Каждая строка показывает:
- ID вопроса
- Gate
- короткий title
- owner
- status
- priority
- blocking badge
- decision deadline / required before gate

### Detail drawer / sheet
По нажатию открыть:
- полный вопрос;
- контекст и зачем решение нужно;
- варианты;
- рекомендуемый default, если он определён;
- owner;
- dependencies;
- affected screens / services;
- decision deadline;
- final decision;
- rationale;
- дата решения;
- ссылка на Figma frame / Git issue / ADR / code area.

## Обязательные corrections

1. Q39 не является открытым выбором стека. Канонический проект уже Flutter. Покажи его как:
   - Status: Locked by Existing Architecture
   - Decision: Flutter
   - запрещено предлагать React Native/native rewrite в рамках UI refactor.

2. Q19 исправить:
   - не `React Native + TFLite`;
   - использовать формулировку `реальный on-device ML в текущем Flutter stack или демонстрационный prototype`.

3. Q1 и Q41 относятся к одному product decision по Light Theme.
   - сохрани оба исходных ID для трассировки;
   - визуально пометь Q41 как duplicate / continuation of Q1;
   - одно финальное решение должно закрывать оба пункта.

4. Q4 не должен предлагать фиктивную iOS-заглушку как эквивалент Android health integration.
   - сформулировать как platform scope decision: Android integration now, separate iOS health integration later, либо обе платформы в одном release.

## Не блокировать дизайн всеми вопросами сразу

Раздели вопросы на:
- Hard blocker текущего gate;
- Soft decision with safe default;
- Future decision;
- Architecture locked;
- Duplicate / needs merge.

Для D6 покажи отдельный блок `Нужно решить перед продолжением`.

Hard blockers D6:
- Q19 ML scope;
- Q20 supported exercises;
- Q21 exercise-to-camera-angle matrix;
- Q23 TTS strategy;
- Q26 relationship with existing WorkoutDone / summary route.

Soft defaults, которые можно временно использовать до Product decision:
- Q22 не сохранять видео/кадры; summary metadata only, если storage не утверждён;
- Q24 использовать язык приложения / системы;
- Q25 не показывать raw confidence percentage, показывать human-readable reliability state.

Эти defaults должны быть помечены как provisional, а не final decisions.

## Visual design

Сохрани текущий dark premium internal prototype style:
- lime для active / resolved / selected;
- red только для blocker и conflict;
- amber для needs decision;
- neutral для future/deferred;
- compact rows;
- sticky filters;
- no giant cards for every question.

## Prototype interactions

Сделай кликабельный сценарий:
Research → Решения → Filter D6 → Open Q19 → Compare options → Mark provisional recommendation → Return → Filter Owner: Product → Open Q20.

Также показать:
- conflict badge;
- duplicate badge;
- locked decision;
- resolved item with rationale.

## Developer handoff for Decision Registry

Этот экран может оставаться Figma-only internal documentation и не обязан попадать в production Flutter app.

В handoff явно отметить:
- `INTERNAL DESIGN GOVERNANCE SCREEN`
- `NOT END-USER PRODUCT SCOPE`

Если позже потребуется реальный инструмент управления решениями, это отдельный admin/internal project, а не часть мобильного Fitness App.
